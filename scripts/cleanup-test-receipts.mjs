import { createClient } from '@supabase/supabase-js'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const DEFAULT_UPLOAD_TOKEN = '0a552a27-0b64-456e-a5b3-e50e261d2e4f'

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
  else if (arg.startsWith('--upload-token=')) flags.uploadToken = arg.slice('--upload-token='.length)
  else if (arg === '--upload-token') flags.uploadToken = args[++i]
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
  --upload-token <t> 测试账号上传 token，默认使用专用测试账号 token
  --user-id <uuid>   直接指定测试账号 user_id，仅限调试
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

function trimTrailingSlash(value) {
  return value.replace(/\/$/, '')
}

async function resolveSupabaseUrl() {
  const explicitUrl = process.env.TEST_SUPABASE_URL
    || process.env.SUPABASE_URL
    || process.env.SUPABASE_PROJECT_URL

  if (explicitUrl) return trimTrailingSlash(explicitUrl.trim())

  try {
    const projectRef = (await readFile(path.join(process.cwd(), 'supabase', '.temp', 'project-ref'), 'utf8')).trim()
    if (projectRef) return `https://${projectRef}.supabase.co`
  } catch {
    // Fall through to Vite URL, which may be a Worker proxy in local production-like config.
  }

  return trimTrailingSlash(requireEnv('VITE_SUPABASE_URL'))
}

function resolveAdminKey() {
  return process.env.TEST_SUPABASE_SERVICE_ROLE_KEY
    || process.env.SUPABASE_SERVICE_ROLE_KEY
    || requireEnv('VITE_SUPABASE_ANON_KEY')
}

export function hasMatchingTestMeta(row, jsonField, runId) {
  const meta = row?.[jsonField]?.test_meta
  if (!meta || meta.is_test !== true || meta.source !== 'local_validation') return false
  return runId ? meta.test_run_id === runId : true
}

async function resolveUserId(sb) {
  if (flags.userId) {
    return {
      userId: flags.userId,
      uploadToken: null,
      identitySource: 'user_id',
    }
  }

  const uploadToken = flags.uploadToken || process.env.TEST_RECEIPT_UPLOAD_TOKEN || DEFAULT_UPLOAD_TOKEN
  const { data, error } = await sb
    .from('user_configs')
    .select('user_id')
    .eq('upload_token', uploadToken)
    .eq('is_active', true)
    .maybeSingle()

  if (error) throw new Error(`upload_token 反查 user_id 失败: ${error.message}`)
  if (!data?.user_id) throw new Error('upload_token 未找到有效测试账号，不能继续清理。')

  return {
    userId: data.user_id,
    uploadToken,
    identitySource: 'upload_token',
  }
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

  const runId = flags.runId || null
  const limit = Number.isFinite(flags.limit) && flags.limit > 0 ? Math.min(flags.limit, 2000) : 500
  const sb = createClient(await resolveSupabaseUrl(), resolveAdminKey(), {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  })
  const identity = await resolveUserId(sb)
  const userId = identity.userId

  if (flags.execute && !flags.yes) {
    throw new Error('真实删除必须同时传 --execute --yes。')
  }
  if (flags.execute && !runId) {
    throw new Error('真实删除必须指定 --run-id，避免误删整个测试账号数据。')
  }
  if (flags.execute && flags.userId) {
    throw new Error('真实删除不允许直接使用 --user-id，请使用 upload_token 反查，避免误删非测试账号数据。')
  }

  console.log('测试识别数据清理')
  console.log('----------------')
  console.log(`mode: ${flags.execute ? 'execute' : 'dry-run'}`)
  console.log(`identity_source: ${identity.identitySource}`)
  console.log(`user_id: ${userId}`)
  console.log(`upload_token: ${identity.uploadToken ? '(provided)' : '-'}`)
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
