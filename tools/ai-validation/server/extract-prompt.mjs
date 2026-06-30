/**
 * ═══════════════════════════════════════════════
 * Prompt 快照提取脚本
 * ═══════════════════════════════════════════════
 *
 * 从 supabase/functions/ingest-receipt/prompts.ts 提取完整 prompt 文本，
 * 生成 prompt-snapshot.json 供追踪台展示。
 *
 * 用法: npx tsx tools/ai-validation/server/extract-prompt.mjs
 *
 * prompts.ts 改动后需重新执行此脚本。
 */

import { writeFileSync, readFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { createHash } from 'node:crypto'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// prompts.ts 的路径
const PROMPTS_TS_PATH = path.resolve(__dirname, '..', '..', '..', 'supabase', 'functions', 'ingest-receipt', 'prompts.ts')

// 输出文件路径
const OUTPUT_PATH = path.join(__dirname, 'prompt-snapshot.json')

// 动态导入 prompts.ts（通过 tsx 运行时支持 TS，Windows 需要 file:// URL）
const promptsModule = await import(pathToFileURL(PROMPTS_TS_PATH).href)

const { buildPrompt, buildFeedbackPrompt, PROMPT } = promptsModule

// ═══════════════════════════════════════════════
// 提取静态 prompt（默认参数）
// ═══════════════════════════════════════════════

// 第一次调用：视觉识别 prompt（默认参数）
const visionPrompt = buildPrompt()

// 第二次调用：文案生成 prompt（用 mock 识别结果）
const mockRecognizedFields = {
  image_type: 'sport_detail',
  record_type: 'sport',
  domain_key: 'sport',
  title: '户外骑行',
  summary: '运动42分钟，骑行9.79公里，消耗359千卡。',
  payload_jsonb: {
    sport_type: '户外骑行',
    duration_minutes: 42.63,
    calories: 359,
    distance_km: 9.79,
    avg_speed_kmh: 13.78,
    avg_heart_rate: 141,
  },
}

const feedbackPrompt = buildFeedbackPrompt({
  recognizedFields: mockRecognizedFields,
  builtPayload: mockRecognizedFields.payload_jsonb,
  clientLocalTime: '2026-06-14T15:49:00+08:00',
  weekday: '周日',
})

// ═══════════════════════════════════════════════
// 计算版本信息
// ═══════════════════════════════════════════════

function computeHash(text) {
  return createHash('sha256').update(text).digest('hex').slice(0, 16)
}

const snapshot = {
  generated_at: new Date().toISOString(),
  source_file: 'supabase/functions/ingest-receipt/prompts.ts',
  version: 'platform-v3-builtins',
  vision_prompt: {
    full_text: visionPrompt,
    hash: computeHash(visionPrompt),
    char_count: visionPrompt.length,
    description: '第一次调用：视觉识别 prompt（buildPrompt 默认参数）',
    note: '实际发送时会附带动态参数（clientLocalTime、weekday、memory、persona 等），见 trace.model_context 和 trace.user_context',
  },
  feedback_prompt: {
    full_text: feedbackPrompt,
    hash: computeHash(feedbackPrompt),
    char_count: feedbackPrompt.length,
    description: '第二次调用：文案生成 prompt（buildFeedbackPrompt，使用 mock 识别结果）',
    note: '实际发送时 recognizedFields 和 memory 是动态的，每次不同。此处用 mock 数据展示 prompt 骨架结构。',
    mock_input: mockRecognizedFields,
  },
  // PROMPT 常量（等同于 buildPrompt() 无参数调用）
  prompt_constant: {
    full_text: PROMPT,
    hash: computeHash(PROMPT),
    char_count: PROMPT.length,
  },
}

// ═══════════════════════════════════════════════
// 保存历史版本（如果内容有变化）
// ═══════════════════════════════════════════════

const HISTORY_DIR = path.join(__dirname, 'prompt-history')

function saveHistoryIfChanged(newSnapshot) {
  // 读取上一次的快照
  let prevSnapshot = null
  if (existsSync(OUTPUT_PATH)) {
    try {
      prevSnapshot = JSON.parse(readFileSync(OUTPUT_PATH, 'utf-8'))
    } catch {}
  }

  // 比对 hash，如果没变化就不保存历史
  const visionChanged = !prevSnapshot || prevSnapshot.vision_prompt?.hash !== newSnapshot.vision_prompt.hash
  const feedbackChanged = !prevSnapshot || prevSnapshot.feedback_prompt?.hash !== newSnapshot.feedback_prompt.hash

  if (!visionChanged && !feedbackChanged) {
    return { saved: false, reason: '内容未变化' }
  }

  // 保存历史
  if (!existsSync(HISTORY_DIR)) {
    mkdirSync(HISTORY_DIR, { recursive: true })
  }

  const now = new Date()
  const ts = now.toISOString().replace(/[-:T]/g, '').slice(0, 14) // YYYYMMDDhhmmss
  const shortHash = newSnapshot.vision_prompt.hash.slice(0, 6)
  const historyFile = path.join(HISTORY_DIR, `${ts}_${shortHash}.json`)

  // 带上变更标记
  const historyEntry = {
    ...newSnapshot,
    saved_at: now.toISOString(),
    changes: {
      vision_changed: visionChanged,
      feedback_changed: feedbackChanged,
    },
  }

  writeFileSync(historyFile, JSON.stringify(historyEntry, null, 2), 'utf-8')
  return { saved: true, file: path.basename(historyFile) }
}

// ═══════════════════════════════════════════════
// 写入文件
// ═══════════════════════════════════════════════

const historyResult = saveHistoryIfChanged(snapshot)
writeFileSync(OUTPUT_PATH, JSON.stringify(snapshot, null, 2), 'utf-8')

console.log('═══════════════════════════════════════════════')
console.log('  Prompt 快照提取完成')
console.log('═══════════════════════════════════════════════')
console.log(`  源文件:   ${PROMPTS_TS_PATH}`)
console.log(`  输出文件: ${OUTPUT_PATH}`)
console.log('')
console.log(`  视觉识别 Prompt:`)
console.log(`    字符数: ${snapshot.vision_prompt.char_count}`)
console.log(`    hash:   ${snapshot.vision_prompt.hash}`)
console.log('')
console.log(`  文案生成 Prompt:`)
console.log(`    字符数: ${snapshot.feedback_prompt.char_count}`)
console.log(`    hash:   ${snapshot.feedback_prompt.hash}`)
console.log('')
if (historyResult.saved) {
  console.log(`  历史版本已保存: ${historyResult.file}`)
} else {
  console.log(`  历史版本: ${historyResult.reason}，未保存`)
}
console.log('')
console.log('  prompts.ts 改动后请重新运行: npx tsx tools/ai-validation/server/extract-prompt.mjs')
console.log('═══════════════════════════════════════════════')
