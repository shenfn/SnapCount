import { mkdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { buildExposureEvents } from './lib/render-contract.mjs'
import { toProductionExposureRows } from './lib/exposure-ledger-serializer.mjs'

function parseArgs(argv) {
  const result = { surface: 'shortcut_notification' }
  for (const arg of argv) {
    if (arg.startsWith('--snapshot=')) result.snapshot = arg.slice(11)
    else if (arg.startsWith('--user-id=')) result.userId = arg.slice(10)
    else if (arg.startsWith('--surface=')) result.surface = arg.slice(10)
    else if (arg.startsWith('--delivery-attempt-id=')) result.deliveryAttemptId = arg.slice(22)
    else if (arg.startsWith('--output=')) result.output = arg.slice(9)
  }
  if (!result.snapshot) throw new Error('Missing --snapshot=<path>')
  if (!result.userId) throw new Error('Missing --user-id=<uuid>')
  return result
}

const args = parseArgs(process.argv.slice(2))
const snapshot = JSON.parse(await readFile(path.resolve(args.snapshot), 'utf8'))
const renderPlan = snapshot.render_plans?.[args.surface]
if (!renderPlan) throw new Error(`Snapshot has no render plan for ${args.surface}`)
const realPlan = { ...renderPlan, simulation_only: false, render_state: renderPlan.delivery_state_when_sent }
const events = buildExposureEvents({ [args.surface]: realPlan }, {
  traceId: `dry-run:${snapshot.data_boundary?.user_id}:${args.surface}`,
  occurredAt: snapshot.data_boundary?.as_of ?? snapshot.generated_at,
  simulationOnly: false,
})
const deliveryAttemptId = args.deliveryAttemptId ?? `dry-run-${Date.now()}`
const rows = toProductionExposureRows(events, {
  userId: args.userId,
  deliveryAttemptId,
  traceId: events[0]?.trace_id ?? null,
  recordId: snapshot.current_record?.id ?? null,
  recordType: snapshot.current_record?.type ?? 'expense',
  domainKey: snapshot.current_record?.type ?? 'expense',
  entityId: snapshot.entity_filter?.entity_id ?? null,
  source: 'local_dry_run_preview',
})
const envelope = {
  dry_run: true,
  insert_executed: false,
  warning: 'Production-shaped preview only. Do not insert unless the surface delivery really occurred.',
  source_snapshot: path.resolve(args.snapshot),
  rows,
}
const outputPath = path.resolve(args.output ?? path.join('test-results', 'expression-planner', 'exposure-insert-preview.json'))
await mkdir(path.dirname(outputPath), { recursive: true })
await writeFile(outputPath, JSON.stringify(envelope, null, 2) + '\n', 'utf8')
console.log(outputPath)
console.log(JSON.stringify({ dry_run: true, row_count: rows.length, surface: args.surface, semantic_keys: rows.map(row => row.semantic_key) }, null, 2))
