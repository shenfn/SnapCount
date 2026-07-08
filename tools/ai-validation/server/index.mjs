/**
 * ═══════════════════════════════════════════════
 * AI 识别链路追踪台 - 本地服务
 * ═══════════════════════════════════════════════
 *
 * 职责：
 *   1. 只读本地 test-results/ 和 test-cases/ 目录，为追踪台前端提供数据 API。
 *   2. 远程模式：通过 Supabase service_role 只读查询真实账号的 AI 识别记录。
 *   3. 上传测试：通过 upload_token 向远程 EF 发起真实识别请求。
 *
 * 安全约束：
 *   - 只监听 127.0.0.1:5181，不暴露外网
 *   - 本地图片接口只允许 test-cases/ 目录，路径安全校验拒绝 .. 和绝对路径
 *   - service_role key 仅在服务端使用，不出现在任何 API 响应或前端代码中
 *   - 远程查询全部为只读 .select()，禁止 insert/update/delete
 *   - 远程写操作仅限上传测试（通过 upload_token 调 EF）
 *   - 账号配置 accounts.json 不入 Git，只存 upload_token，不存 user_id
 *
 * API 路由：
 *   GET  /api/runs                              列出所有本地批次
 *   GET  /api/runs/:runId/summary               读取批次 summary.json
 *   GET  /api/runs/:runId/traces                列出批次内所有 trace 摘要
 *   GET  /api/runs/:runId/traces/:caseKey       读取单个完整 trace.json
 *   GET  /api/images?path=<relative-path>       读取本地测试图片（仅限 test-cases/）
 *   GET  /api/prompt                            返回完整 prompt 快照
 *   POST /api/upload-test                       上传图片执行测试（返回 jobId）
 *   GET  /api/upload-test/:jobId/status         轮询上传任务状态
 *
 *   GET  /api/accounts                          列出可用账号（仅 key + label）
 *   GET  /api/remote/accounts/:accountKey/days  查询远程账号有记录的日期列表
 *   GET  /api/remote/accounts/:accountKey/days/:date/traces  查询某天的记录列表
 *   GET  /api/remote/accounts/:accountKey/days/:date/traces/:logId  查询单条记录详情
 *   GET  /api/remote/images?logId=...           下载远程图片（按 logId 校验归属）
 *   GET  /api/remote/accounts/:accountKey/memory  查询 companion 记忆上下文
 *
 *   GET  /api/health                            健康检查
 */

import express from 'express'
import { readFile, readdir, stat, writeFile, mkdir, rename, copyFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
import { createClient } from '@supabase/supabase-js'
import WebSocket from 'ws'  // Node.js 20 无原生 WebSocket，需手动提供
import { buildTraceFromAiLog, toShanghaiDate, parseRawDebug } from '../lib/trace-builder.mjs'

const require = createRequire(import.meta.url)

// ═══════════════════════════════════════════════
// 配置
// ═══════════════════════════════════════════════

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// 项目根目录：tools/ai-validation/server/ 往上 3 级
const PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..')

const TEST_RESULTS_DIR = path.join(PROJECT_ROOT, 'test-results')
const TEST_CASES_DIR = path.join(PROJECT_ROOT, 'test-cases')

const PORT = 5181
const HOST = '127.0.0.1'

// 允许的图片扩展名
const ALLOWED_IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp', '.gif'])

// MIME 类型映射
const MIME_MAP = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
}

// ═══════════════════════════════════════════════
// 工具函数
// ═══════════════════════════════════════════════

/**
 * 安全拼接路径，防止路径逃逸
 * @param {string} base - 基础目录
 * @param {string} relative - 相对路径
 * @returns {string|null} 安全的绝对路径，如果不安全返回 null
 */
function safeJoinPath(base, relative) {
  if (!relative || typeof relative !== 'string') return null
  // 拒绝绝对路径和路径逃逸
  if (path.isAbsolute(relative)) return null
  if (relative.includes('..')) return null
  const joined = path.resolve(base, relative)
  // 最终路径必须在 base 目录内
  if (!joined.startsWith(base + path.sep) && joined !== base) return null
  return joined
}

/**
 * 递归查找目录下所有指定扩展名的文件
 * @param {string} dir - 起始目录
 * @param {string} ext - 文件扩展名（如 '.trace.json'）
 * @returns {Promise<string[]>} 相对于 dir 的文件路径列表
 */
async function findFilesRecursive(dir, ext, baseDir = dir) {
  const results = []
  let entries
  try {
    entries = await readdir(dir, { withFileTypes: true })
  } catch {
    return results
  }
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      const subResults = await findFilesRecursive(fullPath, ext, baseDir)
      results.push(...subResults)
    } else if (entry.name.endsWith(ext)) {
      results.push(path.relative(baseDir, fullPath))
    }
  }
  return results
}

/**
 * 安全读取 JSON 文件
 * @param {string} filePath - 文件绝对路径
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
async function safeReadJson(filePath) {
  try {
    const content = await readFile(filePath, 'utf-8')
    return { data: JSON.parse(content), error: null }
  } catch (err) {
    return { data: null, error: err.message }
  }
}

/**
 * 从 trace 文件相对路径推导 case_key
 * 例如: sport/2026-06-27/001-cycling-9_79km.trace.json → sport/2026-06-27/001-cycling-9_79km
 * @param {string} relativePath
 * @returns {string}
 */
function deriveCaseKey(relativePath) {
  // 统一使用正斜杠，确保跨平台一致，便于 URL 传递
  return relativePath.replace(/\.trace\.json$/, '').replace(/\\/g, '/')
}

/**
 * 从文件名中提取域（路径第一段）
 * @param {string} relativePath
 * @returns {string|null}
 */
function extractDomain(relativePath) {
  const parts = relativePath.split(path.sep)
  return parts.length > 1 ? parts[0] : null
}

/**
 * 统一错误响应
 */
function sendError(res, status, message, detail) {
  res.status(status).json({ error: message, detail: detail || undefined })
}

// ═══════════════════════════════════════════════
// Express 应用
// ═══════════════════════════════════════════════

const app = express()
app.use((req, res, next) => {
  // 简单请求日志
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`)
  next()
})

// ═══════════════════════════════════════════════
// 路由：GET /api/runs - 列出所有批次
// ═══════════════════════════════════════════════

app.get('/api/runs', async (req, res) => {
  try {
    if (!existsSync(TEST_RESULTS_DIR)) {
      return res.json({ runs: [] })
    }

    const entries = await readdir(TEST_RESULTS_DIR, { withFileTypes: true })
    const runs = []

    for (const entry of entries) {
      if (!entry.isDirectory()) continue
      const runDir = path.join(TEST_RESULTS_DIR, entry.name)
      const summaryPath = path.join(runDir, 'summary.json')

      if (!existsSync(summaryPath)) {
        // 没有 summary.json 的目录也列出，但标记为 incomplete
        runs.push({
          run_id: entry.name,
          generated_at: null,
          total_cases: null,
          success_cases: null,
          failed_cases: null,
          has_summary: false,
        })
        continue
      }

      const { data, error } = await safeReadJson(summaryPath)
      if (error || !data) {
        runs.push({
          run_id: entry.name,
          generated_at: null,
          total_cases: null,
          success_cases: null,
          failed_cases: null,
          has_summary: false,
          summary_error: error,
        })
        continue
      }

      // 以真实 summary.json 结构为准
      runs.push({
        run_id: data.run_id || entry.name,
        generated_at: data.generated_at || null,
        total_cases: data.total_cases ?? null,
        success_cases: data.success_cases ?? null,
        failed_cases: data.failed_cases ?? null,
        ai_feedback_cases: data.ai_feedback_cases ?? null,
        has_summary: true,
      })
    }

    // 按生成时间倒序排列，无时间的排最后
    runs.sort((a, b) => {
      if (!a.generated_at) return 1
      if (!b.generated_at) return -1
      return new Date(b.generated_at) - new Date(a.generated_at)
    })

    res.json({ runs })
  } catch (err) {
    sendError(res, 500, 'Failed to list runs', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/runs/:runId/summary - 读取批次 summary
// ═══════════════════════════════════════════════

app.get('/api/runs/:runId/summary', async (req, res) => {
  try {
    const { runId } = req.params
    // runId 只允许字母数字和连字符，防止路径注入
    if (!/^[a-zA-Z0-9_-]+$/.test(runId)) {
      return sendError(res, 400, 'Invalid runId')
    }

    const summaryPath = path.join(TEST_RESULTS_DIR, runId, 'summary.json')
    if (!existsSync(summaryPath)) {
      return sendError(res, 404, 'Summary not found', `Run "${runId}" has no summary.json`)
    }

    const { data, error } = await safeReadJson(summaryPath)
    if (error) {
      return sendError(res, 500, 'Failed to parse summary', error)
    }

    res.json(data)
  } catch (err) {
    sendError(res, 500, 'Failed to read summary', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/runs/:runId/traces - 列出批次内所有 trace 摘要
// ═══════════════════════════════════════════════

app.get('/api/runs/:runId/traces', async (req, res) => {
  try {
    const { runId } = req.params
    if (!/^[a-zA-Z0-9_-]+$/.test(runId)) {
      return sendError(res, 400, 'Invalid runId')
    }

    const runDir = path.join(TEST_RESULTS_DIR, runId)
    if (!existsSync(runDir)) {
      return sendError(res, 404, 'Run not found', `Run "${runId}" does not exist`)
    }

    // 递归查找所有 .trace.json 文件
    const traceFiles = await findFilesRecursive(runDir, '.trace.json')

    const traces = []
    for (const relPath of traceFiles) {
      const fullPath = path.join(runDir, relPath)
      const { data, error } = await safeReadJson(fullPath)
      // 检查同目录是否存在 review.json
      const reviewPath = fullPath.replace(/\.trace\.json$/, '.review.json')
      let hasReview = false
      let reviewRatings = null
      if (existsSync(reviewPath)) {
        const { data: reviewData } = await safeReadJson(reviewPath)
        if (reviewData && reviewData.ratings) {
          hasReview = true
          reviewRatings = reviewData.ratings
        }
      }
      if (error || !data) {
        // 解析失败的 trace 也列出，标记错误
        traces.push({
          case_key: deriveCaseKey(relPath),
          trace_id: null,
          file: path.basename(relPath, '.trace.json'),
          domain: extractDomain(relPath),
          date: null,
          status: 'parse_error',
          elapsed_ms: null,
          has_ai_feedback: false,
          image_relative_path: null,
          parse_error: error,
          has_review: hasReview,
          review_ratings: reviewRatings,
        })
        continue
      }

      // 从 trace.json 提取摘要字段
      traces.push({
        case_key: deriveCaseKey(relPath),
        trace_id: data.trace_id || null,
        ai_log_id: data.ai_log_id || null,
        file: data.case?.test_case_file || path.basename(relPath, '.trace.json'),
        domain: data.case?.test_case_domain || extractDomain(relPath),
        date: data.case?.test_case_date || null,
        status: data.status || 'unknown',
        elapsed_ms: data.steps?.find((s) => s.step_id === 'upload_request')?.duration_ms || null,
        has_ai_feedback: data.user_visible_outputs?.some(
          (o) => o.output_type === 'app_ai_feedback'
        ) || false,
        image_relative_path: data.case?.image_relative_path || null,
        has_review: hasReview,
        review_ratings: reviewRatings,
      })
    }

    res.json({ traces })
  } catch (err) {
    sendError(res, 500, 'Failed to list traces', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/runs/:runId/traces/:caseKey - 读取单个完整 trace
// ═══════════════════════════════════════════════
// caseKey 是相对于 runDir 的路径（不含 .trace.json 后缀）
// 例如: sport/2026-06-27/001-cycling-9_79km
// ═══════════════════════════════════════════════

app.get('/api/runs/:runId/traces/:caseKey(*)', async (req, res) => {
  try {
    const { runId, caseKey } = req.params
    if (!/^[a-zA-Z0-9_-]+$/.test(runId)) {
      return sendError(res, 400, 'Invalid runId')
    }

    // caseKey 安全校验
    if (!caseKey || caseKey.includes('..') || path.isAbsolute(caseKey)) {
      return sendError(res, 400, 'Invalid caseKey')
    }

    const runDir = path.join(TEST_RESULTS_DIR, runId)
    const tracePath = path.resolve(runDir, caseKey + '.trace.json')

    // 最终路径必须在 runDir 内
    if (!tracePath.startsWith(runDir + path.sep) && tracePath !== path.join(runDir, caseKey + '.trace.json')) {
      return sendError(res, 400, 'Invalid caseKey path')
    }

    if (!existsSync(tracePath)) {
      return sendError(res, 404, 'Trace not found', `No trace file at "${caseKey}"`)
    }

    const { data, error } = await safeReadJson(tracePath)
    if (error) {
      return sendError(res, 500, 'Failed to parse trace', error)
    }

    res.json(data)
  } catch (err) {
    sendError(res, 500, 'Failed to read trace', err.message)
  }
})

// ═══════════════════════════════════════════════
// 远程点评：自动缓存图片到本地
// 点评远程记录时，把对应图片下载到 test-results/<run-id>/_images/
// 这样离线分析时能直接从本地读取，不用再请求远程
// ═══════════════════════════════════════════════
async function cacheRemoteImageForReview(review, traceSnapshot) {
  if (!supabaseAdmin || !traceSnapshot) return

  // 从 trace 快照中提取 logId 和 image_url
  const logId = traceSnapshot.trace_id || traceSnapshot.ai_log_id
  const imageUrl = traceSnapshot.case?.image_relative_path || traceSnapshot.case?.image_url
  if (!logId || !imageUrl) return

  // 从 image_url 下载图片（Supabase Storage 私有桶）
  const { data, error } = await supabaseAdmin.storage
    .from('receipt-images')
    .download(imageUrl)

  if (error || !data) {
    console.warn(`[review] 下载图片失败: ${imageUrl}`, error?.message)
    return
  }

  // 保存到点评同目录下的 _images 子目录
  const runDir = path.join(TEST_RESULTS_DIR, review.run_id)
  const imageDir = path.join(runDir, '_images')
  await mkdir(imageDir, { recursive: true })

  // 文件名用 logId + 原始扩展名
  const ext = path.extname(imageUrl) || '.jpg'
  const localImagePath = path.join(imageDir, `${logId}${ext}`)
  const buffer = Buffer.from(await data.arrayBuffer())
  await writeFile(localImagePath, buffer)

  // 在 review 中记录本地图片路径
  review.local_image_path = path.relative(TEST_RESULTS_DIR, localImagePath)
  console.log(`[review] 图片已缓存: ${review.local_image_path}`)
}

// ═══════════════════════════════════════════════
// 路由：POST /api/runs/:runId/reviews/:caseKey - 保存点评
// ═══════════════════════════════════════════════
// 请求体：review-v1 对象（不含 reviewed_at / case_key / run_id，由服务端补）
// 落盘到 test-results/<run-id>/<caseKey>.review.json
// ═══════════════════════════════════════════════

const VALID_ISSUE_TAGS = new Set([
  'wrong_domain', 'wrong_amount', 'wrong_date', 'wrong_category',
  'missing_key_field', 'ai_feedback_too_generic', 'ai_feedback_too_exaggerated',
  'ai_feedback_wrong_tone', 'hallucination', 'model_timeout', 'parse_failure', 'other',
])

app.post('/api/runs/:runId/reviews/:caseKey(*)', express.json({ limit: '1mb' }), async (req, res) => {
  try {
    const { runId, caseKey } = req.params
    if (!/^[a-zA-Z0-9_-]+$/.test(runId)) {
      return sendError(res, 400, 'Invalid runId')
    }
    if (!caseKey || caseKey.includes('..') || path.isAbsolute(caseKey)) {
      return sendError(res, 400, 'Invalid caseKey')
    }

    const body = req.body || {}
    // 校验 ratings
    const ratings = body.ratings || {}
    const ra = Number(ratings.recognition_accuracy)
    const fq = Number(ratings.feedback_quality)
    if (!Number.isInteger(ra) || ra < 1 || ra > 5) {
      return sendError(res, 400, 'Invalid ratings.recognition_accuracy', 'must be integer 1-5')
    }
    if (!Number.isInteger(fq) || fq < 1 || fq > 5) {
      return sendError(res, 400, 'Invalid ratings.feedback_quality', 'must be integer 1-5')
    }
    // 校验 issue_tags
    const issueTags = Array.isArray(body.issue_tags) ? body.issue_tags : []
    for (const tag of issueTags) {
      if (!VALID_ISSUE_TAGS.has(tag)) {
        return sendError(res, 400, 'Invalid issue_tag', `"${tag}" is not a valid tag`)
      }
    }

    const runDir = path.join(TEST_RESULTS_DIR, runId)
    const reviewPath = path.resolve(runDir, caseKey + '.review.json')
    if (!reviewPath.startsWith(runDir + path.sep) && reviewPath !== path.join(runDir, caseKey + '.review.json')) {
      return sendError(res, 400, 'Invalid caseKey path')
    }

    // 确保父目录存在
    await mkdir(path.dirname(reviewPath), { recursive: true })

    const review = {
      schema_version: 'review-v1',
      case_key: caseKey,
      run_id: runId,
      reviewed_at: new Date().toISOString(),
      mode: body.mode || 'trace',
      ratings: { recognition_accuracy: ra, feedback_quality: fq },
      issue_tags: issueTags,
      notes: typeof body.notes === 'string' ? body.notes.slice(0, 2000) : '',
      suggested_action: typeof body.suggested_action === 'string' ? body.suggested_action.slice(0, 500) : '',
      sim_snapshot: body.sim_snapshot || null,
      trace_snapshot: body.trace_snapshot || null,
    }

    // 远程模式：点评时自动缓存对应图片到本地
    // 这样离线分析时能直接从本地读取图片，不用再请求远程
    if (runId.startsWith('remote-') && body.trace_snapshot) {
      try {
        await cacheRemoteImageForReview(review, body.trace_snapshot)
      } catch (imgErr) {
        console.warn('[review] 缓存远程图片失败（不影响点评保存）:', imgErr.message)
      }
    }

    await writeFile(reviewPath, JSON.stringify(review, null, 2), 'utf-8')

    res.json({ ok: true, path: path.relative(TEST_RESULTS_DIR, reviewPath), reviewed_at: review.reviewed_at })
  } catch (err) {
    sendError(res, 500, 'Failed to save review', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/runs/:runId/reviews/:caseKey - 读取单个点评
// ═══════════════════════════════════════════════

app.get('/api/runs/:runId/reviews/:caseKey(*)', async (req, res) => {
  try {
    const { runId, caseKey } = req.params
    if (!/^[a-zA-Z0-9_-]+$/.test(runId)) {
      return sendError(res, 400, 'Invalid runId')
    }
    if (!caseKey || caseKey.includes('..') || path.isAbsolute(caseKey)) {
      return sendError(res, 400, 'Invalid caseKey')
    }

    const runDir = path.join(TEST_RESULTS_DIR, runId)
    const reviewPath = path.resolve(runDir, caseKey + '.review.json')
    if (!reviewPath.startsWith(runDir + path.sep) && reviewPath !== path.join(runDir, caseKey + '.review.json')) {
      return sendError(res, 400, 'Invalid caseKey path')
    }

    if (!existsSync(reviewPath)) {
      return sendError(res, 404, 'Review not found')
    }

    const { data, error } = await safeReadJson(reviewPath)
    if (error) {
      return sendError(res, 500, 'Failed to parse review', error)
    }

    res.json(data)
  } catch (err) {
    sendError(res, 500, 'Failed to read review', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/runs/:runId/reviews - 列出全部点评摘要
// ═══════════════════════════════════════════════

app.get('/api/runs/:runId/reviews', async (req, res) => {
  try {
    const { runId } = req.params
    if (!/^[a-zA-Z0-9_-]+$/.test(runId)) {
      return sendError(res, 400, 'Invalid runId')
    }

    const runDir = path.join(TEST_RESULTS_DIR, runId)
    if (!existsSync(runDir)) {
      return res.json({ reviews: [] })
    }

    const reviewFiles = await findFilesRecursive(runDir, '.review.json')
    const reviews = []
    for (const relPath of reviewFiles) {
      const fullPath = path.join(runDir, relPath)
      const { data, error } = await safeReadJson(fullPath)
      if (error || !data) continue
      reviews.push({
        case_key: data.case_key || relPath.replace(/\.review\.json$/, ''),
        reviewed_at: data.reviewed_at || null,
        ratings: data.ratings || null,
        issue_tags: data.issue_tags || [],
        mode: data.mode || 'trace',
        file: relPath,
      })
    }

    res.json({ reviews })
  } catch (err) {
    sendError(res, 500, 'Failed to list reviews', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/images?path=<relative-path> - 读取测试图片
// ═══════════════════════════════════════════════
// 只允许 test-cases/ 目录下的图片
// ═══════════════════════════════════════════════

app.get('/api/images', async (req, res) => {
  try {
    const { path: relativePath } = req.query
    if (!relativePath) {
      return sendError(res, 400, 'Missing path parameter')
    }

    // 安全校验：只允许 test-cases/ 开头
    const normalizedPath = String(relativePath).replace(/\\/g, '/')
    if (!normalizedPath.startsWith('test-cases/')) {
      return sendError(res, 403, 'Forbidden', 'Only test-cases/ images are allowed')
    }

    // 去掉 test-cases/ 前缀后做路径安全校验
    const subPath = normalizedPath.slice('test-cases/'.length)
    if (subPath.includes('..') || path.isAbsolute(subPath)) {
      return sendError(res, 403, 'Forbidden', 'Path traversal detected')
    }

    const imagePath = path.join(TEST_CASES_DIR, subPath)
    // 最终路径必须在 TEST_CASES_DIR 内
    if (!imagePath.startsWith(TEST_CASES_DIR + path.sep) && imagePath !== TEST_CASES_DIR) {
      return sendError(res, 403, 'Forbidden', 'Path outside test-cases directory')
    }

    if (!existsSync(imagePath)) {
      return sendError(res, 404, 'Image not found', `No image at "${relativePath}"`)
    }

    // 检查扩展名
    const ext = path.extname(imagePath).toLowerCase()
    if (!ALLOWED_IMAGE_EXTENSIONS.has(ext)) {
      return sendError(res, 403, 'Forbidden', `File type "${ext}" not allowed`)
    }

    const contentType = MIME_MAP[ext] || 'application/octet-stream'
    res.setHeader('Content-Type', contentType)
    res.setHeader('Cache-Control', 'public, max-age=3600')

    const fileBuffer = await readFile(imagePath)
    res.send(fileBuffer)
  } catch (err) {
    sendError(res, 500, 'Failed to read image', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/prompt - 获取 prompt 快照
// ═══════════════════════════════════════════════
// 返回从 prompts.ts 提取的完整 prompt 文本
// 快照由 extract-prompt.mjs 预生成，server 只读文件
// ═══════════════════════════════════════════════

app.get('/api/prompt', async (req, res) => {
  try {
    const snapshotPath = path.join(__dirname, 'prompt-snapshot.json')
    if (!existsSync(snapshotPath)) {
      return sendError(res, 404, 'Prompt snapshot not found', '请先运行 npx tsx extract-prompt.mjs 生成快照')
    }
    const { data, error } = await safeReadJson(snapshotPath)
    if (error) {
      return sendError(res, 500, 'Failed to parse prompt snapshot', error)
    }
    res.json(data)
  } catch (err) {
    sendError(res, 500, 'Failed to read prompt snapshot', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/prompt-history - 列出 prompt 历史版本
// ═══════════════════════════════════════════════

app.get('/api/prompt-history', async (req, res) => {
  try {
    const historyDir = path.join(__dirname, 'prompt-history')
    if (!existsSync(historyDir)) {
      return res.json({ versions: [] })
    }
    const files = await readdir(historyDir)
    const versions = []
    for (const file of files) {
      if (!file.endsWith('.json')) continue
      const { data } = await safeReadJson(path.join(historyDir, file))
      if (!data) continue
      versions.push({
        file,
        saved_at: data.saved_at || file,
        vision_hash: data.vision_prompt?.hash?.slice(0, 8) || 'unknown',
        vision_chars: data.vision_prompt?.char_count || 0,
        feedback_hash: data.feedback_prompt?.hash?.slice(0, 8) || 'unknown',
        feedback_chars: data.feedback_prompt?.char_count || 0,
        changes: data.changes || null,
      })
    }
    // 按时间倒序
    versions.sort((a, b) => (b.saved_at || '').localeCompare(a.saved_at || ''))
    res.json({ versions })
  } catch (err) {
    sendError(res, 500, 'Failed to list prompt history', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/prompt-history/:file - 读取指定历史版本
// ═══════════════════════════════════════════════

app.get('/api/prompt-history/:file', async (req, res) => {
  try {
    const file = path.basename(req.params.file)
    if (!file.endsWith('.json')) {
      return sendError(res, 400, 'Invalid file')
    }
    const filePath = path.join(__dirname, 'prompt-history', file)
    if (!existsSync(filePath)) {
      return sendError(res, 404, 'History version not found', file)
    }
    const { data, error } = await safeReadJson(filePath)
    if (error) {
      return sendError(res, 500, 'Failed to parse', error)
    }
    res.json(data)
  } catch (err) {
    sendError(res, 500, 'Failed to read history', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：POST /api/refresh-prompt - 刷新 prompt 快照
// ═══════════════════════════════════════════════
// 运行 extract-prompt.mjs 重新提取 prompt，自动保存历史版本
// ═══════════════════════════════════════════════

app.post('/api/refresh-prompt', async (req, res) => {
  try {
    const scriptPath = path.join(__dirname, 'extract-prompt.mjs')
    const tsxPath = path.join(__dirname, 'node_modules', '.bin', 'tsx')
    const child = spawn(tsxPath, [scriptPath], {
      cwd: __dirname,
      env: { ...process.env, ...envLocal },
      shell: true,
    })

    let stdoutData = ''
    let stderrData = ''

    child.stdout.on('data', (data) => { stdoutData += data.toString() })
    child.stderr.on('data', (data) => { stderrData += data.toString() })

    child.on('close', (code) => {
      if (code !== 0) {
        return res.json({ success: false, error: `脚本退出码 ${code}`, stderr: stderrData })
      }
      // 解析输出中的 hash 和字符数
      const visionHash = stdoutData.match(/vision.*?hash:\s*(\S+)/i)?.[1] || ''
      const visionChars = stdoutData.match(/视觉.*?字符数:\s*(\d+)/)?.[1] || 0
      const feedbackChars = stdoutData.match(/文案.*?字符数:\s*(\d+)/)?.[1] || 0
      const historySaved = stdoutData.match(/历史版本已保存:\s*(\S+)/)?.[1] || null

      res.json({
        success: true,
        vision_hash: visionHash,
        vision_chars: Number(visionChars),
        feedback_chars: Number(feedbackChars),
        history_saved: historySaved,
      })
    })
  } catch (err) {
    sendError(res, 500, 'Refresh failed', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：POST /api/local-simulate - 本地 prompt 模拟
// ═══════════════════════════════════════════════
// 直接调用 qwen API，使用本地 prompts.ts 的 prompt，
// 不经过 Edge Function，用于快速验证 prompt 改动。
//
// 请求体 JSON:
//   { mode: 'paste' | 'file', imageBase64?: string, existingPath?: string }
//
// 返回:
//   { jobId }
// 轮询 GET /api/local-simulate/:jobId/status 获取结果
// ═══════════════════════════════════════════════

const simulateJobs = new Map()

app.post('/api/local-simulate', express.json({ limit: '20mb' }), async (req, res) => {
  try {
    const { mode, imageBase64, existingPath, noVisionThinking, visionModel, feedbackModel } = req.body

    let imagePath = ''

    if (mode === 'paste') {
      if (!imageBase64) {
        return sendError(res, 400, 'Missing imageBase64')
      }
      const pendingDir = path.join(PROJECT_ROOT, 'test-cases', '_pending')
      if (!existsSync(pendingDir)) {
        await mkdir(pendingDir, { recursive: true })
      }
      const timestamp = Date.now()
      imagePath = path.join(pendingDir, `sim_${timestamp}.png`)
      await writeFile(imagePath, Buffer.from(imageBase64, 'base64'))
    } else {
      if (!existingPath) {
        return sendError(res, 400, 'Missing existingPath')
      }
      const resolved = path.resolve(PROJECT_ROOT, existingPath)
      if (!resolved.startsWith(PROJECT_ROOT)) {
        return sendError(res, 403, 'Path not allowed')
      }
      if (!existsSync(resolved)) {
        return sendError(res, 404, 'File not found', existingPath)
      }
      imagePath = resolved
    }

    const jobId = `sim-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`

    simulateJobs.set(jobId, {
      status: 'running',
      step: 'starting',
      imagePath,
      startTime: Date.now(),
      output: [],
      error: null,
      result: null,
    })

    runLocalSimulate(jobId, imagePath, noVisionThinking === true, visionModel || null, feedbackModel || null)

    res.json({ jobId })
  } catch (err) {
    sendError(res, 500, 'Local simulate failed', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/local-simulate/:jobId/status
// ═══════════════════════════════════════════════

app.get('/api/local-simulate/:jobId/status', (req, res) => {
  const job = simulateJobs.get(req.params.jobId)
  if (!job) {
    return sendError(res, 404, 'Job not found', req.params.jobId)
  }
  res.json({
    status: job.status,
    step: job.step,
    elapsed: Date.now() - job.startTime,
    output: job.output.slice(-10),
    error: job.error,
    result: job.result,
    runId: job.runId || null,
    traceCaseKey: job.traceCaseKey || null,
  })
})

// ═══════════════════════════════════════════════
// 异步执行本地模拟
// ═══════════════════════════════════════════════

async function runLocalSimulate(jobId, imagePath, noVisionThinking, visionModel, feedbackModel) {
  const job = simulateJobs.get(jobId)
  const scriptPath = path.join(__dirname, 'local-simulate.mjs')
  const relativeImagePath = path.relative(PROJECT_ROOT, imagePath).replace(/\\/g, '/')

  // 用 tsx 执行（需要 TS 支持）
  const tsxPath = path.join(__dirname, 'node_modules', '.bin', 'tsx')
  const args = [scriptPath, '--image', relativeImagePath]
  if (noVisionThinking) args.push('--no-vision-thinking')
  if (visionModel) args.push('--vision-model', visionModel)
  if (feedbackModel) args.push('--feedback-model', feedbackModel)
  const child = spawn(tsxPath, args, {
    cwd: PROJECT_ROOT,
    env: { ...process.env, ...envLocal },
    shell: true,
  })

  let stdoutData = ''

  child.stdout.on('data', (data) => {
    stdoutData += data.toString()
  })

  child.stderr.on('data', (data) => {
    const text = data.toString().trim()
    if (text) {
      job.output.push(text)
      if (text.includes('视觉识别')) job.step = 'recognizing'
      else if (text.includes('文案生成')) job.step = 'generating'
    }
  })

  child.on('close', async (code) => {
    if (code !== 0) {
      job.status = 'error'
      job.step = 'failed'
      job.error = `脚本退出码 ${code}`
      return
    }

    try {
      const result = JSON.parse(stdoutData.trim())
      job.result = result

      // 生成 trace.json、移动图片、更新 summary
      job.step = 'saving'
      const traceInfo = await saveSimResultAsTrace(result, imagePath)
      job.traceCaseKey = traceInfo.caseKey
      job.runId = traceInfo.runId

      job.status = 'done'
      job.step = 'completed'
    } catch (err) {
      job.status = 'error'
      job.step = 'parse-failed'
      job.error = `结果解析或保存失败: ${err.message}`
    }
  })
}

// ═══════════════════════════════════════════════
// 本地模拟结果保存为 trace.json
// ═══════════════════════════════════════════════

async function saveSimResultAsTrace(result, originalImagePath) {
  const visionParsed = result.vision_output?.parsed || {}
  const feedbackParsed = result.feedback_output?.parsed || {}
  const elapsedMs = result.elapsed_ms || 0

  // 获取域
  const domain = visionParsed.domain_key
    || visionParsed.record_type
    || 'uncertain'
  const domainDir = (domain && domain !== 'uncertain' && domain !== 'unknown') ? domain : 'uncertain'

  // 生成 runId
  const today = new Date().toISOString().slice(0, 10).replace(/-/g, '')
  const runId = `manual-sim-${today}`
  const dateStr = new Date().toISOString().slice(0, 10)

  // 移动图片（如果在 _pending 下）
  const pendingDir = path.join(PROJECT_ROOT, 'test-cases', '_pending')
  let finalImagePath = originalImagePath
  let finalRelativePath = path.relative(PROJECT_ROOT, originalImagePath).replace(/\\/g, '/')

  if (originalImagePath.startsWith(pendingDir)) {
    const finalDir = path.join(PROJECT_ROOT, 'test-cases', domainDir, dateStr)
    if (!existsSync(finalDir)) {
      await mkdir(finalDir, { recursive: true })
    }
    const fileName = path.basename(originalImagePath)
    const finalAbsPath = path.join(finalDir, fileName)
    await rename(originalImagePath, finalAbsPath)
    finalImagePath = finalAbsPath
    finalRelativePath = path.relative(PROJECT_ROOT, finalAbsPath).replace(/\\/g, '/')
  }

  // 生成 trace.json
  const timestamp = Date.now()
  const traceDir = path.join(TEST_RESULTS_DIR, runId, 'single', domainDir, dateStr)
  if (!existsSync(traceDir)) {
    await mkdir(traceDir, { recursive: true })
  }
  const traceFileBase = `${timestamp}`
  const traceFilePath = path.join(traceDir, `${traceFileBase}.trace.json`)
  const caseKey = `single/${domainDir}/${dateStr}/${traceFileBase}`

  // 构造 trace 数据（和线上 EF 的 trace.json 结构兼容）
  const traceData = {
    trace_id: `sim-${timestamp}`,
    run_id: runId,
    status: 'done',
    created_at: new Date().toISOString(),
    is_local_sim: true,
    case: {
      test_run_id: runId,
      test_case_domain: domainDir,
      test_case_date: dateStr,
      test_case_file: finalRelativePath,
      image_relative_path: finalRelativePath,
      mode: 'local-simulate',
    },
    model_context: {
      vision_mode: 'screenshot',
      model_provider: 'qwen',
      model_name: result.vision_output?.model || 'qwen3.6-flash',
      feedback_model: result.feedback_output?.model || 'qwen3.6-flash',
    },
    steps: [
      {
        step_id: 'upload_request',
        name: '本地模拟启动',
        status: 'success',
        duration_ms: elapsedMs,
        input_snapshot: {
          image: finalRelativePath,
          mode: 'local-simulate',
        },
        output_snapshot: {
          status: 'done',
        },
        user_visible: false,
        visibility_level: 'L1',
      },
      {
        step_id: 'prompt_build',
        name: 'Prompt 构造',
        status: 'success',
        duration_ms: null,
        input_snapshot: {},
        output_snapshot: {
          prompt_version: 'local-simulate',
          prompt_snapshot_available: true,
        },
        user_visible: false,
        visibility_level: 'L2',
        artifact_refs: ['prompt'],
      },
      {
        step_id: 'model_call',
        name: '视觉识别调用',
        status: 'success',
        duration_ms: null,
        input_snapshot: {
          model: result.vision_output?.model || 'qwen3.6-flash',
          temperature: 0.1,
          enable_thinking: true,
        },
        output_snapshot: {
          has_raw_text: !!result.vision_output?.raw_text,
          has_extracted_json: !!visionParsed,
          finish_reason: 'stop',
        },
        user_visible: false,
        visibility_level: 'L2',
        artifact_refs: ['model_raw'],
      },
      {
        step_id: 'model_parse',
        name: '模型解析',
        status: 'success',
        duration_ms: null,
        input_snapshot: {},
        output_snapshot: {
          extracted_json_available: !!visionParsed,
          record_type: visionParsed.record_type || null,
          domain_key: visionParsed.domain_key || null,
          title: visionParsed.title || null,
          confidence: visionParsed.confidence || null,
        },
        user_visible: false,
        visibility_level: 'L2',
        artifact_refs: ['model_raw.extracted_json'],
      },
      {
        step_id: 'companion_feedback',
        name: '伴随文案 / AI 反馈',
        status: 'success',
        duration_ms: null,
        input_snapshot: {},
        output_snapshot: {
          final: feedbackParsed.companion_message || null,
          has_ai_feedback: !!feedbackParsed.ai_feedback,
        },
        user_visible: true,
        visibility_level: 'L0',
        artifact_refs: ['companion'],
      },
    ],
    user_visible_outputs: [
      {
        output_type: 'app_companion_message',
        label: 'App 伴随文案',
        value: feedbackParsed.companion_message || '',
        source_step: 'companion_feedback',
        user_visible: true,
      },
      ...(feedbackParsed.ai_feedback ? [{
        output_type: 'app_ai_feedback',
        label: 'App AI 弹窗反馈',
        value: feedbackParsed.ai_feedback,
        source_step: 'companion_feedback',
        user_visible: true,
      }] : []),
    ],
    artifacts: {
      model_raw: {
        text: result.vision_output?.raw_text || '',
        extracted_json: visionParsed,
        usage: result.vision_output?.usage || null,
      },
      companion: {
        final: feedbackParsed.companion_message || '',
        ai_feedback: feedbackParsed.ai_feedback || null,
      },
      prompt: {
        version: 'local-simulate',
        vision_full_text: result.vision_prompt || '',
        feedback_full_text: result.feedback_prompt || '',
      },
    },
  }

  await writeFile(traceFilePath, JSON.stringify(traceData, null, 2), 'utf-8')

  // 更新 summary.json
  await updateSimSummary(runId)

  return { caseKey, runId, domain: domainDir }
}

// ═══════════════════════════════════════════════
// 更新本地模拟批次的 summary.json
// ═══════════════════════════════════════════════

async function updateSimSummary(runId) {
  const runDir = path.join(TEST_RESULTS_DIR, runId)
  const summaryPath = path.join(runDir, 'summary.json')

  // 统计当前批次的 trace 数量
  const traceFiles = await findFilesRecursive(runDir, '.trace.json')
  let successCount = 0
  let feedbackCount = 0

  for (const relPath of traceFiles) {
    const { data } = await safeReadJson(path.join(runDir, relPath))
    if (data) {
      if (data.status === 'done') successCount++
      if (data.user_visible_outputs?.some(o => o.output_type === 'app_ai_feedback')) feedbackCount++
    }
  }

  const summary = {
    run_id: runId,
    generated_at: new Date().toISOString(),
    response_mode: 'json',
    capture_kind: 'local-simulate',
    source_app: 'trace-console',
    total_cases: traceFiles.length,
    success_cases: successCount,
    failed_cases: traceFiles.length - successCount,
    ai_feedback_cases: feedbackCount,
    dry_run: false,
  }

  await writeFile(summaryPath, JSON.stringify(summary, null, 2), 'utf-8')
}

// ═══════════════════════════════════════════════
// 路由：POST /api/upload-test - 上传图片执行测试
// ═══════════════════════════════════════════════
// 接收图片（base64）或已有路径，spawn 脚本执行，返回 jobId
//
// 请求体 JSON:
//   { mode: 'paste' | 'file', imageBase64?: string, existingPath?: string, runId?: string, accountKey?: string }
//
// accountKey 可选，指定后使用该账号的 upload_token 执行测试（如 'test' / 'test2'）
// 未指定时脚本使用默认测试账号 token
//
// 流程:
//   1. paste 模式：保存到 test-cases/_pending/<timestamp>.png
//   2. file 模式 + existingPath 在 test-cases 下：直接用原路径
//   3. file 模式 + existingPath 不在 test-cases 下：复制到 _pending
//   4. spawn 脚本执行（带 --upload-token 如有 accountKey）
//   5. 完成后从 trace 读取域，移动图片到 test-cases/<domain>/<date>/
//   6. 更新 trace 中的路径字段
// ═══════════════════════════════════════════════

const uploadJobs = new Map()

app.post('/api/upload-test', express.json({ limit: '20mb' }), async (req, res) => {
  try {
    const { mode, imageBase64, existingPath, runId, accountKey } = req.body

    if (!mode || (mode !== 'paste' && mode !== 'file')) {
      return sendError(res, 400, 'Invalid mode', 'mode must be "paste" or "file"')
    }

    // 解析 accountKey → upload_token（可选）
    let uploadToken = null
    if (accountKey) {
      if (!accountsConfig || !accountsConfig[accountKey]) {
        return sendError(res, 400, 'Invalid accountKey', `账号 ${accountKey} 不存在`)
      }
      uploadToken = accountsConfig[accountKey].upload_token
    }

    // 生成默认 runId
    const today = new Date().toISOString().slice(0, 10).replace(/-/g, '')
    const finalRunId = runId || `manual-check-${today}`

    let imagePath = ''

    if (mode === 'paste') {
      if (!imageBase64) {
        return sendError(res, 400, 'Missing imageBase64', 'paste mode requires imageBase64')
      }
      // 保存到 _pending 目录
      const pendingDir = path.join(PROJECT_ROOT, 'test-cases', '_pending')
      if (!existsSync(pendingDir)) {
        await mkdir(pendingDir, { recursive: true })
      }
      const timestamp = Date.now()
      imagePath = path.join(pendingDir, `${timestamp}.png`)
      const buffer = Buffer.from(imageBase64, 'base64')
      await writeFile(imagePath, buffer)
    } else {
      // file 模式
      if (!existingPath) {
        return sendError(res, 400, 'Missing existingPath', 'file mode requires existingPath')
      }
      // 安全校验
      const resolved = path.resolve(PROJECT_ROOT, existingPath)
      if (!resolved.startsWith(PROJECT_ROOT)) {
        return sendError(res, 403, 'Path not allowed', 'existingPath must be within project root')
      }
      if (!existsSync(resolved)) {
        return sendError(res, 404, 'File not found', existingPath)
      }

      // 检查是否已在 test-cases 下
      const testCasesDir = path.join(PROJECT_ROOT, 'test-cases')
      if (resolved.startsWith(testCasesDir)) {
        // 直接用原路径
        imagePath = resolved
      } else {
        // 复制到 _pending
        const pendingDir = path.join(PROJECT_ROOT, 'test-cases', '_pending')
        if (!existsSync(pendingDir)) {
          await mkdir(pendingDir, { recursive: true })
        }
        const timestamp = Date.now()
        const ext = path.extname(resolved) || '.png'
        imagePath = path.join(pendingDir, `${timestamp}${ext}`)
        await copyFile(resolved, imagePath)
      }
    }

    // 生成 jobId
    const jobId = `job-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`

    // 初始化任务状态
    uploadJobs.set(jobId, {
      status: 'running',
      step: 'starting',
      imagePath,
      runId: finalRunId,
      startTime: Date.now(),
      output: [],
      error: null,
      traceCaseKey: null,
    })

    // 异步执行脚本
    runTestScript(jobId, imagePath, finalRunId, uploadToken)

    res.json({ jobId, runId: finalRunId })
  } catch (err) {
    sendError(res, 500, 'Upload failed', err.message)
  }
})

// ═══════════════════════════════════════════════
// 路由：GET /api/upload-test/:jobId/status - 轮询任务状态
// ═══════════════════════════════════════════════

app.get('/api/upload-test/:jobId/status', (req, res) => {
  const job = uploadJobs.get(req.params.jobId)
  if (!job) {
    return sendError(res, 404, 'Job not found', req.params.jobId)
  }
  res.json({
    status: job.status,
    step: job.step,
    runId: job.runId,
    elapsed: Date.now() - job.startTime,
    output: job.output.slice(-10),
    error: job.error,
    traceCaseKey: job.traceCaseKey,
  })
})

// ═══════════════════════════════════════════════
// 加载 .env.local（上传测试功能需要）
// ═══════════════════════════════════════════════
// 安全说明：server 自身的 API 路由不使用这些环境变量，
// 仅在 spawn test-ingest-receipt.mjs 时注入到子进程环境，
// 让脚本能读取 VITE_SUPABASE_URL 等配置。
// ═══════════════════════════════════════════════

function loadEnvLocal() {
  const envPath = path.join(PROJECT_ROOT, '.env.local')
  if (!existsSync(envPath)) return {}
  const content = require('fs').readFileSync(envPath, 'utf-8')
  const env = {}
  for (const line of content.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eqIdx = trimmed.indexOf('=')
    if (eqIdx < 0) continue
    const key = trimmed.slice(0, eqIdx).trim()
    let val = trimmed.slice(eqIdx + 1).trim()
    // 去除引号
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1)
    }
    env[key] = val
  }
  return env
}

const envLocal = loadEnvLocal()

// ═══════════════════════════════════════════════
// Supabase 客户端 & 账号解析（远程模式）
// ═══════════════════════════════════════════════

const SUPABASE_URL = envLocal.VITE_SUPABASE_URL || envLocal.SUPABASE_URL || null
const SUPABASE_SERVICE_ROLE_KEY = envLocal.SUPABASE_SERVICE_ROLE_KEY || null

let supabaseAdmin = null
if (SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY) {
  supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    // Node.js 20 无原生 WebSocket，传入 ws 作为 realtime transport
    // 我们只用 PostgREST + Storage，不订阅 realtime 频道，但构造函数仍需要 WebSocket 实现
    realtime: { transport: WebSocket },
  })
} else {
  console.warn('[远程模式] 未找到 SUPABASE_URL 或 SUPABASE_SERVICE_ROLE_KEY，远程查询功能不可用')
}

/**
 * 加载账号配置文件
 * @returns {Object|null} 账号配置
 */
function loadAccounts() {
  const accountsPath = path.join(__dirname, 'accounts.json')
  if (!existsSync(accountsPath)) {
    return null
  }
  try {
    const content = require('fs').readFileSync(accountsPath, 'utf-8')
    return JSON.parse(content)
  } catch (err) {
    console.error('[账号配置] 解析失败:', err.message)
    return null
  }
}

const accountsConfig = loadAccounts()

// 账号解析缓存：accountKey → { user_id, label, upload_token, resolved_at }
const accountCache = new Map()
const ACCOUNT_CACHE_TTL = 5 * 60 * 1000 // 5 分钟

/**
 * 通过 upload_token 解析账号的 user_id
 * 使用 service_role 查询 user_configs 表，结果缓存 5 分钟
 * @param {string} accountKey - 账号 key（如 'test' / 'test2'）
 * @returns {Promise<{user_id: string, label: string, upload_token: string}|null>}
 */
async function resolveAccount(accountKey) {
  if (!accountsConfig || !accountsConfig[accountKey]) {
    return null
  }
  const account = accountsConfig[accountKey]

  // 检查缓存
  const cached = accountCache.get(accountKey)
  if (cached && Date.now() - cached.resolved_at < ACCOUNT_CACHE_TTL) {
    return cached
  }

  if (!supabaseAdmin) {
    throw new Error('Supabase 客户端未初始化，无法解析账号')
  }

  // 通过 upload_token 查 user_configs 表获取 user_id
  const { data, error } = await supabaseAdmin
    .from('user_configs')
    .select('user_id, is_active')
    .eq('upload_token', account.upload_token)
    .eq('is_active', true)
    .limit(1)

  if (error) {
    throw new Error(`查询 user_configs 失败: ${error.message}`)
  }
  if (!data || data.length === 0) {
    throw new Error(`upload_token 无效或已停用: ${accountKey}`)
  }

  const resolved = {
    user_id: data[0].user_id,
    label: account.label,
    upload_token: account.upload_token,
    resolved_at: Date.now(),
  }
  accountCache.set(accountKey, resolved)
  return resolved
}

// ═══════════════════════════════════════════════
// 异步执行测试脚本
// ═══════════════════════════════════════════════

async function runTestScript(jobId, imagePath, runId, uploadToken = null) {
  const job = uploadJobs.get(jobId)
  const scriptPath = path.join(PROJECT_ROOT, 'scripts', 'test-ingest-receipt.mjs')
  const relativeImagePath = path.relative(PROJECT_ROOT, imagePath).replace(/\\/g, '/')

  // 合并环境变量：process.env + .env.local（.env.local 优先）
  const childEnv = { ...process.env, ...envLocal }

  // 构建命令参数：--upload-token 仅在指定账号时传入
  const scriptArgs = [scriptPath, '--image', relativeImagePath, '--run-id', runId]
  if (uploadToken) {
    scriptArgs.push('--upload-token', uploadToken)
  }

  const child = spawn('node', scriptArgs, {
    cwd: PROJECT_ROOT,
    env: childEnv,
    shell: false,
  })

  child.stdout.on('data', (data) => {
    const text = data.toString().trim()
    if (text) {
      job.output.push(text)
      // 更新步骤
      if (text.includes('上传中') || text.includes('uploading')) job.step = 'uploading'
      else if (text.includes('识别中') || text.includes('AI')) job.step = 'recognizing'
      else if (text.includes('写入') || text.includes('trace')) job.step = 'saving'
    }
  })

  child.stderr.on('data', (data) => {
    const text = data.toString().trim()
    if (text) job.output.push(`[stderr] ${text}`)
  })

  child.on('close', async (code) => {
    if (code !== 0) {
      job.status = 'error'
      job.step = 'failed'
      job.error = `脚本退出码 ${code}`
      return
    }

    try {
      job.step = 'moving'
      // 从 trace 中读取域信息，移动图片到最终目录
      const traceResult = await findAndProcessTrace(runId, relativeImagePath)
      job.traceCaseKey = traceResult.caseKey
      job.status = 'done'
      job.step = 'completed'
    } catch (err) {
      job.status = 'error'
      job.step = 'trace-post-process-failed'
      job.error = `脚本成功但后处理失败: ${err.message}`
    }
  })
}

// ═══════════════════════════════════════════════
// 从 trace 中读取域，移动图片，更新路径
// ═══════════════════════════════════════════════

async function findAndProcessTrace(runId, originalRelativePath) {
  const runDir = path.join(PROJECT_ROOT, 'test-results', runId)
  if (!existsSync(runDir)) {
    throw new Error(`Run directory not found: ${runDir}`)
  }

  // 遍历 run 目录找到匹配的 trace.json
  const traceFile = await findTraceByImagePath(runDir, originalRelativePath)
  if (!traceFile) {
    throw new Error(`Trace file not found for image: ${originalRelativePath}`)
  }

  const { data: traceData } = await safeReadJson(traceFile)
  if (!traceData) {
    throw new Error(`Failed to parse trace: ${traceFile}`)
  }

  // 获取域：优先从 model_raw 的 extracted_json 中取 domain_key/record_type
  // test_case_domain 在单图模式下是 "single"，不是实际识别的域
  let domain = 'uncertain'
  const modelRaw = traceData.artifacts?.model_raw?.extracted_json
  let parsedModel = null
  if (modelRaw) {
    try { parsedModel = typeof modelRaw === 'string' ? JSON.parse(modelRaw) : modelRaw } catch {}
  }
  domain = parsedModel?.domain_key
    || parsedModel?.record_type
    || traceData.artifacts?.model_raw?.text && (() => {
      try {
        const t = traceData.artifacts.model_raw.text
        const m = t.match(/"domain_key"\s*:\s*"([^"]+)"/)
        return m ? m[1] : null
      } catch { return null }
    })()
    || 'uncertain'

  // 确定最终域目录名
  const domainDir = (domain && domain !== 'uncertain' && domain !== 'unknown' && domain !== 'single') ? domain : 'uncertain'

  // 获取日期
  const today = new Date().toISOString().slice(0, 10)
  const finalDir = path.join(PROJECT_ROOT, 'test-cases', domainDir, today)

  // 原图片路径
  const originalAbsPath = path.join(PROJECT_ROOT, originalRelativePath)
  const fileName = path.basename(originalAbsPath)

  // 如果图片在 _pending 下，移动到最终目录
  // 如果图片已在 test-cases 下，不移动
  const pendingDir = path.join(PROJECT_ROOT, 'test-cases', '_pending')
  let finalRelativePath = originalRelativePath

  if (originalAbsPath.startsWith(pendingDir)) {
    if (!existsSync(finalDir)) {
      await mkdir(finalDir, { recursive: true })
    }
    const finalAbsPath = path.join(finalDir, fileName)
    await rename(originalAbsPath, finalAbsPath)
    finalRelativePath = path.relative(PROJECT_ROOT, finalAbsPath).replace(/\\/g, '/')

    // 更新 trace 中的路径
    traceData.case = traceData.case || {}
    traceData.case.test_case_file = finalRelativePath
    traceData.case.image_relative_path = finalRelativePath
    // 更新 steps 中可能引用图片路径的地方
    if (traceData.steps) {
      for (const step of traceData.steps) {
        if (step.input_snapshot?.image_relative_path === originalRelativePath) {
          step.input_snapshot.image_relative_path = finalRelativePath
        }
        // 也匹配只含文件名的情况
        if (step.input_snapshot?.image_relative_path === path.basename(originalRelativePath)) {
          step.input_snapshot.image_relative_path = finalRelativePath
        }
      }
    }

    await writeFile(traceFile, JSON.stringify(traceData, null, 2), 'utf-8')
  }

  // 计算 caseKey
  const traceRelPath = path.relative(path.join(PROJECT_ROOT, 'test-results', runId), traceFile).replace(/\\/g, '/')
  const caseKey = traceRelPath.replace(/\.trace\.json$/, '')

  return { caseKey, domain: domainDir }
}

// 递归查找匹配 image_relative_path 的 trace.json
async function findTraceByImagePath(dir, targetPath) {
  const entries = await readdir(dir, { withFileTypes: true })
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      const found = await findTraceByImagePath(fullPath, targetPath)
      if (found) return found
    } else if (entry.name.endsWith('.trace.json')) {
      const { data } = await safeReadJson(fullPath)
      if (!data) continue
      // 匹配 image_relative_path 或 test_case_file（可能只含文件名）
      const imgPath = data.case?.image_relative_path || ''
      const caseFile = data.case?.test_case_file || ''
      // 归一化比较：都转成正斜杠
      const targetNorm = targetPath.replace(/\\/g, '/')
      if (imgPath === targetNorm
        || caseFile === targetNorm
        || caseFile === path.basename(targetNorm)
        || imgPath === path.basename(targetNorm)) {
        return fullPath
      }
    }
  }
  return null
}

// ═══════════════════════════════════════════════
// 远程模式：账号列表 & 查询 API
// ═══════════════════════════════════════════════

/**
 * GET /api/accounts - 列出可用账号（仅 key + label，不含 token）
 */
app.get('/api/accounts', (req, res) => {
  if (!accountsConfig) {
    return sendError(res, 500, 'Accounts config not found', 'accounts.json 不存在，请参考 accounts.example.json 创建')
  }
  const list = Object.entries(accountsConfig).map(([key, val]) => ({
    key,
    label: val.label || key,
  }))
  res.json({ accounts: list })
})

/**
 * 计算上海时区某天的 UTC 时间范围
 * Shanghai = UTC+8，无夏令时
 * @param {string} dateStr - YYYY-MM-DD
 * @returns {{startUtc: string, endUtc: string}}
 */
function shanghaiDateToUtcRange(dateStr) {
  const start = new Date(dateStr + 'T00:00:00+08:00')
  const end = new Date(dateStr + 'T23:59:59+08:00')
  return {
    startUtc: start.toISOString(),
    endUtc: end.toISOString(),
  }
}

/**
 * 判断图片状态
 * @param {string|null} imageUrl
 * @returns {'available'|'no_image_url'|'expired'}
 */
function determineImageStatus(imageUrl) {
  if (!imageUrl) return 'no_image_url'
  if (imageUrl.startsWith('tmp/')) return 'expired'
  return 'available'
}

/**
 * GET /api/remote/accounts/:accountKey/days - 查询有记录的日期列表
 * 拉取最近 500 条记录，在 Node 里按 Asia/Shanghai 分组
 */
app.get('/api/remote/accounts/:accountKey/days', async (req, res) => {
  try {
    const account = await resolveAccount(req.params.accountKey)
    if (!account) {
      return sendError(res, 404, 'Account not found', `账号 ${req.params.accountKey} 不存在`)
    }
    if (!supabaseAdmin) {
      return sendError(res, 503, 'Supabase not initialized', 'service_role key 未配置')
    }

    // 兼容历史记录：EF 修复前的记录 user_id 为 null，同时匹配 null
    const { data, error } = await supabaseAdmin
      .from('ai_recognition_logs')
      .select('created_at, status')
      .or(`user_id.eq.${account.user_id},user_id.is.null`)
      .order('created_at', { ascending: false })
      .limit(500)

    if (error) {
      return sendError(res, 502, 'Supabase query failed', error.message)
    }

    // 在 Node 里按 Asia/Shanghai 日期分组
    const dayMap = new Map()
    for (const row of data || []) {
      const date = toShanghaiDate(row.created_at)
      if (!dayMap.has(date)) {
        dayMap.set(date, { date, count: 0, success: 0, error: 0 })
      }
      const day = dayMap.get(date)
      day.count++
      if (row.status === 'success') day.success++
      else if (row.status === 'error' || row.status === 'ai_error' || row.status === 'db_error') day.error++
    }

    const days = Array.from(dayMap.values()).sort((a, b) => b.date.localeCompare(a.date))
    res.json({ days })
  } catch (err) {
    sendError(res, 500, 'Remote query failed', err.message)
  }
})

/**
 * GET /api/remote/accounts/:accountKey/days/:date/traces - 查询某天的记录列表
 * date 格式：YYYY-MM-DD（上海时区）
 */
app.get('/api/remote/accounts/:accountKey/days/:date/traces', async (req, res) => {
  try {
    const { accountKey, date } = req.params
    const account = await resolveAccount(accountKey)
    if (!account) {
      return sendError(res, 404, 'Account not found', `账号 ${accountKey} 不存在`)
    }

    // 验证日期格式
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return sendError(res, 400, 'Invalid date', '日期格式应为 YYYY-MM-DD')
    }

    const { startUtc, endUtc } = shanghaiDateToUtcRange(date)

    const { data, error } = await supabaseAdmin
      .from('ai_recognition_logs')
      .select('id, created_at, image_url, image_type, record_type, status, confidence, duration_ms, model_name, target_table, target_id, raw_response, ai_response')
      .or(`user_id.eq.${account.user_id},user_id.is.null`)
      .gte('created_at', startUtc)
      .lte('created_at', endUtc)
      .order('created_at', { ascending: false })
      .limit(50)

    if (error) {
      return sendError(res, 502, 'Supabase query failed', error.message)
    }

    // 查询本地是否有点评
    const runId = `remote-${date}`
    const reviewsDir = path.join(TEST_RESULTS_DIR, runId)
    const reviewedCaseKeys = new Set()
    if (existsSync(reviewsDir)) {
      const reviewFiles = await findFilesRecursive(reviewsDir, '.review.json')
      for (const rf of reviewFiles) {
        const { data: reviewData } = await safeReadJson(path.join(reviewsDir, rf))
        if (reviewData?.case_key) {
          reviewedCaseKeys.add(reviewData.case_key)
        }
      }
    }

    const traces = (data || []).map(row => {
      const caseKey = `remote/${date}/${row.id}`
      // record_type 可能为 null（EF 修复前的历史记录），从 raw_response 中补取
      let recordType = row.record_type
      let imageType = row.image_type
      if (!recordType || !imageType) {
        const rawDebug = parseRawDebug(row.raw_response)
        const aiResp = rawDebug || row.ai_response
        if (aiResp) {
          if (!recordType) recordType = aiResp.record_type || aiResp.domain_key || null
          if (!imageType) imageType = aiResp.image_type || null
        }
      }
      return {
        case_key: caseKey,
        trace_id: row.id,
        ai_log_id: row.id,
        file: null,
        domain: recordType || 'unknown',
        record_type: recordType || null,
        image_type: imageType || null,
        date,
        status: row.status,
        elapsed_ms: row.duration_ms ?? null,
        has_ai_feedback: false,
        image_relative_path: row.image_url || null,
        image_status: determineImageStatus(row.image_url),
        has_review: reviewedCaseKeys.has(caseKey),
        review_ratings: null,
        is_remote: true,
      }
    })

    res.json({ traces })
  } catch (err) {
    sendError(res, 500, 'Remote query failed', err.message)
  }
})

/**
 * GET /api/remote/accounts/:accountKey/days/:date/traces/:logId - 查询单条记录详情
 * 返回 trace 兼容格式（支持三级降级）
 */
app.get('/api/remote/accounts/:accountKey/days/:date/traces/:logId', async (req, res) => {
  try {
    const { accountKey, date, logId } = req.params
    const account = await resolveAccount(accountKey)
    if (!account) {
      return sendError(res, 404, 'Account not found', `账号 ${accountKey} 不存在`)
    }

    const { data, error } = await supabaseAdmin
      .from('ai_recognition_logs')
      .select('*')
      .eq('id', logId)
      .or(`user_id.eq.${account.user_id},user_id.is.null`)
      .limit(1)

    if (error) {
      return sendError(res, 502, 'Supabase query failed', error.message)
    }
    if (!data || data.length === 0) {
      return sendError(res, 404, 'Record not found', `logId ${logId} 不存在或不属于该账号`)
    }

    const logRow = data[0]
    const trace = buildTraceFromAiLog(logRow, { runId: `remote-${date}`, dateStr: date, accountKey })

    // 查询本地点评
    const caseKey = `remote/${date}/${logId}`
    const reviewPath = path.join(TEST_RESULTS_DIR, `remote-${date}`, 'single', logRow.record_type || 'unknown', date, `${logId}.review.json`)
    if (existsSync(reviewPath)) {
      const { data: reviewData } = await safeReadJson(reviewPath)
      if (reviewData) {
        trace.review = reviewData
      }
    }

    res.json(trace)
  } catch (err) {
    sendError(res, 500, 'Remote query failed', err.message)
  }
})

/**
 * GET /api/remote/images?logId=...&accountKey=... - 下载远程图片
 * 按 logId 查询 image_url，校验 user_id 归属后从 Storage 下载
 */
app.get('/api/remote/images', async (req, res) => {
  try {
    const { logId, accountKey } = req.query
    if (!logId || !accountKey) {
      return sendError(res, 400, 'Missing parameters', '需要 logId 和 accountKey')
    }

    const account = await resolveAccount(accountKey)
    if (!account) {
      return sendError(res, 404, 'Account not found', `账号 ${accountKey} 不存在`)
    }

    // 按 logId 查询，校验归属（兼容历史 null user_id 记录）
    const { data, error } = await supabaseAdmin
      .from('ai_recognition_logs')
      .select('image_url, user_id')
      .eq('id', logId)
      .or(`user_id.eq.${account.user_id},user_id.is.null`)
      .limit(1)

    if (error) {
      return sendError(res, 502, 'Supabase query failed', error.message)
    }
    if (!data || data.length === 0) {
      return res.status(404).json({ error: '图片记录不存在或不属于该账号', reason: 'not_found' })
    }

    const imageUrl = data[0].image_url
    if (!imageUrl) {
      return res.status(404).json({ error: '原图未保留', reason: 'no_image_url' })
    }
    if (imageUrl.startsWith('tmp/')) {
      // tmp/ 路径可能已被清理，尝试下载但允许 404
    }

    // 本地缓存
    const cacheDir = path.join(TEST_CASES_DIR, '_remote_cache')
    if (!existsSync(cacheDir)) {
      await mkdir(cacheDir, { recursive: true })
    }
    const ext = path.extname(imageUrl) || '.jpg'
    const cachePath = path.join(cacheDir, `${logId}${ext}`)

    // 如果已缓存，直接返回
    if (existsSync(cachePath)) {
      const buffer = await readFile(cachePath)
      const mime = ext === '.png' ? 'image/png' : ext === '.webp' ? 'image/webp' : 'image/jpeg'
      res.setHeader('Content-Type', mime)
      res.setHeader('Cache-Control', 'private, max-age=3600')
      return res.end(buffer)
    }

    // 从 Supabase Storage 下载
    const { data: fileData, error: downloadError } = await supabaseAdmin
      .storage
      .from('receipt-images')
      .download(imageUrl)

    if (downloadError) {
      return res.status(404).json({ error: '图片下载失败', reason: imageUrl.startsWith('tmp/') ? 'expired' : 'not_found', detail: downloadError.message })
    }

    // 缓存到本地
    const buffer = Buffer.from(await fileData.arrayBuffer())
    await writeFile(cachePath, buffer)

    const mime = ext === '.png' ? 'image/png' : ext === '.webp' ? 'image/webp' : 'image/jpeg'
    res.setHeader('Content-Type', mime)
    res.setHeader('Cache-Control', 'private, max-age=3600')
    res.end(buffer)
  } catch (err) {
    sendError(res, 500, 'Image download failed', err.message)
  }
})

/**
 * GET /api/remote/accounts/:accountKey/memory - 查询 companion 记忆上下文
 */
app.get('/api/remote/accounts/:accountKey/memory', async (req, res) => {
  try {
    const account = await resolveAccount(req.params.accountKey)
    if (!account) {
      return sendError(res, 404, 'Account not found', `账号 ${req.params.accountKey} 不存在`)
    }
    if (!supabaseAdmin) {
      return sendError(res, 503, 'Supabase not initialized', 'service_role key 未配置')
    }

    const { data, error } = await supabaseAdmin
      .rpc('get_companion_context', { p_user_id: account.user_id })

    if (error) {
      return sendError(res, 502, 'RPC call failed', error.message)
    }

    res.json(data || { settings: { enabled: false }, short_term: {}, long_term: [] })
  } catch (err) {
    sendError(res, 500, 'Memory query failed', err.message)
  }
})

// ═══════════════════════════════════════════════
// 健康检查
// ═══════════════════════════════════════════════

app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'trace-console-server',
    port: PORT,
    project_root: PROJECT_ROOT,
    test_results_exists: existsSync(TEST_RESULTS_DIR),
    test_cases_exists: existsSync(TEST_CASES_DIR),
    remote_enabled: Boolean(supabaseAdmin),
    accounts_loaded: Boolean(accountsConfig),
  })
})

// ═══════════════════════════════════════════════
// 启动服务
// ═══════════════════════════════════════════════

app.listen(PORT, HOST, () => {
  console.log('═══════════════════════════════════════════════')
  console.log('  AI 识别链路追踪台 - 本地服务')
  console.log('═══════════════════════════════════════════════')
  console.log(`  监听地址:  http://${HOST}:${PORT}`)
  console.log(`  项目根目录: ${PROJECT_ROOT}`)
  console.log(`  test-results: ${existsSync(TEST_RESULTS_DIR) ? '存在' : '不存在'}`)
  console.log(`  test-cases:   ${existsSync(TEST_CASES_DIR) ? '存在' : '不存在'}`)
  console.log(`  远程模式:     ${supabaseAdmin ? '可用' : '不可用（未配置 service_role key）'}`)
  console.log(`  账号配置:     ${accountsConfig ? Object.keys(accountsConfig).length + ' 个' : '未加载'}`)
  console.log('═══════════════════════════════════════════════')
  console.log('')
  console.log('可用接口:')
  console.log(`  GET  /api/health`)
  console.log(`  GET  /api/accounts                          列出可用账号`)
  console.log(`  GET  /api/runs                              列出本地批次`)
  console.log(`  GET  /api/runs/:runId/traces/:caseKey       读取本地 trace`)
  console.log(`  GET  /api/images?path=...                   读取本地图片`)
  console.log(`  POST /api/upload-test                       上传测试`)
  console.log(`  GET  /api/remote/accounts/:key/days          远程日期列表`)
  console.log(`  GET  /api/remote/accounts/:key/days/:date/traces       远程记录列表`)
  console.log(`  GET  /api/remote/accounts/:key/days/:date/traces/:logId 远程记录详情`)
  console.log(`  GET  /api/remote/images?logId=...           下载远程图片`)
  console.log(`  GET  /api/remote/accounts/:key/memory       查询记忆上下文`)
  console.log('')
})

// 优雅退出
process.on('SIGINT', () => {
  console.log('\n服务已停止')
  process.exit(0)
})
process.on('SIGTERM', () => {
  console.log('\n服务已停止')
  process.exit(0)
})
