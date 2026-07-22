import { mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createClient } from '@supabase/supabase-js'
import { compactJson, summarizeResult, normalizePathForReport, buildTraceFromUploadResult } from '../tools/ai-validation/lib/trace-builder.mjs'

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
  else if (arg.startsWith('--access-token=')) flags.accessToken = arg.slice('--access-token='.length)
  else if (arg === '--access-token') flags.accessToken = args[++i]
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
  npm run test:receipt -- --image ./test.jpg --access-token <jwt>
  npm run test:receipt -- --dir ./test-cases
  npm run test:receipt -- --dir ./test-cases --domain expense
  npm run test:receipt -- --dir ./test-cases --dry-run

选项:
  --image <path>         测试单张图片
  --dir <path>           批量扫描测试目录
  --domain <name>        仅跑指定域，例如 expense
  --user-id <uuid>       与 access token 同时使用时校验目标用户
  --access-token <jwt>   使用临时测试账号的登录 JWT
  --upload-token <t>     使用本地配置的上传 token
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
  return flags.uploadToken || process.env.TEST_RECEIPT_UPLOAD_TOKEN || null
}

function resolveAccessToken() {
  return flags.accessToken || process.env.TEST_RECEIPT_ACCESS_TOKEN || null
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
  // user_id 只用于和 JWT 交叉校验，不能单独作为身份凭据。
  if (userId) {
    form.append('user_id', userId)
  }
  if (!context.accessToken && context.uploadToken) {
    form.append('upload_token', context.uploadToken)
  }

  const startedAt = Date.now()
  const resp = await fetch(context.endpoint, {
    method: 'POST',
    headers: {
      apikey: context.anonKey,
      Authorization: `Bearer ${context.accessToken || context.anonKey}`,
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
      access_token_used: Boolean(payload.context.accessToken),
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
  const trace = buildTraceFromUploadResult({
    ...payload,
    responseFile: targetPath,
  })
  await writeFile(tracePath, `${compactJson(trace)}\n`, 'utf8')
  return {
    responseFile: targetPath,
    traceFile: tracePath,
  }
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
    access_token_used: Boolean(context.accessToken),
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
  const accessToken = resolveAccessToken()
  const responseMode = normalizeResponseMode()
  const captureKind = resolveCaptureKind()
  const sourceApp = resolveSourceApp()
  const logEnrichKey = flags.noLogEnrich ? null : resolveLogEnrichKey()
  const logClient = await createLogClient({ endpoint, key: logEnrichKey })
  const outputRoot = path.resolve(flags.outputDir || 'test-results')
  const runId = flags.runId || buildDefaultRunId()
  const cases = await buildCaseList({ image: flags.image, dir: flags.dir, domain: flags.domain })
  if (!flags.dryRun && !accessToken && !uploadToken) {
    throw new Error('缺少测试身份：请设置 TEST_RECEIPT_ACCESS_TOKEN、TEST_RECEIPT_UPLOAD_TOKEN 或传入对应参数。')
  }

  const context = {
    endpoint,
    anonKey,
    userId,
    uploadToken,
    accessToken,
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
  console.log(`user_id: ${userId || '-'}`)
  console.log(`access_token: ${accessToken ? '(provided)' : '-'}`)
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
