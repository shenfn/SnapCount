// 随手账 ── AI 识别日志查看器
// 用法: npm run logs:ai -- [选项]
//   --today         仅今天
//   --status=error  过滤状态 (error/success/duplicate/pending)
//   --type=expense  按 record_type 过滤
//   --limit=30      显示条数 (默认20)
//   --hours=24      最近 N 小时
//   --detail        显示完整 AI 响应 JSON

import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL
const anonKey = process.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  console.error('Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY in environment.')
  console.error('请确认 .env.local 存在且配置正确')
  process.exit(1)
}

const sb = createClient(url, anonKey)

const args = process.argv.slice(2)
const flags = {}
args.forEach(a => {
  if (a === '--today') flags.today = true
  else if (a === '--detail') flags.detail = true
  else if (a.startsWith('--status=')) flags.status = a.split('=')[1]
  else if (a.startsWith('--type=')) flags.type = a.split('=')[1]
  else if (a.startsWith('--limit=')) flags.limit = parseInt(a.split('=')[1])
  else if (a.startsWith('--hours=')) flags.hours = parseInt(a.split('=')[1])
})

const limit = Math.min(flags.limit || 20, 100)

async function main() {
  let query = sb.from('ai_recognition_logs')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit)

  if (flags.today) {
    const today = new Date().toISOString().slice(0, 10)
    query = query.gte('created_at', `${today}T00:00:00Z`)
  }
  if (flags.hours) {
    const since = new Date(Date.now() - flags.hours * 3600 * 1000).toISOString()
    query = query.gte('created_at', since)
  }
  if (flags.status === 'error') {
    query = query.in('status', ['ai_error', 'db_error', 'error'])
  } else if (flags.status) {
    query = query.eq('status', flags.status)
  }
  if (flags.type) {
    query = query.eq('record_type', flags.type)
  }

  const { data, error } = await query
  if (error) { console.error('查询失败:', error.message); process.exit(1) }
  if (!data || !data.length) { console.log('没有匹配的日志。'); return }

  // 统计
  const counts = {}, types = {}
  let totalMs = 0, msCount = 0
  data.forEach(row => {
    counts[row.status] = (counts[row.status] || 0) + 1
    types[row.record_type || '?'] = (types[row.record_type || '?'] || 0) + 1
    if (row.duration_ms) { totalMs += row.duration_ms; msCount++ }
  })

  const c = (k) => counts[k] || 0

  console.log('')
  console.log('══════════════════════════════════════════════')
  console.log(`  AI 识别日志 · ${data.length} 条`)
  if (flags.today) console.log('  范围：今天')
  if (flags.hours) console.log(`  范围：最近 ${flags.hours}h`)
  console.log('──────────────────────────────────────────────')
  console.log(`  成功 ${c('success')}  |  待处理 ${c('pending')}  |  重复 ${c('duplicate')}`)
  console.log(`  AI错误 ${c('ai_error')}  |  DB错误 ${c('db_error')}`)
  console.log('──────────────────────────────────────────────')
  console.log(`  类型: ${Object.entries(types).map(([k,v]) => `${k}(${v})`).join('  ')}`)
  if (msCount) console.log(`  平均耗时: ${Math.round(totalMs / msCount)}ms  |  总计: ${(totalMs / 1000).toFixed(1)}s`)
  console.log('══════════════════════════════════════════════')
  console.log('')

  data.forEach((row, i) => {
    const ts = new Date(row.created_at).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })
    const icons = { success: '+', pending: '~', duplicate: '=', ai_error: '!', db_error: '!' }
    const icon = icons[row.status] || '?'

    console.log(`#${i + 1}  ${icon} ${row.status.padEnd(9)} | ${(row.record_type || '?').padEnd(8)} | ${(row.image_type || '?').padEnd(14)} | ${ts}`)
    console.log(`   conf=${row.confidence ?? '?'}  |  ${row.duration_ms ?? '?'}ms`)

    let ai = null
    try { ai = typeof row.ai_response === 'string' ? JSON.parse(row.ai_response) : row.ai_response } catch {}
    if (ai) {
      const parts = []
      if (ai.amount) parts.push(`¥${ai.amount}`)
      if (ai.merchant_name) parts.push(ai.merchant_name)
      if (ai.source_name) parts.push(ai.source_name)
      if (ai.category) parts.push(ai.category)
      if (ai.platform && ai.platform !== '其他') parts.push(ai.platform)
      if (ai.payment_method) parts.push(ai.payment_method)
      if (parts.length) console.log(`   识别: ${parts.join(' · ')}`)
    }

    if (row.error_message) console.log(`   错误: ${row.error_message.slice(0, 150)}`)
    if (row.duplicate_kind) console.log(`   重复: ${row.duplicate_kind} → ${row.duplicate_ref_table || '?'}`)
    if (row.target_table) console.log(`   入库: ${row.target_table}/${(row.target_id || '').slice(0, 8)}`)
    if (row.staging_record_id) console.log(`   中转: ${(row.staging_record_id || '').slice(0, 8)}`)
    if (row.prompt_version) console.log(`   prompt: ${row.prompt_version}`)

    if (flags.detail && row.ai_response) {
      try {
        const d = typeof row.ai_response === 'string' ? JSON.parse(row.ai_response) : row.ai_response
        console.log(`   JSON: ${JSON.stringify(d).slice(0, 500)}`)
      } catch {}
    }
    console.log('')
  })

  console.log(`共 ${data.length} 条。`)
}

main().catch(e => { console.error('执行失败:', e.message); process.exit(1) })
