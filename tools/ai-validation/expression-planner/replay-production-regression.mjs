import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createClient } from '@supabase/supabase-js'
import { build } from 'esbuild'

const here = path.dirname(fileURLToPath(import.meta.url))
const projectRoot = path.resolve(here, '..', '..', '..')
const defaultOutputRoot = path.resolve(projectRoot, '..', '..', '别提交到github上', 'reference', '算法讨论', '表达规划器真实数据回放')
const genericDomains = new Set(['income', 'sleep', 'sport', 'food', 'reading', 'wallet'])

function parseArgs(argv) {
  const args = {
    mode: 'fetch',
    outputRoot: defaultOutputRoot,
    includeTests: false,
    since: null,
    input: null,
  }
  for (const arg of argv) {
    if (arg.startsWith('--mode=')) args.mode = arg.slice(7)
    else if (arg.startsWith('--output-root=')) args.outputRoot = path.resolve(arg.slice(14))
    else if (arg.startsWith('--input=')) args.input = path.resolve(arg.slice(8))
    else if (arg.startsWith('--since=')) args.since = arg.slice(8)
    else if (arg === '--include-tests') args.includeTests = true
  }
  if (!['fetch', 'offline'].includes(args.mode)) throw new Error('--mode must be fetch or offline')
  if (args.mode === 'offline' && !args.input) throw new Error('--input=<source.snapshot.json> is required in offline mode')
  if (args.since && Number.isNaN(new Date(args.since).getTime())) throw new Error('--since must be an ISO date or datetime')
  return args
}

function requireEnv(names) {
  for (const name of names) if (process.env[name]) return process.env[name]
  throw new Error(`Missing one of: ${names.join(', ')}`)
}

async function fetchAll(queryFactory, pageSize = 500) {
  const rows = []
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await queryFactory().range(from, from + pageSize - 1)
    if (error) throw new Error(error.message)
    rows.push(...(data ?? []))
    if (!data || data.length < pageSize) return rows
  }
}

function timestampForPath(value = new Date()) {
  return value.toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15)
}

function stableUserKey(userId) {
  if (!userId) return 'user-unknown'
  return `user-${createHash('sha256').update(userId).digest('hex').slice(0, 12)}`
}

function gitState() {
  try {
    const revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: projectRoot, encoding: 'utf8' }).trim()
    const status = execFileSync('git', ['status', '--short'], { cwd: projectRoot, encoding: 'utf8' }).trim()
    return { revision, dirty: Boolean(status), status: status ? status.split(/\r?\n/) : [] }
  } catch {
    return { revision: null, dirty: null, status: [] }
  }
}

function cloneWithoutUserId(row) {
  const { user_id: userId, ...rest } = row
  return { ...rest, user_key: stableUserKey(userId) }
}

function isTestRecord(row) {
  return Boolean(row?.payload_jsonb?.test_meta)
}

function eventTime(row) {
  const value = row.occurred_at ?? row.created_at
  const time = new Date(value ?? '').getTime()
  return Number.isFinite(time) ? time : null
}

function transactionOccurredAt(row) {
  const date = row.transaction_date
  if (!date) return row.created_at ?? null
  const time = row.transaction_time || '12:00:00'
  return `${date}T${time}+08:00`
}

function rowOrder(a, b) {
  return (eventTime(a) ?? Number.MAX_SAFE_INTEGER) - (eventTime(b) ?? Number.MAX_SAFE_INTEGER)
}

function groupBy(rows, keyOf) {
  const result = new Map()
  for (const row of rows) {
    const key = keyOf(row)
    if (!result.has(key)) result.set(key, [])
    result.get(key).push(row)
  }
  return result
}

function latestShadowByRecord(rows) {
  const result = new Map()
  for (const row of rows) {
    if (!row.record_id) continue
    const previous = result.get(row.record_id)
    if (!previous || new Date(row.created_at) > new Date(previous.created_at)) result.set(row.record_id, row)
  }
  return result
}

function candidateKeys(plan) {
  return [...new Set((Array.isArray(plan?.candidates) ? plan.candidates : [])
    .map(item => item?.claim?.semantic_key)
    .filter(Boolean))]
}

function surfaceSelectedKeys(plan, surface) {
  const direct = plan?.plan_summary?.[surface]?.selected
    ?? plan?.plan_summary?.plans?.[surface]?.selected
    ?? (surface === 'shortcut_notification' ? plan?.selected : null)
  if (!Array.isArray(direct)) return []
  return [...new Set(direct.map(item => item?.semantic_key ?? item?.claim?.semantic_key).filter(Boolean))]
}

function summarizePlan(plan) {
  if (!plan || typeof plan !== 'object' || Object.keys(plan).length === 0) {
    return { status: 'not_run', candidate_count: null, candidate_keys: [], selected: {} }
  }
  const candidateCount = Number.isFinite(Number(plan.candidate_count)) ? Number(plan.candidate_count) : null
  return {
    status: plan.status ?? 'unknown',
    candidate_count: candidateCount,
    candidate_keys: candidateKeys(plan),
    selected: Object.fromEntries(['shortcut_notification', 'pwa_pending_ai_card', 'record_detail', 'weekly_report']
      .map(surface => [surface, surfaceSelectedKeys(plan, surface)])),
  }
}

function candidateDetails(plan) {
  return (Array.isArray(plan?.candidates) ? plan.candidates : []).map(item => ({
    candidate_id: item.candidate_id,
    semantic_key: item.claim?.semantic_key ?? null,
    dimension: item.dimension ?? null,
    claim_type: item.claim_type ?? null,
    canonical_text: item.claim?.canonical_text ?? null,
    structured_value: item.claim?.structured_value ?? null,
    quality: item.quality ?? null,
    eligibility: item.eligibility ?? null,
    scores: Object.fromEntries(Object.entries(item.scoring?.surfaces ?? {}).map(([surface, value]) => [surface, value?.score ?? null])),
  }))
}

function diffPlan(oldPlan, localPlan) {
  const oldSummary = summarizePlan(oldPlan)
  const localSummary = summarizePlan(localPlan)
  const oldKeys = new Set(oldSummary.candidate_keys)
  const localKeys = new Set(localSummary.candidate_keys)
  return {
    old: oldSummary,
    local: localSummary,
    added_candidate_keys: [...localKeys].filter(key => !oldKeys.has(key)),
    removed_candidate_keys: [...oldKeys].filter(key => !localKeys.has(key)),
    record_detail_selection_changed: JSON.stringify(oldSummary.selected.record_detail ?? []) !== JSON.stringify(localSummary.selected.record_detail ?? []),
    shortcut_selection_changed: JSON.stringify(oldSummary.selected.shortcut_notification ?? []) !== JSON.stringify(localSummary.selected.shortcut_notification ?? []),
  }
}

async function loadPlanner() {
  const entryPoint = path.join(projectRoot, 'supabase', 'functions', 'ingest-receipt', 'expression-shadow-planner.ts')
  const bundle = await build({
    absWorkingDir: projectRoot,
    entryPoints: [entryPoint],
    bundle: true,
    platform: 'node',
    format: 'esm',
    write: false,
  })
  const dataUrl = `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  return import(dataUrl)
}

async function fetchSource(args) {
  const url = requireEnv(['SUPABASE_URL', 'VITE_SUPABASE_URL'])
  const key = requireEnv(['SUPABASE_SERVICE_ROLE_KEY', 'TEST_SUPABASE_SERVICE_ROLE_KEY'])
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

  const transactions = await fetchAll(() => {
    let query = client.from('transactions')
      .select('id,created_at,transaction_date,transaction_time,type,amount,merchant_name,platform,category,payment_method,status,source,note,user_id,companion_message,ai_feedback')
      .eq('type', 'expense')
      .order('created_at', { ascending: true })
    if (args.since) query = query.gte('created_at', args.since)
    return query
  })

  const dataRecords = await fetchAll(() => {
    let query = client.from('data_records')
      .select('id,created_at,updated_at,domain_key,domain_version,occurred_at,title,summary,payload_jsonb,source,user_id')
      .order('created_at', { ascending: true })
    if (args.since) query = query.gte('created_at', args.since)
    return query
  })

  const shadowRuns = await fetchAll(() => {
    let query = client.from('expression_shadow_runs')
      .select('id,created_at,occurred_at,record_type,record_id,surface,response_mode,rollout_mode,lifecycle_state,baseline_payload,collector_result,proposed_plan,proposed_score_summary,collector_version,processing_error,changes_user_output,user_id')
      .order('created_at', { ascending: true })
    if (args.since) query = query.gte('created_at', args.since)
    return query
  })

  const exposures = await fetchAll(() => {
    let query = client.from('expression_exposure_events')
      .select('id,created_at,occurred_at,record_id,record_type,domain_key,candidate_id,semantic_key,claim_type,dimension,surface,lifecycle_state,selection_mode,score,expression_plan_version,render_contract_version,scoring_version,visible_field_paths,metadata,user_id')
      .order('created_at', { ascending: true })
    if (args.since) query = query.gte('created_at', args.since)
    return query
  })

  const feedback = await fetchAll(() => {
    let query = client.from('expression_feedback_events')
      .select('id,created_at,occurred_at,exposure_event_id,candidate_id,semantic_key,surface,visible_field_paths,primary_choice,issue_annotations,free_text,suggested_action,source_review_schema,source_review_key,metadata,user_id')
      .order('created_at', { ascending: true })
    if (args.since) query = query.gte('created_at', args.since)
    return query
  })

  const filteredRecords = args.includeTests ? dataRecords : dataRecords.filter(row => !isTestRecord(row))
  return {
    schema_version: 'expression-production-source-v0.1',
    fetched_at: new Date().toISOString(),
    read_only: true,
    filters: { since: args.since, include_tests: args.includeTests },
    privacy: { user_ids: 'sha256-prefix pseudonyms', images: 'not exported', hashes: 'not exported' },
    transactions: transactions.map(cloneWithoutUserId),
    data_records: filteredRecords.map(cloneWithoutUserId),
    shadow_runs: shadowRuns.map(cloneWithoutUserId),
    exposures: exposures.map(cloneWithoutUserId),
    feedback: feedback.map(cloneWithoutUserId),
  }
}

async function readSource(inputPath) {
  const parsed = JSON.parse(await readFile(inputPath, 'utf8'))
  if (parsed.schema_version !== 'expression-production-source-v0.1') throw new Error('Unsupported source snapshot schema')
  return parsed
}

function replayGeneric(source, planner, shadowByRecord) {
  const rows = []
  const grouped = groupBy(
    source.data_records.filter(row => genericDomains.has(row.domain_key)),
    row => `${row.user_key}:${row.domain_key}`,
  )
  for (const records of grouped.values()) {
    const ordered = [...records].sort(rowOrder)
    for (let index = 0; index < ordered.length; index += 1) {
      const current = ordered[index]
      const occurredAt = current.occurred_at ?? current.created_at
      if (!occurredAt || eventTime(current) === null) {
        rows.push({ record_id: current.id, domain_key: current.domain_key, user_key: current.user_key, status: 'skipped', reason: 'missing_event_time' })
        continue
      }
      const causalRecords = ordered.slice(0, index + 1).map(record => ({
        id: record.id,
        occurred_at: record.occurred_at ?? record.created_at,
        title: record.title,
        summary: record.summary,
        payload: record.payload_jsonb ?? {},
        source_type: record.source,
      }))
      const localPlan = planner.buildGenericExpressionShadowPlan({
        domainKey: current.domain_key,
        records: causalRecords,
        currentRecordId: current.id,
        domainProfile: {},
      })
      const oldShadow = shadowByRecord.get(current.id)
      rows.push({
        record_id: current.id,
        user_key: current.user_key,
        domain_key: current.domain_key,
        occurred_at: occurredAt,
        causal_history_count: causalRecords.length,
        current_record: { title: current.title, summary: current.summary, payload: current.payload_jsonb ?? {} },
        old_shadow: oldShadow ? {
          created_at: oldShadow.created_at,
          collector_version: oldShadow.collector_version,
          baseline_payload: oldShadow.baseline_payload ?? null,
          candidates: candidateDetails(oldShadow.proposed_plan),
          plan: summarizePlan(oldShadow.proposed_plan),
        } : null,
        local_candidates: candidateDetails(localPlan),
        comparison: diffPlan(oldShadow?.proposed_plan, localPlan),
      })
    }
  }
  return rows
}

function replayExpenses(source, planner, shadowByRecord) {
  const rows = []
  const grouped = groupBy(source.transactions, row => row.user_key)
  for (const transactions of grouped.values()) {
    const ordered = transactions
      .map(row => ({ ...row, occurred_at: transactionOccurredAt(row) }))
      .filter(row => row.status === 'done' && row.occurred_at)
      .sort(rowOrder)
    for (let index = 0; index < ordered.length; index += 1) {
      const current = ordered[index]
      const causalTransactions = ordered.slice(0, index + 1).map(row => ({
        id: row.id,
        transaction_date: row.transaction_date,
        transaction_time: row.transaction_time,
        created_at: row.created_at,
        amount: row.amount,
        merchant_name: row.merchant_name,
        category: row.category,
        platform: row.platform,
        payment_method: row.payment_method,
        status: row.status,
      }))
      const localPlan = planner.buildExpressionShadowPlan({ transactions: causalTransactions, currentRecordId: current.id })
      const oldShadow = shadowByRecord.get(current.id)
      rows.push({
        record_id: current.id,
        user_key: current.user_key,
        domain_key: 'expense',
        occurred_at: current.occurred_at,
        causal_history_count: causalTransactions.length,
        current_record: {
          amount: current.amount,
          merchant_name: current.merchant_name,
          category: current.category,
          platform: current.platform,
          payment_method: current.payment_method,
          status: current.status,
        },
        old_shadow: oldShadow ? {
          created_at: oldShadow.created_at,
          collector_version: oldShadow.collector_version,
          baseline_payload: oldShadow.baseline_payload ?? null,
          candidates: candidateDetails(oldShadow.proposed_plan),
          plan: summarizePlan(oldShadow.proposed_plan),
        } : null,
        local_candidates: candidateDetails(localPlan),
        comparison: diffPlan(oldShadow?.proposed_plan, localPlan),
      })
    }
  }
  return rows
}

function countBy(rows, keyOf) {
  const counts = new Map()
  for (const row of rows) {
    const key = keyOf(row)
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }
  return Object.fromEntries([...counts.entries()].sort((a, b) => String(a[0]).localeCompare(String(b[0]))))
}

function fieldCoverage(records, domainKey, fields) {
  const scoped = records.filter(row => row.domain_key === domainKey)
  return {
    records: scoped.length,
    fields: Object.fromEntries(fields.map(field => [field, scoped.filter(row => {
      const value = row.payload_jsonb?.[field]
      return Array.isArray(value) ? value.length > 0 : value !== null && value !== undefined && value !== ''
    }).length])),
  }
}

function buildSummary(source, rows) {
  const completeRows = rows.filter(row => row.comparison)
  const domains = [...new Set(completeRows.map(row => row.domain_key))].sort()
  const exposureById = new Map(source.exposures.map(row => [row.id, row]))
  const usableFeedback = source.feedback.filter(row => exposureById.get(row.exposure_event_id)?.surface === 'record_detail')
  return {
    schema_version: 'expression-production-regression-summary-v0.1',
    source_fetched_at: source.fetched_at,
    generated_at: new Date().toISOString(),
    causal_replay: true,
    current_domain_profile_used: false,
    source_counts: {
      transactions: source.transactions.length,
      data_records: source.data_records.length,
      shadow_runs: source.shadow_runs.length,
      exposures: source.exposures.length,
      feedback: source.feedback.length,
      usable_record_detail_feedback: usableFeedback.length,
    },
    field_coverage: {
      food: fieldCoverage(source.data_records, 'food', ['meal_type', 'total_calorie_kcal', 'dishes', 'time_context']),
      sleep: fieldCoverage(source.data_records, 'sleep', ['sleep_hours', 'sleep_minutes', 'sleep_start_at', 'wake_at', 'quality_score', 'deep_sleep_minutes', 'light_sleep_minutes', 'rem_minutes']),
    },
    domains: Object.fromEntries(domains.map(domain => {
      const scoped = completeRows.filter(row => row.domain_key === domain)
      const oldRan = scoped.filter(row => row.old_shadow && row.comparison.old.status !== 'not_run')
      const localZero = scoped.filter(row => row.comparison.local.candidate_count === 0)
      return [domain, {
        replayed: scoped.length,
        old_shadow_matched: oldRan.length,
        old_zero_candidate: oldRan.filter(row => row.comparison.old.candidate_count === 0).length,
        local_zero_candidate: localZero.length,
        candidate_set_changed_on_matched_shadow: oldRan.filter(row => row.comparison.added_candidate_keys.length || row.comparison.removed_candidate_keys.length).length,
        detail_selection_changed_on_matched_shadow: oldRan.filter(row => row.comparison.record_detail_selection_changed).length,
        added_semantic_keys_on_matched_shadow: countBy(oldRan.flatMap(row => row.comparison.added_candidate_keys), key => key),
        local_candidate_keys: countBy(scoped.flatMap(row => row.comparison.local.candidate_keys), key => key),
      }]
    })),
    training_readiness: {
      deterministic_replay: completeRows.length >= 100 ? 'ready' : 'insufficient',
      preference_calibration: usableFeedback.length >= 30 ? 'ready_for_experiment' : 'insufficient_labels',
      learned_ranker: usableFeedback.length >= 200 ? 'ready_for_prototype' : 'insufficient_labels',
      note: 'Raw records are replay inputs, not preference labels. Only feedback tied to record_detail exposure counts as current preference supervision.',
    },
  }
}

function markdown(summary, runDir) {
  const lines = [
    '# 表达规划器真实数据回放报告',
    '',
    `> 生成时间：${summary.generated_at}`,
    `> 本地目录：${runDir}`,
    '> 只读生产快照；按用户隔离、按发生时间因果回放；未使用当前时点画像。',
    '',
    '## 数据规模',
    '',
    '| 数据 | 数量 |',
    '|---|---:|',
    `| 消费记录 | ${summary.source_counts.transactions} |`,
    `| 领域记录 | ${summary.source_counts.data_records} |`,
    `| 旧 Shadow | ${summary.source_counts.shadow_runs} |`,
    `| 曝光 | ${summary.source_counts.exposures} |`,
    `| 点评 | ${summary.source_counts.feedback} |`,
    `| 可用于当前偏好学习的详情点评 | ${summary.source_counts.usable_record_detail_feedback} |`,
    '',
    '## 回放结果',
    '',
    '| 域 | 回放数 | 匹配旧 Shadow | 旧零候选 | 本地零候选 | 匹配样本候选变化 | 匹配样本详情变化 |',
    '|---|---:|---:|---:|---:|---:|---:|',
  ]
  for (const [domain, value] of Object.entries(summary.domains)) {
    lines.push(`| ${domain} | ${value.replayed} | ${value.old_shadow_matched} | ${value.old_zero_candidate} | ${value.local_zero_candidate} | ${value.candidate_set_changed_on_matched_shadow} | ${value.detail_selection_changed_on_matched_shadow} |`)
  }
  lines.push(
    '',
    '## 字段覆盖',
    '',
    '```json',
    JSON.stringify(summary.field_coverage, null, 2),
    '```',
    '',
    '## 训练判断',
    '',
    `- 确定性规则与候选回归：${summary.training_readiness.deterministic_replay}`,
    `- 偏好权重校准：${summary.training_readiness.preference_calibration}`,
    `- 学习排序模型：${summary.training_readiness.learned_ranker}`,
    '',
    '原始记录用于重建事实和历史上下文，不等于人工偏好标签。',
    '',
    '## 文件',
    '',
    '- `source.snapshot.json`：本次只读快照，可脱离线上重复回放。',
    '- `replay-results.json`：逐条候选、分数、旧 Shadow 对照与变化。',
    '- `summary.json`：聚合指标，适合版本间机器比较。',
    '- `feedback.snapshot.json`：点评及其曝光关联，保留在本地敏感目录。',
    '- `zero-candidates.json`：当前仍为零候选的逐条诊断入口。',
  )
  return lines.join('\n') + '\n'
}

async function writeJson(filePath, value) {
  await writeFile(filePath, JSON.stringify(value, null, 2) + '\n', 'utf8')
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const source = args.mode === 'fetch' ? await fetchSource(args) : await readSource(args.input)
  const planner = await loadPlanner()
  const shadowByRecord = latestShadowByRecord(source.shadow_runs)
  const replayRows = [
    ...replayExpenses(source, planner, shadowByRecord),
    ...replayGeneric(source, planner, shadowByRecord),
  ].sort((a, b) => String(a.occurred_at ?? '').localeCompare(String(b.occurred_at ?? '')))
  const summary = buildSummary(source, replayRows)

  const runName = `回放-${timestampForPath(new Date())}`
  const runDir = path.join(args.outputRoot, 'runs', runName)
  await mkdir(runDir, { recursive: true })
  await writeJson(path.join(runDir, 'source.snapshot.json'), source)
  await writeJson(path.join(runDir, 'replay-results.json'), {
    schema_version: 'expression-production-regression-results-v0.1',
    generated_at: summary.generated_at,
    planner_git: gitState(),
    source_snapshot: 'source.snapshot.json',
    rows: replayRows,
  })
  await writeJson(path.join(runDir, 'summary.json'), summary)
  await writeJson(path.join(runDir, 'feedback.snapshot.json'), {
    schema_version: 'expression-feedback-local-snapshot-v0.1',
    exposures: source.exposures,
    feedback: source.feedback,
  })
  await writeJson(path.join(runDir, 'zero-candidates.json'), {
    schema_version: 'expression-zero-candidate-diagnosis-v0.1',
    generated_at: summary.generated_at,
    rows: replayRows.filter(row => row.comparison?.local?.candidate_count === 0).map(row => ({
      record_id: row.record_id,
      user_key: row.user_key,
      domain_key: row.domain_key,
      occurred_at: row.occurred_at,
      causal_history_count: row.causal_history_count,
      current_record: row.current_record,
      old_shadow: row.old_shadow,
    })),
  })
  await writeFile(path.join(runDir, '报告.md'), markdown(summary, runDir), 'utf8')
  await writeJson(path.join(args.outputRoot, 'latest.json'), {
    schema_version: 'expression-production-regression-latest-v0.1',
    run_dir: runDir,
    generated_at: summary.generated_at,
    source_snapshot: path.join(runDir, 'source.snapshot.json'),
    summary: path.join(runDir, 'summary.json'),
  })

  execFileSync(process.execPath, [path.join(here, 'generate-production-replay-viewer.mjs'), `--run=${runDir}`], {
    cwd: projectRoot,
    stdio: 'inherit',
  })

  console.log(JSON.stringify({ run_dir: runDir, replayed: replayRows.length, summary }, null, 2))
}

main().catch(error => {
  console.error(error.stack || error.message)
  process.exitCode = 1
})
