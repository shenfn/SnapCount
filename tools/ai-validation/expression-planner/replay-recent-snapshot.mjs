import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..')
const anonymousAccountKey = Symbol('single-account-without-user-id')

function argument(name) {
  const prefix = `--${name}=`
  return process.argv.find(item => item.startsWith(prefix))?.slice(prefix.length) ?? null
}

function requireArgument(name) {
  const value = argument(name)
  if (!value) throw new Error(`Missing required argument: --${name}=<path>`)
  return path.resolve(value)
}

function timestamp(value) {
  const parsed = new Date(value ?? '').getTime()
  return Number.isFinite(parsed) ? parsed : null
}

function isInEvaluationWindow(record, window) {
  const value = timestamp(record.created_at ?? record.occurred_at)
  const start = timestamp(window?.start)
  const end = timestamp(window?.end_exclusive)
  return value !== null && start !== null && end !== null && value >= start && value < end
}

function accountKey(record) {
  const userId = typeof record?.user_id === 'string' ? record.user_id.trim() : ''
  return userId || anonymousAccountKey
}

function groupByAccount(records) {
  const groups = new Map()
  for (const record of records) {
    const key = accountKey(record)
    const group = groups.get(key) ?? []
    group.push(record)
    groups.set(key, group)
  }
  return groups
}

function withoutUserId(value) {
  if (Array.isArray(value)) return value.map(withoutUserId)
  if (!value || typeof value !== 'object') return value
  return Object.fromEntries(Object.entries(value)
    .filter(([key]) => key !== 'user_id')
    .map(([key, item]) => [key, withoutUserId(item)]))
}

function domainPlannerRecord(record) {
  const { user_id: _userId, payload_jsonb: payloadJson, ...rest } = record
  return {
    ...rest,
    payload: record.payload ?? payloadJson ?? {},
  }
}

function selectedSurfaces(plan, semanticKey) {
  return Object.entries(plan.plan_summary ?? {})
    .filter(([, summary]) => summary.selected?.some(item => item.semantic_key === semanticKey))
    .map(([surface]) => surface)
}

function compactCandidate(candidate, plan) {
  const semanticKey = candidate.claim?.semantic_key ?? null
  return {
    semantic_key: semanticKey,
    dimension: candidate.dimension ?? null,
    claim_type: candidate.claim_type ?? null,
    canonical_text: candidate.claim?.canonical_text ?? null,
    structured_value: withoutUserId(candidate.claim?.structured_value ?? null),
    quality: withoutUserId(candidate.quality ?? null),
    surface_scores: withoutUserId(candidate.scoring?.surfaces ?? {}),
    selected_surfaces: selectedSurfaces(plan, semanticKey),
  }
}

function compactPlan(record, domainKey, plan) {
  return {
    record_id: record.id,
    domain_key: domainKey,
    created_at: record.created_at ?? null,
    occurred_at: record.occurred_at ?? null,
    status: plan.status,
    reason: plan.reason ?? null,
    candidate_count: plan.candidate_count ?? 0,
    candidates: (plan.candidates ?? []).map(candidate => compactCandidate(candidate, plan)),
    plan_summary: withoutUserId(plan.plan_summary ?? null),
  }
}

function increment(map, key, amount = 1) {
  map.set(key, (map.get(key) ?? 0) + amount)
}

function summarize(records) {
  const candidateFrequency = new Map()
  const selectedFrequency = new Map()
  const zeroByDomain = new Map()

  for (const record of records) {
    if (!record.candidate_count) increment(zeroByDomain, record.domain_key)
    for (const candidate of record.candidates) increment(candidateFrequency, `${record.domain_key}:${candidate.semantic_key}`)
    for (const [surface, plan] of Object.entries(record.plan_summary ?? {})) {
      for (const selected of plan.selected ?? []) increment(selectedFrequency, `${surface}:${selected.semantic_key}`)
    }
  }

  const rows = map => [...map.entries()]
    .map(([key, count]) => ({ key, count }))
    .sort((left, right) => right.count - left.count || left.key.localeCompare(right.key))

  return {
    evaluated_record_count: records.length,
    records_with_candidates: records.filter(record => record.candidate_count > 0).length,
    zero_candidate_count: records.filter(record => !record.candidate_count).length,
    zero_candidate_by_domain: rows(zeroByDomain),
    candidate_frequency: rows(candidateFrequency),
    selected_frequency: rows(selectedFrequency),
  }
}

function selectedSignature(record) {
  return Object.fromEntries(Object.entries(record.plan_summary ?? {}).map(([surface, plan]) => [
    surface,
    (plan.selected ?? []).map(item => item.semantic_key),
  ]))
}

export function compareRecords(baselineRecords, currentRecords) {
  const baselineById = new Map(baselineRecords.map(record => [record.record_id, record]))
  const candidate_changes = []
  const selection_changes = []
  const zero_candidate_regressions = []

  for (const current of currentRecords) {
    const baseline = baselineById.get(current.record_id)
    if (!baseline) continue
    const beforeCandidates = baseline.candidates.map(item => item.semantic_key)
    const afterCandidates = current.candidates.map(item => item.semantic_key)
    if (JSON.stringify(beforeCandidates) !== JSON.stringify(afterCandidates)) {
      candidate_changes.push({ record_id: current.record_id, domain_key: current.domain_key, before: beforeCandidates, after: afterCandidates })
    }
    const beforeSelection = selectedSignature(baseline)
    const afterSelection = selectedSignature(current)
    if (JSON.stringify(beforeSelection) !== JSON.stringify(afterSelection)) {
      selection_changes.push({ record_id: current.record_id, domain_key: current.domain_key, before: beforeSelection, after: afterSelection })
    }
    if (baseline.candidate_count > 0 && current.candidate_count === 0) {
      zero_candidate_regressions.push({ record_id: current.record_id, domain_key: current.domain_key })
    }
  }

  return {
    candidate_change_count: candidate_changes.length,
    selection_change_count: selection_changes.length,
    zero_candidate_regression_count: zero_candidate_regressions.length,
    candidate_changes,
    selection_changes,
    zero_candidate_regressions,
  }
}

async function loadPlanner() {
  const bundle = await build({
    absWorkingDir: projectRoot,
    entryPoints: ['supabase/functions/ingest-receipt/expression-shadow-planner.ts'],
    bundle: true,
    platform: 'node',
    format: 'esm',
    write: false,
  })
  const url = `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
  return import(url)
}

export async function replaySnapshot(snapshot) {
  const { buildExpressionShadowPlan, buildGenericExpressionShadowPlan } = await loadPlanner()
  const evaluated = []

  for (const transactions of groupByAccount(snapshot.transactions ?? []).values()) {
    for (const record of transactions) {
      if (!isInEvaluationWindow(record, snapshot.window)) continue
      const plan = buildExpressionShadowPlan({
        transactions,
        currentRecordId: record.id,
      })
      evaluated.push(compactPlan(record, 'expense', plan))
    }
  }

  for (const accountRecords of groupByAccount(snapshot.domain_records ?? []).values()) {
    const recordsByDomain = new Map()
    for (const record of accountRecords) {
      const records = recordsByDomain.get(record.domain_key) ?? []
      records.push(record)
      recordsByDomain.set(record.domain_key, records)
    }
    for (const [domainKey, records] of recordsByDomain) {
      const plannerRecords = records.map(domainPlannerRecord)
      for (const record of records) {
        if (!isInEvaluationWindow(record, snapshot.window)) continue
        const plan = buildGenericExpressionShadowPlan({
          domainKey,
          records: plannerRecords,
          currentRecordId: record.id,
        })
        evaluated.push(compactPlan(record, domainKey, plan))
      }
    }
  }

  evaluated.sort((left, right) =>
    String(left.created_at ?? left.occurred_at).localeCompare(String(right.created_at ?? right.occurred_at))
    || left.record_id.localeCompare(right.record_id))

  return {
    schema_version: 'recent-snapshot-replay-v0.1',
    source_schema_version: snapshot.schema_version ?? null,
    generated_at: new Date().toISOString(),
    evaluation_window: snapshot.window,
    summary: summarize(evaluated),
    records: evaluated,
  }
}

async function main() {
  const inputPath = requireArgument('input')
  const outputPath = path.resolve(argument('output') ?? path.join(path.dirname(inputPath), 'replay-results.json'))
  const snapshot = JSON.parse(await readFile(inputPath, 'utf8'))
  const output = await replaySnapshot(snapshot)
  const baselinePath = argument('baseline')
  if (baselinePath) {
    const baseline = JSON.parse(await readFile(path.resolve(baselinePath), 'utf8'))
    output.comparison = compareRecords(baseline.records ?? [], output.records)
  }
  await writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8')
  process.stdout.write(`${JSON.stringify({ output: outputPath, ...output.summary }, null, 2)}\n`)
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main()
}
