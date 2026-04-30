import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL
const anonKey = process.env.VITE_SUPABASE_ANON_KEY
const limitArg = Number(process.argv[2] || '10')
const limit = Number.isFinite(limitArg) && limitArg > 0 ? Math.min(limitArg, 50) : 10

if (!url || !anonKey) {
  console.error('Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY in environment.')
  process.exit(1)
}

const sb = createClient(url, anonKey)

const { data, error } = await sb
  .from('ai_recognition_logs')
  .select('created_at,status,record_type,image_type,confidence,duration_ms,duplicate_kind,target_table,target_id,error_message')
  .order('created_at', { ascending: false })
  .limit(limit)

if (error) {
  console.error('Query failed:', error.message)
  process.exit(1)
}

for (const item of data || []) {
  const time = item.created_at?.replace('T', ' ').replace(/\.\d+\+\d+:\d+$/, '') || '-'
  const status = item.status || '-'
  const recordType = item.record_type || '-'
  const imageType = item.image_type || '-'
  const confidence = typeof item.confidence === 'number' ? item.confidence.toFixed(2) : '-'
  const duration = item.duration_ms ?? '-'
  const duplicate = item.duplicate_kind || '-'
  const target = item.target_table && item.target_id ? `${item.target_table}:${item.target_id}` : '-'
  console.log(`${time} | ${status} | ${recordType} | ${imageType} | conf=${confidence} | ${duration}ms | dup=${duplicate} | ${target}`)
  if (item.error_message) {
    console.log(`  error: ${item.error_message}`)
  }
}
