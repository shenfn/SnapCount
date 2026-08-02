import { createClient } from '@supabase/supabase-js'
import { mkdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..')

function requireEnv(names) {
  for (const name of names) if (process.env[name]) return process.env[name]
  throw new Error(`Missing one of: ${names.join(', ')}`)
}

function json(value) {
  return JSON.stringify(value ?? null)
}

function baselineRecordType(row) {
  return row.record_type ?? row.baseline_payload?.record_type ?? row.baseline_payload?.ai_feedback?.record_type ?? 'unknown'
}

function selectedBySurface(row) {
  const plan = row.proposed_plan ?? {}
  const plans = plan.plan_summary?.plans ?? plan.score_summary?.plans ?? row.proposed_score_summary?.plans
  if (plans && typeof plans === 'object') {
    return Object.fromEntries(Object.entries(plans).map(([surface, value]) => [surface, Array.isArray(value?.selected) ? value.selected : []]))
  }
  const selected = plan.selected
  if (Array.isArray(selected)) return { shortcut_notification: selected }
  if (selected && typeof selected === 'object') return { shortcut_notification: [selected] }
  return {}
}

function selectedItems(row) {
  return Object.values(selectedBySurface(row)).flat()
}

function diagnosticRow(row, index) {
  const plan = row.proposed_plan ?? {}
  const baseline = row.baseline_payload ?? {}
  const selected = selectedItems(row)
  const selectedBySurfaceMap = selectedBySurface(row)
  const candidateCount = plan.candidate_count ?? row.proposed_score_summary?.candidate_count ?? null
  const baselineStatus = baseline.status ?? 'unknown'
  const autoFlags = []
  if (candidateCount === 0) autoFlags.push('candidate_count_zero')
  if (candidateCount === null) autoFlags.push('planner_output_missing_or_not_auto_planned')
  if (baselineStatus === 'pending' || baselineStatus === 'staging') autoFlags.push('baseline_not_final')
  if (selected.length > 0) autoFlags.push('planner_selected_candidate')
  return {
    sample_id: `shadow-${String(index + 1).padStart(2, '0')}`,
    occurred_at: row.occurred_at,
    record_type: baselineRecordType(row),
    record_id: row.record_id,
    ai_log_id: row.ai_log_id,
    baseline_status: baselineStatus,
    baseline_badge: baseline.ai_feedback?.badge ?? null,
    baseline_utility: baseline.ai_feedback?.utility_line ?? null,
    baseline_notification: baseline.notification ?? null,
    candidate_count: candidateCount,
    selected_semantic_keys: [...new Set(selected.map(item => item.semantic_key).filter(Boolean))],
    selected_by_surface: Object.fromEntries(Object.entries(selectedBySurfaceMap).map(([surface, items]) => [surface, [...new Set(items.map(item => item.semantic_key).filter(Boolean))]])),
    selected_claims: selected.map(item => item.canonical_text ?? null).filter(Boolean),
    rollout_mode: row.rollout_mode,
    changes_user_output: row.changes_user_output,
    collector_version: row.collector_version,
    auto_flags: autoFlags,
    error_codes: [],
    root_layer: null,
    expected_action: null,
    fact_contract_can_block: null,
    notes: null,
  }
}

function escapeCell(value) {
  return String(value ?? '').replaceAll('|', '\\|').replaceAll('\n', '<br>')
}

function markdown(rows, fetchedAt) {
  const lines = [
    '# Expression Planner Shadow 逐条诊断表',
    '',
    `> 自动导出时间：${fetchedAt}`,
    '> 数据来源：生产 `expression_shadow_runs`；本文件只读导出，不代表 Planner 已接管生产。',
    '> `error_codes`、`root_layer`、`expected_action` 和 `fact_contract_can_block` 必须人工确认，脚本不自动猜测。',
    '',
    '| sample_id | 时间 | 域 | baseline 状态 | Planner 候选数 | Planner 选择 | 按 Surface 选择 | 自动标记 | 错误编码 | 根因层 | Fact Contract |',
    '|---|---|---|---|---:|---|---|---|---|---|---|',
  ]
  for (const row of rows) {
    const surfaceSelection = Object.entries(row.selected_by_surface ?? {})
      .filter(([, keys]) => keys.length > 0)
      .map(([surface, keys]) => `${surface}: ${keys.join(', ')}`)
      .join('<br>')
    lines.push(`| ${row.sample_id} | ${escapeCell(row.occurred_at)} | ${escapeCell(row.record_type)} | ${escapeCell(row.baseline_status)} | ${row.candidate_count ?? ''} | ${escapeCell(row.selected_semantic_keys.join(', '))} | ${escapeCell(surfaceSelection)} | ${escapeCell(row.auto_flags.join(', '))} | ${escapeCell(row.error_codes.join(', '))} | ${escapeCell(row.root_layer)} | ${escapeCell(row.fact_contract_can_block)} |`)
  }
  lines.push('', '## 字段说明', '', '- `Planner 候选数`：Shadow 记录中的候选数量；空值表示没有自动规划结果或当时处于待处理链路。', '- `Planner 选择`：Shadow 记录写入的候选语义键，不等于用户实际看到的内容。', '- `自动标记`：仅描述数据形状，不是质量结论。', '- `错误编码`：使用诊断索引中的编码，例如 `fact_wrong`、`candidate_missing`、`semantic_repeat`。', '- `根因层`：在 `fact → candidate → gate → score → selection → surface → render → feedback → operations` 中选择一个主要层级。', '- `Fact Contract`：填写 `yes`、`partial` 或 `no`。')
  return lines.join('\n') + '\n'
}

async function main() {
  const url = requireEnv(['TEST_SUPABASE_URL', 'SUPABASE_URL', 'VITE_SUPABASE_URL'])
  const key = requireEnv(['TEST_SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'TEST_RECEIPT_LOG_KEY', 'VITE_SUPABASE_ANON_KEY'])
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data, error } = await client.from('expression_shadow_runs')
    .select('occurred_at,ai_log_id,record_type,record_id,rollout_mode,baseline_payload,proposed_plan,proposed_score_summary,changes_user_output,collector_version')
    .order('occurred_at', { ascending: true })
  if (error) throw new Error(error.message)

  const fetchedAt = new Date().toISOString()
  const rows = (data ?? []).map(diagnosticRow)
  const outputDir = path.join(projectRoot, 'test-results', 'expression-planner', 'diagnosis')
  await mkdir(outputDir, { recursive: true })
  await writeFile(path.join(outputDir, 'shadow-runs-v0.1.json'), JSON.stringify({ schema_version: 'shadow-diagnosis-v0.1', fetched_at: fetchedAt, read_only: true, rows }, null, 2) + '\n')
  await writeFile(path.join(outputDir, 'shadow-runs-v0.1.md'), markdown(rows, fetchedAt))
  console.log(JSON.stringify({ row_count: rows.length, output_dir: outputDir, read_only: true }, null, 2))
}

main().catch(error => {
  console.error(error.message)
  process.exitCode = 1
})
