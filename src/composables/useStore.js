import { ref, reactive, computed, nextTick } from 'vue'
import { sb, SUPABASE_URL, SUPABASE_ANON_KEY } from '../lib/supabase'
import {
  getSystemDomainDefinitions,
  getSystemDomainLabel,
  getUniversalDomainMeta as getRegistryUniversalDomainMeta,
  hydrateDomainRegistry,
  getDomainRegistryStatus,
} from '../domains/registry'
import { buildHomeTimeline, buildTodaySummary, buildUniversalRecordTitle as buildUniversalRecordTitleFromAdapter } from '../domains/storeAdapters'
import { buildDailyCards, buildDayRecords } from '../domains/dayAdapters'
import { buildFinanceOverview } from '../domains/financeOverviewAdapter'
import {
  buildUniversalRecordDraft,
  hydrateUniversalModalFromRecord,
  resetUniversalModal,
  validateUniversalModal,
} from '../domains/universalFormAdapter'
import {
  formatDate, formatMonthLabel, mapTransaction,
  incomeCatMap, catCodeMap, payAliasMap,
  getLocalDateKey, localDateKeyOf,
} from '../utils/helpers'
import { isLiabilityAccount, mapAccountRow, normalizeAccountType } from '../adapters/domain/accountAdapter'

// 把 Supabase/Postgres 常见错误信息翻译为中文
function humanizeDbError(err) {
  const msg = (err?.message || String(err || '')).trim()
  if (!msg) return '未知错误'
  if (/row-level security|rls/i.test(msg)) return '没有操作权限，请重新登录后再试'
  if (/duplicate key|unique constraint/i.test(msg)) return '数据已存在（重复）'
  if (/violates not-null/i.test(msg)) return '必填字段未填写'
  if (/violates check constraint/i.test(msg)) return '数据格式不符合要求'
  if (/foreign key/i.test(msg)) return '关联数据不存在或已被删除'
  if (/permission denied/i.test(msg)) return '权限不足，请重新登录'
  if (/jwt|invalid.*token|expired/i.test(msg)) return '登录状态已失效，请重新登录'
  if (/network|failed to fetch|load failed/i.test(msg)) return '网络连接失败，请检查网络后重试'
  return msg
}

export function useStore() {
  const USER_SETTING_FIELDS = {
    aiLogsEnabled: 'ai_logs_enabled',
    keepSourceImages: 'keep_source_images',
  }

  const currentYear = ref(new Date().getFullYear())
  const currentMonth = ref(new Date().getMonth() + 1)
  const currentPage = ref('home')
  const pageHistory = ref([])
  const pageScrollPositions = reactive({})
  const currentUserId = ref(null)
  const currentUserEmail = ref('')
  const isLoggedIn = ref(false)

  const bills = ref([])
  const incomeRecords = ref([])
  const recentIncomeRecords = ref([])
  const transportRecords = ref([])
  const stagingRecords = ref([])
  const processedStagingRecords = ref([])
  const dataRecords = ref([])
  const accounts = ref([])
  const selectedAccount = ref(null)
  const selectedAccountEntries = ref([])
  const accountEntriesLoading = ref(false)
  const unboundRecords = ref({ expenses: [], incomes: [] })
  const unboundRecordsLoading = ref(false)
  const unboundRecordFilter = ref('all')
  const walletAccountCreatingSourceIds = new Set()

  const currentFilter = ref('all')
  const pendingFilter = ref('all') // all | routing_failed | pending_review | ai_error | bill_pending
  const timelineExpanded = ref(false)
  const pendingExpanded = ref(false)
  const processedExpanded = ref(false)
  const batchMode = ref(false)
  const selectedStagingIds = ref(new Set())
  const loading = ref(false)
  const loadError = ref('')
  const flashMsg = ref('')
  const flashVisible = ref(false)
  let flashTimer = null

  const imgOverlay = reactive({ open: false, src: '' })
  const detailRecord = ref(null)
  const activeDomainId = ref(null)
  const activeDateKey = ref('')
  const activeDayKind = ref('all')
  const dailyCardVisibleCount = ref(8)

  const pendingModal = reactive({
    open: false,
    bill: null,
    entryType: 'expense',
    merchantName: '',
    amount: '',
    platform: null,
    category: null,
    payment: null,
    incomeCategory: 'other',
    accountId: null,
    accountUnbound: false,
  })

  const incomeModal = reactive({
    open: false,
    mode: 'create',
    id: null,
    cat: 'salary',
    amount: '',
    source: '',
    note: '',
    date: '',
    imageUrl: null,
    imagePath: null,
    imageLoadError: false,
    accountId: null,
    accountUnbound: false,
  })

  const expenseModal = reactive({
    open: false,
    mode: 'create',
    id: null,
    amount: '',
    merchantName: '',
    platform: null,
    category: null,
    payment: null,
    note: '',
    date: '',
    time: '',
    imageUrl: null,
    imagePath: null,
    imageLoadError: false,
    accountId: null,
    accountUnbound: false,
  })

  const universalModal = reactive({
    open: false,
    mode: 'create',
    id: null,
    domainKey: 'sport',
    title: '',
    primaryValue: '',
    dimension: '',
    note: '',
    date: '',
    time: '',
    sleepStartTime: '',
    wakeTime: '',
    imagePath: null,
    imageUrl: null,
    imageLoadError: false,
    originalPayload: null,
  })

  const deleteConfirm = reactive({
    open: false,
    type: null,
    id: null,
    imagePath: null,
  })

  const accountModal = reactive({
    open: false,
    mode: 'create',
    id: null,
    name: '',
    type: 'wallet_balance',
    institution: '',
    last4: '',
    initialBalance: '',
    isDefaultExpense: false,
    isDefaultIncome: false,
    isArchived: false,
  })

  const settingsState = reactive({
    aiLogsEnabled: true,
    keepSourceImages: true,
  })
  const actionState = reactive({
    pendingEntry: false,
    income: false,
    expense: false,
    account: false,
    settings: false,
    retryStaging: false,
  })

  const monthLabel = computed(() => formatMonthLabel(currentYear.value, currentMonth.value))

  const doneBills = computed(() => bills.value.filter(b => b.status === 'done'))
  const pendingBills = computed(() => bills.value.filter(b => b.status === 'pending'))

  const totalExpense = computed(() => doneBills.value.reduce((s, b) => s + b.amount, 0))
  const totalIncome = computed(() => incomeRecords.value.reduce((s, r) => s + r.amount, 0))
  const netBalance = computed(() => totalIncome.value - totalExpense.value)
  const currentMonthDayKey = computed(() => getLocalDateKey())
  const todayExpense = computed(() => {
    const todayKey = getLocalDateKey()
    return doneBills.value
      .filter(bill => bill.dateRaw === todayKey)
      .reduce((sum, bill) => sum + bill.amount, 0)
  })

  const recentEntries = computed(() => {
    const expenseItems = bills.value.map(b => ({ ...b, entryKind: 'expense', sortDate: b.createdAt || `${b.dateRaw || ''} ${b.time || ''}` }))
    const incomeItems = recentIncomeRecords.value.map(r => ({ ...r, entryKind: 'income', sortDate: r.createdAt || `${r.dateRaw || ''} ${r.time || ''}` }))
    return [...expenseItems, ...incomeItems].sort((a, b) => (b.sortDate || '').localeCompare(a.sortDate || ''))
  })

  const filteredBills = computed(() => {
    if (currentFilter.value === 'all') return bills.value
    return bills.value.filter(b => b.cat === currentFilter.value)
  })

  const pendingSummary = computed(() => {
    const summary = {
      total: pendingBills.value.length + stagingRecords.value.length,
      billPending: pendingBills.value.length,
      routingFailed: 0,
      pendingReview: 0,
      aiError: 0,
    }
    stagingRecords.value.forEach(item => {
      if (item.status === 'routing_failed' || item.status === 'unrouted' || item.status === 'unassigned') summary.routingFailed += 1
      else if (item.status === 'pending_review') summary.pendingReview += 1
      else if (item.status === 'ai_error' || item.status === 'failed') summary.aiError += 1
    })
    return summary
  })

  const domains = computed(() => {
    const universalCount = (key) => dataRecords.value.filter(item => item.domainKey === key).length
    return getSystemDomainDefinitions().map(domain => {
      let recordCount = universalCount(domain.id)
      if (domain.storage.recordKind === 'expense') recordCount = bills.value.length
      if (domain.storage.recordKind === 'income') recordCount = incomeRecords.value.length
      return {
        ...domain,
        meta: `本月 ${recordCount} 条 · 系统内置`,
        recordCount,
        isSystem: true,
      }
    })
  })

  const todaySummary = computed(() => {
    return buildTodaySummary({
      bills: bills.value,
      incomeRecords: incomeRecords.value,
      dataRecords: dataRecords.value,
      stagingRecords: stagingRecords.value,
      todayKey: getLocalDateKey(),
    })
  })

  const homeTimeline = computed(() => {
    return buildHomeTimeline({
      stagingRecords: stagingRecords.value,
      bills: bills.value,
      incomeRecords: incomeRecords.value,
      dataRecords: dataRecords.value,
      domains: domains.value,
    })
  })

  const dailyCards = computed(() => {
    return buildDailyCards({
      bills: bills.value,
      incomeRecords: incomeRecords.value,
      dataRecords: dataRecords.value,
      stagingRecords: stagingRecords.value,
      year: currentYear.value,
      month: currentMonth.value,
    })
  })

  const visibleDailyCards = computed(() => dailyCards.value.slice(0, dailyCardVisibleCount.value))

  const activeDayRecords = computed(() => {
    if (!activeDateKey.value) return []
    const records = buildDayRecords({
      dateKey: activeDateKey.value,
      bills: bills.value,
      incomeRecords: incomeRecords.value,
      dataRecords: dataRecords.value,
      stagingRecords: stagingRecords.value,
      domains: domains.value,
    })
    if (activeDayKind.value === 'all') return records
    return records.filter(item => item.kind === activeDayKind.value || item.domainKey === activeDayKind.value)
  })

  const financeOverview = computed(() => {
    return buildFinanceOverview({
      bills: bills.value,
      incomeRecords: incomeRecords.value,
      dataRecords: dataRecords.value,
      accounts: accounts.value,
      todayKey: getLocalDateKey(),
    })
  })

  const timelineGroups = computed(() => {
    const items = homeTimeline.value
    if (!items.length) return []
    const today = getLocalDateKey()
    const yesterday = getLocalDateKey(new Date(Date.now() - 86400000))
    const dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

    function getGroupKey(item) {
      const raw = item.dateRaw
      if (!raw || raw.length < 10) return 'older'
      const dateStr = localDateKeyOf(raw)
      if (dateStr === today) return 'today'
      if (dateStr === yesterday) return 'yesterday'
      const d = new Date(dateStr + 'T00:00:00')
      if (isNaN(d.getTime())) return 'older'
      const diffDays = Math.floor((new Date(today + 'T00:00:00') - d) / 86400000)
      if (diffDays <= 6 && diffDays >= 2) return `${dateStr}|${d.getMonth() + 1}月${d.getDate()}日 · ${dayNames[d.getDay()]}`
      return 'older'
    }

    const groups = {}
    items.forEach(item => {
      const key = getGroupKey(item)
      if (!groups[key]) groups[key] = []
      groups[key].push(item)
    })

    const result = []
    Object.entries(groups).forEach(([key, groupItems]) => {
      if (key === 'today') result.push({ key: 'today', label: '今天', items: groupItems })
      else if (key === 'yesterday') result.push({ key: 'yesterday', label: '昨天', items: groupItems })
      else if (key !== 'older') {
        const [, label] = key.split('|')
        result.push({ key, label: label || key, items: groupItems })
      }
    })
    result.sort((a, b) => {
      if (a.key === 'today') return -1
      if (b.key === 'today') return 1
      if (a.key === 'yesterday') return -1
      if (b.key === 'yesterday') return 1
      return (b.key.split('|')[0] || '').localeCompare(a.key.split('|')[0] || '')
    })
    if (groups['older']) result.push({ key: 'older', label: '更早的记录', items: groups['older'] })
    return result
  })

  const visibleTimelineGroups = computed(() => {
    const groups = timelineGroups.value
    if (timelineExpanded.value) return groups
    const visible = groups.filter(g => g.key === 'today' || g.key === 'yesterday')
    const older = groups.filter(g => g.key !== 'today' && g.key !== 'yesterday')
    if (older.length > 0) {
      const olderCount = older.reduce((sum, g) => sum + g.items.length, 0)
      visible.push({ key: 'collapsed', label: `更早的记录（${olderCount}条）`, items: [], isCollapsed: true })
    }
    return visible
  })

  const platformChartData = computed(() => {
    const grouped = {}
    doneBills.value.forEach(b => {
      const p = b.platform && b.platform !== '?' ? b.platform : '其他'
      grouped[p] = (grouped[p] || 0) + b.amount
    })
    const entries = Object.entries(grouped).sort((a, b) => b[1] - a[1])
    const maxAmt = entries[0]?.[1] || 1
    return entries.map(([name, amount]) => ({ name, amount, pct: amount / maxAmt * 100 }))
  })

  const payChartData = computed(() => {
    const grouped = {}
    doneBills.value.forEach(b => {
      const p = b.payment && b.payment !== '?' ? b.payment : '其他'
      grouped[p] = (grouped[p] || 0) + b.amount
    })
    const total = Object.values(grouped).reduce((a, b) => a + b, 0) || 1
    const entries = Object.entries(grouped).sort((a, b) => b[1] - a[1])
    return entries.map(([name, amount]) => ({ name, amount, pct: Math.round(amount / total * 100) }))
  })

  function resetUserData() {
    bills.value = []
    incomeRecords.value = []
    recentIncomeRecords.value = []
    transportRecords.value = []
    stagingRecords.value = []
    processedStagingRecords.value = []
    dataRecords.value = []
    loadError.value = ''
    loading.value = false
    selectedStagingIds.value = new Set()
    batchMode.value = false
    detailRecord.value = null
    activeDomainId.value = null
    pageHistory.value = []
    settingsState.aiLogsEnabled = true
    settingsState.keepSourceImages = true
    Object.keys(actionState).forEach((key) => {
      actionState[key] = false
    })
  }

  function isActionPending(key) {
    return !!actionState[key]
  }

  async function runLockedAction(key, task) {
    if (!key || typeof task !== 'function') return null
    if (actionState[key]) return null
    actionState[key] = true
    try {
      return await task()
    } finally {
      actionState[key] = false
    }
  }

  async function loadUserSettings() {
    if (!currentUserId.value) {
      settingsState.aiLogsEnabled = true
      settingsState.keepSourceImages = true
      return
    }
    const { data, error } = await sb.from('user_configs')
      .select('ai_logs_enabled, keep_source_images')
      .eq('user_id', currentUserId.value)
      .maybeSingle()
    if (error) {
      console.warn('加载用户设置失败:', error.message)
      return
    }
    settingsState.aiLogsEnabled = data?.ai_logs_enabled ?? true
    settingsState.keepSourceImages = data?.keep_source_images ?? true
  }

  let lastRefreshTs = 0
  const REFRESH_MIN_INTERVAL = 3000

  // 静默刷新（用于后台切回前台时自动拉新）
  // - 不显示全屏 loading
  // - 至少间隔 3 秒，避免频繁切换时刷爆
  // - 失败静默忽略
  async function refreshIfStale() {
    if (!isLoggedIn.value) return
    const now = Date.now()
    if (now - lastRefreshTs < REFRESH_MIN_INTERVAL) return
    lastRefreshTs = now
    try {
      await loadData(0, true)
    } catch (e) {
      console.warn('[refreshIfStale] failed silently:', e)
    }
  }

  // Phase 1：域协议 hydrate 状态（每次会话只拉一次）
  let domainSchemasLoaded = false

  // ────────────────────────────────────────────────
  // Phase A：daily_domain_summary 按需加载（PageInsights 用）
  // ────────────────────────────────────────────────
  const dailySummary = ref([])
  const dailySummaryLoading = ref(false)
  const dailySummaryError = ref('')
  let dailySummaryLoadedAt = 0
  const DAILY_SUMMARY_TTL = 60 * 1000 // 60s 缓存窗口，PageInsights 重复打开不重复拉

  // AI 洞察生成（调 generate-insights Edge Function）
  const aiInsight = ref(null)        // 当前展示的 insight 记录
  const aiInsightLoading = ref(false)
  const aiInsightError = ref('')
  const aiInsightCached = ref(false)

  async function generateAiInsight({ days = 14, force = false, question = '' } = {}) {
    aiInsightLoading.value = true
    aiInsightError.value = ''
    try {
      const { data: { session } } = await sb.auth.getSession()
      const token = session?.access_token
      if (!token) throw new Error('未登录，无法调用 AI')

      const resp = await fetch(`${SUPABASE_URL}/functions/v1/generate-insights`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'apikey': SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({ days, force, question }),
      })
      const json = await resp.json()
      if (!resp.ok) throw new Error(json?.error || `AI 服务返回 ${resp.status}`)

      aiInsight.value = json.insight
      aiInsightCached.value = !!json.cached
      return json
    } catch (e) {
      aiInsightError.value = e?.message || String(e)
      console.warn('[ai_insight] 生成失败:', e)
      throw e
    } finally {
      aiInsightLoading.value = false
    }
  }

  // 启动时尝试取最近一次缓存的 insight（如有），不强制
  async function loadLatestAiInsight({ days = 14 } = {}) {
    try {
      const { data } = await sb
        .from('ai_insights')
        .select('*')
        .eq('days_range', days)
        .eq('status', 'success')
        .order('generated_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (data) {
        aiInsight.value = data
        aiInsightCached.value = true
      }
      return data
    } catch (e) {
      return null
    }
  }

  async function loadDailySummary({ days = 30, force = false } = {}) {
    const now = Date.now()
    if (!force && dailySummary.value.length && (now - dailySummaryLoadedAt < DAILY_SUMMARY_TTL)) {
      return dailySummary.value
    }
    dailySummaryLoading.value = true
    dailySummaryError.value = ''
    try {
      const sinceDate = new Date()
      sinceDate.setDate(sinceDate.getDate() - (Number(days) || 30))
      const sinceStr = sinceDate.toISOString().slice(0, 10)
      const { data, error } = await sb
        .from('daily_domain_summary')
        .select('*')
        .gte('date', sinceStr)
        .order('date', { ascending: true })
      if (error) throw error
      dailySummary.value = data || []
      dailySummaryLoadedAt = now
      return dailySummary.value
    } catch (e) {
      dailySummaryError.value = humanizeDbError(e)
      console.warn('[daily_summary] 加载失败:', e?.message || e)
      return []
    } finally {
      dailySummaryLoading.value = false
    }
  }

  async function loadDomainSchemas() {
    if (domainSchemasLoaded) return
    try {
      const { data, error } = await sb.from('data_domains')
        .select('key,schema_json,display_json,version,status')
        .eq('is_system', true)
      if (error) {
        console.warn('[域协议] 加载 data_domains 失败，使用内置兜底 schema:', error.message)
        return
      }
      hydrateDomainRegistry(data || [])
      domainSchemasLoaded = true
      // 调试输出：协议化重构 Phase 1 验证用
      const status = getDomainRegistryStatus()
      console.log('[域协议] hydrate 完成', {
        hydratedAt: status.hydratedAt,
        domains: (data || []).map(d => ({
          key: d.key,
          facts: d.schema_json?.facts?.length || 0,
          dimensions: d.schema_json?.dimensions?.length || 0,
        })),
      })
    } catch (e) {
      console.warn('[域协议] 加载异常，使用内置兜底 schema:', e?.message || e)
    }
  }

  async function loadData(attempt = 0, silent = false) {
    if (attempt === 0 && !silent) loading.value = true
    if (attempt === 0 && !silent) loadError.value = ''
    if (attempt === 0) lastRefreshTs = Date.now()
    if (attempt === 0) await loadUserSettings()
    // Phase 1：拉取域协议（每会话一次，失败不阻断主流程）
    if (attempt === 0) loadDomainSchemas()
    try {
      const padM = String(currentMonth.value).padStart(2, '0')
      const start = `${currentYear.value}-${padM}-01`
      const lastDay = new Date(currentYear.value, currentMonth.value, 0).getDate()
      const end = `${currentYear.value}-${padM}-${String(lastDay).padStart(2, '0')}`

      const { data: txs, error: txErr } = await sb.from('transactions')
        .select('*')
        .gte('transaction_date', start)
        .lte('transaction_date', end)
        .order('transaction_date', { ascending: false })
        .order('transaction_time', { ascending: false })
      if (txErr) throw new Error('账单查询失败: ' + txErr.message)

      bills.value = (txs || []).map(mapTransaction)
      transportRecords.value = bills.value
        .filter(b => b.cat === 'transport' && b.amount >= 200)
        .map(b => ({ id: b.id, type: b.transport_type || '交通', desc: b.name, amount: b.amount, date: b.date }))

      const { data: incs, error: incErr } = await sb.from('income_records')
        .select('*')
        .gte('income_date', start)
        .lte('income_date', end)
        .order('income_date', { ascending: false })
      if (incErr) console.warn('加载收入失败:', incErr.message)

      incomeRecords.value = (incs || []).map(r => ({
        id: r.id,
        cat: r.category,
        source: r.source_name,
        amount: Number(r.amount),
        date: formatDate(r.income_date),
        dateRaw: r.income_date,
        createdAt: r.created_at,
        time: '',
        icon: incomeCatMap[r.category]?.icon || '💰',
        note: r.note,
        image_url: r.image_url,
        image_path: r.image_url,
        sourceType: r.source || 'manual',
        companionMessage: r.companion_message || '',
        accountId: r.account_id || null,
      }))

      unboundRecords.value = {
        expenses: bills.value.filter(b => b.status === 'done' && !b.accountId),
        incomes: incomeRecords.value.filter(r => !r.accountId),
      }

      const { data: recentIncs, error: recentIncErr } = await sb.from('income_records')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(10)
      if (recentIncErr) console.warn('加载最近收入失败:', recentIncErr.message)

      recentIncomeRecords.value = (recentIncs || []).map(r => ({
        id: r.id,
        cat: r.category,
        source: r.source_name,
        amount: Number(r.amount),
        date: formatDate(r.income_date),
        dateRaw: r.income_date,
        createdAt: r.created_at,
        time: '',
        icon: incomeCatMap[r.category]?.icon || '💰',
        note: r.note,
        image_url: r.image_url,
        image_path: r.image_url,
        sourceType: r.source || 'manual',
        companionMessage: r.companion_message || '',
        accountId: r.account_id || null,
      }))

      const { data: universalRows, error: universalErr } = await sb.from('data_records')
        .select('*')
        .gte('occurred_at', `${start}T00:00:00+08:00`)
        .lte('occurred_at', `${end}T23:59:59+08:00`)
        .order('occurred_at', { ascending: false, nullsFirst: false })
        .order('created_at', { ascending: false })
        .limit(120)
      if (universalErr) {
        console.warn('加载通用记录失败:', universalErr.message)
        dataRecords.value = []
      } else {
        dataRecords.value = (universalRows || []).map(r => {
          const payload = r.payload_jsonb || {}
          return {
            id: r.id,
            domainId: r.domain_id,
            domainKey: r.domain_key,
            domainVersion: r.domain_version || '1.0',
            occurredAt: r.occurred_at,
            createdAt: r.created_at,
            title: r.title,
            summary: r.summary,
            payload: {
              ...payload,
              linked_account_id: r.linked_account_id || payload.linked_account_id || null,
              account_snapshot_kind: r.account_snapshot_kind || payload.account_snapshot_kind || null,
              snapshot_balance: r.snapshot_balance ?? payload.snapshot_balance ?? null,
            },
            companionMessage: payload?.companion_message || '',
            imagePath: r.source_image_path,
            imageHash: r.source_image_hash,
            stagingRecordId: r.staging_record_id,
            source: r.source || 'staging',
          }
        })
      }

      const { data: accountRows, error: accountErr } = await sb.from('accounts')
        .select('*')
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: true })
      if (accountErr) {
        console.warn('加载账户失败:', accountErr.message)
        accounts.value = []
      } else {
        accounts.value = (accountRows || []).map(mapAccountRow)
      }

      const { data: staging, error: stagingErr } = await sb.from('staging_records')
        .select('*')
        .not('status', 'in', '(discarded,archived)')
        .or(`occurred_at.gte.${start}T00:00:00+08:00,occurred_at.is.null`)
        .order('occurred_at', { ascending: false, nullsFirst: false })
        .limit(30)
      if (stagingErr) console.warn('加载中转站失败:', stagingErr.message)

      stagingRecords.value = stagingErr ? [] : await Promise.all((staging || []).map(async r => {
        const imageUrl = await getSignedImageUrl(r.image_path)
        return ({
        id: r.id,
        status: r.status,
        occurredAt: r.occurred_at,
        createdAt: r.created_at,
        imagePath: r.image_path,
        imageUrl,
        imageLoadError: !!r.image_path && !imageUrl,
        imageHash: r.image_hash,
        imageType: r.image_type,
        recordType: r.record_type || 'uncertain',
        domainKey: r.detected_domain_key,
        domainName: r.detected_domain_name,
        targetDomainId: r.target_domain_id,
        confidence: Number(r.confidence || 0),
        summary: r.ai_summary || r.failure_reason || '等待处理的截图',
        failureReason: r.failure_reason,
        lastErrorType: r.last_error_type,
        lastErrorMessage: r.last_error_message,
        extracted: r.extracted_json || {},
        companionMessage: r.companion_message || r.extracted_json?.companion_message || '',
        retryCount: r.retry_count || 0,
        targetRecordId: r.target_record_id,
        resolvedAction: r.resolved_action,
        resolvedAt: r.resolved_at,
        discardReason: r.discard_reason,
        })
      }))

      // 已处理的中转站记录（最近 30 条）
      const { data: processed, error: procErr } = await sb.from('staging_records')
        .select('*')
        .in('status', ['archived', 'discarded'])
        .order('resolved_at', { ascending: false, nullsFirst: false })
        .limit(30)
      if (procErr) console.warn('加载已处理记录失败:', procErr.message)

      processedStagingRecords.value = procErr ? [] : await Promise.all((processed || []).map(async r => {
        const imageUrl = await getSignedImageUrl(r.image_path)
        return ({
        id: r.id,
        status: r.status,
        occurredAt: r.occurred_at,
        createdAt: r.created_at,
        resolvedAt: r.resolved_at,
        imagePath: r.image_path,
        imageUrl,
        imageLoadError: !!r.image_path && !imageUrl,
        imageHash: r.image_hash,
        imageType: r.image_type,
        recordType: r.record_type || 'uncertain',
        domainKey: r.detected_domain_key,
        domainName: r.detected_domain_name,
        targetDomainId: r.target_domain_id,
        targetRecordId: r.target_record_id,
        confidence: Number(r.confidence || 0),
        summary: r.ai_summary || r.failure_reason || '',
        companionMessage: r.companion_message || r.extracted_json?.companion_message || '',
        failureReason: r.failure_reason,
        resolvedAction: r.resolved_action,
        discardReason: r.discard_reason,
        })
      }))
    } catch (e) {
      console.error('[loadData 异常]', e)
      const isNetworkError = /load failed|fetch|network|failed to fetch/i.test(e.message || '')
      const maxAttempts = isNetworkError ? 4 : 2
      if (attempt < maxAttempts) {
        // 网络层错误使用指数退避重试（1s → 2s → 4s → 8s）
        const delay = isNetworkError ? Math.min(1000 * 2 ** attempt, 8000) : 1000
        await new Promise(r => setTimeout(r, delay))
        return loadData(attempt + 1, silent)
      }
      if (silent) return
      const tip = isNetworkError
        ? `网络连接不稳定，请检查网络或稍后重试`
        : e.message
      loadError.value = `加载失败: ${tip}`
    } finally {
      if (attempt === 0 && !silent) loading.value = false
    }
  }

  async function changeMonth(delta) {
    const now = new Date()
    let m = currentMonth.value + delta
    let y = currentYear.value
    if (m < 1) { m = 12; y-- }
    if (m > 12) { m = 1; y++ }
    if (new Date(y, m - 1, 1) > new Date(now.getFullYear(), now.getMonth(), 1)) return
    currentYear.value = y
    currentMonth.value = m
    dailyCardVisibleCount.value = 8
    activeDateKey.value = ''
    activeDayKind.value = 'all'
    await loadData()
  }

  function showFlash(msg) {
    flashMsg.value = msg
    flashVisible.value = true
    if (flashTimer) clearTimeout(flashTimer)
    flashTimer = setTimeout(() => { flashVisible.value = false }, 2000)
  }

  function showError(msg) {
    showFlash(`❌ ${msg}`)
  }

  function showWarn(msg) {
    showFlash(`⚠ ${msg}`)
  }

  async function getSignedImageUrl(raw) {
    if (!raw) return null
    if (raw.startsWith('https://')) return raw
    const { data, error } = await sb.storage.from('receipt-images').createSignedUrl(raw, 3600)
    if (error) {
      console.warn('生成截图预览链接失败:', error.message, raw)
      return null
    }
    return data?.signedUrl || null
  }

  let pendingModalInitial = null

  async function openPendingModal(bill) {
    pendingModal.open = true
    const rawImagePath = bill.image_path || bill.image_url || null
    const resolvedUrl = await getSignedImageUrl(rawImagePath)
    pendingModal.bill = { ...bill, image_path: rawImagePath, image_url: resolvedUrl, imageLoadError: !!rawImagePath && !resolvedUrl }
    pendingModal.entryType = bill.type === 'income' ? 'income' : 'expense'
    pendingModal.merchantName = bill.name !== '未识别商家' ? bill.name : ''
    pendingModal.amount = String(bill.amount)
    pendingModal.platform = bill.platform !== '?' ? bill.platform : null
    pendingModal.category = catCodeMap[bill.cat] || (bill.cat !== '?' ? bill.cat : null)
    pendingModal.payment = payAliasMap[bill.payment] || (bill.payment !== '?' ? bill.payment : null)
    pendingModal.incomeCategory = 'other'
    pendingModal.accountId = resolveAccountIdForPayment({
      existingAccountId: bill.accountId,
      paymentMethod: pendingModal.payment,
      kind: pendingModal.entryType,
    })
    pendingModal.accountUnbound = !pendingModal.accountId
    pendingModalInitial = {
      entryType: pendingModal.entryType,
      merchantName: pendingModal.merchantName,
      amount: pendingModal.amount,
      platform: pendingModal.platform,
      category: pendingModal.category,
      payment: pendingModal.payment,
      incomeCategory: pendingModal.incomeCategory,
      accountId: pendingModal.accountId,
      accountUnbound: pendingModal.accountUnbound,
    }
  }

  function hasPendingChanges() {
    if (!pendingModalInitial) return false
    return pendingModal.entryType !== pendingModalInitial.entryType
      || pendingModal.merchantName !== pendingModalInitial.merchantName
      || pendingModal.amount !== pendingModalInitial.amount
      || pendingModal.platform !== pendingModalInitial.platform
      || pendingModal.category !== pendingModalInitial.category
      || pendingModal.payment !== pendingModalInitial.payment
      || pendingModal.incomeCategory !== pendingModalInitial.incomeCategory
      || pendingModal.accountId !== pendingModalInitial.accountId
      || pendingModal.accountUnbound !== pendingModalInitial.accountUnbound
  }

  function resetPendingChanges() {
    if (!pendingModalInitial) return
    pendingModal.entryType = pendingModalInitial.entryType
    pendingModal.merchantName = pendingModalInitial.merchantName
    pendingModal.amount = pendingModalInitial.amount
    pendingModal.platform = pendingModalInitial.platform
    pendingModal.category = pendingModalInitial.category
    pendingModal.payment = pendingModalInitial.payment
    pendingModal.incomeCategory = pendingModalInitial.incomeCategory
    pendingModal.accountId = pendingModalInitial.accountId
    pendingModal.accountUnbound = pendingModalInitial.accountUnbound
  }

  function markPendingImageUnavailable() {
    if (!pendingModal.bill) return
    pendingModal.bill.image_url = null
    pendingModal.bill.imageLoadError = true
  }

  function closePendingModal() {
    pendingModal.open = false
    pendingModal.bill = null
    pendingModalInitial = null
  }

  let incomeModalInitial = null

  function snapshotIncomeModal() {
    return {
      mode: incomeModal.mode,
      id: incomeModal.id,
      cat: incomeModal.cat,
      amount: incomeModal.amount,
      source: incomeModal.source,
      note: incomeModal.note,
      date: incomeModal.date,
      imagePath: incomeModal.imagePath,
      accountId: incomeModal.accountId,
      accountUnbound: incomeModal.accountUnbound,
    }
  }

  function setIncomeModalInitial() {
    incomeModalInitial = snapshotIncomeModal()
  }

  function hasIncomeChanges() {
    if (!incomeModalInitial) return false
    const current = snapshotIncomeModal()
    return current.mode !== incomeModalInitial.mode
      || current.id !== incomeModalInitial.id
      || current.cat !== incomeModalInitial.cat
      || current.amount !== incomeModalInitial.amount
      || current.source !== incomeModalInitial.source
      || current.note !== incomeModalInitial.note
      || current.date !== incomeModalInitial.date
      || current.imagePath !== incomeModalInitial.imagePath
      || current.accountId !== incomeModalInitial.accountId
      || current.accountUnbound !== incomeModalInitial.accountUnbound
  }

  function resetIncomeChanges() {
    if (!incomeModalInitial) return
    incomeModal.mode = incomeModalInitial.mode
    incomeModal.id = incomeModalInitial.id
    incomeModal.cat = incomeModalInitial.cat
    incomeModal.amount = incomeModalInitial.amount
    incomeModal.source = incomeModalInitial.source
    incomeModal.note = incomeModalInitial.note
    incomeModal.date = incomeModalInitial.date
    incomeModal.imagePath = incomeModalInitial.imagePath
    incomeModal.accountId = incomeModalInitial.accountId
    incomeModal.accountUnbound = incomeModalInitial.accountUnbound
  }

  async function confirmEntry() {
    return runLockedAction('pendingEntry', async () => {
      const amt = parseFloat(pendingModal.amount)
      if (!amt || amt <= 0 || amt > 999999.99) { showWarn('请输入有效金额（0.01 ~ 999999.99）'); return }

      if (pendingModal.entryType === 'income') {
        if (!pendingModal.incomeCategory) { showWarn('请选择收入类型'); return }
        const source = pendingModal.merchantName.trim() || (incomeCatMap[pendingModal.incomeCategory]?.label || '收入')
        const incomeAccountId = pendingModal.accountUnbound ? null : (pendingModal.accountId || defaultAccountIdForKind('income'))
        const { error: confirmErr } = await sb.rpc('confirm_pending_transaction_with_account', {
          p_pending_id: pendingModal.bill.id,
          p_entry_type: 'income',
          p_amount: amt,
          p_merchant_or_source_name: source,
          p_platform: null,
          p_category: null,
          p_payment_method: null,
          p_income_category: pendingModal.incomeCategory,
          p_account_id: incomeAccountId,
        })
        if (confirmErr) { showError('保存失败：' + humanizeDbError(confirmErr)); return }

        const bIdx = bills.value.findIndex(b => b.id === pendingModal.bill.id)
        if (bIdx >= 0) bills.value.splice(bIdx, 1)
        await refreshAccountsFromDB()
        await loadData(0, true)
        closePendingModal()
        showFlash('✓ 收入已记录')
        return
      }

      if (!pendingModal.platform || !pendingModal.category || !pendingModal.payment) return
      const expenseAccountId = pendingModal.accountUnbound
        ? autoAccountIdForPayment(pendingModal.payment, 'expense')
        : (pendingModal.accountId || autoAccountIdForPayment(pendingModal.payment, 'expense') || null)
      const { error } = await sb.rpc('confirm_pending_transaction_with_account', {
        p_pending_id: pendingModal.bill.id,
        p_entry_type: 'expense',
        p_amount: amt,
        p_merchant_or_source_name: pendingModal.merchantName || `${pendingModal.platform}消费`,
        p_platform: pendingModal.platform,
        p_category: pendingModal.category,
        p_payment_method: pendingModal.payment,
        p_income_category: null,
        p_account_id: expenseAccountId,
      })
      if (error) { showError('保存失败：' + humanizeDbError(error)); return }
      await refreshAccountsFromDB()
      // 本地更新账单状态
      const bIdx2 = bills.value.findIndex(b => b.id === pendingModal.bill.id)
      if (bIdx2 >= 0) {
        bills.value[bIdx2] = {
          ...bills.value[bIdx2],
          platform: pendingModal.platform,
          cat: pendingModal.category,
          payment: pendingModal.payment,
          name: pendingModal.merchantName || `${pendingModal.platform}消费`,
          amount: amt,
          status: 'done',
        }
      }
      closePendingModal()
      showFlash('✓ 已保存')
    })
  }

  function openIncomeModal() {
    incomeModal.open = true
    incomeModal.mode = 'create'
    incomeModal.id = null
    incomeModal.cat = 'salary'
    incomeModal.amount = ''
    incomeModal.source = ''
    incomeModal.note = ''
    incomeModal.date = getLocalDateKey()
    incomeModal.imageUrl = null
    incomeModal.imagePath = null
    incomeModal.imageLoadError = false
    incomeModal.accountId = defaultAccountIdForKind('income')
    incomeModal.accountUnbound = !incomeModal.accountId
    setIncomeModalInitial()
  }

  async function openIncomeEditModal(record) {
    incomeModal.open = true
    incomeModal.mode = 'edit'
    incomeModal.id = record.id
    incomeModal.cat = record.cat || 'other'
    incomeModal.amount = String(record.amount)
    incomeModal.source = record.source || ''
    incomeModal.note = record.note || ''
    incomeModal.date = record.dateRaw || getLocalDateKey()
    incomeModal.imagePath = record.image_path || record.image_url || null
    incomeModal.imageUrl = await getSignedImageUrl(incomeModal.imagePath)
    incomeModal.imageLoadError = !!incomeModal.imagePath && !incomeModal.imageUrl
    incomeModal.accountId = record.accountId || defaultAccountIdForKind('income')
    incomeModal.accountUnbound = !incomeModal.accountId
    setIncomeModalInitial()
  }

  function closeIncomeModal() {
    incomeModal.open = false
    incomeModalInitial = null
  }

  async function confirmIncome() {
    return runLockedAction('income', async () => {
      const amt = parseFloat(incomeModal.amount)
      if (!amt || amt <= 0 || amt > 999999.99) { showWarn('请输入有效金额（0.01 ~ 999999.99）'); return }
      if (!incomeModal.cat) { showWarn('请选择收入类型'); return }
      if (!incomeModal.date) { showWarn('请选择到账日期'); return }
      const source = incomeModal.source.trim() || (incomeCatMap[incomeModal.cat]?.label || '收入')
      if (incomeModal.mode === 'edit' && incomeModal.id) {
        const incomeAccountId = incomeModal.accountUnbound ? null : (incomeModal.accountId || null)
        const { error } = await sb.rpc('save_income_with_account', {
          p_id: incomeModal.id,
          p_category: incomeModal.cat,
          p_source_name: source,
          p_amount: amt,
          p_income_date: incomeModal.date,
          p_note: incomeModal.note.trim() || null,
          p_source: null,
          p_image_url: incomeModal.imagePath || null,
          p_image_hash: null,
          p_companion_message: null,
          p_account_id: incomeAccountId,
        })
        if (error) { showError('保存失败：' + humanizeDbError(error)); return }
        await refreshAccountsFromDB()
        if (currentPage.value === 'unbound-records') await loadUnboundRecords()
        closeIncomeModal()
        const applyEdit = (arr) => {
          const idx = arr.findIndex(item => item.id === incomeModal.id)
          if (idx >= 0) {
            arr[idx] = {
              ...arr[idx],
              cat: incomeModal.cat,
              source,
              amount: amt,
              date: formatDate(incomeModal.date),
              dateRaw: incomeModal.date,
              note: incomeModal.note.trim() || null,
              icon: incomeCatMap[incomeModal.cat]?.icon || '💰',
            }
          }
        }
        applyEdit(incomeRecords.value)
        applyEdit(recentIncomeRecords.value)
        showFlash('✓ 收入已更新')
        if (detailRecord.value?.id === incomeModal.id) {
          const updated = incomeRecords.value.find(item => item.id === incomeModal.id)
            || recentIncomeRecords.value.find(item => item.id === incomeModal.id)
          if (updated) {
            await openRecordDetail('income', updated)
          }
        }
        return
      }
      const incomeAccountIdNew = incomeModal.accountUnbound ? null : (incomeModal.accountId || null)
      const { data: newRow, error } = await sb.rpc('save_income_with_account', {
        p_id: null,
        p_category: incomeModal.cat,
        p_source_name: source,
        p_amount: amt,
        p_income_date: incomeModal.date,
        p_note: incomeModal.note.trim() || null,
        p_source: 'manual',
        p_image_url: incomeModal.imagePath || null,
        p_image_hash: null,
        p_companion_message: null,
        p_account_id: incomeAccountIdNew,
      })
      if (error) { showError('保存失败：' + humanizeDbError(error)); return }
      await refreshAccountsFromDB()
      if (currentPage.value === 'unbound-records') await loadUnboundRecords()
      closeIncomeModal()
      const mapped = {
        id: newRow.id,
        cat: newRow.category,
        source: newRow.source_name,
        amount: Number(newRow.amount),
        date: formatDate(newRow.income_date),
        dateRaw: newRow.income_date,
        createdAt: newRow.created_at,
        time: '',
        icon: incomeCatMap[newRow.category]?.icon || '💰',
        note: newRow.note,
        image_url: newRow.image_url,
        image_path: newRow.image_url,
        sourceType: newRow.source || 'manual',
      }
      incomeRecords.value.unshift(mapped)
      showFlash('✓ 收入已记录')
    })
  }

  function markIncomeImageUnavailable() {
    incomeModal.imageUrl = null
    incomeModal.imageLoadError = true
  }

  let expenseModalInitial = null

  function snapshotExpenseModal() {
    return {
      mode: expenseModal.mode,
      id: expenseModal.id,
      amount: expenseModal.amount,
      merchantName: expenseModal.merchantName,
      platform: expenseModal.platform,
      category: expenseModal.category,
      payment: expenseModal.payment,
      note: expenseModal.note,
      date: expenseModal.date,
      time: expenseModal.time,
      imagePath: expenseModal.imagePath,
      accountId: expenseModal.accountId,
      accountUnbound: expenseModal.accountUnbound,
    }
  }

  function setExpenseModalInitial() {
    expenseModalInitial = snapshotExpenseModal()
  }

  function hasExpenseChanges() {
    if (!expenseModalInitial) return false
    const current = snapshotExpenseModal()
    return current.mode !== expenseModalInitial.mode
      || current.id !== expenseModalInitial.id
      || current.amount !== expenseModalInitial.amount
      || current.merchantName !== expenseModalInitial.merchantName
      || current.platform !== expenseModalInitial.platform
      || current.category !== expenseModalInitial.category
      || current.payment !== expenseModalInitial.payment
      || current.note !== expenseModalInitial.note
      || current.date !== expenseModalInitial.date
      || current.time !== expenseModalInitial.time
      || current.imagePath !== expenseModalInitial.imagePath
      || current.accountId !== expenseModalInitial.accountId
      || current.accountUnbound !== expenseModalInitial.accountUnbound
  }

  function resetExpenseChanges() {
    if (!expenseModalInitial) return
    expenseModal.mode = expenseModalInitial.mode
    expenseModal.id = expenseModalInitial.id
    expenseModal.amount = expenseModalInitial.amount
    expenseModal.merchantName = expenseModalInitial.merchantName
    expenseModal.platform = expenseModalInitial.platform
    expenseModal.category = expenseModalInitial.category
    expenseModal.payment = expenseModalInitial.payment
    expenseModal.note = expenseModalInitial.note
    expenseModal.date = expenseModalInitial.date
    expenseModal.time = expenseModalInitial.time
    expenseModal.imagePath = expenseModalInitial.imagePath
    expenseModal.accountId = expenseModalInitial.accountId
    expenseModal.accountUnbound = expenseModalInitial.accountUnbound
  }

  function openExpenseModal() {
    expenseModal.open = true
    expenseModal.mode = 'create'
    expenseModal.id = null
    expenseModal.amount = ''
    expenseModal.merchantName = ''
    expenseModal.platform = null
    expenseModal.category = null
    expenseModal.payment = null
    expenseModal.note = ''
    expenseModal.date = getLocalDateKey()
    expenseModal.time = ''
    expenseModal.imageUrl = null
    expenseModal.imagePath = null
    expenseModal.imageLoadError = false
    expenseModal.accountId = resolveAccountIdForPayment({
      existingAccountId: null,
      paymentMethod: expenseModal.payment,
      kind: 'expense',
    })
    expenseModal.accountUnbound = !expenseModal.accountId
    setExpenseModalInitial()
  }

  async function openExpenseEditModal(record) {
    expenseModal.open = true
    expenseModal.mode = 'edit'
    expenseModal.id = record.id
    expenseModal.amount = String(record.amount || '')
    expenseModal.merchantName = record.name || ''
    expenseModal.platform = record.platform && record.platform !== '?' ? record.platform : null
    expenseModal.category = record.cat && record.cat !== '?' ? record.cat : null
    expenseModal.payment = record.payment && record.payment !== '?' ? record.payment : null
    expenseModal.note = record.note || ''
    expenseModal.date = record.dateRaw || getLocalDateKey()
    expenseModal.time = record.time || ''
    expenseModal.imagePath = record.image_path || record.image_url || null
    expenseModal.imageUrl = await getSignedImageUrl(expenseModal.imagePath)
    expenseModal.imageLoadError = !!expenseModal.imagePath && !expenseModal.imageUrl
    expenseModal.accountId = resolveAccountIdForPayment({
      existingAccountId: record.accountId,
      paymentMethod: expenseModal.payment,
      kind: 'expense',
    })
    expenseModal.accountUnbound = !expenseModal.accountId
    setExpenseModalInitial()
  }

  function closeExpenseModal() {
    expenseModal.open = false
    expenseModalInitial = null
  }

  async function confirmExpense() {
    return runLockedAction('expense', async () => {
      const amt = parseFloat(expenseModal.amount)
      if (!amt || amt <= 0 || amt > 999999.99) { showWarn('请输入有效金额（0.01 ~ 999999.99）'); return }
      if (!expenseModal.platform || !expenseModal.category || !expenseModal.payment) { showWarn('请选择消费渠道、分类和支付方式'); return }
      if (!expenseModal.date) { showWarn('请选择消费日期'); return }

      const merchantName = expenseModal.merchantName.trim() || `${expenseModal.platform}消费`
      const isLargeTransport = expenseModal.category === '出行' && amt >= 200
      const resolvedTime = expenseModal.time || null

      if (expenseModal.mode === 'edit' && expenseModal.id) {
        const expenseAccountId = expenseModal.accountUnbound
          ? autoAccountIdForPayment(expenseModal.payment, 'expense')
          : (expenseModal.accountId || autoAccountIdForPayment(expenseModal.payment, 'expense') || null)
        const { error } = await sb.rpc('save_transaction_with_account', {
          p_id: expenseModal.id,
          p_amount: amt,
          p_merchant_name: merchantName,
          p_platform: expenseModal.platform,
          p_category: expenseModal.category,
          p_payment_method: expenseModal.payment,
          p_transaction_date: expenseModal.date,
          p_transaction_time: resolvedTime,
          p_note: expenseModal.note.trim() || null,
          p_is_large_transport: isLargeTransport,
          p_transport_type: isLargeTransport ? '交通' : null,
          p_source: null,
          p_image_url: expenseModal.imagePath || null,
          p_image_hash: null,
          p_companion_message: null,
          p_account_id: expenseAccountId,
        })
        if (error) { showError('保存失败：' + humanizeDbError(error)); return }
        await refreshAccountsFromDB()
        if (currentPage.value === 'unbound-records') await loadUnboundRecords()
        closeExpenseModal()
        const editIdx = bills.value.findIndex(item => item.id === expenseModal.id)
        if (editIdx >= 0) {
          bills.value[editIdx] = {
            ...bills.value[editIdx],
            name: merchantName,
            platform: expenseModal.platform,
            payment: expenseModal.payment,
            cat: expenseModal.category,
            amount: amt,
            date: formatDate(expenseModal.date),
            dateRaw: expenseModal.date,
            time: resolvedTime ? resolvedTime.slice(0, 5) : '',
            transport_type: isLargeTransport ? '交通' : null,
            note: expenseModal.note.trim() || null,
          }
        }
        showFlash('✓ 支出已更新')
        if (detailRecord.value?.id === expenseModal.id) {
          const updated = bills.value.find(item => item.id === expenseModal.id)
          if (updated) {
            await openRecordDetail('expense', updated)
          }
        }
        return
      }

      const expenseAccountIdNew = expenseModal.accountUnbound
        ? autoAccountIdForPayment(expenseModal.payment, 'expense')
        : (expenseModal.accountId || autoAccountIdForPayment(expenseModal.payment, 'expense') || null)
      const { data: newRow, error } = await sb.rpc('save_transaction_with_account', {
        p_id: null,
        p_amount: amt,
        p_merchant_name: merchantName,
        p_platform: expenseModal.platform,
        p_category: expenseModal.category,
        p_payment_method: expenseModal.payment,
        p_transaction_date: expenseModal.date,
        p_transaction_time: resolvedTime || (new Date().toTimeString().slice(0, 8)),
        p_note: expenseModal.note.trim() || null,
        p_is_large_transport: isLargeTransport,
        p_transport_type: isLargeTransport ? '交通' : null,
        p_source: 'manual',
        p_image_url: expenseModal.imagePath || null,
        p_image_hash: null,
        p_companion_message: null,
        p_account_id: expenseAccountIdNew,
      })
      if (error) { showError('保存失败：' + humanizeDbError(error)); return }
      await refreshAccountsFromDB()
      if (currentPage.value === 'unbound-records') await loadUnboundRecords()
      closeExpenseModal()
      bills.value.unshift(mapTransaction(newRow))
      showFlash('✓ 支出已记录')
    })
  }

  function markExpenseImageUnavailable() {
    expenseModal.imageUrl = null
    expenseModal.imageLoadError = true
  }

  let universalModalInitial = null

  function getUniversalDomainMeta(domainKey = universalModal.domainKey) {
    return getRegistryUniversalDomainMeta(domainKey)
  }

  function snapshotUniversalModal() {
    const meta = getUniversalDomainMeta(universalModal.domainKey)
    const base = {
      mode: universalModal.mode,
      id: universalModal.id,
      domainKey: universalModal.domainKey,
      title: universalModal.title,
      primaryValue: universalModal.primaryValue,
      dimension: universalModal.dimension,
      note: universalModal.note,
      date: universalModal.date,
      time: universalModal.time,
      imagePath: universalModal.imagePath,
    }
    for (const field of meta.formFields || []) {
      base[field.model] = universalModal[field.model]
    }
    return base
  }

  function setUniversalModalInitial() {
    universalModalInitial = snapshotUniversalModal()
  }

  function hasUniversalChanges() {
    if (!universalModalInitial) return false
    const current = snapshotUniversalModal()
    return Object.keys(current).some(key => current[key] !== universalModalInitial[key])
  }

  function resetUniversalChanges() {
    if (!universalModalInitial) return
    Object.assign(universalModal, universalModalInitial)
  }

  function openUniversalModal(domainKey = 'sport') {
    const meta = getUniversalDomainMeta(domainKey)
    resetUniversalModal(universalModal, domainKey, meta, getLocalDateKey())
    setUniversalModalInitial()
  }

  async function openUniversalEditModal(record) {
    const meta = getUniversalDomainMeta(record.domainKey)
    hydrateUniversalModalFromRecord(universalModal, record, meta)
    universalModal.imageUrl = await getSignedImageUrl(universalModal.imagePath)
    universalModal.imageLoadError = !!universalModal.imagePath && !universalModal.imageUrl
    setUniversalModalInitial()
  }

  function closeUniversalModal() {
    universalModal.open = false
    universalModalInitial = null
  }

  async function confirmUniversalRecord() {
    const meta = getUniversalDomainMeta(universalModal.domainKey)
    const validationError = validateUniversalModal(universalModal, meta)
    if (validationError) {
      showWarn(validationError)
      return
    }

    const { data: domainRows, error: domainErr } = await sb.from('data_domains')
      .select('id,key,version')
      .eq('key', universalModal.domainKey)
      .eq('status', 'active')
      .limit(1)
    if (domainErr || !domainRows?.length) {
      showWarn('数据域未就绪，请先执行 007 迁移')
      return
    }

    const domainRow = domainRows[0]
    const draft = buildUniversalRecordDraft(universalModal, meta)
    const body = {
      domain_id: domainRow.id,
      domain_key: universalModal.domainKey,
      domain_version: domainRow.version || '1.0',
      occurred_at: draft.occurredAt,
      title: draft.title,
      summary: draft.summary,
      payload_jsonb: draft.payload,
      source: 'manual',
      source_image_path: universalModal.imagePath || null,
    }

    const wasEdit = universalModal.mode === 'edit' && universalModal.id

    if (wasEdit) {
      const { error } = await sb.from('data_records').update(body).eq('id', universalModal.id)
      if (error) {
        showError('保存失败：' + humanizeDbError(error))
        return
      }
      closeUniversalModal()
      const idx = dataRecords.value.findIndex(r => r.id === universalModal.id)
      if (idx >= 0) {
        dataRecords.value[idx] = {
          ...dataRecords.value[idx],
          occurredAt: draft.occurredAt,
          title: draft.title,
          summary: draft.summary,
          payload: draft.payload,
          imagePath: universalModal.imagePath || null,
        }
      }
      showFlash('✓ 记录已更新')
      if (detailRecord.value?.kind === 'universal' && detailRecord.value.id === universalModal.id) {
        await refreshDetailRecord()
      }
    } else {
      const { data: newRow, error } = await sb.from('data_records')
        .insert({ ...body, user_id: currentUserId.value })
        .select('*')
        .single()
      if (error) {
        showError('保存失败：' + humanizeDbError(error))
        return
      }
      closeUniversalModal()
      dataRecords.value.unshift({
        id: newRow.id,
        domainId: newRow.domain_id,
        domainKey: newRow.domain_key,
        domainVersion: newRow.domain_version || '1.0',
        occurredAt: newRow.occurred_at,
        createdAt: newRow.created_at,
        title: newRow.title,
        summary: newRow.summary,
        payload: newRow.payload_jsonb || {},
        imagePath: newRow.source_image_path,
        imageHash: newRow.source_image_hash,
        stagingRecordId: newRow.staging_record_id,
        source: newRow.source || 'manual',
      })
      showFlash('✓ 记录已添加')
    }
  }

  function markUniversalImageUnavailable() {
    universalModal.imageUrl = null
    universalModal.imageLoadError = true
  }

  function openImgFull(src) {
    imgOverlay.src = src
    imgOverlay.open = true
  }

  function closeImgFull() {
    imgOverlay.open = false
  }

  function openDeleteConfirm(type, id, imagePath = null) {
    deleteConfirm.open = true
    deleteConfirm.type = type
    deleteConfirm.id = id
    deleteConfirm.imagePath = imagePath
  }

  function closeDeleteConfirm() {
    deleteConfirm.open = false
  }

  async function discardStagingRecord(record, reason = 'user_discarded') {
    if (!record?.id) return
    const ok = confirm('确认销毁这条待处理截图？记录会从待处理列表移除。')
    if (!ok) return
    const { error } = await sb.from('staging_records').update({
      status: 'discarded',
      discard_reason: reason,
      resolved_action: 'discarded',
      resolved_at: new Date().toISOString(),
    }).eq('id', record.id)
    if (error) {
      showFlash('❌ 销毁失败：' + error.message)
      return
    }
    const idx = stagingRecords.value.findIndex(r => r.id === record.id)
    if (idx >= 0) stagingRecords.value.splice(idx, 1)
    showFlash('✓ 已销毁')
  }

  function toggleBatchMode() {
    batchMode.value = !batchMode.value
    if (!batchMode.value) selectedStagingIds.value = new Set()
  }

  function toggleSelectStaging(id) {
    const next = new Set(selectedStagingIds.value)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    selectedStagingIds.value = next
  }

  function selectAllStaging(records) {
    selectedStagingIds.value = new Set(records.map(r => r.id))
  }

  function clearSelection() {
    selectedStagingIds.value = new Set()
  }

  async function batchDiscard() {
    const ids = [...selectedStagingIds.value]
    if (!ids.length) return
    const ok = confirm(`确认销毁选中的 ${ids.length} 条记录？`)
    if (!ok) return
    showFlash(`⏳ 正在销毁 ${ids.length} 条...`)
    const { error } = await sb.from('staging_records').update({
      status: 'discarded',
      discard_reason: 'batch_discard',
      resolved_action: 'discarded',
      resolved_at: new Date().toISOString(),
    }).in('id', ids)
    if (error) { showFlash('❌ 批量销毁失败：' + error.message); return }
    ids.forEach(id => {
      const idx = stagingRecords.value.findIndex(r => r.id === id)
      if (idx >= 0) stagingRecords.value.splice(idx, 1)
    })
    selectedStagingIds.value = new Set()
    showFlash(`✓ 已销毁 ${ids.length} 条`)
  }

  async function batchArchive(domainKey) {
    const ids = [...selectedStagingIds.value]
    if (!ids.length) return
    if (domainKey !== 'expense' && domainKey !== 'income') {
      showFlash('批量归档目前仅支持消费和收入域')
      return
    }
    const ok = confirm(`确认将选中的 ${ids.length} 条批量归档到「${getSystemDomainLabel(domainKey, domainKey)}」？`)
    if (!ok) return
    showFlash(`⏳ 正在批量归档 ${ids.length} 条...`)
    let successCount = 0
    for (const id of ids) {
      const record = stagingRecords.value.find(r => r.id === id)
      if (!record) continue
      try {
        await archiveStagingRecord(record, domainKey)
        successCount++
      } catch (e) {
        console.warn('批量归档单条失败:', id, e)
      }
    }
    selectedStagingIds.value = new Set()
    showFlash(`✓ 已归档 ${successCount}/${ids.length} 条`)
  }

  async function retryStagingRecord(record) {
    if (!record?.id) return
    return runLockedAction('retryStaging', async () => {
      showFlash('⏳ 正在重新识别...')
      try {
        const { data: { session } } = await sb.auth.getSession()
        const token = session?.access_token
        if (!token) throw new Error('登录状态已失效，请重新登录')

        const fnUrl = `${SUPABASE_URL}/functions/v1/ingest-receipt`
        const formData = new FormData()
        formData.append('staging_record_id', record.id)
        if (currentUserId.value) formData.append('user_id', currentUserId.value)
        const resp = await fetch(fnUrl, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'apikey': SUPABASE_ANON_KEY,
          },
          body: formData,
        })
        if (!resp.ok) {
          const errText = await resp.text()
          throw new Error(`${resp.status}: ${errText}`)
        }
        const result = await resp.json()
        if (result.status === 'done') {
          showFlash(`✓ 重试成功 → 已归档到「${getSystemDomainLabel(result.record_type, result.record_type)}」`)
          const idx = stagingRecords.value.findIndex(r => r.id === record.id)
          if (idx >= 0) stagingRecords.value.splice(idx, 1)
        } else {
          showFlash('⚠ 重试未确定，请手动选择数据域归档（下方按钮）')
        }
      } catch (e) {
        showFlash('❌ 重试失败：' + (e.message || '未知错误'))
      }
    })
  }

  async function archiveStagingRecord(record, domainKey) {
    if (!record?.id || !domainKey) return
    const domain = domains.value.find(item => item.id === domainKey)
    if (!domain) return

    const ok = confirm(`确认把这条待处理截图归档到「${domain.name}」？`)
    if (!ok) return

    const payload = {
      ...(record.extracted || {}),
      image_type: record.imageType || null,
      record_type: record.recordType || null,
      confidence: record.confidence || 0,
      ai_summary: record.summary || null,
      failure_reason: record.failureReason || null,
    }

    const occurredAt = payload.occurred_at || payload.order_finished_at || record.createdAt || new Date().toISOString()
    const title = buildUniversalRecordTitle(domainKey, payload, record)
    const summary = record.summary || `${domain.name}截图归档`

    if (domainKey === 'expense') {
      const amount = parseFloat(payload.amount || record.summary?.match(/金额\s*(\d+(\.\d+)?)/)?.[1] || '0')
      const paymentMethod = payload.payment_method || null
      const { data: inserted, error: insertErr } = await sb.rpc('save_transaction_with_account', {
        p_id: null,
        p_amount: amount > 0 ? amount : 0.01,
        p_merchant_name: payload.merchant_name || payload.source_name || title || '待补充支出',
        p_platform: payload.platform || '微信',
        p_category: payload.category || null,
        p_payment_method: paymentMethod,
        p_transaction_date: normalizeDateOnly(occurredAt),
        p_transaction_time: null,
        p_note: summary,
        p_is_large_transport: payload.category === 'transport' && amount >= 200,
        p_transport_type: payload.category === 'transport' && amount >= 200 ? '交通' : null,
        p_source: 'ai_scan',
        p_image_url: record.imagePath || null,
        p_image_hash: record.imageHash || null,
        p_companion_message: null,
        p_account_id: autoAccountIdForPayment(paymentMethod, 'expense'),
      })
      if (insertErr) {
        showFlash('❌ 转入支出失败：' + humanizeDbError(insertErr))
        return
      }
      await finishStagingArchive(record, inserted.id, null, 'expense', payload)
      const sIdx = stagingRecords.value.findIndex(r => r.id === record.id)
      if (sIdx >= 0) stagingRecords.value.splice(sIdx, 1)
      showFlash('✓ 已转入支出，必要时可继续补充')
      const bill = bills.value.find(item => item.id === inserted.id)
      if (bill) {
        if (bill.status === 'pending') await openPendingModal(bill)
        else await openExpenseEditModal(bill)
      }
      return
    }

    if (domainKey === 'income') {
      const amount = parseFloat(payload.amount || record.summary?.match(/金额\s*(\d+(\.\d+)?)/)?.[1] || '0')
      const { data: inserted, error: insertErr } = await sb.rpc('save_income_with_account', {
        p_id: null,
        p_category: payload.income_category || 'other',
        p_source_name: payload.source_name || title || '截图识别收入',
        p_amount: amount > 0 ? amount : 0.01,
        p_income_date: normalizeDateOnly(occurredAt),
        p_note: summary,
        p_source: 'ai_scan',
        p_image_url: record.imagePath || null,
        p_image_hash: record.imageHash || null,
        p_companion_message: null,
        p_account_id: defaultAccountIdForKind('income'),
      })
      if (insertErr) {
        showFlash('❌ 转入收入失败：' + humanizeDbError(insertErr))
        return
      }
      await finishStagingArchive(record, inserted.id, null, 'income', payload)
      const sIdx2 = stagingRecords.value.findIndex(r => r.id === record.id)
      if (sIdx2 >= 0) stagingRecords.value.splice(sIdx2, 1)
      showFlash('✓ 已转入收入')
      const income = incomeRecords.value.find(item => item.id === inserted.id)
        || recentIncomeRecords.value.find(item => item.id === inserted.id)
      if (income) await openIncomeEditModal(income)
      return
    }

    const { data: domainRows, error: domainErr } = await sb.from('data_domains')
      .select('id,key,version')
      .eq('key', domainKey)
      .eq('status', 'active')
      .limit(1)
    if (domainErr || !domainRows?.length) {
      showFlash('❌ 数据域未就绪，请先执行 007 迁移')
      return
    }

    const domainRow = domainRows[0]
    const { data: inserted, error: insertErr } = await sb.from('data_records').insert({
      domain_id: domainRow.id,
      domain_key: domainKey,
      domain_version: domainRow.version || '1.0',
      occurred_at: occurredAt,
      title,
      summary,
      payload_jsonb: payload,
      source: 'staging',
      source_image_path: record.imagePath || null,
      source_image_hash: record.imageHash || null,
      staging_record_id: record.id,
      user_id: currentUserId.value,
    }).select('id').single()
    if (insertErr) {
      showFlash('❌ 归档失败：' + humanizeDbError(insertErr))
      return
    }

    const done = await finishStagingArchive(record, inserted.id, domainRow.id, domainKey, payload)
    if (!done) return

    const sIdx3 = stagingRecords.value.findIndex(r => r.id === record.id)
    if (sIdx3 >= 0) stagingRecords.value.splice(sIdx3, 1)
    showFlash(`✓ 已归档到${domain.name}`)
  }

  async function finishStagingArchive(record, targetRecordId, targetDomainId, domainKey, payload) {
    const { error: stagingErr } = await sb.from('staging_records').update({
      status: 'archived',
      target_domain_id: targetDomainId || record.targetDomainId || null,
      target_record_id: targetRecordId,
      resolved_action: 'archived',
      resolved_at: new Date().toISOString(),
    }).eq('id', record.id)
    if (stagingErr) {
      showFlash('❌ 中转站状态更新失败：' + stagingErr.message)
      return false
    }

    const { error: feedbackErr } = await sb.from('user_routing_feedback').insert({
      staging_record_id: record.id,
      image_hash: record.imageHash || null,
      original_domain_key: record.domainKey || null,
      corrected_domain_key: domainKey,
      action: 'archive',
      confidence: record.confidence || null,
      payload_jsonb: payload,
    })
    if (feedbackErr) console.warn('写入路由反馈失败:', feedbackErr.message)
    return true
  }

  function buildUniversalRecordTitle(domainKey, payload, record) {
    return buildUniversalRecordTitleFromAdapter(domainKey, payload, record)
  }

  // ────────────────────────────────────────────────
  // 账户 CRUD + 账户流水统一入口
  // ────────────────────────────────────────────────

  function openAccountModalForCreate() {
    accountModal.open = true
    accountModal.mode = 'create'
    accountModal.id = null
    accountModal.name = ''
    accountModal.type = 'wallet_balance'
    accountModal.institution = ''
    accountModal.last4 = ''
    accountModal.initialBalance = ''
    accountModal.isDefaultExpense = false
    accountModal.isDefaultIncome = false
    accountModal.isArchived = false
  }

  function openAccountModalForEdit(account) {
    if (!account) return
    accountModal.open = true
    accountModal.mode = 'edit'
    accountModal.id = account.id
    accountModal.name = account.name || ''
    accountModal.type = normalizeAccountType(account.type || 'other')
    accountModal.institution = account.institution || ''
    accountModal.last4 = account.last4 || ''
    accountModal.initialBalance = String(account.initialBalance ?? '')
    accountModal.isDefaultExpense = !!account.isDefaultExpense
    accountModal.isDefaultIncome = !!account.isDefaultIncome
    accountModal.isArchived = !!account.isArchived
  }

  function closeAccountModal() {
    accountModal.open = false
  }

  function validateAccountForm() {
    const name = (accountModal.name || '').trim()
    if (!name) return '请输入账户名称'
    if (name.length > 30) return '账户名称最多 30 个字'
    if (accountModal.last4 && !/^\d{4}$/.test(String(accountModal.last4).trim())) return '尾号必须是 4 位数字'
    const init = parseFloat(accountModal.initialBalance || '0')
    if (Number.isNaN(init)) return '初始余额必须是数字'
    return ''
  }

  async function saveAccount() {
    return runLockedAction('account', async () => {
      if (!currentUserId.value) { showWarn('请先登录'); return null }
      const err = validateAccountForm()
      if (err) { showWarn(err); return null }
      const name = accountModal.name.trim()
      const initial = parseFloat(accountModal.initialBalance || '0') || 0
      const last4 = accountModal.last4 && /^\d{4}$/.test(String(accountModal.last4).trim()) ? String(accountModal.last4).trim() : null
      const institution = accountModal.institution.trim() || null

      if (accountModal.mode === 'edit' && accountModal.id) {
        const body = {
          name,
          type: normalizeAccountType(accountModal.type),
          institution,
          last4,
          is_default_expense: !!accountModal.isDefaultExpense,
          is_default_income: !!accountModal.isDefaultIncome,
          is_archived: !!accountModal.isArchived,
          updated_at: new Date().toISOString(),
        }
        const { data, error } = await sb.from('accounts').update(body).eq('id', accountModal.id).select('*').single()
        if (error) { showError('保存失败：' + humanizeDbError(error)); return null }
        // 默认账户互斥
        if (body.is_default_expense) await unsetOtherDefaults('expense', data.id)
        if (body.is_default_income) await unsetOtherDefaults('income', data.id)
        const idx = accounts.value.findIndex(a => a.id === data.id)
        if (idx >= 0) accounts.value[idx] = mapAccountRow(data)
        closeAccountModal()
        showFlash('✓ 账户已更新')
        return data
      }

      const body = {
        user_id: currentUserId.value,
        name,
        type: normalizeAccountType(accountModal.type),
        institution,
        last4,
        currency: 'CNY',
        initial_balance: initial,
        current_balance: initial,
        is_default_expense: !!accountModal.isDefaultExpense,
        is_default_income: !!accountModal.isDefaultIncome,
      }
      const { data, error } = await sb.from('accounts').insert(body).select('*').single()
      if (error) { showError('创建失败：' + humanizeDbError(error)); return null }
      if (body.is_default_expense) await unsetOtherDefaults('expense', data.id)
      if (body.is_default_income) await unsetOtherDefaults('income', data.id)
      accounts.value.unshift(mapAccountRow(data))
      closeAccountModal()
      showFlash('✓ 账户已创建')
      return data
    })
  }

  async function unsetOtherDefaults(kind, keepId) {
    const column = kind === 'expense' ? 'is_default_expense' : 'is_default_income'
    const { error } = await sb.from('accounts')
      .update({ [column]: false })
      .eq('user_id', currentUserId.value)
      .eq(column, true)
      .neq('id', keepId)
    if (error) console.warn(`重置默认 ${kind} 账户失败:`, error.message)
    accounts.value = accounts.value.map(a => a.id === keepId ? a : { ...a, [kind === 'expense' ? 'isDefaultExpense' : 'isDefaultIncome']: false })
  }

  async function archiveAccount(account, archived = true) {
    if (!account?.id) return
    const ok = confirm(archived ? `确认归档账户「${account.name}」？归档后不再作为默认候选。` : `确认恢复账户「${account.name}」？`)
    if (!ok) return
    const { data, error } = await sb.from('accounts')
      .update({ is_archived: archived, updated_at: new Date().toISOString() })
      .eq('id', account.id)
      .select('*')
      .single()
    if (error) { showError('操作失败：' + humanizeDbError(error)); return }
    const idx = accounts.value.findIndex(a => a.id === account.id)
    if (idx >= 0) accounts.value[idx] = mapAccountRow(data)
    showFlash(archived ? '✓ 账户已归档' : '✓ 账户已恢复')
  }

  function mapAccountEntryRow(row) {
    return {
      id: row.id,
      accountId: row.account_id,
      direction: row.direction,
      amount: Number(row.amount || 0),
      entryType: row.entry_type,
      sourceTable: row.source_table || '',
      sourceId: row.source_id || '',
      occurredAt: row.occurred_at,
      note: row.note || '',
      isVoided: !!row.is_voided,
      voidedReason: row.voided_reason || '',
      createdAt: row.created_at,
    }
  }

  async function loadAccountEntries(accountId) {
    if (!accountId) {
      selectedAccountEntries.value = []
      return
    }
    accountEntriesLoading.value = true
    const { data, error } = await sb.from('account_entries')
      .select('*')
      .eq('account_id', accountId)
      .order('occurred_at', { ascending: false })
      .order('created_at', { ascending: false })
      .limit(50)
    accountEntriesLoading.value = false
    if (error) {
      console.warn('加载账户流水失败:', error.message)
      selectedAccountEntries.value = []
      return
    }
    selectedAccountEntries.value = (data || []).map(mapAccountEntryRow)
  }

  async function openAccountDetail(account) {
    if (!account?.id) return
    selectedAccount.value = account
    await loadAccountEntries(account.id)
    navigateTo('account-detail')
  }

  async function refreshAccountDetail() {
    if (!selectedAccount.value?.id) return
    const latest = accounts.value.find(account => account.id === selectedAccount.value.id)
    if (latest) selectedAccount.value = latest
    await loadAccountEntries(selectedAccount.value.id)
  }

  function openAccountEntrySource(entry) {
    if (!entry?.sourceTable || !entry?.sourceId) return
    if (entry.sourceTable === 'transactions') {
      const bill = bills.value.find(item => item.id === entry.sourceId)
      if (bill) openRecordDetail('expense', bill)
      else showFlash('这条支出不在当前月份列表中')
      return
    }
    if (entry.sourceTable === 'income_records') {
      const income = incomeRecords.value.find(item => item.id === entry.sourceId)
        || recentIncomeRecords.value.find(item => item.id === entry.sourceId)
      if (income) openRecordDetail('income', income)
      else showFlash('这条收入不在当前列表中')
      return
    }
    if (entry.sourceTable === 'data_records') {
      const record = dataRecords.value.find(item => item.id === entry.sourceId)
      if (record) openRecordDetail('universal', record)
      else showFlash('这条快照不在当前列表中')
    }
  }

  // 统一流水入口：保证幂等（先作废旧的同源同类流水再插入新的）
  async function upsertAccountEntry({ accountId, direction, amount, entryType, sourceTable, sourceId, occurredAt, note }) {
    if (!accountId) return
    const amt = Number(amount)
    if (!Number.isFinite(amt) || amt <= 0) return
    const { error } = await sb.rpc('create_account_entry_for_record', {
      p_account_id: accountId,
      p_direction: direction,
      p_amount: amt,
      p_entry_type: entryType,
      p_source_table: sourceTable || null,
      p_source_id: sourceId || null,
      p_occurred_at: occurredAt || new Date().toISOString(),
      p_note: note || null,
    })
    if (error) console.warn('写入账户流水失败:', error.message)
  }

  function resolveAccountEntryDirection({ accountId, entryType, fallbackDirection }) {
    const account = accounts.value.find(item => item.id === accountId)
    if (!account) return fallbackDirection
    if (entryType === 'expense' && isLiabilityAccount(account)) return 'in'
    return fallbackDirection
  }

  async function voidAccountEntries(sourceTable, sourceId, reason = 'source_deleted') {
    if (!sourceTable || !sourceId) return
    const { error } = await sb.rpc('void_account_entries_for_record', {
      p_source_table: sourceTable,
      p_source_id: sourceId,
      p_reason: reason,
    })
    if (error) console.warn('作废账户流水失败:', error.message)
  }

  function refreshAccountsFromDB() {
    return sb.from('accounts')
      .select('*')
      .order('sort_order', { ascending: true })
      .order('created_at', { ascending: true })
      .then(({ data, error }) => {
        if (error) { console.warn('刷新账户失败:', error.message); return }
        accounts.value = (data || []).map(mapAccountRow)
      })
  }

  function defaultAccountIdForKind(kind) {
    const acc = accounts.value.find(a => !a.isArchived && (kind === 'expense' ? a.isDefaultExpense : a.isDefaultIncome))
    return acc?.id || null
  }

  function normalizeAccountMatchText(value) {
    return String(value || '').trim().toLowerCase().replace(/\s+/g, '')
  }

  function autoAccountIdForPayment(paymentMethod, kind = 'expense') {
    const paymentText = normalizeAccountMatchText(payAliasMap[paymentMethod] || paymentMethod)
    if (!paymentText || kind !== 'expense') return null

    const candidates = accounts.value.filter(account => !account.isArchived)
    const scoreAccount = (account) => {
      const name = normalizeAccountMatchText(account.name)
      const institution = normalizeAccountMatchText(account.institution)
      const accountText = `${name} ${institution}`
      const type = normalizeAccountType(account.type)
      let score = 0

      if (paymentText.includes('花呗') && type === 'credit_line' && accountText.includes('花呗')) score += 100
      if (paymentText.includes('白条') && type === 'credit_line' && (accountText.includes('白条') || accountText.includes('京东'))) score += 100
      if (paymentText.includes('月付') && type === 'credit_line' && accountText.includes('月付')) score += 100
      if (paymentText.includes('银行卡') && type === 'debit_card') score += 40
      if (paymentText.includes('微信') && type === 'wallet_balance' && accountText.includes('微信')) score += 70
      if (paymentText.includes('支付宝') && type === 'wallet_balance' && accountText.includes('支付宝')) score += 70
      if (name && paymentText.includes(name)) score += 60
      if (institution && paymentText.includes(institution)) score += 50
      return score
    }

    const ranked = candidates
      .map(account => ({ account, score: scoreAccount(account) }))
      .filter(item => item.score > 0)
      .sort((a, b) => b.score - a.score)
    return ranked[0]?.account.id || null
  }

  function resolveAccountIdForPayment({ existingAccountId, paymentMethod, kind }) {
    return existingAccountId || autoAccountIdForPayment(paymentMethod, kind) || defaultAccountIdForKind(kind)
  }

  function accountConfidenceTone(score) {
    if (score >= 0.84) return '高'
    if (score >= 0.6) return '中'
    return '低'
  }

  function accountCandidateReasonText(reasons = []) {
    if (reasons.includes('last4')) return '匹配到账户尾号'
    if (reasons.includes('huabei_exact') || reasons.includes('baitiao_exact') || reasons.includes('monthly_credit_exact')) return '匹配到明确的信用支付名称'
    if (reasons.includes('wechat_exact') || reasons.includes('alipay_exact')) return '匹配到明确的钱包余额名称'
    if (reasons.includes('single_debit_card')) return '当前仅有一张可用银行卡候选'
    if (reasons.includes('type') && (reasons.includes('institution') || reasons.includes('name'))) return '账户类型与机构名称同时命中'
    if (reasons.includes('institution')) return '匹配到机构名称'
    if (reasons.includes('name')) return '匹配到账户名称'
    if (reasons.includes('debit_card_type')) return '支付线索指向银行卡'
    if (reasons.includes('type')) return '账户类型与支付线索一致'
    return '根据支付线索综合推荐'
  }

  function buildPendingAccountHint(record, kind) {
    const inference = record?.accountInference || record?.account_inference || record?.extracted?.account_inference || null
    const source = kind === 'income'
      ? (inference?.receiving_account || inference?.funding_source || null)
      : (inference?.funding_source || null)
    const rawText = source?.raw_text || record?.fundingSourceLabel || record?.payment || null
    const institution = source?.institution || null
    const last4 = source?.last4 || null
    const type = normalizeAccountType(source?.type || null)
    const confidence = Number(source?.confidence || record?.accountConfidence || 0)
    const evidence = source?.evidence || inference?.payment_channel?.evidence || null
    if (!rawText && !institution && !last4 && !type && !confidence) return null
    return { rawText, institution, last4, type, confidence, evidence }
  }

  function rankCandidateAccountsByHint(hint) {
    if (!hint) return []
    const hintText = normalizeAccountMatchText([hint.rawText, hint.institution].filter(Boolean).join(' '))
    const activeDebitCardCount = accounts.value.filter(account => !account.isArchived && normalizeAccountType(account.type) === 'debit_card').length
    return accounts.value
      .filter(account => !account.isArchived)
      .map(account => {
        const type = normalizeAccountType(account.type)
        const name = normalizeAccountMatchText(account.name)
        const institution = normalizeAccountMatchText(account.institution)
        const accountText = `${name} ${institution}`
        const reasons = []
        let score = 0

        if (hint.type && type === hint.type) { score += 0.34; reasons.push('type') }
        if (hint.last4 && account.last4 === hint.last4) { score += 0.42; reasons.push('last4') }
        if (hintText) {
          if (name && hintText.includes(name)) { score += 0.2; reasons.push('name') }
          if (institution && hintText.includes(institution)) { score += 0.2; reasons.push('institution') }
          if (hintText.includes('花呗') && type === 'credit_line' && accountText.includes('花呗')) { score += 0.42; reasons.push('huabei_exact') }
          if (hintText.includes('白条') && type === 'credit_line' && (accountText.includes('白条') || accountText.includes('京东'))) { score += 0.42; reasons.push('baitiao_exact') }
          if (hintText.includes('月付') && type === 'credit_line' && accountText.includes('月付')) { score += 0.42; reasons.push('monthly_credit_exact') }
          if (hintText.includes('微信') && type === 'wallet_balance' && accountText.includes('微信')) { score += 0.42; reasons.push('wechat_exact') }
          if (hintText.includes('支付宝') && type === 'wallet_balance' && accountText.includes('支付宝')) { score += 0.42; reasons.push('alipay_exact') }
          if ((hintText.includes('银行卡') || hintText.includes('银行')) && type === 'debit_card') {
            score += activeDebitCardCount === 1 ? 0.5 : 0.16
            reasons.push(activeDebitCardCount === 1 ? 'single_debit_card' : 'debit_card_type')
          }
        }
        if (hint.confidence >= 0.8) score += 0.04
        return {
          account,
          score: Math.round(Math.min(score, 0.99) * 100) / 100,
          reason: accountCandidateReasonText(reasons),
          confidenceLabel: accountConfidenceTone(score),
        }
      })
      .filter(item => item.score > 0)
      .sort((a, b) => b.score - a.score)
  }

  function pendingAccountReview(kind, record) {
    const hint = buildPendingAccountHint(record, kind)
    const candidates = rankCandidateAccountsByHint(hint).slice(0, 3)
    const top = candidates[0] || null
    return {
      hint,
      candidates,
      reviewReason: hint?.evidence || (hint?.rawText ? `识别到账户线索「${hint.rawText}」但仍需要你确认真实${kind === 'income' ? '到账' : '出资'}账户。` : '当前只有支付通道线索，真实账户还需要你确认。'),
      confidenceText: hint ? `${Math.round((hint.confidence || 0) * 100)}%` : null,
      recommendedAccountId: top?.account?.id || null,
    }
  }

  function accountById(accountId) {
    return accounts.value.find(account => account.id === accountId) || null
  }

  function recommendAccountForRecord(kind, record) {
    if (!record) return null
    const accountId = kind === 'income'
      ? (record.accountId || defaultAccountIdForKind('income'))
      : (record.accountId || autoAccountIdForPayment(record.payment, 'expense') || defaultAccountIdForKind('expense'))
    const account = accountById(accountId)
    if (!account) return null
    const reason = kind === 'income'
      ? (record.accountId ? '已绑定到账账户' : '使用默认收入账户')
      : (record.accountId
          ? '已绑定出资账户'
          : record.payment && record.payment !== '?'
            ? `根据支付方式「${record.payment}」推荐`
            : '使用默认支出账户')
    return {
      account,
      accountId: account.id,
      reason,
      confidence: record.accountId ? '已确认' : (kind === 'expense' && record.payment && record.payment !== '?' ? '高' : '默认'),
    }
  }

  function accountBindingExplanation(kind, record) {
    const recommendation = recommendAccountForRecord(kind, record)
    if (!recommendation) {
      return {
        account: null,
        status: 'unbound',
        title: '未绑定账户',
        reason: kind === 'income' ? '这笔收入还没有到账账户，补绑后会生成账户流水。' : '这笔支出还没有出资账户，补绑后会生成账户流水。',
      }
    }
    if (record?.accountId) {
      return {
        account: recommendation.account,
        status: 'bound',
        title: `已绑定：${recommendation.account.name}`,
        reason: recommendation.reason,
      }
    }
    return {
      account: recommendation.account,
      status: 'recommended',
      title: `推荐绑定：${recommendation.account.name}`,
      reason: recommendation.reason,
    }
  }

  function balanceImpactPreview({ kind, accountId, amount, unbound }) {
    const normalizedAmount = Number(amount || 0)
    if (unbound || !accountId || !Number.isFinite(normalizedAmount) || normalizedAmount <= 0) {
      return {
        title: '暂不影响账户余额',
        detail: '保留记录本身，但不会生成账户流水。',
      }
    }
    const account = accountById(accountId)
    if (!account) {
      return {
        title: '将生成账户流水',
        detail: '保存后会按所选账户更新余额。',
      }
    }
    const liability = isLiabilityAccount(account)
    const verb = kind === 'income'
      ? (liability ? '负债增加' : '余额增加')
      : (liability ? '欠款增加' : '余额减少')
    const sign = kind === 'income' || liability ? '+' : '-'
    return {
      title: `${account.name} ${verb}`,
      detail: `保存后会生成账户流水，${account.name} ${sign}¥${normalizedAmount.toFixed(2)}。`,
    }
  }

  async function bindRecordToRecommendedAccount(kind, record) {
    const recommendation = recommendAccountForRecord(kind, record)
    if (!recommendation?.accountId) {
      showFlash('暂无可推荐账户，请手动选择')
      if (kind === 'expense') await openExpenseEditModal(record)
      if (kind === 'income') await openIncomeEditModal(record)
      return false
    }
    const impact = balanceImpactPreview({ kind, accountId: recommendation.accountId, amount: record?.amount, unbound: false })
    const ok = confirm(`确认补绑到「${recommendation.account.name}」？\n${impact.detail}`)
    if (!ok) return false
    return bindRecordToAccount(kind, record, recommendation.accountId)
  }

  async function bindRecordToAccount(kind, record, accountId) {
    if (!record?.id || !accountId) return false
    if (kind === 'income') {
      const { error } = await sb.rpc('save_income_with_account', {
        p_id: record.id,
        p_category: record.cat || 'other',
        p_source_name: record.source || '收入',
        p_amount: Number(record.amount || 0),
        p_income_date: record.dateRaw || getLocalDateKey(),
        p_note: record.note || null,
        p_source: record.sourceType || null,
        p_image_url: record.image_path || record.image_url || null,
        p_image_hash: null,
        p_companion_message: record.companionMessage || null,
        p_account_id: accountId,
      })
      if (error) { showFlash('补绑失败：' + humanizeDbError(error)); return false }
    } else {
      const time = record.time ? `${record.time.length === 5 ? `${record.time}:00` : record.time}` : null
      const { error } = await sb.rpc('save_transaction_with_account', {
        p_id: record.id,
        p_amount: Number(record.amount || 0),
        p_merchant_name: record.name || '支出',
        p_platform: record.platform && record.platform !== '?' ? record.platform : null,
        p_category: record.cat && record.cat !== '?' ? record.cat : null,
        p_payment_method: record.payment && record.payment !== '?' ? record.payment : null,
        p_transaction_date: record.dateRaw || getLocalDateKey(),
        p_transaction_time: time,
        p_note: record.note || null,
        p_is_large_transport: record.cat === 'transport' && Number(record.amount || 0) >= 200,
        p_transport_type: record.transport_type || null,
        p_source: record.source || null,
        p_image_url: record.image_path || record.image_url || null,
        p_image_hash: record.image_hash || null,
        p_companion_message: record.companionMessage || null,
        p_account_id: accountId,
      })
      if (error) { showFlash('补绑失败：' + humanizeDbError(error)); return false }
    }

    await refreshAccountsFromDB()
    await loadUnboundRecords()
    if (detailRecord.value?.id === record.id) {
      await loadData(0, true)
      await refreshDetailRecord()
    }
    showFlash('✓ 已补绑账户并生成流水')
    return true
  }

  function walletSnapshotKindOf(record) {
    const payload = record?.payload || {}
    if (payload.account_snapshot_kind === 'asset' || payload.account_snapshot_kind === 'liability') return payload.account_snapshot_kind
    return payload.record_kind === 'liability_snapshot' ? 'liability' : 'asset'
  }

  function accountTypeFromWalletSnapshot(record) {
    const payload = record?.payload || {}
    const normalized = normalizeAccountType(payload.account_type)
    if (normalized !== 'other') return normalized
    return walletSnapshotKindOf(record) === 'liability' ? 'credit_line' : 'wallet_balance'
  }

  function amountFromWalletSnapshot(record) {
    const payload = record?.payload || {}
    const value = payload.snapshot_balance ?? payload.amount
    const amount = Number(value)
    return Number.isFinite(amount) && amount >= 0 ? amount : 0
  }

  async function createAccountFromWalletSnapshot(record) {
    if (!record || record.domainKey !== 'wallet') {
      showFlash('只能从钱包快照创建账户')
      return
    }
    if (!currentUserId.value) {
      showFlash('请先登录后再创建账户')
      return
    }
    const payload = record.payload || {}
    if (payload.linked_account_id) {
      showFlash('这条快照已经关联账户')
      return
    }
    if (walletAccountCreatingSourceIds.has(record.id)) {
      showFlash('账户正在创建中，请勿重复点击')
      return
    }
    const localExisting = accounts.value.find(account => account.sourceRecordTable === 'data_records' && account.sourceRecordId === record.id)
    if (localExisting) {
      await linkWalletSnapshotToAccount(record, localExisting.id)
      return
    }
    const amount = amountFromWalletSnapshot(record)
    const now = new Date().toISOString()
    const snapshotAt = record.occurredAt || record.createdAt || now
    const body = {
      user_id: currentUserId.value,
      name: payload.account_name || record.title || '未命名账户',
      type: accountTypeFromWalletSnapshot(record),
      institution: payload.institution || payload.account_name || null,
      last4: payload.last4 && /^\d{4}$/.test(String(payload.last4)) ? String(payload.last4) : null,
      currency: 'CNY',
      initial_balance: amount,
      current_balance: amount,
      snapshot_balance: amount,
      snapshot_at: snapshotAt,
      source_record_table: 'data_records',
      source_record_id: record.id,
    }

    walletAccountCreatingSourceIds.add(record.id)
    try {
      const { data: existingRows, error: existingErr } = await sb.from('accounts')
        .select('*')
        .eq('source_record_table', 'data_records')
        .eq('source_record_id', record.id)
        .eq('user_id', currentUserId.value)
        .order('created_at', { ascending: true })
        .limit(1)
      if (existingErr) {
        showError('检查账户是否已存在失败：' + humanizeDbError(existingErr))
        return
      }
      if (existingRows?.length) {
        const existingAccount = mapAccountRow(existingRows[0])
        if (!accounts.value.some(account => account.id === existingAccount.id)) accounts.value.unshift(existingAccount)
        await linkWalletSnapshotToAccount(record, existingAccount.id)
        return
      }

      const { data: accountRow, error: accountErr } = await sb.from('accounts')
        .insert(body)
        .select('*')
        .single()
      if (accountErr) {
        showError('创建账户失败：' + humanizeDbError(accountErr))
        return
      }

      const linkedPayload = {
        ...payload,
        linked_account_id: accountRow.id,
        account_snapshot_kind: walletSnapshotKindOf(record),
        snapshot_balance: amount,
      }
      const { error: linkErr } = await sb.from('data_records')
        .update({
          linked_account_id: accountRow.id,
          account_snapshot_kind: walletSnapshotKindOf(record),
          snapshot_balance: amount,
          snapshot_at: snapshotAt,
          payload_jsonb: linkedPayload,
        })
        .eq('id', record.id)
      if (linkErr) {
        showError('账户已创建，但关联快照失败：' + humanizeDbError(linkErr))
        await loadData(0, true)
        return
      }

      accounts.value.unshift(mapAccountRow(accountRow))
      const idx = dataRecords.value.findIndex(item => item.id === record.id)
      if (idx >= 0) {
        dataRecords.value[idx] = {
          ...dataRecords.value[idx],
          payload: linkedPayload,
        }
      }
      showFlash('✓ 已从快照创建账户')
    } finally {
      walletAccountCreatingSourceIds.delete(record.id)
    }
  }

  async function linkWalletSnapshotToAccount(record, accountId) {
    if (!record || record.domainKey !== 'wallet' || !accountId) return
    const payload = record.payload || {}
    const amount = amountFromWalletSnapshot(record)
    const snapshotAt = record.occurredAt || record.createdAt || new Date().toISOString()

    const { error: accountErr } = await sb.from('accounts')
      .update({
        snapshot_balance: amount,
        snapshot_at: snapshotAt,
        source_record_table: 'data_records',
        source_record_id: record.id,
        updated_at: new Date().toISOString(),
      })
      .eq('id', accountId)
    if (accountErr) {
      showError('更新账户快照失败：' + humanizeDbError(accountErr))
      return
    }

    const linkedPayload = {
      ...payload,
      linked_account_id: accountId,
      account_snapshot_kind: walletSnapshotKindOf(record),
      snapshot_balance: amount,
    }
    const { error: recordErr } = await sb.from('data_records')
      .update({
        linked_account_id: accountId,
        account_snapshot_kind: walletSnapshotKindOf(record),
        snapshot_balance: amount,
        snapshot_at: snapshotAt,
        payload_jsonb: linkedPayload,
      })
      .eq('id', record.id)
    if (recordErr) {
      showError('账户快照已更新，但记录关联失败：' + humanizeDbError(recordErr))
      await loadData(0, true)
      return
    }

    await loadData(0, true)
    showFlash('✓ 已关联账户')
  }

  function mapIncomeRow(row) {
    return {
      id: row.id,
      cat: row.category,
      source: row.source_name,
      amount: Number(row.amount),
      date: formatDate(row.income_date),
      dateRaw: row.income_date,
      createdAt: row.created_at,
      time: '',
      icon: incomeCatMap[row.category]?.icon || '💰',
      note: row.note,
      image_url: row.image_url,
      image_path: row.image_url,
      sourceType: row.source || 'manual',
      companionMessage: row.companion_message || '',
      accountId: row.account_id || null,
      accountConfidence: row.account_confidence ?? null,
      accountInference: row.account_inference || null,
    }
  }

  async function loadUnboundRecords() {
    unboundRecordsLoading.value = true
    const padM = String(currentMonth.value).padStart(2, '0')
    const start = `${currentYear.value}-${padM}-01`
    const lastDay = new Date(currentYear.value, currentMonth.value, 0).getDate()
    const end = `${currentYear.value}-${padM}-${String(lastDay).padStart(2, '0')}`

    const [txResult, incResult] = await Promise.all([
      sb.from('transactions')
        .select('*')
        .eq('status', 'done')
        .is('account_id', null)
        .gte('transaction_date', start)
        .lte('transaction_date', end)
        .order('transaction_date', { ascending: false })
        .order('transaction_time', { ascending: false })
        .limit(100),
      sb.from('income_records')
        .select('*')
        .is('account_id', null)
        .gte('income_date', start)
        .lte('income_date', end)
        .order('income_date', { ascending: false })
        .limit(100),
    ])
    unboundRecordsLoading.value = false

    if (txResult.error || incResult.error) {
      console.warn('加载未绑定记录失败:', txResult.error?.message || incResult.error?.message)
      showFlash('未绑定记录加载失败')
      return
    }

    unboundRecords.value = {
      expenses: (txResult.data || []).map(mapTransaction),
      incomes: (incResult.data || []).map(mapIncomeRow),
    }
  }

  async function openUnboundRecordsPage(filter = 'all') {
    unboundRecordFilter.value = filter
    await loadUnboundRecords()
    navigateTo('unbound-records')
  }

  function normalizeDateOnly(value) {
    if (!value) return getLocalDateKey()
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value
    const d = new Date(value)
    if (Number.isNaN(d.getTime())) return getLocalDateKey()
    return localDateKeyOf(d)
  }

  function openDomainPage(domainId) {
    activeDomainId.value = domainId
    navigateTo('domain-detail')
  }

  function openDayDetail(dateKey, kind = 'all') {
    activeDateKey.value = dateKey
    activeDayKind.value = kind
    navigateTo('day-detail')
  }

  function showMoreDailyCards() {
    dailyCardVisibleCount.value = Math.min(dailyCardVisibleCount.value + 8, dailyCards.value.length)
  }

  async function openRecordDetail(kind, record) {
    if (!record) return
    let imageUrl = null
    const imagePath = record.image_path || record.image_url || null
      || (kind === 'universal' ? record.imagePath : null)
    if (imagePath) imageUrl = await getSignedImageUrl(imagePath)
    detailRecord.value = {
      id: record.id,
      kind,
      domainId: kind === 'universal' ? record.domainKey : kind,
      imagePath,
      imageUrl,
      imageLoadError: !!imagePath && !imageUrl,
      raw: { ...record },
    }
    navigateTo('record-detail')
  }

  function closeRecordDetail() {
    goBack()
  }

  function navigateTo(page) {
    if (currentPage.value === page) return
    saveCurrentPageScroll()
    const mainPages = ['home', 'pending', 'domains', 'report', 'settings']
    if (mainPages.includes(page)) {
      pageHistory.value = []
    } else {
      pageHistory.value.push(currentPage.value)
    }
    currentPage.value = page
    restorePageScroll(page)
  }

  function goBack() {
    saveCurrentPageScroll()
    const prev = pageHistory.value.pop()
    currentPage.value = prev || 'home'
    restorePageScroll(currentPage.value)
  }

  function saveCurrentPageScroll() {
    if (typeof window === 'undefined') return
    pageScrollPositions[currentPage.value] = window.scrollY || 0
  }

  function restorePageScroll(page) {
    if (typeof window === 'undefined') return
    const y = pageScrollPositions[page] || 0
    nextTick(() => {
      window.requestAnimationFrame(() => {
        window.scrollTo({ top: y, left: 0, behavior: 'auto' })
      })
    })
  }

  async function refreshDetailRecord() {
    if (!detailRecord.value) return
    if (detailRecord.value.kind === 'income') {
      const fresh = incomeRecords.value.find(item => item.id === detailRecord.value.id)
        || recentIncomeRecords.value.find(item => item.id === detailRecord.value.id)
      if (fresh) await openRecordDetail('income', fresh)
      return
    }
    if (detailRecord.value.kind === 'expense') {
      const fresh = bills.value.find(item => item.id === detailRecord.value.id)
      if (fresh) await openRecordDetail('expense', fresh)
      return
    }
    if (detailRecord.value.kind === 'universal') {
      const fresh = dataRecords.value.find(item => item.id === detailRecord.value.id)
      if (fresh) await openRecordDetail('universal', fresh)
    }
  }

  async function openDetailEditor() {
    if (!detailRecord.value?.raw) return
    if (detailRecord.value.kind === 'income') {
      await openIncomeEditModal(detailRecord.value.raw)
      return
    }
    if (detailRecord.value.kind === 'expense') {
      if (detailRecord.value.raw?.status === 'pending') {
        await openPendingModal(detailRecord.value.raw)
        return
      }
      await openExpenseEditModal(detailRecord.value.raw)
      return
    }
    if (detailRecord.value.kind === 'universal') {
      await openUniversalEditModal(detailRecord.value.raw)
    }
  }

  async function toggleSetting(key) {
    if (!(key in settingsState)) return
    if (!currentUserId.value) {
      showFlash('请先登录')
      return
    }
    if (isActionPending('settings')) return
    const field = USER_SETTING_FIELDS[key]
    if (!field) return
    const prev = settingsState[key]
    const next = !prev
    settingsState[key] = next
    try {
      await runLockedAction('settings', async () => {
        const { error } = await sb.from('user_configs').upsert({
          user_id: currentUserId.value,
          [field]: next,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id' })
        if (error) throw error
      })
      showFlash(next ? '✓ 已开启' : '✓ 已关闭')
    } catch (e) {
      settingsState[key] = prev
      showFlash('⚠️ 设置保存失败：' + humanizeDbError(e))
    }
  }

  async function confirmDelete() {
    const { type, id, imagePath } = deleteConfirm
    deleteConfirm.open = false
    try {
      if (type === 'bill') {
        if (pendingModal.open && pendingModal.bill?.id === id) closePendingModal()
        const { error } = await sb.rpc('delete_transaction_with_account', { p_id: id })
        if (error) throw new Error(error.message)
        await refreshAccountsFromDB()
        if (detailRecord.value?.id === id) goBack()
        // 本地移除，避免全量刷新
        const billIdx = bills.value.findIndex(b => b.id === id)
        if (billIdx >= 0) bills.value.splice(billIdx, 1)
        if (imagePath && !imagePath.startsWith('https://')) {
          const { data: refs, error: refErr } = await sb.from('transactions')
            .select('id')
            .eq('image_url', imagePath)
            .limit(1)
          if (refErr) {
            console.warn('检查截图引用失败:', refErr.message)
          } else if (!refs || refs.length === 0) {
            const { error: removeErr } = await sb.storage.from('receipt-images').remove([imagePath])
            if (removeErr) console.warn('删除截图文件失败:', removeErr.message)
          }
        }
        showFlash('✓ 已删除')
      } else if (type === 'income') {
        const { error } = await sb.rpc('delete_income_with_account', { p_id: id })
        if (error) throw new Error(error.message)
        await refreshAccountsFromDB()
        // 本地移除
        const incIdx = incomeRecords.value.findIndex(r => r.id === id)
        if (incIdx >= 0) incomeRecords.value.splice(incIdx, 1)
        const rIncIdx = recentIncomeRecords.value.findIndex(r => r.id === id)
        if (rIncIdx >= 0) recentIncomeRecords.value.splice(rIncIdx, 1)
        if (imagePath && !imagePath.startsWith('https://')) {
          const { data: txRefs, error: txRefErr } = await sb.from('transactions').select('id').eq('image_url', imagePath).limit(1)
          const { data: incRefs, error: incRefErr } = await sb.from('income_records').select('id').eq('image_url', imagePath).limit(1)
          if (txRefErr || incRefErr) {
            console.warn('检查收入截图引用失败:', txRefErr?.message || incRefErr?.message)
          } else if ((!txRefs || txRefs.length === 0) && (!incRefs || incRefs.length === 0)) {
            const { error: removeErr } = await sb.storage.from('receipt-images').remove([imagePath])
            if (removeErr) console.warn('删除收入截图文件失败:', removeErr.message)
          }
        }
        if (incomeModal.open && incomeModal.id === id) closeIncomeModal()
        if (detailRecord.value?.id === id) goBack()
        showFlash('✓ 已删除')
      } else if (type === 'universal') {
        const { error } = await sb.from('data_records').delete().eq('id', id)
        if (error) throw new Error(error.message)
        // 本地移除
        const drIdx = dataRecords.value.findIndex(r => r.id === id)
        if (drIdx >= 0) dataRecords.value.splice(drIdx, 1)
        if (universalModal.open && universalModal.id === id) closeUniversalModal()
        if (detailRecord.value?.id === id) goBack()
        showFlash('✓ 已删除')
      }
    } catch (e) {
      showFlash('❌ 删除失败：' + e.message)
    }
  }

  return {
    currentYear, currentMonth, currentPage, monthLabel,
    pageHistory, pageScrollPositions, currentUserId, currentUserEmail, isLoggedIn,
    loading, loadError,
    bills, incomeRecords, recentIncomeRecords, transportRecords, stagingRecords, processedStagingRecords, dataRecords, accounts,
    selectedAccount, selectedAccountEntries, accountEntriesLoading,
    unboundRecords, unboundRecordsLoading, unboundRecordFilter,
    doneBills, pendingBills, filteredBills,
    recentEntries,
    domains, pendingSummary, todaySummary, homeTimeline, timelineGroups, visibleTimelineGroups,
    dailyCards, visibleDailyCards, activeDateKey, activeDayKind, activeDayRecords, dailyCardVisibleCount,
    financeOverview,
    totalExpense, totalIncome, netBalance,
    todayExpense, currentMonthDayKey,
    platformChartData, payChartData,
    currentFilter, pendingFilter, timelineExpanded, pendingExpanded, processedExpanded,
    batchMode, selectedStagingIds, toggleBatchMode, toggleSelectStaging, selectAllStaging, clearSelection, batchDiscard, batchArchive,
    flashMsg, flashVisible,
    imgOverlay,
    detailRecord, activeDomainId,
    pendingModal,
    incomeModal,
    expenseModal,
    universalModal,
    incomeCatMap,
    dailySummary, dailySummaryLoading, dailySummaryError, loadDailySummary,
    aiInsight, aiInsightLoading, aiInsightError, aiInsightCached,
    generateAiInsight, loadLatestAiInsight,
    loadData, resetUserData, changeMonth, showFlash,
    openPendingModal, closePendingModal, confirmEntry,
    hasPendingChanges, resetPendingChanges,
    markPendingImageUnavailable,
    openIncomeModal, openIncomeEditModal, closeIncomeModal, confirmIncome,
    hasIncomeChanges, resetIncomeChanges, markIncomeImageUnavailable,
    openExpenseModal, openExpenseEditModal, closeExpenseModal, confirmExpense,
    hasExpenseChanges, resetExpenseChanges, markExpenseImageUnavailable,
    openUniversalModal, openUniversalEditModal, closeUniversalModal, confirmUniversalRecord,
    createAccountFromWalletSnapshot, linkWalletSnapshotToAccount,
    accountModal, openAccountModalForCreate, openAccountModalForEdit, closeAccountModal, saveAccount, archiveAccount,
    openAccountDetail, refreshAccountDetail, loadAccountEntries, openAccountEntrySource,
    openUnboundRecordsPage, loadUnboundRecords,
    upsertAccountEntry, voidAccountEntries, refreshAccountsFromDB, defaultAccountIdForKind,
    pendingAccountReview, balanceImpactPreview,
    recommendAccountForRecord, accountBindingExplanation, bindRecordToRecommendedAccount, bindRecordToAccount,
    hasUniversalChanges, resetUniversalChanges, markUniversalImageUnavailable, getUniversalDomainMeta,
    getDomainRegistryStatus,
    openImgFull, closeImgFull,
    deleteConfirm, openDeleteConfirm, closeDeleteConfirm, confirmDelete,
    discardStagingRecord, retryStagingRecord, archiveStagingRecord,
    openDomainPage, openDayDetail, showMoreDailyCards, openRecordDetail, closeRecordDetail, openDetailEditor, refreshDetailRecord,
    navigateTo, goBack,
    settingsState, toggleSetting, loadUserSettings,
    actionState, isActionPending,
    refreshIfStale,
  }
}
