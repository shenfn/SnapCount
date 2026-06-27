import { createClient } from '@supabase/supabase-js'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const DEFAULT_TEST_USER_ID = '0a552a27-0b64-456e-a5b3-e50e261d2e4f'

const args = process.argv.slice(2)
const flags = {}

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i]
  if (arg === '--help' || arg === '-h') flags.help = true
  else if (arg === '--execute') flags.execute = true
  else if (arg === '--yes') flags.yes = true
  else if (arg.startsWith('--run-id=')) flags.runId = arg.slice('--run-id='.length)
  else if (arg === '--run-id') flags.runId = args[++i]
  else if (arg.startsWith('--user-id=')) flags.userId = arg.slice('--user-id='.length)
  else if (arg === '--user-id') flags.userId = args[++i]
  else if (arg.startsWith('--limit=')) flags.limit = Number(arg.slice('--limit='.length))
  else if (arg === '--limit') flags.limit = Number(args[++i])
}

function printHelp() {
  console.log(`
测试识别数据清理工具

默认只 dry-run，不删除任何线上数据。

用法:
  npm run cleanup:test-receipts -- --run-id local-2026-06-23-230500
  npm run cleanup:test-receipts -- --run-id local-2026-06-23-230500 --execute --yes

选项:
  --run-id <id>      指定测试批次，强烈建议必填
  --user-id <uuid>   测试账号，默认使用专用测试账号
  --limit <n>        每张表最多扫描条数，默认 500
  --execute          执行真实删除；不传时只 dry-run
  --yes              配合 --execute 使用，表示已确认删除
`)
}

export function requireEnv(name) {
  const value = process.env[name]
  if (!value) throw new Error(`Missing ${name}. 请先配置 .env.local 或环境变量。`)
  return value
}

export function hasMatchingTestMeta(row, jsonField, runId) {
  const meta = row?.[jsonField]?.test_meta
  if (!meta || meta.is_test !== true || meta.source !== 'local_validation') return false
  return runId ? meta.test_run_id === runId : true
}

function printRows(title, rows, jsonField) {
  console.log('')
  console.log(title)
  console.log('-'.repeat(title.length))
  if (!rows.length) {
    console.log('无匹配记录')
    return
  }
  for (const row of rows) {
    const meta = row[jsonField]?.test_meta || {}
    const label = [
      meta.test_run_id || '-',
      meta.test_case_domain || '-',
      meta.test_case_date || '-',
      meta.test_case_file || '-',
    ].join(' · ')
    console.log(`${row.id} | ${row.created_at || row.updated_at || '-'} | ${label}`)
  }
}

export async function fetchTaggedRows(sb, { table, jsonField, userId, runId, limit }) {
  let query = sb
    .from(table)
    .select(`id,created_at,updated_at,user_id,${jsonField}`)
    .eq('user_id', userId)
    .not(`${jsonField}->test_meta`, 'is', null)
    .limit(limit)

  if (runId) {
    query = query.eq(`${jsonField}->test_meta->>test_run_id`, runId)
  }

  const { data, error } = await query
  if (error) throw new Error(`${table} 查询失败: ${error.message}`)
  return (data || []).filter((row) => hasMatchingTestMeta(row, jsonField, runId))
}

export async function deleteRows(sb, table, ids) {
  if (!ids.length) return { count: 0 }
  const { error } = await sb.from(table).delete().in('id', ids)
  if (error) throw new Error(`${table} 删除失败: ${error.message}`)
  return { count: ids.length }
}

async function main() {
  if (flags.help) {
    printHelp()
    return
  }

  const userId = flags.userId || process.env.TEST_RECEIPT_USER_ID || DEFAULT_TEST_USER_ID
  const runId = flags.runId || null
  const limit = Number.isFinite(flags.limit) && flags.limit > 0 ? Math.min(flags.limit, 2000) : 500

  if (flags.execute && !flags.yes) {
    throw new Error('真实删除必须同时传 --execute --yes。')
  }
  if (flags.execute && !runId) {
    throw new Error('真实删除必须指定 --run-id，避免误删整个测试账号数据。')
  }
  if (flags.execute && userId !== DEFAULT_TEST_USER_ID) {
    throw new Error(`真实删除只允许默认专用测试账号: ${DEFAULT_TEST_USER_ID}`)
  }

  const sb = createClient(requireEnv('VITE_SUPABASE_URL'), requireEnv('VITE_SUPABASE_ANON_KEY'))

  console.log('测试识别数据清理')
  console.log('----------------')
  console.log(`mode: ${flags.execute ? 'execute' : 'dry-run'}`)
  console.log(`user_id: ${userId}`)
  console.log(`run_id: ${runId || '(all test_meta records; dry-run only)'}`)
  console.log(`limit: ${limit}`)

  const dataRecords = await fetchTaggedRows(sb, {
    table: 'data_records',
    jsonField: 'payload_jsonb',
    userId,
    runId,
    limit,
  })
  const stagingRecords = await fetchTaggedRows(sb, {
    table: 'staging_records',
    jsonField: 'extracted_json',
    userId,
    runId,
    limit,
  })

  printRows('data_records.payload_jsonb.test_meta', dataRecords, 'payload_jsonb')
  printRows('staging_records.extracted_json.test_meta', stagingRecords, 'extracted_json')

  console.log('')
  console.log('汇总')
  console.log('----')
  console.log(`data_records: ${dataRecords.length}`)
  console.log(`staging_records: ${stagingRecords.length}`)

  console.log('')
  console.log('注意')
  console.log('----')
  console.log('transactions / income_records 当前没有 test_meta 字段。')
  console.log('如果某次测试直接写入这两张表，请先通过本地 response target id 或 ai_recognition_logs 人工确认，再单独处理。')

  if (!flags.execute) {
    console.log('')
    console.log('dry-run 完成，没有删除任何线上数据。')
    return
  }

  const deletedData = await deleteRows(sb, 'data_records', dataRecords.map((row) => row.id))
  const deletedStaging = await deleteRows(sb, 'staging_records', stagingRecords.map((row) => row.id))

  console.log('')
  console.log('删除完成')
  console.log('--------')
  console.log(`data_records: ${deletedData.count}`)
  console.log(`staging_records: ${deletedStaging.count}`)
}

const isMainModule = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])

if (isMainModule) {
  main().catch((error) => {
    console.error('')
    console.error('清理失败:', error.message)
    process.exit(1)
  })
}
