import { mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

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
  form.append('source_app', 'codex-local-validation')
  form.append('capture_kind', 'test-batch')
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

  const responseFile = await writeCaseArtifacts({
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
    responseFile,
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
  const body = {
    run: {
      run_id: payload.context.runId,
      generated_at: new Date().toISOString(),
      endpoint: payload.context.endpoint,
      response_mode: payload.context.responseMode,
      user_id: payload.context.userId,
      upload_token_used: Boolean(payload.context.uploadToken),
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
  return targetPath
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
    message: item.summary?.message ?? null,
    has_ai_feedback: Boolean(item.summary?.ai_feedback),
    response_file: item.responseFile ? relativeFromRoot(item.responseFile) : null,
  }))

  const aggregate = {
    run_id: context.runId,
    generated_at: new Date().toISOString(),
    endpoint: context.endpoint,
    response_mode: context.responseMode,
    user_id: context.userId,
    upload_token_used: Boolean(context.uploadToken),
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
    `- total_cases: ${aggregate.total_cases}`,
    `- success_cases: ${aggregate.success_cases}`,
    `- failed_cases: ${aggregate.failed_cases}`,
    `- ai_feedback_cases: ${aggregate.ai_feedback_cases}`,
    '',
    `## Cases`,
    '',
    `| domain | date | file | status | record_type | ai_feedback | response |`,
    `| --- | --- | --- | --- | --- | --- | --- |`,
  ]

  for (const item of summaryItems) {
    lines.push(
      `| ${item.domain} | ${item.date ?? '-'} | ${item.file} | ${item.http_status ?? '-'} | ${item.record_type ?? '-'} | ${item.has_ai_feedback ? 'yes' : 'no'} | ${item.response_file ?? '-'} |`,
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
  const outputRoot = path.resolve(flags.outputDir || 'test-results')
  const runId = flags.runId || buildDefaultRunId()
  const cases = await buildCaseList({ image: flags.image, dir: flags.dir, domain: flags.domain })

  const context = {
    endpoint,
    anonKey,
    userId,
    uploadToken,
    responseMode,
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
    } else if (!flags.dir && result.dryRun) {
      console.log('dry_run: true')
    } else if (flags.dir) {
      const recordType = result.summary?.record_type ?? '-'
      const aiFeedbackFlag = result.summary?.ai_feedback ? 'yes' : 'no'
      const statusCode = result.httpStatus ?? '-'
      console.log(`HTTP ${statusCode} · ${result.elapsedMs}ms · record_type=${recordType} · ai_feedback=${aiFeedbackFlag}`)
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
