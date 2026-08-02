import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'

function parseArgs(argv) {
  const args = { failOnZeroRegression: false }
  for (const arg of argv) {
    if (arg.startsWith('--baseline=')) args.baseline = path.resolve(arg.slice(11))
    else if (arg.startsWith('--current=')) args.current = path.resolve(arg.slice(10))
    else if (arg.startsWith('--output=')) args.output = path.resolve(arg.slice(9))
    else if (arg === '--fail-on-zero-regression') args.failOnZeroRegression = true
  }
  if (!args.baseline || !args.current) throw new Error('--baseline=<run dir> and --current=<run dir> are required')
  return args
}

async function readRun(input) {
  const filePath = input.endsWith('.json') ? input : path.join(input, 'replay-results.json')
  const parsed = JSON.parse(await readFile(filePath, 'utf8'))
  if (parsed.schema_version !== 'expression-production-regression-results-v0.1') throw new Error(`Unsupported replay result: ${filePath}`)
  return { filePath, runDir: path.dirname(filePath), parsed }
}

function selectedKeys(row, surface) {
  return row?.comparison?.local?.selected?.[surface] ?? []
}

function candidateKeys(row) {
  return row?.comparison?.local?.candidate_keys ?? []
}

function sameArray(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}

function countBy(rows, keyOf) {
  const counts = new Map()
  for (const row of rows) {
    const key = keyOf(row)
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }
  return Object.fromEntries([...counts.entries()].sort((a, b) => String(a[0]).localeCompare(String(b[0]))))
}

function compare(baseline, current) {
  const baselineById = new Map(baseline.parsed.rows.map(row => [row.record_id, row]))
  const currentById = new Map(current.parsed.rows.map(row => [row.record_id, row]))
  const commonIds = [...baselineById.keys()].filter(id => currentById.has(id))
  const rows = commonIds.map(recordId => {
    const before = baselineById.get(recordId)
    const after = currentById.get(recordId)
    const beforeKeys = candidateKeys(before)
    const afterKeys = candidateKeys(after)
    const beforeSet = new Set(beforeKeys)
    const afterSet = new Set(afterKeys)
    const beforeCount = before?.comparison?.local?.candidate_count
    const afterCount = after?.comparison?.local?.candidate_count
    return {
      record_id: recordId,
      user_key: after.user_key,
      domain_key: after.domain_key,
      occurred_at: after.occurred_at,
      before_candidate_count: beforeCount,
      after_candidate_count: afterCount,
      zero_candidate_regression: beforeCount > 0 && afterCount === 0,
      zero_candidate_improvement: beforeCount === 0 && afterCount > 0,
      added_candidate_keys: afterKeys.filter(key => !beforeSet.has(key)),
      removed_candidate_keys: beforeKeys.filter(key => !afterSet.has(key)),
      detail_selection_changed: !sameArray(selectedKeys(before, 'record_detail'), selectedKeys(after, 'record_detail')),
      shortcut_selection_changed: !sameArray(selectedKeys(before, 'shortcut_notification'), selectedKeys(after, 'shortcut_notification')),
    }
  })
  const domains = [...new Set(rows.map(row => row.domain_key))].sort()
  return {
    schema_version: 'expression-production-regression-comparison-v0.1',
    generated_at: new Date().toISOString(),
    baseline_run: baseline.runDir,
    current_run: current.runDir,
    common_records: rows.length,
    baseline_only_records: [...baselineById.keys()].filter(id => !currentById.has(id)).length,
    current_only_records: [...currentById.keys()].filter(id => !baselineById.has(id)).length,
    totals: {
      zero_candidate_regressions: rows.filter(row => row.zero_candidate_regression).length,
      zero_candidate_improvements: rows.filter(row => row.zero_candidate_improvement).length,
      candidate_set_changes: rows.filter(row => row.added_candidate_keys.length || row.removed_candidate_keys.length).length,
      detail_selection_changes: rows.filter(row => row.detail_selection_changed).length,
      shortcut_selection_changes: rows.filter(row => row.shortcut_selection_changed).length,
    },
    domains: Object.fromEntries(domains.map(domain => {
      const scoped = rows.filter(row => row.domain_key === domain)
      return [domain, {
        common_records: scoped.length,
        zero_candidate_regressions: scoped.filter(row => row.zero_candidate_regression).length,
        zero_candidate_improvements: scoped.filter(row => row.zero_candidate_improvement).length,
        candidate_set_changes: scoped.filter(row => row.added_candidate_keys.length || row.removed_candidate_keys.length).length,
        detail_selection_changes: scoped.filter(row => row.detail_selection_changed).length,
        added_candidate_keys: countBy(scoped.flatMap(row => row.added_candidate_keys), key => key),
        removed_candidate_keys: countBy(scoped.flatMap(row => row.removed_candidate_keys), key => key),
      }]
    })),
    rows: rows.filter(row => row.zero_candidate_regression || row.zero_candidate_improvement || row.added_candidate_keys.length || row.removed_candidate_keys.length || row.detail_selection_changed || row.shortcut_selection_changed),
  }
}

function markdown(result) {
  const lines = [
    '# 表达规划器回归对比',
    '',
    `> 基线：${result.baseline_run}`,
    `> 当前：${result.current_run}`,
    '',
    '| 指标 | 数量 |',
    '|---|---:|',
    `| 共同记录 | ${result.common_records} |`,
    `| 新增零候选（退化） | ${result.totals.zero_candidate_regressions} |`,
    `| 零候选恢复（改善） | ${result.totals.zero_candidate_improvements} |`,
    `| 候选集合变化 | ${result.totals.candidate_set_changes} |`,
    `| 详情选择变化 | ${result.totals.detail_selection_changes} |`,
    `| 快捷通知选择变化 | ${result.totals.shortcut_selection_changes} |`,
    '',
    '## 分域',
    '',
    '| 域 | 共同记录 | 新增零候选 | 零候选恢复 | 候选变化 | 详情变化 |',
    '|---|---:|---:|---:|---:|---:|',
  ]
  for (const [domain, value] of Object.entries(result.domains)) {
    lines.push(`| ${domain} | ${value.common_records} | ${value.zero_candidate_regressions} | ${value.zero_candidate_improvements} | ${value.candidate_set_changes} | ${value.detail_selection_changes} |`)
  }
  return lines.join('\n') + '\n'
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const baseline = await readRun(args.baseline)
  const current = await readRun(args.current)
  const result = compare(baseline, current)
  const outputDir = args.output ?? current.runDir
  const baselineName = path.basename(baseline.runDir)
  const jsonPath = path.join(outputDir, `对比-${baselineName}.json`)
  const markdownPath = path.join(outputDir, `对比-${baselineName}.md`)
  await writeFile(jsonPath, JSON.stringify(result, null, 2) + '\n', 'utf8')
  await writeFile(markdownPath, markdown(result), 'utf8')
  console.log(JSON.stringify({ json: jsonPath, markdown: markdownPath, totals: result.totals }, null, 2))
  if (args.failOnZeroRegression && result.totals.zero_candidate_regressions > 0) process.exitCode = 2
}

main().catch(error => {
  console.error(error.stack || error.message)
  process.exitCode = 1
})
