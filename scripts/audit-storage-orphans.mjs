import { createClient } from '@supabase/supabase-js'
import { mkdir, writeFile } from 'node:fs/promises'
import path from 'node:path'

const args = new Map()
for (let index = 2; index < process.argv.length; index += 1) {
  const item = process.argv[index]
  if (!item.startsWith('--')) continue
  const key = item.slice(2)
  const next = process.argv[index + 1]
  if (next && !next.startsWith('--')) {
    args.set(key, next)
    index += 1
  } else {
    args.set(key, 'true')
  }
}

if (args.has('delete') || args.has('execute')) {
  console.error('This tool is read-only. Delete and execute modes are intentionally unsupported.')
  process.exit(2)
}

const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
const bucket = args.get('bucket') || 'receipt-images'
const generatedAt = new Date()
const runId = generatedAt.toISOString().replace(/[:.]/g, '-')
const outputDir = path.resolve(args.get('out') || path.join('local-only', 'storage-orphan-audit', runId))
const pageSize = Math.min(Math.max(Number(args.get('page-size') || 500), 1), 1000)

if (!supabaseUrl || !serviceRoleKey) {
  console.error('Missing SUPABASE_URL/VITE_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY')
  process.exit(1)
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const referenceTargets = [
  ['transactions', 'image_url'],
  ['income_records', 'image_url'],
  ['data_records', 'source_image_path'],
  ['staging_records', 'image_path'],
  ['ai_recognition_logs', 'image_url'],
]
const managedPathPattern = /^(?:tmp\/)?[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\//i

function isFolder(item) {
  return !item.id && !item.metadata
}

async function listPrefix(prefix = '') {
  const entries = []
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await supabase.storage.from(bucket).list(prefix, {
      limit: 1000,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    })
    if (error) throw new Error(`Storage list failed for ${prefix || '/'}: ${error.message}`)
    entries.push(...(data ?? []))
    if (!data || data.length < 1000) break
  }
  return entries
}

async function collectStorageObjects(prefix = '', output = new Map()) {
  const entries = await listPrefix(prefix)
  for (const item of entries) {
    const objectPath = prefix ? `${prefix}/${item.name}` : item.name
    if (isFolder(item)) {
      await collectStorageObjects(objectPath, output)
    } else {
      output.set(objectPath, {
        path: objectPath,
        size: Number(item.metadata?.size ?? 0) || null,
        updated_at: item.updated_at ?? item.metadata?.updated_at ?? null,
      })
    }
  }
  return output
}

async function collectReferences() {
  const references = new Map()
  const external = []
  for (const [table, column] of referenceTargets) {
    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await supabase.from(table)
        .select(`id,user_id,${column}`)
        .not(column, 'is', null)
        .range(offset, offset + pageSize - 1)
      if (error) throw new Error(`Reference scan failed for ${table}.${column}: ${error.message}`)
      for (const row of data ?? []) {
        const value = row[column]
        if (typeof value !== 'string' || value.length === 0) continue
        const entry = { table, column, id: row.id, user_id: row.user_id, path: value }
        if (/^(https?:\/\/|data:)/i.test(value) || !managedPathPattern.test(value)) {
          external.push(entry)
          continue
        }
        const current = references.get(value) ?? []
        current.push(entry)
        references.set(value, current)
      }
      if (!data || data.length < pageSize) break
    }
  }
  return { references, external }
}

async function collectActiveQueue() {
  const queued = new Map()
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase.from('image_cleanup_queue')
      .select('id,user_id,bucket_name,bucket_path,status,cleanup_reason,attempts,last_error')
      .eq('bucket_name', bucket)
      .in('status', ['pending', 'processing', 'failed', 'dead_letter'])
      .range(offset, offset + pageSize - 1)
    if (error) throw new Error(`Cleanup queue scan failed: ${error.message}`)
    for (const row of data ?? []) queued.set(row.bucket_path, row)
    if (!data || data.length < pageSize) break
  }
  return queued
}

function jsonLines(items) {
  return items.map((item) => JSON.stringify(item)).join('\n') + (items.length ? '\n' : '')
}

await mkdir(outputDir, { recursive: true })
const [objects, referenceResult, queued] = await Promise.all([
  collectStorageObjects(),
  collectReferences(),
  collectActiveQueue(),
])

const orphanCandidates = []
const queuedObjects = []
for (const object of objects.values()) {
  if (referenceResult.references.has(object.path)) continue
  if (queued.has(object.path)) queuedObjects.push({ ...object, queue: queued.get(object.path) })
  else orphanCandidates.push(object)
}

const missingReferencedObjects = []
for (const [objectPath, references] of referenceResult.references) {
  if (!objects.has(objectPath)) missingReferencedObjects.push({ path: objectPath, references })
}

const missingQueuedObjects = []
for (const [objectPath, queue] of queued) {
  if (!objects.has(objectPath)) missingQueuedObjects.push({ path: objectPath, queue })
}

const summary = {
  status: 'read_only_complete',
  generated_at: generatedAt.toISOString(),
  supabase_url: supabaseUrl,
  bucket,
  output_dir: outputDir,
  counts: {
    storage_objects: objects.size,
    referenced_paths: referenceResult.references.size,
    external_or_unmanaged_references: referenceResult.external.length,
    active_queue_paths: queued.size,
    orphan_candidates: orphanCandidates.length,
    queued_unreferenced_objects: queuedObjects.length,
    missing_referenced_objects: missingReferencedObjects.length,
    missing_queued_objects: missingQueuedObjects.length,
  },
  note: 'No files or database rows were deleted. Orphan candidates require separate review and a retention window.',
}

await Promise.all([
  writeFile(path.join(outputDir, 'summary.json'), JSON.stringify(summary, null, 2), 'utf8'),
  writeFile(path.join(outputDir, 'orphan-candidates.jsonl'), jsonLines(orphanCandidates), 'utf8'),
  writeFile(path.join(outputDir, 'queued-unreferenced-objects.jsonl'), jsonLines(queuedObjects), 'utf8'),
  writeFile(path.join(outputDir, 'missing-referenced-objects.jsonl'), jsonLines(missingReferencedObjects), 'utf8'),
  writeFile(path.join(outputDir, 'missing-queued-objects.jsonl'), jsonLines(missingQueuedObjects), 'utf8'),
  writeFile(path.join(outputDir, 'external-or-unmanaged-references.jsonl'), jsonLines(referenceResult.external), 'utf8'),
])

console.log(JSON.stringify(summary, null, 2))
