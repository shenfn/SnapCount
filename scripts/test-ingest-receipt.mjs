import { mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createClient } from '@supabase/supabase-js'

// 默认 upload_token（用于本地测试，Edge Function 会自动反查 user_id）
// 如需直接传 user_id，使用 --user-id 参数（仅限调试）
const DEFAULT_UPLOAD_TOKEN = '0a552a27-0b64-456e-a5b3-e50e261d2e4f'
const SUPPORTED_IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'])

const args = process.argv.slice(2)
const flags = {}

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i]
  if (arg === '--help' || arg === '-h') flags.help = true
  else if (arg === '--dry-run') flags.dryRun = true
  else if (arg === '--text') flags.responseMode = 'text'
  else if (arg === '--json') flags.responseMode = 'json'
  else if (arg.startsWith('--image=')) flags.image = arg.slice('--image='.length)
  else if (arg === '--image') flags.image = args[++i]
  else if (arg.startsWith('--dir=')) flags.dir = arg.slice('--dir='.length)
  else if (arg === '--dir') flags.dir = args[++i]
  else if (arg.startsWith('--user-id=')) flags.userId = arg.slice('--user-id='.length)
  else if (arg === '--user-id') flags.userId = args[++i]
  else if (arg.startsWith('--upload-token=')) flags.uploadToken = arg.slice('--upload-token='.length)
  else if (arg === '--upload-token') flags.uploadToken = args[++i]
  else if (arg.startsWith('--url=')) flags.url = arg.slice('--url='.length)
  else if (arg === '--url') flags.url = args[++i]
  else if (arg.startsWith('--endpoint=')) flags.url = arg.slice('--endpoint='.length)
  else if (arg === '--endpoint') flags.url = args[++i]
  else if (arg.startsWith('--mode=')) flags.responseMode = arg.slice('--mode='.length)
  else if (arg.startsWith('--output-dir=')) flags.outputDir = arg.slice('--output-dir='.length)
  else if (arg === '--output-dir') flags.outputDir = args[++i]
  else if (arg.startsWith('--run-id=')) flags.runId = arg.slice('--run-id='.length)
  else if (arg === '--run-id') flags.runId = args[++i]
  else if (arg.startsWith('--domain=')) flags.domain = arg.slice('--domain='.length)
  else if (arg === '--domain') flags.domain = args[++i]
  else if (arg.startsWith('--capture-kind=')) flags.captureKind = arg.slice('--capture-kind='.length)
  else if (arg === '--capture-kind') flags.captureKind = args[++i]
  else if (arg.startsWith('--source-app=')) flags.sourceApp = arg.slice('--source-app='.length)
  else if (arg === '--source-app') flags.sourceApp = args[++i]
  else if (arg === '--no-log-enrich') flags.noLogEnrich = true
  else if (!flags.image && !flags.dir) flags.image = arg
}

function printHelp() {
  console.log(`
本地回放 AI 截图识别链路

用法:
  npm run test:receipt -- --image ./test.jpg
  npm run test:receipt -- --image ./test.jpg --user-id <uuid>
  npm run test:receipt -- --dir ./test-cases
  npm run test:receipt -- --dir ./test-cases --domain expense
  npm run test:receipt -- --dir ./test-cases --dry-run

选项:
  --image <path>         测试单张图片
  --dir <path>           批量扫描测试目录
  --domain <name>        仅跑指定域，例如 expense
  --user-id <uuid>       指定用户 ID，默认使用测试账号
  --upload-token <t>     使用上传 token 识别用户，可选
  --url <endpoint>       覆盖函数地址，默认读取 VITE_SUPABASE_URL/functions/v1/ingest-receipt
  --output-dir <path>    覆盖结果输出目录，默认 ./test-results
  --run-id <id>          指定测试批次 ID，默认自动生成
  --capture-kind <kind>  指定上传来源类型，默认 test-batch；可用 photo/screenshot/food 等
  --source-app <name>    指定 source_app，默认 codex-local-validation
  --no-log-enrich        不读取 ai_recognition_logs，仅生成接口响应级 trace
  --text                 请求 text 响应模式
  --json                 请求 json 响应模式，默认
  --dry-run              只打印将要请求的目标和图片信息，不上传
`)
}

export function requireEnv(name) {
  const value = process.env[name]
  if (!value) throw new Error(`Missing ${name}. 请先配置 .env.local 或环境变量。`)
  return value
}

export function compactJson(value) {
  return JSON.stringify(value, null, 2)
}

export function guessMime(filePath) {
  const ext = path.extname(filePath).toLowerCase()
  if (ext === '.png') return 'image/png'
  if (ext === '.webp') return 'image/webp'
  if (ext === '.heic' || ext === '.heif') return 'image/heic'
  return 'image/jpeg'
}

export function toRunTimestamp(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z').replace(/:/g, '-')
}

export function buildDefaultRunId() {
  return `local-${toRunTimestamp().replace('T', '-').replace('Z', '')}`
}

export function summarizeResult(result) {
  return {
    status: result.status ?? '-',
    record_type: result.record_type ?? result.data?.type ?? '-',
    id: result.id ?? result.data?.id ?? '-',
    trace_id: result.trace_id ?? null,
    ai_log_id: result.ai_log_id ?? null,
    vision_mode: result.vision_mode ?? null,
    photo_quality_mode: result.photo_quality_mode ?? null,
    model_provider: result.model_provider ?? null,
    model_name: result.model_name ?? null,
    capture_kind: result.capture_kind ?? null,
    source_app: result.source_app ?? null,
    message: result.message ?? '-',
    notification: result.notification ?? result.notification_text ?? '-',
    companion_message: result.companion_message ?? '-',
    ai_feedback: result.ai_feedback ?? null,
    time_context: result.time_context ?? null,
    error: result.error ?? null,
  }
}

function printSingleSummary(summary) {
  console.log('')
  console.log('识别结果摘要')
  console.log('----------------')
  console.log(`status: ${summary.status}`)
  console.log(`record_type: ${summary.record_type}`)
  console.log(`id: ${summary.id}`)
  console.log(`trace_id: ${summary.trace_id ?? '-'}`)
  console.log(`ai_log_id: ${summary.ai_log_id ?? '-'}`)
  console.log(`vision_mode: ${summary.vision_mode ?? '-'}`)
  console.log(`model: ${summary.model_provider ?? '-'}/${summary.model_name ?? '-'}`)
  console.log(`message: ${summary.message}`)
  console.log(`notification: ${summary.notification}`)
  console.log(`companion_message: ${summary.companion_message}`)
  if (summary.ai_feedback) {
    console.log('ai_feedback:')
    console.log(compactJson(summary.ai_feedback))
  } else {
    console.log('ai_feedback: null')
  }
  if (summary.time_context) {
    console.log('time_context:')
    console.log(compactJson(summary.time_context))
  }
  if (summary.error) {
    console.log(`error: ${summary.error}`)
  }
}

function resolveEndpoint() {
  return (flags.url || `${requireEnv('VITE_SUPABASE_URL').replace(/\/$/, '')}/functions/v1/ingest-receipt`).trim()
}

function resolveAnonKey() {
  return requireEnv('VITE_SUPABASE_ANON_KEY')
}

function resolveUserId() {
  // --user-id 显式指定（仅限调试），优先使用
  if (flags.userId) return flags.userId
  return null
}

function resolveUploadToken() {
  // --upload-token 显式指定，或环境变量，或默认值
  return flags.uploadToken || process.env.TEST_RECEIPT_UPLOAD_TOKEN || DEFAULT_UPLOAD_TOKEN
}

function normalizeResponseMode() {
  return flags.responseMode === 'text' ? 'text' : 'json'
}

function resolveCaptureKind() {
  return (flags.captureKind || process.env.TEST_RECEIPT_CAPTURE_KIND || 'test-batch').trim()
}

function resolveSourceApp() {
  return (flags.sourceApp || process.env.TEST_RECEIPT_SOURCE_APP || 'codex-local-validation').trim()
}

function resolveLogEnrichKey() {
  return process.env.TEST_RECEIPT_LOG_KEY
    || process.env.TEST_SUPABASE_SERVICE_ROLE_KEY
    || process.env.SUPABASE_SERVICE_ROLE_KEY
    || null
}

function trimTrailingSlash(value) {
  return value.replace(/\/$/, '')
}

async function resolveLogUrl(endpoint) {
  const explicitUrl = process.env.TEST_SUPABASE_URL
    || process.env.SUPABASE_URL
    || process.env.SUPABASE_PROJECT_URL

  if (explicitUrl) return trimTrailingSlash(explicitUrl.trim())

  try {
    const parsedEndpoint = new URL(endpoint)
    if (parsedEndpoint.hostname.endsWith('.supabase.co')) {
      return parsedEndpoint.origin
    }
  } catch {
    // Fall through to local project-ref discovery.
  }

  try {
    const projectRef = (await readFile(path.join(process.cwd(), 'supabase', '.temp', 'project-ref'), 'utf8')).trim()
    if (projectRef) return `https://${projectRef}.supabase.co`
  } catch {
    // Log enrichment is optional; keep the upload flow usable without local Supabase metadata.
  }

  return null
}

async function createLogClient({ endpoint, key }) {
  if (!key) return null
  const url = await resolveLogUrl(endpoint)
  if (!url) return null
  return createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  })
}

async function fetchAiLogById(logClient, aiLogId) {
  if (!logClient || !aiLogId) return null
  const { data, error } = await logClient
    .from('ai_recognition_logs')
    .select('*')
    .eq('id', aiLogId)
    .maybeSingle()
  if (error) {
    return {
      error: error.message,
      row: null,
    }
  }
  return {
    error: null,
    row: data || null,
  }
}

export function relativeFromRoot(targetPath) {
  return path.relative(process.cwd(), targetPath).split(path.sep).join('/')
}

export function normalizePathForReport(targetPath) {
  return targetPath.split(path.sep).join('/')
}

export async function ensureDir(targetPath) {
  await mkdir(targetPath, { recursive: true })
}

export async function collectImageFiles(rootDir, domainFilter) {
  const results = []

  async function walk(currentDir, domainHint = null, dateHint = null) {
    const entries = await readdir(currentDir, { withFileTypes: true })
    for (const entry of entries) {
      const fullPath = path.join(currentDir, entry.name)
      if (entry.isDirectory()) {
        const nextDomain = domainHint ?? (path.dirname(fullPath) === rootDir ? entry.name : domainHint)
        const nextDate = nextDomain && path.dirname(fullPath) === path.join(rootDir, nextDomain) ? entry.name : dateHint
        await walk(fullPath, nextDomain, nextDate)
        continue
      }
      const ext = path.extname(entry.name).toLowerCase()
      if (!SUPPORTED_IMAGE_EXTENSIONS.has(ext)) continue
      const rel = path.relative(rootDir, fullPath).split(path.sep)
      const inferredDomain = domainHint || rel[0] || 'unknown'
      if (domainFilter && inferredDomain !== domainFilter) continue
      const inferredDate = dateHint || rel[1] || null
      results.push({
        imagePath: fullPath,
        domain: inferredDomain,
        date: inferredDate,
        fileName: entry.name,
      })
    }
  }

  await walk(rootDir)
  results.sort((a, b) => a.imagePath.localeCompare(b.imagePath, 'en'))
  return results
}

export async function buildCaseList({ image, dir, domain }) {
  if (image && dir) throw new Error('不能同时使用 --image 和 --dir。')
  if (!image && !dir) throw new Error('请提供 --image 或 --dir。')

  if (image) {
    const imagePath = path.resolve(image)
    const info = await stat(imagePath)
    if (!info.isFile()) throw new Error(`图片路径不是文件: ${imagePath}`)
    return [{
      imagePath,
      domain: domain || 'single',
      date: null,
      fileName: path.basename(imagePath),
    }]
  }

  const dirPath = path.resolve(dir)
  const info = await stat(dirPath)
  if (!info.isDirectory()) throw new Error(`目录路径不是文件夹: ${dirPath}`)
  const cases = await collectImageFiles(dirPath, domain || null)
  if (!cases.length) throw new Error(`目录下未找到可测试图片: ${dirPath}`)
  return cases
}

export function buildCaseMeta(testCase, runId) {
  return {
    test_run_id: runId,
    test_case_domain: testCase.domain || 'unknown',
    test_case_date: testCase.date || null,
    test_case_file: testCase.fileName,
  }
}

export async function executeCase(testCase, context) {
  const info = await stat(testCase.imagePath)
  const mime = guessMime(testCase.imagePath)
  const userId = context.userId
  const responseMode = context.responseMode
  const caseMeta = buildCaseMeta(testCase, context.runId)
  const relativeImage = relativeFromRoot(testCase.imagePath)

  console.log('')
  console.log(`[${caseMeta.test_case_domain}] ${relativeImage}`)
  console.log(`size: ${(info.size / 1024).toFixed(1)} KB · mime: ${mime}`)

  if (context.dryRun) {
    return {
      ok: true,
      dryRun: true,
      httpStatus: null,
      elapsedMs: 0,
      caseMeta,
      imagePath: testCase.imagePath,
      relativeImage,
      mime,
      summary: null,
      raw: null,
      responseFile: null,
    }
  }

  const bytes = await readFile(testCase.imagePath)
  const blob = new Blob([bytes], { type: mime })
  const form = new FormData()
  form.append('image', blob, path.basename(testCase.imagePath))
  form.append('response_mode', responseMode)
  form.append('client_captured_at', new Date().toISOString())
  form.append('client_request_started_at', new Date().toISOString())
  form.append('source_app', context.sourceApp)
  form.append('capture_kind', context.captureKind)
  form.append('test_run_id', caseMeta.test_run_id)
  form.append('test_case_domain', caseMeta.test_case_domain)
  if (caseMeta.test_case_date) form.append('test_case_date', caseMeta.test_case_date)
  form.append('test_case_file', caseMeta.test_case_file)
  // 身份信息：--user-id 显式指定时传 user_id（仅限调试）
  // 否则默认传 upload_token，由 Edge Function 反查 user_id
  if (userId) {
    form.append('user_id', userId)
  } else if (context.uploadToken) {
    form.append('upload_token', context.uploadToken)
  }

  const startedAt = Date.now()
  const resp = await fetch(context.endpoint, {
    method: 'POST',
    headers: {
      apikey: context.anonKey,
      Authorization: `Bearer ${context.anonKey}`,
    },
    body: form,
  })
  const elapsedMs = Date.now() - startedAt
  const raw = await resp.text()

  let parsed = null
  let summary = null
  if (responseMode === 'json') {
    try {
      parsed = JSON.parse(raw)
      summary = summarizeResult(parsed)
    } catch {
      parsed = null
    }
  }
  const aiLogId = parsed?.ai_log_id || null
  const aiLogFetch = await fetchAiLogById(context.logClient, aiLogId)

  const artifacts = await writeCaseArtifacts({
    context,
    testCase,
    caseMeta,
    relativeImage,
    mime,
    httpStatus: resp.status,
    statusText: resp.statusText,
    elapsedMs,
    raw,
    parsed,
    summary,
    aiLog: aiLogFetch?.row || null,
    aiLogFetchError: aiLogFetch?.error || null,
  })

  return {
    ok: resp.ok && !(summary?.error),
    dryRun: false,
    httpStatus: resp.status,
    elapsedMs,
    caseMeta,
    imagePath: testCase.imagePath,
    relativeImage,
    mime,
    summary,
    raw,
    responseFile: artifacts.responseFile,
    traceFile: artifacts.traceFile,
    aiLog: aiLogFetch?.row || null,
    aiLogFetchError: aiLogFetch?.error || null,
  }
}

export async function writeCaseArtifacts(payload) {
  const safeDate = payload.caseMeta.test_case_date || 'no-date'
  const fileBase = payload.testCase.fileName.replace(/\.[^.]+$/, '')
  const outputDir = path.join(
    payload.context.outputRoot,
    payload.context.runId,
    payload.caseMeta.test_case_domain,
    safeDate,
  )
  await ensureDir(outputDir)
  const targetPath = path.join(outputDir, `${fileBase}.response.json`)
  const tracePath = path.join(outputDir, `${fileBase}.trace.json`)
  const body = {
    run: {
      run_id: payload.context.runId,
      generated_at: new Date().toISOString(),
      endpoint: payload.context.endpoint,
      response_mode: payload.context.responseMode,
      user_id: payload.context.userId,
      upload_token_used: Boolean(payload.context.uploadToken),
      capture_kind: payload.context.captureKind,
      source_app: payload.context.sourceApp,
    },
    case: {
      ...payload.caseMeta,
      image_path: normalizePathForReport(payload.testCase.imagePath),
      image_relative_path: payload.relativeImage,
      mime: payload.mime,
    },
    response: {
      http_status: payload.httpStatus,
      status_text: payload.statusText,
      elapsed_ms: payload.elapsedMs,
      summary: payload.summary,
      parsed: payload.parsed,
      raw: payload.raw,
    },
  }
  await writeFile(targetPath, `${compactJson(body)}\n`, 'utf8')
  const trace = buildTraceArtifact({
    ...payload,
    responseFile: targetPath,
  })
  await writeFile(tracePath, `${compactJson(trace)}\n`, 'utf8')
  return {
    responseFile: targetPath,
    traceFile: tracePath,
  }
}

export function buildTraceArtifact(payload) {
  const parsed = payload.parsed || {}
  const summary = payload.summary || summarizeResult(parsed)
  const aiLog = payload.aiLog || null
  const rawDebug = parseRawDebug(aiLog?.raw_response)
  const traceId = parsed.trace_id || `local-${payload.context.runId}-${payload.caseMeta.test_case_domain}-${payload.caseMeta.test_case_file}`
  const generatedAt = new Date().toISOString()
  const status = summary.error ? 'error' : (summary.status || parsed.status || (payload.httpStatus >= 200 && payload.httpStatus < 300 ? 'success' : 'error'))

  const userVisibleOutputs = [
    parsed.notification_text || parsed.notification ? {
      output_type: 'ios_shortcut_notification',
      label: 'iOS 快捷指令通知',
      value: parsed.notification_text || parsed.notification,
      source_step: 'response_build',
      user_visible: true,
    } : null,
    summary.companion_message && summary.companion_message !== '-' ? {
      output_type: 'app_companion_message',
      label: 'App 伴随文案',
      value: summary.companion_message,
      source_step: 'companion_feedback',
      user_visible: true,
    } : null,
    summary.ai_feedback ? {
      output_type: 'app_ai_feedback',
      label: 'App AI 弹窗反馈',
      value: summary.ai_feedback,
      source_step: 'companion_feedback',
      user_visible: true,
    } : null,
  ].filter(Boolean)

  const dbTargets = parsed.id ? [{
    table: inferTargetTable(summary.record_type, parsed.status),
    id: parsed.id,
    record_type: summary.record_type,
    status: parsed.status || summary.status,
  }] : []

  return {
    trace_id: traceId,
    ai_log_id: parsed.ai_log_id || null,
    run_id: payload.context.runId,
    status,
    created_at: generatedAt,
    case: {
      ...payload.caseMeta,
      image_path: normalizePathForReport(payload.testCase.imagePath),
      image_relative_path: payload.relativeImage,
      mime: payload.mime,
    },
    user_context: {
      user_id: payload.context.userId || null,
      identity_source: payload.context.userId ? 'user_id' : (payload.context.uploadToken ? 'upload_token' : 'none'),
      upload_token_used: Boolean(payload.context.uploadToken),
      is_test_account: Boolean(payload.context.uploadToken),
    },
    request_context: {
      endpoint: payload.context.endpoint,
      response_mode: payload.context.responseMode,
      capture_kind: parsed.capture_kind || rawDebug?.request_context?.capture_kind || payload.context.captureKind,
      source_app: parsed.source_app || rawDebug?.request_context?.source_app || payload.context.sourceApp,
    },
    model_context: {
      vision_mode: parsed.vision_mode || rawDebug?.request_context?.vision_mode || null,
      photo_quality_mode: parsed.photo_quality_mode ?? rawDebug?.request_context?.photo_quality_mode ?? null,
      model_provider: parsed.model_provider || aiLog?.model_provider || null,
      model_name: parsed.model_name || aiLog?.model_name || null,
      prompt_version: aiLog?.prompt_version || rawDebug?.prompt?.version || null,
      prompt_hash: rawDebug?.prompt?.hash || null,
    },
    steps: buildTraceSteps({ payload, parsed, summary, aiLog, rawDebug }),
    user_visible_outputs: userVisibleOutputs,
    artifacts: {
      response_file: normalizePathForReport(payload.responseFile),
      raw_response_available: Boolean(payload.raw),
      parsed_response_available: Boolean(payload.parsed),
      ai_log_available: Boolean(aiLog),
      ai_log_fetch_error: payload.aiLogFetchError || null,
      raw_debug_available: Boolean(rawDebug),
      prompt: rawDebug?.prompt || null,
      dispatcher: rawDebug?.dispatcher || null,
      model_raw: rawDebug?.model_raw || null,
      companion: rawDebug?.companion || null,
      notification: rawDebug?.notification || null,
    },
    db_targets: mergeDbTargets(dbTargets, aiLog),
    errors: summary.error ? [{
      code: parsed.error_code || 'REQUEST_ERROR',
      message: summary.error,
      source_step: payload.httpStatus ? 'response_build' : 'upload_request',
    }] : payload.aiLogFetchError ? [{
      code: 'AI_LOG_FETCH_FAILED',
      message: payload.aiLogFetchError,
      source_step: 'write_ai_log',
    }] : [],
  }
}

function parseRawDebug(value) {
  if (!value) return null
  if (typeof value === 'object') return value
  if (typeof value !== 'string') return null
  try {
    return JSON.parse(value)
  } catch {
    return null
  }
}

function buildTraceSteps({ payload, parsed, summary, aiLog, rawDebug }) {
  const steps = [
    {
      step_id: 'upload_request',
      name: '上传请求',
      status: payload.httpStatus >= 200 && payload.httpStatus < 500 ? 'success' : 'error',
      duration_ms: payload.elapsedMs,
      input_snapshot: {
        image: payload.relativeImage,
        mime: payload.mime,
        capture_kind: payload.context.captureKind,
        source_app: payload.context.sourceApp,
      },
      output_snapshot: {
        http_status: payload.httpStatus,
        status_text: payload.statusText,
      },
      user_visible: false,
      visibility_level: 'L1',
    },
    {
      step_id: 'identity_resolve',
      name: '身份解析',
      status: parsed.error && payload.httpStatus === 401 ? 'error' : 'success',
      input_snapshot: {
        identity_source: payload.context.userId ? 'user_id' : (payload.context.uploadToken ? 'upload_token' : 'none'),
      },
      output_snapshot: {
        user_id: payload.context.userId || null,
        upload_token_used: Boolean(payload.context.uploadToken),
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    buildTimingStep({
      stepId: 'image_hash',
      name: '图片哈希与去重准备',
      timingKey: 'hash',
      rawDebug,
      input: {
        mime: payload.mime,
      },
      output: {
        image_hash: aiLog?.image_hash || null,
        perceptual_hash: aiLog?.perceptual_hash || null,
        perceptual_distance: aiLog?.perceptual_distance ?? null,
      },
    }),
    buildTimingStep({
      stepId: 'duplicate_check',
      name: '去重检查',
      timingKey: 'dup_check',
      rawDebug,
      output: {
        duplicate_kind: aiLog?.duplicate_kind || null,
        duplicate_ref_table: aiLog?.duplicate_ref_table || null,
        duplicate_ref_id: aiLog?.duplicate_ref_id || null,
      },
    }),
    buildTimingStep({
      stepId: 'domain_dispatch',
      name: '低成本预路由 / Dispatcher',
      timingKey: 'dispatcher',
      rawDebug,
      input: {
        source_app: rawDebug?.dispatcher?.source_app || parsed.source_app || payload.context.sourceApp,
      },
      output: {
        selected_domain_key: rawDebug?.dispatcher?.selected_domain_key || null,
        route_confidence: rawDebug?.dispatcher?.route_confidence ?? null,
        route_reason: rawDebug?.dispatcher?.route_reason || null,
        should_call_vision: rawDebug?.dispatcher?.should_call_vision ?? null,
        skip_reason: rawDebug?.dispatcher?.skip_reason || null,
      },
      artifactRefs: ['dispatcher'],
    }),
    {
      step_id: 'prompt_build',
      name: 'Prompt 构造',
      status: rawDebug?.prompt?.version || aiLog?.prompt_version ? 'success' : 'unknown',
      duration_ms: null,
      input_snapshot: {
        response_mode: payload.context.responseMode,
      },
      output_snapshot: {
        prompt_version: aiLog?.prompt_version || rawDebug?.prompt?.version || null,
        prompt_hash: rawDebug?.prompt?.hash || null,
        prompt_snapshot_available: Boolean(rawDebug?.prompt?.messages || rawDebug?.prompt?.text || rawDebug?.prompt?.snapshot),
      },
      user_visible: false,
      visibility_level: 'L2',
      artifact_refs: ['prompt'],
    },
    {
      step_id: 'model_path',
      name: '模型路径',
      status: parsed.model_name || parsed.vision_mode || aiLog?.model_name ? 'success' : 'unknown',
      input_snapshot: {
        capture_kind: parsed.capture_kind || rawDebug?.request_context?.capture_kind || payload.context.captureKind,
        source_app: parsed.source_app || rawDebug?.request_context?.source_app || payload.context.sourceApp,
      },
      output_snapshot: {
        vision_mode: parsed.vision_mode || rawDebug?.request_context?.vision_mode || null,
        photo_quality_mode: parsed.photo_quality_mode ?? rawDebug?.request_context?.photo_quality_mode ?? null,
        model_provider: parsed.model_provider || aiLog?.model_provider || null,
        model_name: parsed.model_name || aiLog?.model_name || null,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    buildTimingStep({
      stepId: 'model_call',
      name: '模型调用',
      timingKey: 'vision_total',
      rawDebug,
      output: {
        response_id: rawDebug?.model_raw?.response_id || null,
        finish_reason: rawDebug?.model_raw?.finish_reason || null,
        attempts: rawDebug?.vision_attempts?.length ?? null,
        has_raw_text: Boolean(rawDebug?.model_raw?.text),
        has_extracted_json: Boolean(rawDebug?.model_raw?.extracted_json),
      },
      artifactRefs: ['model_raw', 'vision_attempts'],
    }),
    {
      step_id: 'model_parse',
      name: '模型解析',
      status: rawDebug?.model_raw?.extracted_json || aiLog?.ai_response ? 'success' : 'unknown',
      duration_ms: null,
      input_snapshot: {
        raw_text_available: Boolean(rawDebug?.model_raw?.text),
      },
      output_snapshot: {
        extracted_json_available: Boolean(rawDebug?.model_raw?.extracted_json),
        record_type: aiLog?.record_type || summary.record_type,
        confidence: aiLog?.confidence ?? null,
      },
      user_visible: false,
      visibility_level: 'L2',
      artifact_refs: ['model_raw.extracted_json', 'ai_response'],
    },
    {
      step_id: 'normalize_validate',
      name: '标准化与校验',
      status: aiLog?.status ? 'success' : 'unknown',
      duration_ms: null,
      input_snapshot: {
        record_type: aiLog?.record_type || summary.record_type,
      },
      output_snapshot: {
        status: aiLog?.status || summary.status,
        confidence: aiLog?.confidence ?? null,
        occurred_at: aiLog?.occurred_at || null,
        order_finished_at: aiLog?.order_finished_at || null,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    {
      step_id: 'companion_feedback',
      name: '伴随文案 / AI 反馈',
      status: rawDebug?.companion || summary.ai_feedback || summary.companion_message !== '-' ? 'success' : 'skipped',
      duration_ms: null,
      input_snapshot: {
        disabled: rawDebug?.companion?.disabled ?? null,
        fallback_used: rawDebug?.companion?.fallback_used ?? null,
        feedback_used: rawDebug?.companion?.feedback_used ?? null,
      },
      output_snapshot: {
        final: rawDebug?.companion?.final || summary.companion_message || null,
        has_ai_feedback: Boolean(rawDebug?.companion?.ai_feedback || summary.ai_feedback),
      },
      user_visible: true,
      visibility_level: 'L0',
      artifact_refs: ['companion'],
    },
    buildTimingStep({
      stepId: 'archive_or_staging',
      name: '归档或中转',
      timingKey: 'db_insert',
      rawDebug,
      output: {
        target_table: aiLog?.target_table || inferTargetTable(summary.record_type, parsed.status),
        target_id: aiLog?.target_id || parsed.id || null,
        staging_record_id: aiLog?.staging_record_id || null,
        data_record_id: aiLog?.data_record_id || null,
      },
    }),
    {
      step_id: 'write_ai_log',
      name: '写入 AI 日志',
      status: aiLog ? 'success' : (parsed.ai_log_id ? 'error' : 'skipped'),
      duration_ms: null,
      input_snapshot: {
        ai_log_id: parsed.ai_log_id || null,
      },
      output_snapshot: {
        ai_log_id: aiLog?.id || parsed.ai_log_id || null,
        raw_debug_available: Boolean(rawDebug),
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    {
      step_id: 'response_build',
      name: '响应构造',
      status: summary.error ? 'error' : 'success',
      input_snapshot: {
        ai_log_id: parsed.ai_log_id || null,
      },
      output_snapshot: {
        status: summary.status,
        record_type: summary.record_type,
        id: summary.id,
        has_ai_feedback: Boolean(summary.ai_feedback),
        has_notification: Boolean(parsed.notification_text || parsed.notification),
      },
      user_visible: true,
      visibility_level: 'L0',
    },
  ]
  return steps.filter(Boolean)
}

function buildTimingStep({ stepId, name, timingKey, rawDebug, input = {}, output = {}, artifactRefs = [] }) {
  const duration = rawDebug?.timings?.[timingKey]
  const hasOutput = Object.values(output).some((value) => value !== null && value !== undefined)
  return {
    step_id: stepId,
    name,
    status: duration !== undefined || hasOutput ? 'success' : 'unknown',
    duration_ms: duration ?? null,
    input_snapshot: input,
    output_snapshot: output,
    user_visible: false,
    visibility_level: 'L2',
    ...(artifactRefs.length ? { artifact_refs: artifactRefs } : {}),
  }
}

function mergeDbTargets(localTargets, aiLog) {
  if (!aiLog?.target_table && !aiLog?.target_id && !aiLog?.staging_record_id && !aiLog?.data_record_id) {
    return localTargets
  }
  const fromLog = {
    table: aiLog.target_table || null,
    id: aiLog.target_id || aiLog.staging_record_id || aiLog.data_record_id || null,
    record_type: aiLog.record_type || null,
    status: aiLog.status || null,
    domain_id: aiLog.domain_id || null,
    staging_record_id: aiLog.staging_record_id || null,
    data_record_id: aiLog.data_record_id || null,
  }
  return [fromLog, ...localTargets.filter((item) => item.id !== fromLog.id)]
}

function inferTargetTable(recordType, status) {
  if (recordType === 'expense') return 'transactions'
  if (recordType === 'income') return 'income_records'
  if (status === 'staging') return 'staging_records'
  if (recordType && recordType !== '-') return 'data_records'
  return null
}

export async function writeBatchSummary(context, results) {
  const runDir = path.join(context.outputRoot, context.runId)
  await ensureDir(runDir)

  const summaryItems = results.map((item) => ({
    domain: item.caseMeta.test_case_domain,
    date: item.caseMeta.test_case_date,
    file: item.caseMeta.test_case_file,
    relative_image: item.relativeImage,
    http_status: item.httpStatus,
    success: item.ok,
    dry_run: item.dryRun,
    elapsed_ms: item.elapsedMs,
    record_type: item.summary?.record_type ?? null,
    trace_id: item.summary?.trace_id ?? null,
    ai_log_id: item.summary?.ai_log_id ?? null,
    vision_mode: item.summary?.vision_mode ?? null,
    model_provider: item.summary?.model_provider ?? null,
    model_name: item.summary?.model_name ?? null,
    message: item.summary?.message ?? null,
    has_ai_feedback: Boolean(item.summary?.ai_feedback),
    response_file: item.responseFile ? relativeFromRoot(item.responseFile) : null,
    trace_file: item.traceFile ? relativeFromRoot(item.traceFile) : null,
  }))

  const aggregate = {
    run_id: context.runId,
    generated_at: new Date().toISOString(),
    endpoint: context.endpoint,
    response_mode: context.responseMode,
    user_id: context.userId,
    upload_token_used: Boolean(context.uploadToken),
    capture_kind: context.captureKind,
    source_app: context.sourceApp,
    total_cases: results.length,
    success_cases: results.filter((item) => item.ok).length,
    failed_cases: results.filter((item) => !item.ok).length,
    ai_feedback_cases: results.filter((item) => item.summary?.ai_feedback).length,
    dry_run: context.dryRun,
    cases: summaryItems,
  }

  await writeFile(path.join(runDir, 'summary.json'), `${compactJson(aggregate)}\n`, 'utf8')

  const lines = [
    `# AI 本地验证结果`,
    '',
    `- run_id: \`${context.runId}\``,
    `- endpoint: \`${context.endpoint}\``,
    `- response_mode: \`${context.responseMode}\``,
    `- user_id: \`${context.userId || '-'}\``,
    `- capture_kind: \`${context.captureKind}\``,
    `- source_app: \`${context.sourceApp}\``,
    `- total_cases: ${aggregate.total_cases}`,
    `- success_cases: ${aggregate.success_cases}`,
    `- failed_cases: ${aggregate.failed_cases}`,
    `- ai_feedback_cases: ${aggregate.ai_feedback_cases}`,
    '',
    `## Cases`,
    '',
    `| domain | date | file | status | record_type | vision | ai_log | ai_feedback | response | trace |`,
    `| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |`,
  ]

  for (const item of summaryItems) {
    lines.push(
      `| ${item.domain} | ${item.date ?? '-'} | ${item.file} | ${item.http_status ?? '-'} | ${item.record_type ?? '-'} | ${item.vision_mode ?? '-'} | ${item.ai_log_id ?? '-'} | ${item.has_ai_feedback ? 'yes' : 'no'} | ${item.response_file ?? '-'} | ${item.trace_file ?? '-'} |`,
    )
  }

  await writeFile(path.join(runDir, 'summary.md'), `${lines.join('\n')}\n`, 'utf8')
}

async function main() {
  if (flags.help) {
    printHelp()
    return
  }

  const endpoint = resolveEndpoint()
  const anonKey = resolveAnonKey()
  const userId = resolveUserId()
  const uploadToken = resolveUploadToken()
  const responseMode = normalizeResponseMode()
  const captureKind = resolveCaptureKind()
  const sourceApp = resolveSourceApp()
  const logEnrichKey = flags.noLogEnrich ? null : resolveLogEnrichKey()
  const logClient = await createLogClient({ endpoint, key: logEnrichKey })
  const outputRoot = path.resolve(flags.outputDir || 'test-results')
  const runId = flags.runId || buildDefaultRunId()
  const cases = await buildCaseList({ image: flags.image, dir: flags.dir, domain: flags.domain })

  const context = {
    endpoint,
    anonKey,
    userId,
    uploadToken,
    responseMode,
    captureKind,
    sourceApp,
    logClient,
    logEnrichEnabled: Boolean(logClient),
    outputRoot,
    runId,
    dryRun: Boolean(flags.dryRun),
  }

  console.log('本地识别回放')
  console.log('----------------')
  console.log(`endpoint: ${endpoint}`)
  console.log(`response_mode: ${responseMode}`)
  console.log(`user_id: ${userId || '-'} ${userId ? '(调试模式)' : ''}`)
  console.log(`upload_token: ${uploadToken ? '(provided)' : '-'}`)
  console.log(`capture_kind: ${captureKind}`)
  console.log(`source_app: ${sourceApp}`)
  console.log(`log_enrich: ${logClient ? 'enabled' : 'disabled'}`)
  console.log(`run_id: ${runId}`)
  console.log(`cases: ${cases.length}`)
  console.log(`output_dir: ${relativeFromRoot(outputRoot)}`)
  if (flags.domain) console.log(`domain_filter: ${flags.domain}`)
  if (flags.dryRun) console.log('mode: dry-run')

  const results = []
  for (const testCase of cases) {
    const result = await executeCase(testCase, context)
    results.push(result)

    if (!flags.dir && result.summary) {
      console.log(`HTTP ${result.httpStatus} · ${result.elapsedMs}ms`)
      printSingleSummary(result.summary)
      if (result.responseFile) {
        console.log(`response_file: ${relativeFromRoot(result.responseFile)}`)
      }
      if (result.traceFile) {
        console.log(`trace_file: ${relativeFromRoot(result.traceFile)}`)
      }
    } else if (!flags.dir && result.dryRun) {
      console.log('dry_run: true')
    } else if (flags.dir) {
      const recordType = result.summary?.record_type ?? '-'
      const aiFeedbackFlag = result.summary?.ai_feedback ? 'yes' : 'no'
      const visionMode = result.summary?.vision_mode ?? '-'
      const statusCode = result.httpStatus ?? '-'
      console.log(`HTTP ${statusCode} · ${result.elapsedMs}ms · record_type=${recordType} · vision=${visionMode} · ai_feedback=${aiFeedbackFlag}`)
    }
  }

  if (flags.dir && !flags.dryRun) {
    await writeBatchSummary(context, results)
    console.log('')
    console.log(`批量结果已写入: ${relativeFromRoot(path.join(outputRoot, runId))}`)
  }

  if (results.some((item) => !item.ok)) {
    process.exitCode = 1
  }
}

const isMainModule = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])

if (isMainModule) {
  main().catch((error) => {
    console.error('')
    console.error('回放失败:', error.message)
    process.exit(1)
  })
}
