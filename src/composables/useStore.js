import { ref, reactive, computed } from 'vue'
import { sb, SUPABASE_URL, SUPABASE_ANON_KEY } from '../lib/supabase'
import {
  formatDate, formatMonthLabel, mapTransaction,
  incomeCatMap, catCodeMap, payAliasMap,
  getLocalDateKey,
} from '../utils/helpers'

export function useStore() {
  const currentYear = ref(new Date().getFullYear())
  const currentMonth = ref(new Date().getMonth() + 1)
  const currentPage = ref('home')
  const pageHistory = ref([])

  const bills = ref([])
  const incomeRecords = ref([])
  const recentIncomeRecords = ref([])
  const transportRecords = ref([])
  const stagingRecords = ref([])
  const processedStagingRecords = ref([])
  const dataRecords = ref([])

  const currentFilter = ref('all')
  const pendingFilter = ref('all') // all | routing_failed | pending_review | ai_error | bill_pending
  const timelineExpanded = ref(false)
  const pendingExpanded = ref(false)
  const processedExpanded = ref(false)
  const loading = ref(false)
  const loadError = ref('')
  const flashMsg = ref('')
  const flashVisible = ref(false)
  let flashTimer = null

  const imgOverlay = reactive({ open: false, src: '' })
  const detailRecord = ref(null)
  const activeDomainId = ref(null)

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
    imageUrl: null,
    imagePath: null,
    imageLoadError: false,
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
    imagePath: null,
    imageUrl: null,
    imageLoadError: false,
  })

  const deleteConfirm = reactive({
    open: false,
    type: null,
    id: null,
    imagePath: null,
  })

  const settingsState = reactive({
    aiLogsEnabled: true,
    keepSourceImages: true,
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
    const expenseCount = bills.value.length
    const incomeCount = incomeRecords.value.length
    const universalCount = (key) => dataRecords.value.filter(item => item.domainKey === key).length
    return [
      {
        id: 'expense',
        name: '消费记账',
        shortName: '消费',
        icon: '💸',
        tone: 'expense',
        color: '#C2410C',
        meta: `本月 ${expenseCount} 条 · 系统内置`,
        recordCount: expenseCount,
        isSystem: true,
        description: '识别消费截图、账单详情和手动支出记录。',
      },
      {
        id: 'income',
        name: '收入记录',
        shortName: '收入',
        icon: '💰',
        tone: 'income',
        color: '#1565C0',
        meta: `本月 ${incomeCount} 条 · 系统内置`,
        recordCount: incomeCount,
        isSystem: true,
        description: '记录工资、转账收款、报销和其他收入来源。',
      },
      {
        id: 'sport',
        name: '运动记录',
        shortName: '运动',
        icon: '🏃',
        tone: 'sport',
        color: '#B45309',
        meta: `本月 ${universalCount('sport')} 条 · 系统内置`,
        recordCount: universalCount('sport'),
        isSystem: true,
        description: '后续承接华为健康、Keep 等运动截图。',
      },
      {
        id: 'sleep',
        name: '睡眠记录',
        shortName: '睡眠',
        icon: '🌙',
        tone: 'sleep',
        color: '#4338CA',
        meta: `本月 ${universalCount('sleep')} 条 · 系统内置`,
        recordCount: universalCount('sleep'),
        isSystem: true,
        description: '后续承接睡眠追踪截图和睡眠日志。',
      },
      {
        id: 'reading',
        name: '阅读记录',
        shortName: '阅读',
        icon: '📚',
        tone: 'reading',
        color: '#0369A1',
        meta: `本月 ${universalCount('reading')} 条 · 系统内置`,
        recordCount: universalCount('reading'),
        isSystem: true,
        description: '后续承接阅读时长、页数和书籍进度记录。',
      },
    ]
  })

  const todaySummary = computed(() => {
    const todayKey = getLocalDateKey()
    const todayBills = bills.value.filter(b => b.status === 'done' && b.dateRaw === todayKey)
    const expenseByPlatform = {}
    todayBills.forEach(b => {
      const p = b.platform && b.platform !== '?' ? b.platform : '其他'
      expenseByPlatform[p] = (expenseByPlatform[p] || 0) + 1
    })
    const todaySport = dataRecords.value.filter(r => r.domainKey === 'sport' && (r.occurredAt || '').slice(0, 10) === todayKey)
    const todaySleep = dataRecords.value.filter(r => r.domainKey === 'sleep' && (r.occurredAt || '').slice(0, 10) === todayKey)
    const todayIncome = incomeRecords.value.filter(r => r.dateRaw === todayKey)
    const todayStaging = stagingRecords.value.filter(r => (r.occurredAt || r.createdAt || '').slice(0, 10) === todayKey)

    return {
      expenseTotal: todayBills.reduce((s, b) => s + b.amount, 0),
      expenseCount: todayBills.length,
      expenseByPlatform,
      incomeTotal: todayIncome.reduce((s, r) => s + r.amount, 0),
      incomeCount: todayIncome.length,
      sportItems: todaySport.map(r => ({ title: r.title || '运动', summary: r.summary, payload: r.payload })),
      sleepItems: todaySleep.map(r => ({ title: r.title || '睡眠', summary: r.summary, payload: r.payload })),
      stagingCount: todayStaging.length,
      isEmpty: todayBills.length === 0 && todaySport.length === 0 && todaySleep.length === 0 && todayIncome.length === 0 && todayStaging.length === 0,
    }
  })

  const homeTimeline = computed(() => {
    const stagingItems = stagingRecords.value.slice(0, 8).map(item => ({
      id: `staging-${item.id}`,
      kind: 'staging',
      title: item.domainName || '待处理截图',
      subtitle: item.summary,
      amountLabel: item.recordType === 'income' ? '+ 待确认' : item.recordType === 'expense' ? '- 待确认' : '待分类',
      dateLabel: item.occurredAt || item.createdAt,
      dateRaw: (item.occurredAt || item.createdAt || '').slice(0, 10),
      occurredTime: item.occurredAt,
      uploadTime: item.createdAt,
      imageUrl: item.imageUrl,
      color: item.status === 'ai_error' ? '#B91C1C' : '#B45309',
      raw: item,
    }))

    const expenseItems = bills.value.slice(0, 15).map(item => ({
      id: `expense-${item.id}`,
      kind: 'expense',
      title: item.name,
      subtitle: `${item.platform || '?'} · ${item.cat || '?'}`,
      amountLabel: `-¥${item.amount.toFixed(2)}`,
      dateLabel: item.createdAt,
      dateRaw: item.dateRaw,
      occurredTime: `${item.dateRaw}${item.time ? ' ' + item.time : ''}`,
      uploadTime: item.createdAt,
      imageUrl: null,
      color: '#C2410C',
      raw: item,
    }))

    const incomeItems = incomeRecords.value.slice(0, 15).map(item => ({
      id: `income-${item.id}`,
      kind: 'income',
      title: item.source || incomeCatMap[item.cat]?.label || '收入',
      subtitle: incomeCatMap[item.cat]?.label || '收入记录',
      amountLabel: `+¥${item.amount.toFixed(2)}`,
      dateLabel: item.createdAt,
      dateRaw: item.dateRaw,
      occurredTime: item.dateRaw,
      uploadTime: item.createdAt,
      imageUrl: null,
      color: '#1565C0',
      raw: item,
    }))

    const universalItems = dataRecords.value.slice(0, 12).map(item => {
      const domain = domains.value.find(d => d.id === item.domainKey)
      return {
        id: `universal-${item.id}`,
        kind: 'universal',
        title: item.title || domain?.name || '通用记录',
        subtitle: item.summary || domain?.description || '通用数据域记录',
        amountLabel: domain?.shortName || '记录',
        dateLabel: item.occurredAt || item.createdAt,
        dateRaw: (item.occurredAt || item.createdAt || '').slice(0, 10),
        occurredTime: item.occurredAt,
        uploadTime: item.createdAt,
        imageUrl: null,
        color: domain?.color || '#2D6A4F',
        raw: item,
      }
    })

    return [...stagingItems, ...expenseItems, ...incomeItems, ...universalItems]
      .sort((a, b) => (b.dateLabel || '').localeCompare(a.dateLabel || ''))
      .slice(0, 25)
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
      const dateStr = raw.slice(0, 10)
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

  async function loadData() {
    loading.value = true
    loadError.value = ''
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
      }))

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
        dataRecords.value = (universalRows || []).map(r => ({
          id: r.id,
          domainId: r.domain_id,
          domainKey: r.domain_key,
          domainVersion: r.domain_version || '1.0',
          occurredAt: r.occurred_at,
          createdAt: r.created_at,
          title: r.title,
          summary: r.summary,
          payload: r.payload_jsonb || {},
          imagePath: r.source_image_path,
          imageHash: r.source_image_hash,
          stagingRecordId: r.staging_record_id,
          source: r.source || 'staging',
        }))
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
        failureReason: r.failure_reason,
        resolvedAction: r.resolved_action,
        discardReason: r.discard_reason,
        })
      }))
    } catch (e) {
      console.error('[loadData 异常]', e)
      loadError.value = `加载失败: ${e.message}`
    } finally {
      loading.value = false
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
    await loadData()
  }

  function showFlash(msg) {
    flashMsg.value = msg
    flashVisible.value = true
    if (flashTimer) clearTimeout(flashTimer)
    flashTimer = setTimeout(() => { flashVisible.value = false }, 2000)
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
    pendingModalInitial = {
      entryType: pendingModal.entryType,
      merchantName: pendingModal.merchantName,
      amount: pendingModal.amount,
      platform: pendingModal.platform,
      category: pendingModal.category,
      payment: pendingModal.payment,
      incomeCategory: pendingModal.incomeCategory,
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
  }

  async function confirmEntry() {
    const amt = parseFloat(pendingModal.amount)
    if (!amt || amt <= 0 || amt > 999999.99) { alert('请输入有效金额（0.01 ~ 999999.99）'); return }

    if (pendingModal.entryType === 'income') {
      if (!pendingModal.incomeCategory) { alert('请选择收入类型'); return }
      const source = pendingModal.merchantName.trim() || (incomeCatMap[pendingModal.incomeCategory]?.label || '收入')
      const { error: incErr } = await sb.from('income_records').insert({
        category: pendingModal.incomeCategory,
        source_name: source,
        amount: amt,
        income_date: pendingModal.bill.dateRaw || new Date().toISOString().slice(0, 10),
        image_url: pendingModal.bill.image_path || null,
        image_hash: pendingModal.bill.image_hash || null,
        source: 'ai_scan',
        note: pendingModal.bill.image_path ? '由截图待补充转入收入' : null,
      })
      if (incErr) { alert('保存失败：' + incErr.message); return }

      const imagePath = pendingModal.bill.image_path
      const { error: delErr } = await sb.from('transactions').delete().eq('id', pendingModal.bill.id)
      if (delErr) { alert('收入已保存，但原待补充记录删除失败：' + delErr.message); return }
      closePendingModal()
      showFlash('✓ 收入已记录')
      await loadData()
      return
    }

    if (!pendingModal.platform || !pendingModal.category || !pendingModal.payment) return
    const { error } = await sb.from('transactions').update({
      platform: pendingModal.platform,
      category: pendingModal.category,
      payment_method: pendingModal.payment,
      merchant_name: pendingModal.merchantName || `${pendingModal.platform}消费`,
      amount: amt,
      status: 'done',
    }).eq('id', pendingModal.bill.id)
    if (error) { alert('保存失败：' + error.message); return }
    closePendingModal()
    showFlash('✓ 已保存')
    await loadData()
  }

  function openIncomeModal() {
    incomeModal.open = true
    incomeModal.mode = 'create'
    incomeModal.id = null
    incomeModal.cat = 'salary'
    incomeModal.amount = ''
    incomeModal.source = ''
    incomeModal.note = ''
    incomeModal.date = new Date().toISOString().slice(0, 10)
    incomeModal.imageUrl = null
    incomeModal.imagePath = null
    incomeModal.imageLoadError = false
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
    incomeModal.date = record.dateRaw || new Date().toISOString().slice(0, 10)
    incomeModal.imagePath = record.image_path || record.image_url || null
    incomeModal.imageUrl = await getSignedImageUrl(incomeModal.imagePath)
    incomeModal.imageLoadError = !!incomeModal.imagePath && !incomeModal.imageUrl
    setIncomeModalInitial()
  }

  function closeIncomeModal() {
    incomeModal.open = false
    incomeModalInitial = null
  }

  async function confirmIncome() {
    const amt = parseFloat(incomeModal.amount)
    if (!amt || amt <= 0 || amt > 999999.99) { alert('请输入有效金额（0.01 ~ 999999.99）'); return }
    if (!incomeModal.cat) { alert('请选择收入类型'); return }
    if (!incomeModal.date) { alert('请选择到账日期'); return }
    const source = incomeModal.source.trim() || (incomeCatMap[incomeModal.cat]?.label || '收入')
    if (incomeModal.mode === 'edit' && incomeModal.id) {
      const { error } = await sb.from('income_records').update({
        category: incomeModal.cat,
        source_name: source,
        amount: amt,
        income_date: incomeModal.date,
        note: incomeModal.note.trim() || null,
      }).eq('id', incomeModal.id)
      if (error) { alert('保存失败：' + error.message); return }
      closeIncomeModal()
      showFlash('✓ 收入已更新')
      await loadData()
      if (detailRecord.value?.id === incomeModal.id) {
        const updated = incomeRecords.value.find(item => item.id === incomeModal.id)
          || recentIncomeRecords.value.find(item => item.id === incomeModal.id)
        if (updated) {
          await openRecordDetail('income', updated)
        }
      }
      return
    }
    const { error } = await sb.from('income_records').insert({
      category: incomeModal.cat,
      source_name: source,
      amount: amt,
      income_date: incomeModal.date,
      note: incomeModal.note.trim() || null,
      source: 'manual',
    })
    if (error) { alert('保存失败：' + error.message); return }
    closeIncomeModal()
    showFlash('✓ 收入已记录')
    await loadData()
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
      imagePath: expenseModal.imagePath,
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
      || current.imagePath !== expenseModalInitial.imagePath
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
    expenseModal.imagePath = expenseModalInitial.imagePath
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
    expenseModal.date = new Date().toISOString().slice(0, 10)
    expenseModal.imageUrl = null
    expenseModal.imagePath = null
    expenseModal.imageLoadError = false
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
    expenseModal.date = record.dateRaw || new Date().toISOString().slice(0, 10)
    expenseModal.imagePath = record.image_path || record.image_url || null
    expenseModal.imageUrl = await getSignedImageUrl(expenseModal.imagePath)
    expenseModal.imageLoadError = !!expenseModal.imagePath && !expenseModal.imageUrl
    setExpenseModalInitial()
  }

  function closeExpenseModal() {
    expenseModal.open = false
    expenseModalInitial = null
  }

  async function confirmExpense() {
    const amt = parseFloat(expenseModal.amount)
    if (!amt || amt <= 0 || amt > 999999.99) { alert('请输入有效金额（0.01 ~ 999999.99）'); return }
    if (!expenseModal.platform || !expenseModal.category || !expenseModal.payment) { alert('请选择消费渠道、分类和支付方式'); return }
    if (!expenseModal.date) { alert('请选择消费日期'); return }

    const merchantName = expenseModal.merchantName.trim() || `${expenseModal.platform}消费`
    const isLargeTransport = expenseModal.category === '出行' && amt >= 200
    const today = new Date().toISOString().slice(0, 10)
    const nowTime = new Date().toTimeString().slice(0, 8)

    if (expenseModal.mode === 'edit' && expenseModal.id) {
      const { error } = await sb.from('transactions').update({
        amount: amt,
        merchant_name: merchantName,
        platform: expenseModal.platform,
        category: expenseModal.category,
        payment_method: expenseModal.payment,
        transaction_date: expenseModal.date,
        transaction_time: expenseModal.date === today ? nowTime : null,
        note: expenseModal.note.trim() || null,
        is_large_transport: isLargeTransport,
        transport_type: isLargeTransport ? '交通' : null,
      }).eq('id', expenseModal.id)
      if (error) { alert('保存失败：' + error.message); return }
      closeExpenseModal()
      showFlash('✓ 支出已更新')
      await loadData()
      if (detailRecord.value?.id === expenseModal.id) {
        const updated = bills.value.find(item => item.id === expenseModal.id)
        if (updated) {
          await openRecordDetail('expense', updated)
        }
      }
      return
    }

    const { error } = await sb.from('transactions').insert({
      type: 'expense',
      amount: amt,
      merchant_name: merchantName,
      platform: expenseModal.platform,
      category: expenseModal.category,
      payment_method: expenseModal.payment,
      status: 'done',
      transaction_date: expenseModal.date,
      transaction_time: expenseModal.date === today ? nowTime : null,
      source: 'manual',
      note: expenseModal.note.trim() || null,
      is_large_transport: isLargeTransport,
      transport_type: isLargeTransport ? '交通' : null,
    })
    if (error) { alert('保存失败：' + error.message); return }
    closeExpenseModal()
    showFlash('✓ 支出已记录')
    await loadData()
  }

  function markExpenseImageUnavailable() {
    expenseModal.imageUrl = null
    expenseModal.imageLoadError = true
  }

  let universalModalInitial = null

  function getUniversalDomainMeta(domainKey = universalModal.domainKey) {
    const map = {
      sport: {
        title: '添加运动',
        editTitle: '编辑运动',
        primaryLabel: '运动时长（分钟）',
        primaryKey: 'duration_minutes',
        dimensionLabel: '运动类型',
        dimensionKey: 'sport_type',
        placeholder: '如：跑步、步行、力量训练',
        defaultTitle: '运动记录',
      },
      sleep: {
        title: '添加睡眠',
        editTitle: '编辑睡眠',
        primaryLabel: '睡眠时长（小时）',
        primaryKey: 'sleep_hours',
        dimensionLabel: '质量等级',
        dimensionKey: 'quality_level',
        placeholder: '如：良好、一般、深睡不足',
        defaultTitle: '睡眠记录',
      },
      reading: {
        title: '添加阅读',
        editTitle: '编辑阅读',
        primaryLabel: '阅读时长（分钟）',
        primaryKey: 'reading_minutes',
        dimensionLabel: '书名',
        dimensionKey: 'book_name',
        placeholder: '如：原则、微信读书',
        defaultTitle: '阅读记录',
      },
    }
    return map[domainKey] || map.sport
  }

  function snapshotUniversalModal() {
    return {
      mode: universalModal.mode,
      id: universalModal.id,
      domainKey: universalModal.domainKey,
      title: universalModal.title,
      primaryValue: universalModal.primaryValue,
      dimension: universalModal.dimension,
      note: universalModal.note,
      date: universalModal.date,
      imagePath: universalModal.imagePath,
    }
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
    universalModal.open = true
    universalModal.mode = 'create'
    universalModal.id = null
    universalModal.domainKey = domainKey
    universalModal.title = ''
    universalModal.primaryValue = ''
    universalModal.dimension = ''
    universalModal.note = ''
    universalModal.date = new Date().toISOString().slice(0, 10)
    universalModal.imagePath = null
    universalModal.imageUrl = null
    universalModal.imageLoadError = false
    if (meta.dimensionKey === 'quality_level') universalModal.dimension = '良好'
    setUniversalModalInitial()
  }

  async function openUniversalEditModal(record) {
    const meta = getUniversalDomainMeta(record.domainKey)
    const payload = record.payload || {}
    universalModal.open = true
    universalModal.mode = 'edit'
    universalModal.id = record.id
    universalModal.domainKey = record.domainKey
    universalModal.title = record.title || ''
    universalModal.primaryValue = payload[meta.primaryKey] ? String(payload[meta.primaryKey]) : ''
    universalModal.dimension = payload[meta.dimensionKey] || ''
    universalModal.note = record.summary || payload.note || ''
    universalModal.date = (record.occurredAt || record.createdAt || new Date().toISOString()).slice(0, 10)
    universalModal.imagePath = record.imagePath || null
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
    const primary = parseFloat(universalModal.primaryValue)
    if (!primary || primary <= 0 || primary > 99999) {
      alert('请输入有效数值')
      return
    }
    if (!universalModal.dimension.trim()) {
      alert(`请填写${meta.dimensionLabel}`)
      return
    }
    if (!universalModal.date) {
      alert('请选择日期')
      return
    }

    const { data: domainRows, error: domainErr } = await sb.from('data_domains')
      .select('id,key,version')
      .eq('key', universalModal.domainKey)
      .eq('status', 'active')
      .limit(1)
    if (domainErr || !domainRows?.length) {
      alert('数据域未就绪，请先执行 007 迁移')
      return
    }

    const domainRow = domainRows[0]
    const title = universalModal.title.trim() || universalModal.dimension.trim() || meta.defaultTitle
    const payload = {
      [meta.primaryKey]: primary,
      [meta.dimensionKey]: universalModal.dimension.trim(),
      note: universalModal.note.trim() || null,
      source_app: 'manual',
    }
    const body = {
      domain_id: domainRow.id,
      domain_key: universalModal.domainKey,
      domain_version: domainRow.version || '1.0',
      occurred_at: `${universalModal.date}T12:00:00+08:00`,
      title,
      summary: universalModal.note.trim() || `${meta.dimensionLabel}：${universalModal.dimension.trim()}`,
      payload_jsonb: payload,
      source: 'manual',
      source_image_path: universalModal.imagePath || null,
    }

    const wasEdit = universalModal.mode === 'edit' && universalModal.id
    const query = wasEdit
      ? sb.from('data_records').update(body).eq('id', universalModal.id)
      : sb.from('data_records').insert(body)
    const { error } = await query
    if (error) {
      alert('保存失败：' + error.message)
      return
    }
    closeUniversalModal()
    showFlash(wasEdit ? '✓ 记录已更新' : '✓ 记录已添加')
    await loadData()
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
    showFlash('✓ 已销毁')
    await loadData()
  }

  async function retryStagingRecord(record) {
    if (!record?.id) return
    showFlash('⏳ 正在重新识别...')
    try {
      const fnUrl = `${SUPABASE_URL}/functions/v1/ingest-receipt`
      const formData = new FormData()
      formData.append('staging_record_id', record.id)
      const resp = await fetch(fnUrl, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${SUPABASE_ANON_KEY}` },
        body: formData,
      })
      if (!resp.ok) {
        const errText = await resp.text()
        throw new Error(`${resp.status}: ${errText}`)
      }
      const result = await resp.json()
      if (result.status === 'done') {
        const domainLabel = { expense: '消费记账', income: '收入记录', sport: '运动记录', sleep: '睡眠记录', reading: '阅读记录' }
        showFlash(`✓ 重试成功 → 已归档到「${domainLabel[result.record_type] || result.record_type}」`)
      } else {
        showFlash('⚠ 重试未确定，请手动选择数据域归档（下方按钮）')
      }
      await loadData()
    } catch (e) {
      showFlash('❌ 重试失败：' + (e.message || '未知错误'))
    }
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
      const { data: inserted, error: insertErr } = await sb.from('transactions').insert({
        type: 'expense',
        amount: amount > 0 ? amount : 0.01,
        merchant_name: payload.merchant_name || payload.source_name || title || '待补充支出',
        platform: payload.platform || '微信',
        category: payload.category || null,
        payment_method: payload.payment_method || null,
        status: payload.category && payload.payment_method ? 'done' : 'pending',
        transaction_date: normalizeDateOnly(occurredAt),
        source: 'ai_scan',
        image_url: record.imagePath || null,
        image_hash: record.imageHash || null,
        note: summary,
      }).select('id').single()
      if (insertErr) {
        showFlash('❌ 转入支出失败：' + insertErr.message)
        return
      }
      await finishStagingArchive(record, inserted.id, null, 'expense', payload)
      showFlash('✓ 已转入支出，必要时可继续补充')
      await loadData()
      const bill = bills.value.find(item => item.id === inserted.id)
      if (bill) {
        if (bill.status === 'pending') await openPendingModal(bill)
        else await openExpenseEditModal(bill)
      }
      return
    }

    if (domainKey === 'income') {
      const amount = parseFloat(payload.amount || record.summary?.match(/金额\s*(\d+(\.\d+)?)/)?.[1] || '0')
      const { data: inserted, error: insertErr } = await sb.from('income_records').insert({
        category: payload.income_category || 'other',
        source_name: payload.source_name || title || '截图识别收入',
        amount: amount > 0 ? amount : 0.01,
        income_date: normalizeDateOnly(occurredAt),
        note: summary,
        image_url: record.imagePath || null,
        image_hash: record.imageHash || null,
        source: 'ai_scan',
      }).select('id').single()
      if (insertErr) {
        showFlash('❌ 转入收入失败：' + insertErr.message)
        return
      }
      await finishStagingArchive(record, inserted.id, null, 'income', payload)
      showFlash('✓ 已转入收入')
      await loadData()
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
    }).select('id').single()
    if (insertErr) {
      showFlash('❌ 归档失败：' + insertErr.message)
      return
    }

    const done = await finishStagingArchive(record, inserted.id, domainRow.id, domainKey, payload)
    if (!done) return

    showFlash(`✓ 已归档到${domain.name}`)
    await loadData()
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
    if (domainKey === 'sport') return payload.sport_type || payload.activity_type || '运动记录'
    if (domainKey === 'sleep') return payload.quality_level || '睡眠记录'
    if (domainKey === 'reading') return payload.book_name || payload.title || '阅读记录'
    return record.domainName || '通用记录'
  }

  function normalizeDateOnly(value) {
    if (!value) return new Date().toISOString().slice(0, 10)
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value
    const d = new Date(value)
    if (Number.isNaN(d.getTime())) return new Date().toISOString().slice(0, 10)
    return d.toISOString().slice(0, 10)
  }

  function openDomainPage(domainId) {
    activeDomainId.value = domainId
    navigateTo('domain-detail')
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
    const mainPages = ['home', 'pending', 'domains', 'report', 'settings']
    if (mainPages.includes(page)) {
      pageHistory.value = []
    } else {
      pageHistory.value.push(currentPage.value)
    }
    currentPage.value = page
  }

  function goBack() {
    const prev = pageHistory.value.pop()
    currentPage.value = prev || 'home'
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

  function toggleSetting(key) {
    if (!(key in settingsState)) return
    settingsState[key] = !settingsState[key]
    showFlash(settingsState[key] ? '✓ 已开启' : '✓ 已关闭')
  }

  async function confirmDelete() {
    const { type, id, imagePath } = deleteConfirm
    deleteConfirm.open = false
    try {
      if (type === 'bill') {
        if (pendingModal.open && pendingModal.bill?.id === id) closePendingModal()
        const { error } = await sb.from('transactions').delete().eq('id', id)
        if (error) throw new Error(error.message)
        if (detailRecord.value?.id === id) goBack()
        if (imagePath && !imagePath.startsWith('https://')) {
          const { data: refs, error: refErr } = await sb.from('transactions')
            .select('id')
            .eq('image_url', imagePath)
            .limit(1)
          if (refErr) {
            console.warn('检查截图引用失败:', refErr.message)
          } else if (!refs || refs.length === 0) {
            const { error: removeErr } = await sb.storage.from('receipt-images').remove([imagePath])
            if (removeErr) {
              console.warn('删除截图文件失败:', removeErr.message)
              showFlash('✓ 已删除（截图清理失败，可稍后重试）')
            } else {
              showFlash('✓ 已删除')
            }
          } else {
            showFlash('✓ 已删除')
          }
        } else {
          showFlash('✓ 已删除')
        }
      } else if (type === 'income') {
        const { error } = await sb.from('income_records').delete().eq('id', id)
        if (error) throw new Error(error.message)
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
        if (universalModal.open && universalModal.id === id) closeUniversalModal()
        if (detailRecord.value?.id === id) goBack()
        showFlash('✓ 已删除')
      }
      await loadData()
    } catch (e) {
      showFlash('❌ 删除失败：' + e.message)
    }
  }

  return {
    currentYear, currentMonth, currentPage, monthLabel,
    pageHistory,
    loading, loadError,
    bills, incomeRecords, recentIncomeRecords, transportRecords, stagingRecords, processedStagingRecords, dataRecords,
    doneBills, pendingBills, filteredBills,
    recentEntries,
    domains, pendingSummary, todaySummary, homeTimeline, timelineGroups, visibleTimelineGroups,
    totalExpense, totalIncome, netBalance,
    todayExpense, currentMonthDayKey,
    platformChartData, payChartData,
    currentFilter, pendingFilter, timelineExpanded, pendingExpanded, processedExpanded,
    flashMsg, flashVisible,
    imgOverlay,
    detailRecord, activeDomainId,
    pendingModal,
    incomeModal,
    expenseModal,
    universalModal,
    incomeCatMap,
    loadData, changeMonth, showFlash,
    openPendingModal, closePendingModal, confirmEntry,
    hasPendingChanges, resetPendingChanges,
    markPendingImageUnavailable,
    openIncomeModal, openIncomeEditModal, closeIncomeModal, confirmIncome,
    hasIncomeChanges, resetIncomeChanges, markIncomeImageUnavailable,
    openExpenseModal, openExpenseEditModal, closeExpenseModal, confirmExpense,
    hasExpenseChanges, resetExpenseChanges, markExpenseImageUnavailable,
    openUniversalModal, openUniversalEditModal, closeUniversalModal, confirmUniversalRecord,
    hasUniversalChanges, resetUniversalChanges, markUniversalImageUnavailable, getUniversalDomainMeta,
    openImgFull, closeImgFull,
    deleteConfirm, openDeleteConfirm, closeDeleteConfirm, confirmDelete,
    discardStagingRecord, retryStagingRecord, archiveStagingRecord,
    openDomainPage, openRecordDetail, closeRecordDetail, openDetailEditor, refreshDetailRecord,
    navigateTo, goBack,
    settingsState, toggleSetting,
  }
}
