/**
 * ═══════════════════════════════════════════════
 * AI 识别链路追踪台 - 本地文件读取服务
 * ═══════════════════════════════════════════════
 *
 * 职责：
 *   只读本地 test-results/ 和 test-cases/ 目录，为追踪台前端提供数据 API。
 *
 * 安全约束：
 *   - 只监听 127.0.0.1:5181，不暴露外网
 *   - 图片接口只允许 test-cases/ 目录
 *   - 路径安全校验：拒绝 .. 和绝对路径
 *   - 不读取任何 .env 文件，不需要任何密钥
 *   - 不执行任何线上调用
 *
 * API 路由：
 *   GET /api/runs                              列出所有批次
 *   GET /api/runs/:runId/summary               读取批次 summary.json
 *   GET /api/runs/:runId/traces                列出批次内所有 trace 摘要
 *   GET /api/runs/:runId/traces/:caseKey       读取单个完整 trace.json
 *   GET /api/images?path=<relative-path>       读取测试图片（仅限 test-cases/）
 */

import express from 'express'
import { readFile, readdir, stat } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

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
  console.log('═══════════════════════════════════════════════')
  console.log('')
  console.log('可用接口:')
  console.log(`  GET http://${HOST}:${PORT}/api/health`)
  console.log(`  GET http://${HOST}:${PORT}/api/runs`)
  console.log(`  GET http://${HOST}:${PORT}/api/runs/:runId/summary`)
  console.log(`  GET http://${HOST}:${PORT}/api/runs/:runId/traces`)
  console.log(`  GET http://${HOST}:${PORT}/api/runs/:runId/traces/:caseKey`)
  console.log(`  GET http://${HOST}:${PORT}/api/images?path=test-cases/...`)
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
