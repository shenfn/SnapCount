/**
 * ═══════════════════════════════════════════════
 * 本地 Prompt 模拟脚本
 * ═══════════════════════════════════════════════
 *
 * 读取本地 prompts.ts 生成 prompt，直接调用 qwen API，
 * 不经过 Edge Function，用于快速验证 prompt 改动。
 *
 * 用法: npx tsx local-simulate.mjs --image <path>
 *
 * 输出 JSON 到 stdout:
 *   {
 *     "vision_prompt": "...",
 *     "vision_output": { ... },
 *     "feedback_prompt": "...",
 *     "feedback_output": { ... },
 *     "elapsed_ms": 12345
 *   }
 */

import { readFileSync, existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..')
const PROMPTS_TS_PATH = path.resolve(PROJECT_ROOT, 'supabase', 'functions', 'ingest-receipt', 'prompts.ts')

// ═══════════════════════════════════════════════
// 参数解析
// ═══════════════════════════════════════════════

const args = process.argv.slice(2)
let imagePath = ''
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--image' && args[i + 1]) imagePath = args[i + 1]
}

if (!imagePath) {
  console.error('Usage: npx tsx local-simulate.mjs --image <path>')
  process.exit(1)
}

const absImagePath = path.resolve(imagePath)
if (!existsSync(absImagePath)) {
  console.error(`Image not found: ${absImagePath}`)
  process.exit(1)
}

// ═══════════════════════════════════════════════
// 读取环境变量
// ═══════════════════════════════════════════════

function loadEnvFile(filePath) {
  if (!existsSync(filePath)) return {}
  const content = readFileSync(filePath, 'utf-8')
  const env = {}
  for (const line of content.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eqIdx = trimmed.indexOf('=')
    if (eqIdx < 0) continue
    const key = trimmed.slice(0, eqIdx).trim()
    let val = trimmed.slice(eqIdx + 1).trim()
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1)
    }
    env[key] = val
  }
  return env
}

const envLocal = loadEnvFile(path.join(PROJECT_ROOT, '.env.local'))
const QWEN_API_KEY = process.env.QWEN_API_KEY || envLocal.QWEN_API_KEY || envLocal.VITE_QWEN_API_KEY

if (!QWEN_API_KEY) {
  console.error('Missing QWEN_API_KEY. 请在 .env.local 中配置 QWEN_API_KEY')
  process.exit(1)
}

const QWEN_ENDPOINT = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'
// 和 EF 保持一致：截图用 qwen3.6-flash，照片用 qwen3.7-plus，文案用 qwen3.6-flash
const QWEN_SCREENSHOT_MODEL = envLocal.QWEN_MODEL || 'qwen3.6-flash'
const QWEN_PHOTO_MODEL = envLocal.QWEN_PHOTO_MODEL || 'qwen3.7-plus'
const QWEN_FEEDBACK_MODEL = envLocal.FEEDBACK_TEXT_MODEL || QWEN_SCREENSHOT_MODEL

// ═══════════════════════════════════════════════
// 加载 prompts.ts
// ═══════════════════════════════════════════════

const promptsModule = await import(pathToFileURL(PROMPTS_TS_PATH).href)
const { buildPrompt, buildFeedbackPrompt } = promptsModule

// ═══════════════════════════════════════════════
// 工具函数
// ═══════════════════════════════════════════════

function imageToBase64(filePath) {
  const buffer = readFileSync(filePath)
  return buffer.toString('base64')
}

function getMime(filePath) {
  const ext = path.extname(filePath).toLowerCase()
  if (ext === '.png') return 'image/png'
  if (ext === '.webp') return 'image/webp'
  return 'image/jpeg'
}

function extractJsonFromText(text) {
  // 尝试从 markdown 代码块中提取
  const codeBlockMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/)
  if (codeBlockMatch) {
    try { return JSON.parse(codeBlockMatch[1].trim()) } catch {}
  }
  // 尝试直接 parse
  try { return JSON.parse(text.trim()) } catch {}
  // 尝试找到第一个 { 到最后一个 }
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start >= 0 && end > start) {
    try { return JSON.parse(text.slice(start, end + 1)) } catch {}
  }
  return null
}

// ═══════════════════════════════════════════════
// 调用 qwen 视觉识别
// ═══════════════════════════════════════════════

async function callVision(imageBase64, mime, promptText) {
  const dataUrl = `data:${mime};base64,${imageBase64}`
  const body = {
    model: QWEN_SCREENSHOT_MODEL,
    messages: [{
      role: 'user',
      content: [
        { type: 'image_url', image_url: { url: dataUrl } },
        { type: 'text', text: promptText },
      ],
    }],
    temperature: 0.1,
    max_completion_tokens: 4096,
    enable_thinking: true,
  }

  const resp = await fetch(QWEN_ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${QWEN_API_KEY}`,
      'api-key': QWEN_API_KEY,
    },
    body: JSON.stringify(body),
  })

  if (!resp.ok) {
    const txt = await resp.text()
    throw new Error(`Vision API error ${resp.status}: ${txt}`)
  }

  const data = await resp.json()
  const message = data?.choices?.[0]?.message ?? {}
  const rawText = typeof message.content === 'string' ? message.content : JSON.stringify(message.content ?? {})
  const parsed = extractJsonFromText(rawText)
  return { rawText, parsed, usage: data?.usage || null }
}

// ═══════════════════════════════════════════════
// 调用 qwen 文案生成
// ═══════════════════════════════════════════════

async function callFeedback(recognizedFields, builtPayload, promptText) {
  const body = {
    model: QWEN_FEEDBACK_MODEL,
    messages: [{
      role: 'user',
      content: promptText,
    }],
    temperature: 0.85,
    max_completion_tokens: 1024,
    enable_thinking: false,
  }

  const resp = await fetch(QWEN_ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${QWEN_API_KEY}`,
      'api-key': QWEN_API_KEY,
    },
    body: JSON.stringify(body),
  })

  if (!resp.ok) {
    const txt = await resp.text()
    throw new Error(`Feedback API error ${resp.status}: ${txt}`)
  }

  const data = await resp.json()
  const message = data?.choices?.[0]?.message ?? {}
  const rawText = typeof message.content === 'string' ? message.content : JSON.stringify(message.content ?? {})
  const parsed = extractJsonFromText(rawText)
  return { rawText, parsed, usage: data?.usage || null }
}

// ═══════════════════════════════════════════════
// 主流程
// ═══════════════════════════════════════════════

const startedAt = Date.now()

try {
  // 1. 生成视觉识别 prompt
  const visionPrompt = buildPrompt()

  // 2. 读取图片
  const imageBase64 = imageToBase64(absImagePath)
  const mime = getMime(absImagePath)

  process.stderr.write('调用视觉识别...\n')
  const visionResult = await callVision(imageBase64, mime, visionPrompt)
  process.stderr.write(`视觉识别完成 (${Date.now() - startedAt}ms)\n`)

  if (!visionResult.parsed) {
    throw new Error('视觉识别结果解析失败')
  }

  // 3. 生成文案 prompt
  const recognizedFields = visionResult.parsed
  const builtPayload = recognizedFields.payload_jsonb || {}
  const now = new Date()
  const feedbackPrompt = buildFeedbackPrompt({
    recognizedFields,
    builtPayload,
    clientLocalTime: now.toISOString(),
    weekday: ['周日','周一','周二','周三','周四','周五','周六'][now.getDay()],
  })

  // 4. 调用文案生成
  process.stderr.write('调用文案生成...\n')
  const feedbackStartedAt = Date.now()
  const feedbackResult = await callFeedback(recognizedFields, builtPayload, feedbackPrompt)
  process.stderr.write(`文案生成完成 (${Date.now() - feedbackStartedAt}ms)\n`)

  // 5. 输出结果
  const result = {
    vision_prompt: visionPrompt,
    vision_output: {
      model: QWEN_SCREENSHOT_MODEL,
      raw_text: visionResult.rawText,
      parsed: visionResult.parsed,
      usage: visionResult.usage,
    },
    feedback_prompt: feedbackPrompt,
    feedback_output: {
      model: QWEN_FEEDBACK_MODEL,
      raw_text: feedbackResult.rawText,
      parsed: feedbackResult.parsed,
      usage: feedbackResult.usage,
    },
    elapsed_ms: Date.now() - startedAt,
  }

  console.log(JSON.stringify(result, null, 2))

} catch (err) {
  process.stderr.write(`Error: ${err.message}\n`)
  process.exit(1)
}
