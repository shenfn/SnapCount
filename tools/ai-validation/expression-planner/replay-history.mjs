import { createClient } from '@supabase/supabase-js'
import { execFileSync } from 'node:child_process'
import { access, mkdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { compileMerchantAliases, resolveMerchant } from './lib/entity-normalizer.mjs'
import { buildRecognitionLedger, compileEventOverrides, summarizeLedger } from './lib/event-ledger.mjs'
import { generateFactCandidates } from './lib/fact-candidates.mjs'
import { generateComparisonCandidates } from './lib/comparison-candidates.mjs'
import { evaluateCandidates, summarizeEligibility } from './lib/eligibility-gates.mjs'
import { scoreCandidates, summarizeScores } from './lib/deterministic-scoring.mjs'
import { buildExpressionPlans, summarizePlans } from './lib/expression-plan.mjs'
import { buildExposureEvents, buildRenderPlans } from './lib/render-contract.mjs'
import { auditTransactions, buildOccurredAt, summarizeTransactions } from './lib/replay-core.mjs'
import { buildExpressionSummary, buildExpressionTrace } from './lib/trace-export.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const projectRoot = path.resolve(__dirname, '..', '..', '..')

function parseArgs(argv) {
  const result = { timezoneOffset: '+08:00', timeZone: 'Asia/Shanghai' }
  for (const arg of argv) {
    if (arg.startsWith('--user-id=')) result.userId = arg.slice(10)
    else if (arg.startsWith('--as-of=')) result.asOf = arg.slice(8)
    else if (arg.startsWith('--merchant=')) result.merchant = arg.slice(11)
    else if (arg.startsWith('--current-record-id=')) result.currentRecordId = arg.slice(20)
    else if (arg.startsWith('--timezone-offset=')) result.timezoneOffset = arg.slice(18)
    else if (arg.startsWith('--output-dir=')) result.outputDir = arg.slice(13)
    else if (arg.startsWith('--trace-run-id=')) result.traceRunId = arg.slice(15)
    else if (arg.startsWith('--alias-config=')) result.aliasConfig = arg.slice(15)
    else if (arg.startsWith('--event-overrides=')) result.eventOverrides = arg.slice(18)
  }
  if (!result.userId) throw new Error('Missing required --user-id=<uuid>')
  if (!result.asOf || Number.isNaN(new Date(result.asOf).getTime())) throw new Error('Missing or invalid --as-of=<ISO datetime>')
  return result
}

function requireEnv(names) {
  for (const name of names) if (process.env[name]) return process.env[name]
  throw new Error(`Missing one of: ${names.join(', ')}`)
}

function localDateOf(value, timeZone) {
  const parts = new Intl.DateTimeFormat('en', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(value))
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]))
  return `${values.year}-${values.month}-${values.day}`
}

async function readJson(relativePath) {
  const filePath = path.isAbsolute(relativePath) ? relativePath : path.join(__dirname, relativePath)
  const text = await readFile(filePath, 'utf8')
  return JSON.parse(text.replace(/^\uFEFF/, ''))
}

async function firstAvailablePath(paths) {
  for (const candidate of paths.filter(Boolean)) {
    const filePath = path.isAbsolute(candidate) ? candidate : path.join(__dirname, candidate)
    try {
      await access(filePath)
      return candidate
    } catch {}
  }
  throw new Error(`No readable config found: ${paths.filter(Boolean).join(', ')}`)
}

async function fetchAll(queryFactory, pageSize = 1000) {
  const rows = []
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await queryFactory().range(from, from + pageSize - 1)
    if (error) throw new Error(error.message)
    rows.push(...(data ?? []))
    if (!data || data.length < pageSize) return rows
  }
}

function latestBy(logs, field) {
  const result = new Map()
  for (const row of logs) {
    const key = row[field]
    if (!key) continue
    const previous = result.get(key)
    if (!previous || new Date(row.created_at) > new Date(previous.created_at)) result.set(key, row)
  }
  return result
}

function gitRevision() {
  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: projectRoot, encoding: 'utf8' }).trim()
  } catch {
    return null
  }
}

function plannerEntityIds(ledger, merchantFilter) {
  if (merchantFilter?.entity_id) return [merchantFilter.entity_id]
  return [...new Set(
    ledger
      .filter(event => event.count_in_facts && event.amount !== null)
      .map(event => event.merchant?.entity_id)
      .filter(Boolean),
  )]
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const url = requireEnv(['TEST_SUPABASE_URL', 'SUPABASE_URL', 'VITE_SUPABASE_URL'])
  const key = requireEnv(['TEST_SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'TEST_RECEIPT_LOG_KEY', 'VITE_SUPABASE_ANON_KEY'])
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

  const aliasConfigPath = await firstAvailablePath([
    args.aliasConfig,
    'configs/entity-aliases.v0.1.json',
    'configs/entity-aliases.public.v0.1.json',
  ])
  const eventOverrideConfigPath = await firstAvailablePath([
    args.eventOverrides,
    'configs/event-overrides.v0.1.json',
    'configs/event-overrides.public.v0.1.json',
  ])
  const aliasConfig = await readJson(aliasConfigPath)
  const eventOverrideConfig = await readJson(eventOverrideConfigPath)
  const aliasMap = compileMerchantAliases(aliasConfig)
  const overrideMap = compileEventOverrides(eventOverrideConfig)
  const merchantFilter = args.merchant ? resolveMerchant(args.merchant, aliasMap) : null
  const asOfDate = localDateOf(args.asOf, args.timeZone)

  const transactions = await fetchAll(() => client.from('transactions')
    .select('id,created_at,transaction_date,transaction_time,type,amount,merchant_name,platform,category,payment_method,status,source,note,user_id,account_id,companion_message,ai_feedback,image_hash')
    .eq('user_id', args.userId).lte('created_at', args.asOf).order('created_at', { ascending: true }))

  const logs = await fetchAll(() => client.from('ai_recognition_logs')
    .select('id,created_at,occurred_at,order_finished_at,status,duplicate_kind,duplicate_ref_id,target_table,target_id,staging_record_id,image_hash,record_type,image_type,ai_response,prompt_version,model_name,user_id')
    .eq('user_id', args.userId).lte('created_at', args.asOf).order('created_at', { ascending: true }))

  const logsByTarget = latestBy(logs, 'target_id')
  const logsByHash = latestBy(logs, 'image_hash')
  const records = transactions.map(row => ({
    ...row,
    occurred_at: buildOccurredAt(row, args.timezoneOffset),
    merchant: resolveMerchant(row.merchant_name, aliasMap),
    source_log: logsByTarget.get(row.id) ?? logsByHash.get(row.image_hash) ?? null,
  })).filter(row => row.occurred_at && new Date(row.occurred_at) <= new Date(args.asOf))

  const scopedRecords = records.filter(row => !merchantFilter || row.merchant.entity_id === merchantFilter.entity_id)
  const ledger = buildRecognitionLedger(logs, { aliasMap, resolveMerchant, overrideMap })
    .filter(event => new Date(event.known_at) <= new Date(args.asOf))
    .filter(event => localDateOf(event.event_at, args.timeZone) === asOfDate)
    .filter(event => !merchantFilter || event.merchant.entity_id === merchantFilter.entity_id)
  const entityIds = plannerEntityIds(ledger, merchantFilter)
  const generatedFactCandidates = entityIds.flatMap(entityId => generateFactCandidates(ledger, {
    entityId,
    localDate: asOfDate,
    timeZone: args.timeZone,
  }))
  const generatedComparisonCandidates = entityIds.flatMap(entityId => generateComparisonCandidates({
    records: scopedRecords,
    currentDayEvents: ledger,
    entityId,
    localDate: asOfDate,
  }))

  const eligibleFactCandidates = evaluateCandidates(generatedFactCandidates)
  const eligibleComparisonCandidates = evaluateCandidates(generatedComparisonCandidates)
  const eligibilitySummary = summarizeEligibility([...eligibleFactCandidates, ...eligibleComparisonCandidates])
  const scoringOptions = {
    context: { entity_id: merchantFilter?.entity_id ?? null },
    preferenceProfile: {},
    exposureHistory: {},
  }
  const factCandidates = scoreCandidates(eligibleFactCandidates, scoringOptions)
  const comparisonCandidates = scoreCandidates(eligibleComparisonCandidates, scoringOptions)
  const allCandidates = [...factCandidates, ...comparisonCandidates]
  const scoringSummary = summarizeScores(allCandidates)
  const expressionPlans = buildExpressionPlans(allCandidates)
  const expressionPlanSummary = summarizePlans(expressionPlans)
  const renderPlans = buildRenderPlans(expressionPlans, allCandidates)
  const exposureEvents = buildExposureEvents(renderPlans, {
    traceId: `expression-replay:${args.userId}:${merchantFilter?.entity_id ?? 'all-merchants'}:${asOfDate}`,
    occurredAt: args.asOf,
    simulationOnly: true,
  })

  const currentDayRecords = scopedRecords.filter(row => row.transaction_date === asOfDate)
  const currentRecord = args.currentRecordId
    ? scopedRecords.find(row => row.id === args.currentRecordId) ?? null
    : scopedRecords.at(-1) ?? null
  const snapshot = {
    schema_version: 'expression-replay-snapshot-v0.3',
    generated_at: new Date().toISOString(),
    read_only: true,
    input: args,
    versions: {
      replay: 'replay-history-v0.3',
      git_revision: gitRevision(),
      working_tree_state: 'local_worktree_may_be_dirty',
      alias_config: aliasConfig.version ?? null,
      event_override_config: eventOverrideConfig.version ?? null,
      candidate: 'candidate-v0.1',
      scoring: 'deterministic-score-v0.2',
      expression_plan: 'expression-plan-v0.1',
      render_contract: 'render-contract-v0.1',
    },
    planner_scope: {
      mode: merchantFilter ? 'single_entity' : 'all_entities',
      entity_ids: entityIds,
      entity_partitioning: 'candidates_generated_per_entity_before_global_surface_selection',
    },
    configuration: {
      alias_config_path: aliasConfigPath,
      event_override_config_path: eventOverrideConfigPath,
      private_config_loaded: !aliasConfigPath.includes('.public.') || !eventOverrideConfigPath.includes('.public.'),
      preference_profile: {},
      exposure_history: {},
    },
    data_boundary: {
      user_id: args.userId,
      as_of: args.asOf,
      transaction_query_boundary: 'known_at <= as_of and event_at <= as_of',
      profile_source: 'rebuilt_from_raw_transactions_and_recognition_ledger',
      future_profile_used: false,
    },
    entity_filter: merchantFilter,
    current_record: currentRecord,
    confirmed_record_summaries: {
      all_history: summarizeTransactions(scopedRecords, args.currentRecordId),
      current_day: summarizeTransactions(currentDayRecords, args.currentRecordId),
    },
    recognition_ledger: {
      summary: summarizeLedger(ledger),
      events: ledger,
    },
    fact_candidates: factCandidates,
    comparison_candidates: comparisonCandidates,
    eligibility_summary: eligibilitySummary,
    scoring_context: { preference_profile_source: 'neutral_default', exposure_history_source: 'empty_baseline' },
    scoring_summary: scoringSummary,
    expression_plans: expressionPlans,
    expression_plan_summary: expressionPlanSummary,
    render_plans: renderPlans,
    exposure_events: exposureEvents,
    audit: auditTransactions(scopedRecords),
    records: scopedRecords,
  }

  const outputDir = args.outputDir ? path.resolve(args.outputDir) : path.join(projectRoot, 'test-results', 'expression-planner', 'replays')
  await mkdir(outputDir, { recursive: true })
  const safeAsOf = args.asOf.replace(/[:.]/g, '-').replaceAll('+', 'plus')
  const entityPart = merchantFilter?.entity_id ?? 'all-merchants'
  const outputPath = path.join(outputDir, `${args.userId}__${entityPart}__${safeAsOf}.context.snapshot.json`)
  await writeFile(outputPath, JSON.stringify(snapshot, null, 2) + '\n', 'utf8')

  const trace = buildExpressionTrace(snapshot, { runId: args.traceRunId, localDate: asOfDate })
  const traceRunDir = path.join(projectRoot, 'test-results', trace.run_id)
  const traceDomainDir = path.join(traceRunDir, 'expression_planner', asOfDate)
  await mkdir(traceDomainDir, { recursive: true })
  const tracePath = path.join(traceDomainDir, `${trace.case.test_case_file}.trace.json`)
  const summaryPath = path.join(traceRunDir, 'summary.json')
  await writeFile(tracePath, JSON.stringify(trace, null, 2) + '\n', 'utf8')
  await writeFile(summaryPath, JSON.stringify(buildExpressionSummary(trace), null, 2) + '\n', 'utf8')

  console.log(outputPath)
  console.log(tracePath)
  console.log(JSON.stringify({
    confirmed_records: scopedRecords.length,
    confirmed_current_day: currentDayRecords.length,
    ledger: snapshot.recognition_ledger.summary,
    fact_candidates: factCandidates.map(item => item.claim),
    comparison_candidates: comparisonCandidates.map(item => item.claim),
    eligibility: eligibilitySummary,
    scoring: scoringSummary,
    expression_plans: expressionPlanSummary,
    render_plans: Object.fromEntries(Object.entries(renderPlans).map(([surface, plan]) => [surface, { selected_count: plan.selected.length, render_state: plan.render_state, simulation_only: plan.simulation_only }])),
    exposure_preview_count: exposureEvents.length,
    category_conflicts: snapshot.audit.category_conflicts,
  }, null, 2))
}

main().catch(error => {
  console.error(error.message)
  process.exitCode = 1
})
