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
let noVisionThinking = false
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--image' && args[i + 1]) imagePath = args[i + 1]
  if (args[i] === '--no-vision-thinking') noVisionThinking = true
}

if (!imagePath) {
  console.error('Usage: npx tsx local-simulate.mjs --image <path> [--no-vision-thinking]')
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
  if (!text || typeof text !== 'string') return null
  let cleaned = text
  // 剥除 <think>...</think> 标签（thinking 模式输出可能含此标签）
  cleaned = cleaned.replace(/<think>[\s\S]*?<\/think>/gi, '')
  // 剥除未闭合的 <think> 标签（模型可能只输出开头标签）
  cleaned = cleaned.replace(/<think>[\s\S]*/gi, '')
  // 尝试从 markdown 代码块中提取
  const codeBlockMatch = cleaned.match(/```(?:json)?\s*([\s\S]*?)```/)
  if (codeBlockMatch) {
    try { return JSON.parse(codeBlockMatch[1].trim()) } catch {}
  }
  // 尝试直接 parse
  try { return JSON.parse(cleaned.trim()) } catch {}
  // 尝试找到第一个 { 到最后一个 }
  const start = cleaned.indexOf('{')
  const end = cleaned.lastIndexOf('}')
  if (start >= 0 && end > start) {
    try { return JSON.parse(cleaned.slice(start, end + 1)) } catch {}
  }
  return null
}

// ═══════════════════════════════════════════════
// 调用 qwen 视觉识别
// ═══════════════════════════════════════════════

async function callVision(imageBase64, mime, promptText, useThinking) {
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
    enable_thinking: useThinking,
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
  return {
    rawText,
    parsed,
    parse_ok: parsed !== null,
    usage: data?.usage || null,
  }
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
  return {
    rawText,
    parsed,
    parse_ok: parsed !== null,
    usage: data?.usage || null,
  }
}

// ═══════════════════════════════════════════════
// 主流程
// ═══════════════════════════════════════════════

const startedAt = Date.now()
const useVisionThinking = !noVisionThinking

try {
  // 1. 生成视觉识别 prompt
  const visionPrompt = buildPrompt()

  // 2. 读取图片
  const imageBase64 = imageToBase64(absImagePath)
  const mime = getMime(absImagePath)

  process.stderr.write(`调用视觉识别${useVisionThinking ? '' : '（已关闭 thinking）'}...\n`)
  const visionResult = await callVision(imageBase64, mime, visionPrompt, useVisionThinking)
  process.stderr.write(`视觉识别完成 (${Date.now() - startedAt}ms)\n`)

  // 3. 输出结果基础结构（即使解析失败也输出，让 UI 能显示 parse_ok: false）
  const result = {
    vision_prompt: visionPrompt,
    vision_thinking_enabled: useVisionThinking,
    vision_output: {
      model: QWEN_SCREENSHOT_MODEL,
      raw_text: visionResult.rawText,
      parsed: visionResult.parsed,
      parse_ok: visionResult.parse_ok,
      usage: visionResult.usage,
    },
    feedback_prompt: null,
    feedback_output: null,
    elapsed_ms: Date.now() - startedAt,
  }

  // 4. 视觉识别解析失败时，跳过文案生成，直接输出（UI 可据此标红）
  if (!visionResult.parsed) {
    process.stderr.write('警告：视觉识别结果解析失败，跳过文案生成\n')
    console.log(JSON.stringify(result, null, 2))
    process.exit(0)
  }

  // 5. 生成文案 prompt
  const recognizedFields = visionResult.parsed
  const builtPayload = recognizedFields.payload_jsonb || {}
  const now = new Date()
  const feedbackPrompt = buildFeedbackPrompt({
    recognizedFields,
    builtPayload,
    clientLocalTime: now.toISOString(),
    weekday: ['周日','周一','周二','周三','周四','周五','周六'][now.getDay()],
  })

  // 6. 调用文案生成
  process.stderr.write('调用文案生成...\n')
  const feedbackStartedAt = Date.now()
  const feedbackResult = await callFeedback(recognizedFields, builtPayload, feedbackPrompt)
  process.stderr.write(`文案生成完成 (${Date.now() - feedbackStartedAt}ms)\n`)

  // 7. 补全输出结果
  result.feedback_prompt = feedbackPrompt
  result.feedback_output = {
    model: QWEN_FEEDBACK_MODEL,
    raw_text: feedbackResult.rawText,
    parsed: feedbackResult.parsed,
    parse_ok: feedbackResult.parse_ok,
    usage: feedbackResult.usage,
  }
  result.elapsed_ms = Date.now() - startedAt

  console.log(JSON.stringify(result, null, 2))

} catch (err) {
  process.stderr.write(`Error: ${err.message}\n`)
  process.exit(1)
}
