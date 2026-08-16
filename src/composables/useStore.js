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
  formatMonthLabel, mapTransaction,
  incomeCatMap, payAliasMap,
  getLocalDateKey, localDateKeyOf,
} from '../utils/helpers'
import {
  isLiabilityAccount,
  mapAccountRow,
  normalizeAccountType,
  shouldAdoptSnapshotAsOpeningBalance,
} from '../adapters/domain/accountAdapter'
import { normalizeFinanceOptionValue } from '../domains/financeReviewOptions'
import {
  isPlannerDeliveryEnvelopeValid,
  plannerDeliveryIdentityMatches,
} from '../utils/expressionPresentation'
import { createExpressionRepository } from '../repositories/expressionRepository'
import { createExpressionPlanState } from '../features/expression/createExpressionPlanState'
import { createSettingsRepository } from '../repositories/settingsRepository'
import { createSettingsState } from '../features/settings/createSettingsState'
import { createDefaultSettingsState } from '../features/settings/settingsConfig'
import { createAuthRepository } from '../repositories/authRepository'
import { createSessionState } from '../features/auth/createSessionState'
import { createStagingRepository } from '../repositories/stagingRepository'
import { createRecordRepository, mapDataRecordRow, mapIncomeRow } from '../repositories/recordRepository'
import { createAccountRepository } from '../repositories/accountRepository'
import { createStagingRetryFeature } from '../features/staging/createStagingRetryFeature'
import { createStagingArchiveFeature } from '../features/staging/createStagingArchiveFeature'
import { createStagingDiscardFeature } from '../features/staging/createStagingDiscardFeature'
import { createFinanceSaveFeature } from '../features/finance/createFinanceSaveFeature'
import { createAccountBindingFeature } from '../features/finance/createAccountBindingFeature'
import { createRepaymentFeature } from '../features/accounts/createRepaymentFeature'
import { createScreenshotRepaymentFeature } from '../features/accounts/createScreenshotRepaymentFeature'
import { createWalletSnapshotFeature } from '../features/accounts/createWalletSnapshotFeature'
import { buildScreenshotRepaymentCandidate } from '../features/accounts/buildScreenshotRepaymentCandidate'
import { createAccountDetailFeature } from '../features/accounts/createAccountDetailFeature'
import { createAccountManagementFeature } from '../features/accounts/createAccountManagementFeature'
import {
  resolveFinanceOccurrence,
} from '../utils/financeOccurrence'

const PRIMARY_EXPENSE_CATEGORIES = new Set(['餐饮', '购物', '出行', '娱乐', '生活', '健康', '教育', '其他'])
const PENDING_QUEUE_QUERY_LIMIT = 1000

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
  const currentYear = ref(new Date().getFullYear())
  const currentMonth = ref(new Date().getMonth() + 1)
  const currentPage = ref('home')
  const pageHistory = ref([])
  const pageScrollPositions = reactive({})
  const currentUserId = ref(null)
  const currentUserEmail = ref('')
  const isLoggedIn = ref(false)

  const bills = ref([])
  const pendingBills = ref([])
  const incomeRecords = ref([])
  const recentIncomeRecords = ref([])
  const transportRecords = ref([])
  const stagingRecords = ref([])
  const processedStagingRecords = ref([])
  const dataRecords = ref([])
  const accounts = ref([])
  const financeVocabulary = ref([])
  const repaymentCycles = ref([])
  const selectedAccount = ref(null)
  const selectedAccountEntries = ref([])
  const selectedAccountPayments = ref([])
  const selectedAccountSourceSnapshot = ref(null)
  const accountEntriesLoading = ref(false)
  const accountListState = ref({ status: 'idle', error: null })
  const accountDetailState = ref({ status: 'idle', identity: null, sections: {}, error: null })
  const unboundRecords = ref({ expenses: [], incomes: [] })
  const unboundRecordsLoading = ref(false)
  const unboundRecordFilter = ref('all')
  let stagingRetryFeature = null
  let stagingArchiveFeature = null
  let stagingDiscardFeature = null
  let financeSaveFeature = null
  let accountBindingFeature = null
  let repaymentFeature = null
  let screenshotRepaymentFeature = null
  let walletSnapshotFeature = null
  let accountDetailFeature = null
  let accountManagementFeature = null
  let accountCommandSequence = 0

  const currentFilter = ref('all')
  const pendingFilter = ref('all') // all | routing_failed | pending_review | ai_error | bill_pending
  const timelineExpanded = ref(false)
  const pendingExpanded = ref(false)
  const processedExpanded = ref(false)
  const batchMode = ref(false)
  const selectedStagingIds = ref(new Set())
  const loading = ref(false)
  const loadError = ref('')
  // loadErrorDetail：承载友好错误结构（title / userAction / code / retryable），
  // 由 src/lib/supabase.js 的 FriendlyNetworkError 注入；
  // App.vue 的错误浮层会优先消费这个对象，回退到 loadError 字符串。
  const loadErrorDetail = ref(null)
  const flashMsg = ref('')
  const flashVisible = ref(false)
  let flashTimer = null
  const signedImageUrlCache = new Map()
  const signedImageUrlRequests = new Map()
  const signedImageUrlCacheLifetime = 50 * 60 * 1000

  const imgOverlay = reactive({ open: false, src: '' })
  const detailRecord = ref(null)
  const expressionPlanState = createExpressionPlanState({
    repository: createExpressionRepository({
      client: sb,
      baseUrl: SUPABASE_URL,
      anonKey: SUPABASE_ANON_KEY,
    }),
    cache: ref({}),
    isDeliveryValid: isPlannerDeliveryEnvelopeValid,
    deliveryIdentityMatches: plannerDeliveryIdentityMatches,
  })
  const {
    recordExpressionPlanCache,
    invalidateRecordExpressionPlan,
    loadRecordExpressionPlan,
    ackRecordExpressionPlan,
    submitExpressionFeedback,
  } = expressionPlanState
  const activeDomainId = ref(null)
  const activeDateKey = ref('')
  const activeDayKind = ref('all')
  const dailyCardVisibleCount = ref(8)

  const pendingModal = reactive({
    open: false,
    bill: null,
    returnToQueue: false,
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
    stagingSource: null,
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
    stagingSource: null,
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
    stagingSource: null,
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
    billDay: '',
    paymentDueDay: '',
    autoDebitAccountId: null,
    autoConfirmRepayment: false,
    isDefaultExpense: false,
    isDefaultIncome: false,
    isArchived: false,
    commandKey: null,
  })

  const settingsFeature = createSettingsState({
    repository: createSettingsRepository({ client: sb }),
    state: reactive(createDefaultSettingsState()),
  })
  const { settingsState } = settingsFeature
  const authRepository = createAuthRepository({ client: sb })
  const stagingRepository = createStagingRepository({
    client: sb,
    baseUrl: SUPABASE_URL,
    anonKey: SUPABASE_ANON_KEY,
  })
  const recordRepository = createRecordRepository({ client: sb })
  const accountRepository = createAccountRepository({ client: sb })
  accountManagementFeature = createAccountManagementFeature({
    repository: accountRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  screenshotRepaymentFeature = createScreenshotRepaymentFeature({
    repository: accountRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  walletSnapshotFeature = createWalletSnapshotFeature({
    repository: accountRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  financeSaveFeature = createFinanceSaveFeature({
    repository: recordRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  accountBindingFeature = createAccountBindingFeature({
    repository: recordRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  repaymentFeature = createRepaymentFeature({
    repository: accountRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  accountDetailFeature = createAccountDetailFeature({
    accountRepository,
    loadSourceSnapshot: account => loadAccountSourceSnapshot(account),
    getCurrentUserId: () => currentUserId.value,
    onStateChange: nextState => {
      accountDetailState.value = nextState
      accountEntriesLoading.value = nextState.sections?.entries?.status === 'loading'
    },
  })
  stagingRetryFeature = createStagingRetryFeature({
    repository: stagingRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  stagingArchiveFeature = createStagingArchiveFeature({
    repository: stagingRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  stagingDiscardFeature = createStagingDiscardFeature({
    repository: stagingRepository,
    getCurrentUserId: () => currentUserId.value,
  })
  const sessionFeature = createSessionState({
    getCurrentUserId: () => currentUserId.value,
    setIdentity(user) {
      currentUserId.value = user.id
      currentUserEmail.value = user.email || ''
      isLoggedIn.value = true
    },
    clearIdentity() {
      currentUserId.value = null
      currentUserEmail.value = ''
      isLoggedIn.value = false
    },
    resetUserData,
    navigateHome: () => navigateTo('home'),
    loadData,
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
    const expenseItems = bills.value.map(b => ({ ...b, entryKind: 'expense', sortDate: b.occurredAt || b.createdAt || `${b.dateRaw || ''} ${b.time || ''}` }))
    const incomeItems = recentIncomeRecords.value.map(r => ({ ...r, entryKind: 'income', sortDate: r.occurredAt || r.createdAt || `${r.dateRaw || ''} ${r.time || ''}` }))
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
      repaymentCycles: repaymentCycles.value,
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
    loadDataRunId += 1
    stagingRetryFeature?.reset()
    stagingArchiveFeature?.reset()
    stagingDiscardFeature?.reset()
    financeSaveFeature.reset()
    accountBindingFeature.reset()
    repaymentFeature.reset()
    screenshotRepaymentFeature.reset()
    walletSnapshotFeature.reset()
    accountDetailFeature.reset()
    accountManagementFeature.reset()
    bills.value = []
    pendingBills.value = []
    incomeRecords.value = []
    recentIncomeRecords.value = []
    transportRecords.value = []
    stagingRecords.value = []
    processedStagingRecords.value = []
    dataRecords.value = []
    accounts.value = []
    financeVocabulary.value = []
    financeVocabularyAvailable = true
    repaymentCycles.value = []
    selectedAccount.value = null
    selectedAccountEntries.value = []
    selectedAccountPayments.value = []
    selectedAccountSourceSnapshot.value = null
    accountEntriesLoading.value = false
    accountListState.value = { status: 'idle', error: null }
    accountDetailState.value = { status: 'idle', identity: null, sections: {}, error: null }
    unboundRecords.value = { expenses: [], incomes: [] }
    unboundRecordsLoading.value = false
    dailySummary.value = []
    dailySummaryLoading.value = false
    dailySummaryError.value = ''
    dailySummaryLoadedAt = 0
    aiInsight.value = null
    aiInsightLoading.value = false
    aiInsightError.value = ''
    aiInsightCached.value = false
    signedImageUrlCache.clear()
    signedImageUrlRequests.clear()
    loadError.value = ''
    loadErrorDetail.value = null
    loading.value = false
    lastRefreshTs = 0
    selectedStagingIds.value = new Set()
    batchMode.value = false
    detailRecord.value = null
    imgOverlay.open = false
    imgOverlay.src = ''
    expressionPlanState.reset()
    activeDomainId.value = null
    activeDateKey.value = ''
    activeDayKind.value = 'all'
    dailyCardVisibleCount.value = 8
    pageHistory.value = []
    Object.keys(pageScrollPositions).forEach(key => delete pageScrollPositions[key])
    pendingModal.open = false
    incomeModal.open = false
    expenseModal.open = false
    universalModal.open = false
    accountModal.open = false
    deleteConfirm.open = false
    settingsFeature.reset()
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
      if (key.startsWith('pendingEntry:')) delete actionState[key]
      else actionState[key] = false
    }
  }

  async function loadUserSettings(options) {
    const result = await settingsFeature.load(currentUserId.value, options)
    if (!result.ok && !result.stale) {
      console.warn('加载用户设置失败:', result.error?.message || result.error)
    }
    return result
  }

  async function initializeAuth() {
    const unsubscribe = authRepository.subscribe((event, nextSession) => {
      void sessionFeature.handleAuthEvent(event, nextSession).catch(error => {
        console.error('认证会话处理失败:', error)
        showFlash('⚠️ 登录状态更新失败，请重试')
      })
    })
    try {
      const session = await authRepository.getSession()
      await sessionFeature.applySession(session)
      return unsubscribe
    } catch (error) {
      unsubscribe()
      throw error
    }
  }

  function signIn(email, password) {
    return authRepository.signIn({ email, password })
  }

  function signUp(email, password, consent) {
    return authRepository.signUp({ email, password, ...consent })
  }

  function signOut() {
    return authRepository.signOut()
  }

  let financeVocabularyAvailable = true

  function isMissingFinanceVocabularyError(error) {
    const message = String(error?.message || '')
    return error?.code === 'PGRST205'
      || error?.code === 'PGRST202'
      || error?.code === '42P01'
      || /user_finance_vocabulary|record_user_finance_vocabulary/i.test(message)
  }

  function mapFinanceVocabularyRow(row) {
    return {
      id: row.id,
      kind: row.kind,
      displayName: row.display_name,
      normalizedName: row.normalized_name,
      primaryCategory: row.primary_category || null,
      linkedAccountId: row.linked_account_id || null,
      source: row.source,
      status: row.status,
      usageCount: Number(row.usage_count || 0),
      lastUsedAt: row.last_used_at,
    }
  }

  async function loadFinanceVocabulary() {
    if (!currentUserId.value || !financeVocabularyAvailable) {
      financeVocabulary.value = []
      return
    }
    const expectedUserId = currentUserId.value
    const { data, error } = await sb.from('user_finance_vocabulary')
      .select('id,kind,display_name,normalized_name,primary_category,linked_account_id,source,status,usage_count,last_used_at')
      .eq('status', 'active')
      .order('usage_count', { ascending: false })
      .order('last_used_at', { ascending: false })
      .limit(200)
    if (error) {
      if (isMissingFinanceVocabularyError(error)) financeVocabularyAvailable = false
      else console.warn('加载个人财务词表失败:', error.message)
      return
    }
    if (currentUserId.value !== expectedUserId) return
    financeVocabulary.value = (data || []).map(mapFinanceVocabularyRow)
  }

  async function recordFinanceVocabulary({ kind, value, primaryCategory = null, linkedAccountId = null }) {
    const expectedUserId = currentUserId.value
    if (!expectedUserId || !financeVocabularyAvailable) return null
    const displayName = normalizeFinanceOptionValue(kind, value)
    if (!displayName) return null
    const { data, error } = await sb.rpc('record_user_finance_vocabulary', {
      p_kind: kind,
      p_display_name: displayName,
      p_primary_category: primaryCategory,
      p_linked_account_id: linkedAccountId,
    })
    if (error) {
      if (isMissingFinanceVocabularyError(error)) financeVocabularyAvailable = false
      else console.warn('更新个人财务词表失败:', error.message)
      return null
    }
    if (currentUserId.value !== expectedUserId) return null
    if (!data) return null
    const mapped = mapFinanceVocabularyRow(data)
    const existingIndex = financeVocabulary.value.findIndex(item => item.id === mapped.id)
    if (existingIndex >= 0) financeVocabulary.value[existingIndex] = mapped
    else financeVocabulary.value.push(mapped)
    return mapped
  }

  function learnConfirmedExpenseVocabulary({ platform, category, payment, accountId }) {
    const normalizedCategory = normalizeFinanceOptionValue('category', category)
    const updates = [
      recordFinanceVocabulary({ kind: 'platform', value: platform }),
      recordFinanceVocabulary({ kind: 'payment', value: payment, linkedAccountId: accountId }),
    ]
    if (PRIMARY_EXPENSE_CATEGORIES.has(normalizedCategory)) {
      updates.push(recordFinanceVocabulary({
        kind: 'category',
        value: normalizedCategory,
        primaryCategory: normalizedCategory,
      }))
    }
    Promise.allSettled(updates).catch(error => console.warn('更新个人财务词表失败:', error?.message || error))
  }

  let lastRefreshTs = 0
  let loadDataRunId = 0
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
    } catch (e) {
      console.warn('[域协议] 加载异常，使用内置兜底 schema:', e?.message || e)
    }
  }

  async function loadData(attempt = 0, silent = false, runId = null) {
    if (attempt === 0 || !runId) runId = ++loadDataRunId
    const expectedUserId = currentUserId.value
    const isCurrentDataLoad = () => (
      runId === loadDataRunId && currentUserId.value === expectedUserId
    )
    if (attempt === 0 && !silent) loading.value = true
    if (attempt === 0 && !silent) {
      loadError.value = ''
      loadErrorDetail.value = null
    }
    if (attempt === 0) lastRefreshTs = Date.now()
    if (attempt === 0) {
      loadUserSettings().catch(e => console.warn('加载用户设置失败:', e?.message || e))
      loadFinanceVocabulary().catch(e => console.warn('加载个人财务词表失败:', e?.message || e))
    }
    // Phase 1：拉取域协议（每会话一次，失败不阻断主流程）
    if (attempt === 0) loadDomainSchemas()
    try {
      const padM = String(currentMonth.value).padStart(2, '0')
      const start = `${currentYear.value}-${padM}-01`
      const lastDay = new Date(currentYear.value, currentMonth.value, 0).getDate()
      const end = `${currentYear.value}-${padM}-${String(lastDay).padStart(2, '0')}`

      const [
        txResult,
        pendingTxResult,
        incResult,
        recentIncResult,
        universalResult,
        accountResult,
        stagingResult,
      ] = await Promise.all([
        recordRepository.listExpenses({ start, end }),
        recordRepository.listPendingExpenses({ limit: PENDING_QUEUE_QUERY_LIMIT }),
        recordRepository.listIncomes({ start, end }),
        recordRepository.listRecentIncomes({ limit: 10 }),
        recordRepository.listUniversalRecords({ start, end, limit: 120 }),
        accountRepository.listAccounts(),
        stagingRepository.listOpen({ limit: PENDING_QUEUE_QUERY_LIMIT }),
      ])

      if (!isCurrentDataLoad()) return { ok: false, stale: true }

      if (txResult.status !== 'accepted') throw new Error('账单查询失败: ' + txResult.error)
      if (pendingTxResult.status !== 'accepted') throw new Error('待补全账单查询失败: ' + pendingTxResult.error)
      bills.value = txResult.rows
      pendingBills.value = pendingTxResult.rows
      transportRecords.value = bills.value
        .filter(b => b.cat === 'transport' && b.amount >= 200)
        .map(b => ({ id: b.id, type: b.transport_type || '交通', desc: b.name, amount: b.amount, date: b.date }))

      if (incResult.status !== 'accepted') console.warn('加载收入失败:', incResult.error)
      incomeRecords.value = incResult.status === 'accepted' ? incResult.rows : []

      unboundRecords.value = {
        expenses: bills.value.filter(b => b.status === 'done' && !b.accountId),
        incomes: incomeRecords.value.filter(r => !r.accountId),
      }

      if (recentIncResult.status !== 'accepted') console.warn('加载最近收入失败:', recentIncResult.error)
      recentIncomeRecords.value = recentIncResult.status === 'accepted' ? recentIncResult.rows : []

      if (universalResult.status !== 'accepted') {
        console.warn('加载通用记录失败:', universalResult.error)
        dataRecords.value = []
      } else {
        dataRecords.value = universalResult.rows
      }

      if (accountResult.status !== 'accepted') {
        console.warn('加载账户失败:', accountResult.error)
        accountListState.value = { status: 'failed', error: accountResult.error || '账户列表读取失败' }
      } else {
        accounts.value = accountResult.rows
        accountListState.value = { status: 'accepted', error: null }
      }

      const stagingErr = stagingResult?.status === 'accepted' ? null : stagingResult
      if (stagingErr) console.warn('加载中转站失败:', stagingErr.error || '请求未完成')

      const stagingRows = stagingErr ? [] : (stagingResult.rows || [])

      stagingRecords.value = stagingRows.map(record => ({
        ...record,
        repaymentCandidate: null,
      }))

      if (!silent) {
        repaymentCycles.value = []
        processedStagingRecords.value = []
      }

      const cycleMonth = `${currentYear.value}-${String(currentMonth.value).padStart(2, '0')}`
      const hydratePendingBillImages = async () => {
        const pendingPaths = pendingBills.value
          .map(bill => bill.image_path || bill.image_url)
          .filter(Boolean)
        const imageUrlMap = await getSignedImageUrlMap(pendingPaths)
        if (!isCurrentDataLoad()) return
        const hydratePendingBill = bill => {
          const imagePath = bill.image_path || bill.image_url || null
          const imageUrl = imagePath ? imageUrlMap[imagePath] || null : null
          return {
            ...bill,
            imageUrl,
            imageLoadError: Boolean(imagePath && !imageUrl),
          }
        }
        pendingBills.value = pendingBills.value.map(hydratePendingBill)
        const pendingIds = new Set(pendingBills.value.map(bill => bill.id))
        bills.value = bills.value.map(bill => (
          pendingIds.has(bill.id) ? hydratePendingBill(bill) : bill
        ))
      }
      const hydrateStagingImages = async () => {
        const imageUrlMap = await getSignedImageUrlMap(stagingRows.map(r => r.imagePath))
        if (!isCurrentDataLoad()) return
        stagingRecords.value = stagingRecords.value.map(record => {
          const imageUrl = imageUrlMap[record.imagePath] || null
          return {
            ...record,
            imageUrl,
            imageLoadError: !!record.imagePath && !imageUrl,
          }
        })
      }
      const loadRepaymentCycles = async () => {
        const ensureResult = await accountRepository.ensureRepaymentCycles({ cycleMonth })
        if (ensureResult.status !== 'accepted') console.warn('生成还款周期失败:', ensureResult.error)
        const cycleResult = await accountRepository.listRepaymentCycles({ limit: 80 })
        if (!isCurrentDataLoad()) return
        if (cycleResult.status !== 'accepted') {
          console.warn('加载还款周期失败:', cycleResult.error)
        } else {
          repaymentCycles.value = cycleResult.rows
          stagingRecords.value = stagingRecords.value.map(record => ({
            ...record,
            repaymentCandidate: buildRepaymentCandidateForStaging(record),
          }))
        }
      }
      const loadProcessedStaging = async () => {
        const processedResult = await stagingRepository.listProcessed({ limit: 30 })
        if (processedResult.status !== 'accepted') {
          console.warn('加载已处理记录失败:', processedResult.error || '请求未完成')
          return
        }
        const processedRows = processedResult.rows || []
        const processedImageUrlMap = await getSignedImageUrlMap(processedRows.map(r => r.imagePath))
        if (!isCurrentDataLoad()) return
        processedStagingRecords.value = processedRows.map(r => {
          const imageUrl = processedImageUrlMap[r.imagePath] || null
          return ({
            ...r,
            imageUrl,
            imageLoadError: !!r.imagePath && !imageUrl,
          })
        })
      }

      const supplementalLoad = Promise.allSettled([
        hydratePendingBillImages(),
        hydrateStagingImages(),
        loadRepaymentCycles(),
        loadProcessedStaging(),
      ]).then(results => {
        results.forEach(result => {
          if (result.status === 'rejected') console.warn('后台加载附加数据失败:', result.reason?.message || result.reason)
        })
      })
      if (silent) await supplementalLoad
      return { ok: true }
    } catch (e) {
      if (!isCurrentDataLoad()) return { ok: false, stale: true, error: e }
      console.error('[loadData 异常]', e)
      // 优先使用 supabase.js 抛出的 FriendlyNetworkError 上的结构化信息：
      //   - friendly: { title, message, userAction[], code, retryable }
      // 没有 friendly 时回退到旧的"消息字符串关键字匹配"逻辑。
      // 注意：supabase-js 内部会吞掉 FriendlyNetworkError 实例，把它包装成普通 Object，
      // 所以我们从 window.__lastSupabaseNetworkError 读取最近一次网络错误的 friendly 结构。
      let friendly = e && e.friendly ? e.friendly : null
      if (!friendly && typeof window !== 'undefined' && window.__lastSupabaseNetworkError) {
        // 检查时间戳：只使用 5 秒内的错误，避免读到旧的全局残留
        const age = Date.now() - (window.__lastSupabaseNetworkError.__timestamp || 0)
        if (age < 5000) {
          friendly = window.__lastSupabaseNetworkError
        }
      }
      const isNetworkError = friendly
        ? friendly.retryable
        : /load failed|fetch|network|failed to fetch/i.test(e.message || '')
      const maxAttempts = isNetworkError ? 4 : 2
      if (attempt < maxAttempts) {
        // 网络层错误使用指数退避重试（1s → 2s → 4s → 8s）
        const delay = isNetworkError ? Math.min(1000 * 2 ** attempt, 8000) : 1000
        await new Promise(r => setTimeout(r, delay))
        return loadData(attempt + 1, silent, runId)
      }
      if (silent) return { ok: false, error: e, silent: true }
      if (friendly) {
        // 有友好结构：同时填充 detail（供 UI 渲染指导步骤）和 string（向后兼容）
        loadErrorDetail.value = friendly
        loadError.value = friendly.title || `加载失败: ${friendly.message}`
      } else {
        const tip = isNetworkError
          ? `网络连接不稳定，请检查网络或稍后重试`
          : e.message
        loadErrorDetail.value = null
        loadError.value = `加载失败: ${tip}`
      }
      return { ok: false, error: e }
    } finally {
      if (attempt === 0 && !silent && isCurrentDataLoad()) loading.value = false
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
    const cached = signedImageUrlCache.get(raw)
    if (cached?.expiresAt > Date.now()) return cached.url
    if (cached) signedImageUrlCache.delete(raw)

    const inFlight = signedImageUrlRequests.get(raw)
    if (inFlight) return inFlight

    const request = (async () => {
      const { data, error } = await sb.storage.from('receipt-images').createSignedUrl(raw, 3600)
      if (error) {
        console.warn('生成截图预览链接失败:', error.message, raw)
        return null
      }
      const url = data?.signedUrl || null
      if (url) {
        signedImageUrlCache.set(raw, {
          url,
          expiresAt: Date.now() + signedImageUrlCacheLifetime,
        })
      }
      return url
    })()
    signedImageUrlRequests.set(raw, request)
    try {
      return await request
    } finally {
      signedImageUrlRequests.delete(raw)
    }
  }

  async function getSignedImageUrlMap(rawPaths = []) {
    const out = {}
    const storagePaths = []
    rawPaths.filter(Boolean).forEach(raw => {
      if (raw.startsWith('https://')) out[raw] = raw
      else {
        const cached = signedImageUrlCache.get(raw)
        if (cached?.expiresAt > Date.now()) out[raw] = cached.url
        else {
          if (cached) signedImageUrlCache.delete(raw)
          storagePaths.push(raw)
        }
      }
    })
    const uniquePaths = Array.from(new Set(storagePaths))
    if (!uniquePaths.length) return out

    const { data, error } = await sb.storage.from('receipt-images').createSignedUrls(uniquePaths, 3600)
    if (error) {
      console.warn('批量生成截图预览链接失败:', error.message)
      return out
    }
    ;(data || []).forEach((item, index) => {
      const path = item.path || uniquePaths[index]
      if (path && item.signedUrl) {
        out[path] = item.signedUrl
        signedImageUrlCache.set(path, {
          url: item.signedUrl,
          expiresAt: Date.now() + signedImageUrlCacheLifetime,
        })
      }
    })
    return out
  }

  let pendingModalInitial = null

  async function openPendingModal(bill, { returnToQueue = false } = {}) {
    const rawImagePath = bill.image_path || bill.image_url || null
    const existingImageUrl = bill.imageUrl || (rawImagePath?.startsWith('https://') ? rawImagePath : null)
    pendingModal.bill = {
      ...bill,
      image_path: rawImagePath,
      image_url: existingImageUrl,
      imageUrl: existingImageUrl,
      imageLoadError: false,
      imageLoading: !!rawImagePath && !existingImageUrl,
    }
    pendingModal.returnToQueue = Boolean(returnToQueue)
    pendingModal.entryType = bill.type === 'income' ? 'income' : 'expense'
    pendingModal.merchantName = bill.name !== '未识别商家' ? bill.name : ''
    pendingModal.amount = String(bill.amount)
    pendingModal.platform = bill.platform !== '?' ? bill.platform : null
    pendingModal.category = normalizeFinanceOptionValue('category', bill.cat) || null
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
    pendingModal.open = true

    if (!rawImagePath) return
    const billId = bill.id
    const resolvedUrl = await getSignedImageUrl(rawImagePath)
    if (!pendingModal.open || pendingModal.bill?.id !== billId) return
    const nextImageUrl = resolvedUrl || pendingModal.bill.image_url || null
    pendingModal.bill = {
      ...pendingModal.bill,
      image_url: nextImageUrl,
      imageUrl: nextImageUrl,
      imageLoadError: !nextImageUrl,
      imageLoading: false,
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
    pendingModal.bill.imageUrl = null
    pendingModal.bill.imageLoadError = true
    pendingModal.bill.imageLoading = false
  }

  function buildRepaymentCandidateForStaging(record) {
    return buildScreenshotRepaymentCandidate(record, accounts.value, repaymentCycles.value)
  }

  function formatYuan(value) {
    const amount = Number(value || 0)
    return `¥${amount.toFixed(2)}`
  }

  function closePendingModal() {
    pendingModal.open = false
    pendingModal.bill = null
    pendingModal.returnToQueue = false
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
      stagingSourceId: incomeModal.stagingSource?.id || null,
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

  let pendingAccountRefreshPromise = null
  let pendingAccountRefreshRequested = false

  function queuePendingAccountRefresh() {
    pendingAccountRefreshRequested = true
    if (pendingAccountRefreshPromise) return

    pendingAccountRefreshPromise = (async () => {
      while (pendingAccountRefreshRequested) {
        pendingAccountRefreshRequested = false
        await refreshAccountsFromDB()
      }
    })().catch(error => {
      console.warn('后台刷新账户失败:', error?.message || error)
    }).finally(() => {
      pendingAccountRefreshPromise = null
      if (pendingAccountRefreshRequested) queuePendingAccountRefresh()
    })
  }

  function syncLocalUnboundRecords() {
    unboundRecords.value = {
      expenses: bills.value.filter(bill => bill.status === 'done' && !bill.accountId),
      incomes: incomeRecords.value.filter(record => !record.accountId),
    }
  }

  function isInSelectedMonth(value) {
    const dateKey = localDateKeyOf(value)
    const selectedMonth = `${currentYear.value}-${String(currentMonth.value).padStart(2, '0')}`
    return dateKey.slice(0, 7) === selectedMonth
  }

  function pendingEntryActionKey(pendingId) {
    return pendingId ? `pendingEntry:${pendingId}` : ''
  }

  function isPendingEntrySaving(pendingId) {
    const actionKey = pendingEntryActionKey(pendingId)
    return !!actionKey && isActionPending(actionKey)
  }

  function setPendingEntryBackgroundSaving(pendingId, saving) {
    const updateCollection = collection => {
      const index = collection.value.findIndex(item => item.id === pendingId)
      if (index < 0) return
      const current = collection.value[index]
      if (!saving && current.status !== 'saving') return
      collection.value[index] = {
        ...current,
        status: saving ? 'saving' : 'pending',
        backgroundSaving: saving,
      }
    }
    updateCollection(pendingBills)
    updateCollection(bills)
    if (pendingModal.bill?.id === pendingId) {
      pendingModal.bill = {
        ...pendingModal.bill,
        status: saving ? 'saving' : 'pending',
        backgroundSaving: saving,
      }
    }
  }

  async function confirmEntry() {
    const bill = pendingModal.bill
    const pendingId = bill?.id
    const actionKey = pendingEntryActionKey(pendingId)
    if (!actionKey) return { ok: false }

    try {
      return await runLockedAction(actionKey, async () => {
      const entryType = pendingModal.entryType
      const amount = parseFloat(pendingModal.amount)
      const merchantName = String(pendingModal.merchantName || '').trim()
      const platform = pendingModal.platform
      const category = pendingModal.category
      const payment = pendingModal.payment
      const incomeCategory = pendingModal.incomeCategory
      const accountId = pendingModal.accountId
      const accountUnbound = pendingModal.accountUnbound

      if (!amount || amount <= 0 || amount > 999999.99) {
        showWarn('请输入有效金额（0.01 ~ 999999.99）')
        return { ok: false }
      }

      if (entryType === 'income') {
        if (!incomeCategory) {
          showWarn('请选择收入类型')
          return { ok: false }
        }
        setPendingEntryBackgroundSaving(pendingId, true)
        const source = merchantName || (incomeCatMap[incomeCategory]?.label || '收入')
        const incomeAccountId = accountUnbound ? null : (accountId || defaultAccountIdForKind('income'))
        const { data, error } = await sb.rpc('confirm_pending_transaction_with_account', {
          p_pending_id: pendingId,
          p_entry_type: 'income',
          p_amount: amount,
          p_merchant_or_source_name: source,
          p_platform: null,
          p_category: null,
          p_payment_method: null,
          p_income_category: incomeCategory,
          p_account_id: incomeAccountId,
        })
        if (error) {
          setPendingEntryBackgroundSaving(pendingId, false)
          showError('上一条保存失败，已放回待补充：' + humanizeDbError(error))
          return { ok: false }
        }
        invalidateRecordExpressionPlan(pendingId)
        const confirmedIncomeId = data?.income_record?.id
        if (confirmedIncomeId && confirmedIncomeId !== pendingId) {
          invalidateRecordExpressionPlan(confirmedIncomeId)
        }

        pendingBills.value = pendingBills.value.filter(item => item.id !== pendingId)
        bills.value = bills.value.filter(item => item.id !== pendingId)

        if (data?.income_record) {
          const mappedIncome = mapIncomeRow(data.income_record)
          const currentMonthRows = incomeRecords.value.filter(item => item.id !== mappedIncome.id)
          incomeRecords.value = isInSelectedMonth(mappedIncome.dateRaw)
            ? [mappedIncome, ...currentMonthRows]
            : currentMonthRows
          recentIncomeRecords.value = [
            mappedIncome,
            ...recentIncomeRecords.value.filter(item => item.id !== mappedIncome.id),
          ].slice(0, 10)
        }

        syncLocalUnboundRecords()
        queuePendingAccountRefresh()
        showFlash('✓ 收入已收下')
        return { ok: true, recordType: 'income', pendingId }
      }

      if (!platform || !category || !payment) return { ok: false }
      setPendingEntryBackgroundSaving(pendingId, true)
      const expenseAccountId = accountUnbound
        ? null
        : (accountId || autoAccountIdForPayment(payment, 'expense') || null)
      const { data, error } = await sb.rpc('confirm_pending_transaction_with_account', {
        p_pending_id: pendingId,
        p_entry_type: 'expense',
        p_amount: amount,
        p_merchant_or_source_name: merchantName || `${platform}消费`,
        p_platform: platform,
        p_category: category,
        p_payment_method: payment,
        p_income_category: null,
        p_account_id: expenseAccountId,
      })
      if (error) {
        setPendingEntryBackgroundSaving(pendingId, false)
        showError('上一条保存失败，已放回待补充：' + humanizeDbError(error))
        return { ok: false }
      }
      invalidateRecordExpressionPlan(pendingId)
      const confirmedExpenseId = data?.transaction?.id
      if (confirmedExpenseId && confirmedExpenseId !== pendingId) {
        invalidateRecordExpressionPlan(confirmedExpenseId)
      }

      const pendingBill = pendingBills.value.find(item => item.id === pendingId) || bill
      const billIndex = bills.value.findIndex(item => item.id === pendingId)
      const currentBill = billIndex >= 0 ? bills.value[billIndex] : pendingBill
      const confirmedBill = data?.transaction ? mapTransaction(data.transaction) : {
        ...currentBill,
        platform,
        cat: category,
        payment,
        name: merchantName || `${platform}消费`,
        amount,
        status: 'done',
        accountId: expenseAccountId,
      }
      const mergedBill = {
        ...currentBill,
        ...confirmedBill,
        imageUrl: currentBill.imageUrl || bill.image_url || null,
        imageLoadError: currentBill.imageLoadError || false,
      }
      pendingBills.value = pendingBills.value.filter(item => item.id !== pendingId)
      if (isInSelectedMonth(mergedBill.dateRaw)) {
        if (billIndex >= 0) bills.value[billIndex] = mergedBill
        else bills.value.unshift(mergedBill)
      } else if (billIndex >= 0) {
        bills.value.splice(billIndex, 1)
      }

      transportRecords.value = bills.value
        .filter(item => normalizeFinanceOptionValue('category', item.cat) === '出行' && item.amount >= 200)
        .map(item => ({ id: item.id, type: item.transport_type || '交通', desc: item.name, amount: item.amount, date: item.date }))
      syncLocalUnboundRecords()
      learnConfirmedExpenseVocabulary({
        platform,
        category,
        payment,
        accountId: expenseAccountId,
      })
      queuePendingAccountRefresh()
      showFlash('✓ 账单已收下')
      return { ok: true, recordType: 'expense', pendingId }
      })
    } catch (error) {
      setPendingEntryBackgroundSaving(pendingId, false)
      showError('上一条保存失败，已放回待补充：' + humanizeDbError(error))
      return { ok: false }
    }
  }

  async function confirmStagingRepayment(record) {
    const candidate = record?.repaymentCandidate || buildRepaymentCandidateForStaging(record)
    if (!record?.id || !candidate?.cycle) return false
    const ok = confirm(`确认把这张截图作为还款证据？\n账单：${candidate.account.name} ${candidate.cycle.cycleMonth}\n金额：¥${Number(candidate.amount || 0).toFixed(2)}`)
    if (!ok) return false
    const result = await screenshotRepaymentFeature.confirm({
      stagingId: record.id,
      cycleId: candidate.cycle.id,
      paidAmount: Number(candidate.amount || 0),
      debitAccountId: candidate.cycle.autoDebitAccountId || candidate.account.autoDebitAccountId || null,
      note: '根据还款截图确认',
    }, {
      onAccepted: ({ cycle }) => {
        convergeRepaymentCycle(cycle)
        const idx = stagingRecords.value.findIndex(item => item.id === record.id)
        if (idx >= 0) stagingRecords.value.splice(idx, 1)
        rememberProcessedStaging(record, {
          status: 'archived',
          domainKey: 'wallet',
          resolvedDomainKey: 'wallet',
          targetKind: 'repayment_cycle',
          targetRecordId: cycle.id,
          targetReference: `repayment_cycle/${cycle.id}`,
          resolvedAction: 'liability_repayment_confirmed',
          resolvedAt: new Date().toISOString(),
        })
      },
      refresh: async () => {
        const refresh = await loadData(0, true)
        if (!refresh?.ok) throw new Error('账户与中转列表刷新失败')
      },
    })
    if (result.status === 'accepted') {
      showFlash(result.refreshStatus === 'failed'
        ? '✓ 已根据截图确认还款；列表刷新失败，请稍后刷新'
        : '✓ 已根据截图确认还款')
    } else if (result.status === 'rejected' && result.reason === 'screenshot_repayment_conflict') {
      showFlash('还款截图正在以另一种方式处理，请稍后重试')
    } else if (result.status === 'failed') {
      showFlash('还款截图确认失败：' + humanizeDbError(result.error))
    }
    return result
  }

  function stagingArchivePayload(record) {
    const extracted = record?.extracted && typeof record.extracted === 'object' ? record.extracted : {}
    const nested = extracted.payload_jsonb && typeof extracted.payload_jsonb === 'object'
      ? extracted.payload_jsonb
      : {}
    const { payload_jsonb: _nestedPayload, ...direct } = extracted
    return { ...nested, ...direct }
  }

  function stagingFinanceOccurrence(record, payload = {}) {
    return resolveFinanceOccurrence({
      occurredAt: payload.occurred_at || payload.order_finished_at || record?.occurredAt || null,
      date: payload.transaction_date || payload.income_date || payload.record_date || payload.date || null,
      time: payload.transaction_time || payload.record_time || payload.time || null,
      fallbackInstant: record?.createdAt || null,
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
    incomeModal.stagingSource = null
    setIncomeModalInitial()
  }

  function openIncomeStagingModal(record) {
    if (!record?.id) return false
    const payload = stagingArchivePayload(record)
    const occurrence = stagingFinanceOccurrence(record, payload)
    const hasAccountChoice = Object.prototype.hasOwnProperty.call(payload, 'account_id')
    incomeModal.open = true
    incomeModal.mode = 'staging'
    incomeModal.id = null
    incomeModal.cat = payload.income_category || 'other'
    incomeModal.amount = payload.amount == null ? '' : String(payload.amount)
    incomeModal.source = payload.source_name || payload.merchant_name || payload.title || ''
    incomeModal.note = payload.note || record.summary || ''
    incomeModal.date = occurrence.date || getLocalDateKey()
    incomeModal.imagePath = record.imagePath || null
    incomeModal.imageUrl = record.imageUrl || null
    incomeModal.imageLoadError = Boolean(record.imagePath && !record.imageUrl)
    incomeModal.accountId = hasAccountChoice ? payload.account_id || null : defaultAccountIdForKind('income')
    incomeModal.accountUnbound = hasAccountChoice ? !payload.account_id : !incomeModal.accountId
    incomeModal.stagingSource = record
    setIncomeModalInitial()
    return true
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
    incomeModal.stagingSource = null
    setIncomeModalInitial()
  }

  function closeIncomeModal() {
    incomeModal.open = false
    incomeModal.stagingSource = null
    incomeModalInitial = null
  }

  function upsertFinanceRecord(records, record) {
    const index = records.findIndex(item => item.id === record.id)
    if (index >= 0) records[index] = record
    else records.unshift(record)
  }

  async function confirmIncome() {
    return runLockedAction('income', async () => {
      const amt = parseFloat(incomeModal.amount)
      if (!amt || amt <= 0 || amt > 999999.99) { showWarn('请输入有效金额（0.01 ~ 999999.99）'); return }
      if (!incomeModal.cat) { showWarn('请选择收入类型'); return }
      if (!incomeModal.date) { showWarn('请选择到账日期'); return }
      const source = incomeModal.source.trim() || (incomeCatMap[incomeModal.cat]?.label || '收入')
      if (incomeModal.mode === 'staging' && incomeModal.stagingSource) {
        const stagingSource = incomeModal.stagingSource
        const originalOccurrence = stagingFinanceOccurrence(stagingSource, stagingArchivePayload(stagingSource))
        const incomeOccurrence = originalOccurrence.date === incomeModal.date
          ? originalOccurrence
          : resolveFinanceOccurrence({ date: incomeModal.date })
        const result = await archiveStagingRecord(stagingSource, 'income', {
          confirm: false,
          payloadOverrides: {
            amount: amt,
            source_name: source,
            income_category: incomeModal.cat,
            account_id: incomeModal.accountUnbound ? null : incomeModal.accountId || null,
            occurred_at: incomeOccurrence.occurredAt,
            income_date: incomeOccurrence.date,
            note: incomeModal.note.trim() || null,
          },
          summaryOverride: incomeModal.note.trim() || stagingSource.summary,
          explicitAccount: true,
          financeOccurrence: incomeOccurrence,
        })
        if (!result) return null
        closeIncomeModal()
        return result
      }
      const isEdit = incomeModal.mode === 'edit' && Boolean(incomeModal.id)
      const recordId = isEdit ? incomeModal.id : null
      const incomeAccountId = incomeModal.accountUnbound ? null : (incomeModal.accountId || null)
      const incomeOccurrence = resolveFinanceOccurrence({ date: incomeModal.date })
      const result = await financeSaveFeature.saveIncome({
        id: recordId,
        category: incomeModal.cat,
        sourceName: source,
        amount: amt,
        incomeDate: incomeModal.date,
        occurredAt: incomeOccurrence.occurredAt,
        note: incomeModal.note.trim() || null,
        source: isEdit ? null : 'manual',
        imageUrl: incomeModal.imagePath || null,
        imageHash: null,
        companionMessage: null,
        accountId: incomeAccountId,
      }, {
        onAccepted: ({ record }) => {
          invalidateRecordExpressionPlan(record.id)
          upsertFinanceRecord(incomeRecords.value, record)
          upsertFinanceRecord(recentIncomeRecords.value, record)
          closeIncomeModal()
        },
        refresh: async (_accepted, { userId }) => {
          await refreshAccountsFromDB({ expectedUserId: userId, throwOnError: true })
          if (currentPage.value === 'unbound-records') {
            await loadUnboundRecords({ expectedUserId: userId, throwOnError: true })
          }
        },
      })
      if (result.status === 'stale') return result
      if (result.status !== 'accepted') {
        showError('保存失败：' + humanizeDbError(result.error || '请重新登录后再试'))
        return result
      }
      if (detailRecord.value?.id === result.record.id) await openRecordDetail('income', result.record)
      if (result.refreshStatus === 'failed') showFlash('✓ 收入已保存，账户或列表刷新失败，请稍后刷新页面')
      else showFlash(isEdit ? '✓ 收入已更新' : '✓ 收入已记录')
      return result
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
      stagingSourceId: expenseModal.stagingSource?.id || null,
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
    expenseModal.stagingSource = null
    setExpenseModalInitial()
  }

  function openExpenseStagingModal(record) {
    if (!record?.id) return false
    const payload = stagingArchivePayload(record)
    const occurrence = stagingFinanceOccurrence(record, payload)
    const hasAccountChoice = Object.prototype.hasOwnProperty.call(payload, 'account_id')
    expenseModal.open = true
    expenseModal.mode = 'staging'
    expenseModal.id = null
    expenseModal.amount = payload.amount == null ? '' : String(payload.amount)
    expenseModal.merchantName = payload.merchant_name || payload.title || ''
    expenseModal.platform = normalizeFinanceOptionValue('platform', payload.platform) || payload.platform || null
    expenseModal.category = normalizeFinanceOptionValue('category', payload.category) || payload.category || null
    expenseModal.payment = normalizeFinanceOptionValue('payment', payload.payment_method) || payload.payment_method || null
    expenseModal.note = payload.note || record.summary || ''
    expenseModal.date = occurrence.date || getLocalDateKey()
    expenseModal.time = occurrence.time?.slice(0, 5) || ''
    expenseModal.imagePath = record.imagePath || null
    expenseModal.imageUrl = record.imageUrl || null
    expenseModal.imageLoadError = Boolean(record.imagePath && !record.imageUrl)
    const inferredAccountId = resolveAccountIdForPayment({
      existingAccountId: null,
      paymentMethod: expenseModal.payment,
      kind: 'expense',
    })
    expenseModal.accountId = hasAccountChoice ? payload.account_id || null : inferredAccountId
    expenseModal.accountUnbound = hasAccountChoice ? !payload.account_id : !expenseModal.accountId
    expenseModal.stagingSource = record
    setExpenseModalInitial()
    return true
  }

  async function openExpenseEditModal(record) {
    expenseModal.open = true
    expenseModal.mode = 'edit'
    expenseModal.id = record.id
    expenseModal.amount = String(record.amount || '')
    expenseModal.merchantName = record.name || ''
    expenseModal.platform = normalizeFinanceOptionValue('platform', record.platform) || null
    expenseModal.category = normalizeFinanceOptionValue('category', record.cat) || null
    expenseModal.payment = normalizeFinanceOptionValue('payment', record.payment) || null
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
    expenseModal.stagingSource = null
    setExpenseModalInitial()
  }

  function closeExpenseModal() {
    expenseModal.open = false
    expenseModal.stagingSource = null
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

      if (expenseModal.mode === 'staging' && expenseModal.stagingSource) {
        const stagingSource = expenseModal.stagingSource
        const expenseOccurrence = resolveFinanceOccurrence({
          date: expenseModal.date,
          time: resolvedTime,
        })
        const result = await archiveStagingRecord(stagingSource, 'expense', {
          confirm: false,
          payloadOverrides: {
            amount: amt,
            merchant_name: merchantName,
            platform: expenseModal.platform,
            category: expenseModal.category,
            payment_method: expenseModal.payment,
            account_id: expenseModal.accountUnbound ? null : expenseModal.accountId || null,
            transaction_time: resolvedTime,
            occurred_at: expenseOccurrence.occurredAt,
            note: expenseModal.note.trim() || null,
          },
          summaryOverride: expenseModal.note.trim() || stagingSource.summary,
          explicitAccount: true,
          financeOccurrence: expenseOccurrence,
        })
        if (!result) return null
        closeExpenseModal()
        return result
      }

      const isEdit = expenseModal.mode === 'edit' && Boolean(expenseModal.id)
      const recordId = isEdit ? expenseModal.id : null
      const expenseAccountId = expenseModal.accountUnbound
        ? null
        : (expenseModal.accountId || autoAccountIdForPayment(expenseModal.payment, 'expense') || null)
      const transactionTime = isEdit ? resolvedTime : (resolvedTime || new Date().toTimeString().slice(0, 8))
      const expenseOccurrence = resolveFinanceOccurrence({
        date: expenseModal.date,
        time: transactionTime,
      })
      const expensePlatform = expenseModal.platform
      const expenseCategory = expenseModal.category
      const expensePayment = expenseModal.payment
      const result = await financeSaveFeature.saveExpense({
        id: recordId,
        amount: amt,
        merchantName,
        platform: expensePlatform,
        category: expenseCategory,
        paymentMethod: expensePayment,
        transactionDate: expenseModal.date,
        transactionTime,
        occurredAt: expenseOccurrence.occurredAt,
        note: expenseModal.note.trim() || null,
        isLargeTransport,
        transportType: isLargeTransport ? '交通' : null,
        source: isEdit ? null : 'manual',
        imageUrl: expenseModal.imagePath || null,
        imageHash: null,
        companionMessage: null,
        accountId: expenseAccountId,
      }, {
        onAccepted: ({ record }) => {
          invalidateRecordExpressionPlan(record.id)
          learnConfirmedExpenseVocabulary({
            platform: expensePlatform,
            category: expenseCategory,
            payment: expensePayment,
            accountId: expenseAccountId,
          })
          upsertFinanceRecord(bills.value, record)
          closeExpenseModal()
        },
        refresh: async (_accepted, { userId }) => {
          await refreshAccountsFromDB({ expectedUserId: userId, throwOnError: true })
          if (currentPage.value === 'unbound-records') {
            await loadUnboundRecords({ expectedUserId: userId, throwOnError: true })
          }
        },
      })
      if (result.status === 'stale') return result
      if (result.status !== 'accepted') {
        showError('保存失败：' + humanizeDbError(result.error || '请重新登录后再试'))
        return result
      }
      if (detailRecord.value?.id === result.record.id) await openRecordDetail('expense', result.record)
      if (result.refreshStatus === 'failed') showFlash('✓ 支出已保存，账户或列表刷新失败，请稍后刷新页面')
      else showFlash(isEdit ? '✓ 支出已更新' : '✓ 支出已记录')
      return result
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
      stagingSourceId: universalModal.stagingSource?.id || null,
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
    universalModal.stagingSource = null
    setUniversalModalInitial()
  }

  function openUniversalRepairFromStaging(record, domainKey = record?.domainKey) {
    if (!record?.id || !domainKey) return false
    const meta = getUniversalDomainMeta(domainKey)
    if (!meta) return false

    const extracted = record.extracted && typeof record.extracted === 'object' ? record.extracted : {}
    const nestedPayload = extracted.payload_jsonb && typeof extracted.payload_jsonb === 'object'
      ? extracted.payload_jsonb
      : {}
    const { payload_jsonb: _nested, ...directPayload } = extracted
    const payload = { ...directPayload, ...nestedPayload }
    const occurredAt = record.occurredAt || record.createdAt || new Date().toISOString()

    resetUniversalModal(universalModal, domainKey, meta, localDateKeyOf(occurredAt) || getLocalDateKey())
    universalModal.stagingSource = {
      id: record.id,
      imagePath: record.imagePath || null,
      imageHash: record.imageHash || null,
    }
    universalModal.title = String(payload.title || '').trim()
    universalModal.primaryValue = payload[meta.primaryKey] == null ? '' : String(payload[meta.primaryKey])
    universalModal.dimension = String(payload[meta.dimensionKey] || '').trim()
    universalModal.note = /缺少字段|置信度不足/i.test(record.summary || '') ? '' : (record.summary || '')
    universalModal.date = localDateKeyOf(occurredAt) || getLocalDateKey()
    universalModal.time = String(occurredAt).slice(11, 16)
    universalModal.imagePath = record.imagePath || null
    universalModal.imageUrl = record.imageUrl || null
    universalModal.imageLoadError = false
    universalModal.originalPayload = payload
    setUniversalModalInitial()

    if (!universalModal.imageUrl && universalModal.imagePath) {
      const sourceId = record.id
      getSignedImageUrl(universalModal.imagePath).then(url => {
        if (universalModal.stagingSource?.id !== sourceId) return
        universalModal.imageUrl = url
        universalModal.imageLoadError = !url
      })
    }
    return true
  }

  async function openUniversalEditModal(record) {
    const meta = getUniversalDomainMeta(record.domainKey)
    hydrateUniversalModalFromRecord(universalModal, record, meta)
    universalModal.stagingSource = null
    universalModal.imageUrl = await getSignedImageUrl(universalModal.imagePath)
    universalModal.imageLoadError = !!universalModal.imagePath && !universalModal.imageUrl
    setUniversalModalInitial()
  }

  function closeUniversalModal() {
    universalModal.open = false
    universalModal.stagingSource = null
    universalModalInitial = null
  }

  async function confirmUniversalRecord() {
    const meta = getUniversalDomainMeta(universalModal.domainKey)
    const validationError = validateUniversalModal(universalModal, meta)
    if (validationError) {
      showWarn(validationError)
      return
    }

    const stagingSource = universalModal.stagingSource
    if (stagingSource) {
      const draft = buildUniversalRecordDraft(universalModal, meta)
      const payload = {
        ...draft.payload,
        source_app: draft.payload.source_app === 'manual' ? '截图补全' : draft.payload.source_app,
      }
      const domainKey = universalModal.domainKey
      const { data, error } = await sb.rpc('archive_staging_record', {
        p_staging_id: stagingSource.id,
        p_domain_key: domainKey,
        p_title: draft.title,
        p_record_date: universalModal.date,
        p_record_time: universalModal.time || null,
        p_occurred_at: draft.occurredAt,
        p_summary: draft.summary,
        p_payload: payload,
      })
      if (error) {
        showError('保存失败：' + humanizeDbError(error))
        return
      }
      invalidateRecordExpressionPlan(stagingSource.id)
      invalidateRecordExpressionPlan(data?.target_record_id)

      const stagingIndex = stagingRecords.value.findIndex(item => item.id === stagingSource.id)
      if (stagingIndex >= 0) stagingRecords.value.splice(stagingIndex, 1)
      closeUniversalModal()
      showFlash(`✓ 已补全并归入${getSystemDomainLabel(domainKey, '记录')}`)
      void loadData(0, true)
      return data
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
      invalidateRecordExpressionPlan(universalModal.id)
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
      invalidateRecordExpressionPlan(newRow?.id)
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

  async function openDataRecordImage(record) {
    const raw = record?.imagePath || record?.source_image_path || record?.imageUrl || ''
    if (!raw) {
      showFlash('这条记录没有可预览的截图')
      return false
    }
    const url = await getSignedImageUrl(raw)
    if (!url) {
      showFlash('截图链接生成失败，请稍后重试')
      return false
    }
    openImgFull(url)
    return true
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

  function rememberProcessedStaging(record, values) {
    const processed = { ...record, ...values }
    processedStagingRecords.value = [
      processed,
      ...processedStagingRecords.value.filter(item => item.id !== record.id),
    ].slice(0, 30)
    return processed
  }

  async function discardStagingRecord(record, reason = 'user_discarded', options = {}) {
    if (!record?.id) return null
    if (options.confirm !== false) {
      const ok = confirm('确认销毁这条待处理截图？原图也会在后台安全清理。')
      if (!ok) return null
    }
    const result = await stagingDiscardFeature.discard(record, reason, {
      afterAccepted: async () => {
        const idx = stagingRecords.value.findIndex(r => r.id === record.id)
        if (idx >= 0) stagingRecords.value.splice(idx, 1)
        rememberProcessedStaging(record, {
          status: 'discarded',
          resolvedAction: 'discarded',
          resolvedAt: new Date().toISOString(),
          discardReason: reason,
        })
      },
    })

    if (result.status !== 'accepted') {
      if (result.status !== 'stale') showFlash('❌ 销毁失败：' + (result.error || '请求未完成'))
      return result
    }

    if (result.convergenceStatus === 'failed') showFlash('✓ 已销毁；列表更新失败，请稍后刷新')
    else if (result.cleanupQueued) showFlash('✓ 已销毁，原图已加入后台清理')
    else if (result.cleanupStatus === 'skipped_external') showFlash('✓ 已销毁；外部图片链接不由芥子删除')
    else showFlash('✓ 已销毁')
    return result
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
    const records = ids.map(id => stagingRecords.value.find(record => record.id === id)).filter(Boolean)
    const results = await Promise.allSettled(records.map(record => (
      discardStagingRecord(record, 'batch_discard', { confirm: false })
    )))
    const successCount = results.filter(result => (
      result.status === 'fulfilled' && result.value?.status === 'accepted'
    )).length
    selectedStagingIds.value = new Set()
    batchMode.value = false
    showFlash(successCount === ids.length
      ? `✓ 已销毁 ${successCount} 条，原图将在后台安全清理`
      : `⚠ 已销毁 ${successCount}/${ids.length} 条，其余请重试`)
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
        const result = await archiveStagingRecord(record, domainKey, { confirm: false })
        if (result) successCount++
      } catch (e) {
        console.warn('批量归档单条失败:', id, e)
      }
    }
    selectedStagingIds.value = new Set()
    batchMode.value = false
    showFlash(`✓ 已归档 ${successCount}/${ids.length} 条`)
  }

  async function retryStagingRecord(record) {
    if (!record?.id) return
    return runLockedAction('retryStaging', async () => {
      showFlash('⏳ 正在重新识别...')
      try {
        const result = await stagingRetryFeature.retry(record)
        if (result.status === 'accepted') {
          showFlash(`✓ 重试成功 → 已归档到「${getSystemDomainLabel(result.payload?.record_type, result.payload?.record_type)}」`)
          const idx = stagingRecords.value.findIndex(r => r.id === record.id)
          if (idx >= 0) stagingRecords.value.splice(idx, 1)
          return result
        }
        if (result.nextRetryCount != null) {
          const idx = stagingRecords.value.findIndex(r => r.id === record.id)
          if (idx >= 0) stagingRecords.value[idx] = {
            ...stagingRecords.value[idx],
            retryCount: result.nextRetryCount,
          }
        }
        if (result.reason === 'retry_limit_exceeded') {
          showFlash('⚠ 已达到重试上限，请手动调整、归档或销毁')
        } else if (result.reason === 'retry_failed') {
          showFlash('⚠ 重试仍未确定，记录已保留，请手动选择数据域归档')
        } else if (result.status === 'stale') {
          return result
        } else {
          showFlash('❌ 重试失败：' + (result.error || '未知错误'))
        }
        return result
      } catch (e) {
        showFlash('❌ 重试失败：' + (e.message || '未知错误'))
        return { status: 'failed', reason: 'client_error', recordId: record.id, recordStillVisible: true, error: e.message || '未知错误' }
      }
    })
  }

  async function archiveStagingRecord(record, domainKey, options = {}) {
    if (!record?.id || !domainKey) return null
    const domain = domains.value.find(item => item.id === domainKey)
    if (!domain) return null

    if (options.confirm !== false) {
      const ok = confirm('确认把这条待处理截图归档到「' + domain.name + '」？')
      if (!ok) return null
    }

    const payload = {
      ...stagingArchivePayload(record),
      ...(options.payloadOverrides || {}),
      image_type: record.imageType || null,
      record_type: record.recordType || null,
      confidence: record.confidence || 0,
      ai_summary: record.summary || null,
      failure_reason: record.failureReason || null,
    }
    const financeOccurrence = options.financeOccurrence || stagingFinanceOccurrence(record, payload)
    const amount = Number.parseFloat(
      payload.amount
      ?? record.summary?.match(/金额\s*(\d+(\.\d+)?)/)?.[1]
      ?? '0',
    )
    const title = buildUniversalRecordTitle(domainKey, payload, record)
    const summary = options.summaryOverride || record.summary || domain.name + '截图归档'
    const accountId = options.explicitAccount
      ? payload.account_id || null
      : domainKey === 'expense'
        ? autoAccountIdForPayment(payload.payment_method || null, 'expense')
        : domainKey === 'income'
          ? defaultAccountIdForKind('income')
          : null

    const result = await stagingArchiveFeature.archive(record, domainKey, {
      amount: Number.isFinite(amount) ? amount : null,
      title: domainKey === 'expense'
        ? payload.merchant_name || payload.source_name || title || null
        : domainKey === 'income'
          ? payload.source_name || title || null
          : title,
      platform: payload.platform || null,
      category: payload.category || null,
      paymentMethod: payload.payment_method || null,
      incomeCategory: payload.income_category || null,
      recordDate: financeOccurrence.date || null,
      recordTime: financeOccurrence.time || null,
      occurredAt: financeOccurrence.occurredAt || null,
      summary,
      payload,
      accountId,
      afterAccepted: async () => {
        const refresh = await loadData(0, true)
        if (!refresh?.ok) throw new Error('归档成功，但列表刷新失败')
      },
    })

    if (result.status === 'rejected') {
      if (result.reason === 'missing_amount') {
        showFlash('⚠ 缺少有效金额，请补全后再归档')
      } else if (result.reason === 'unauthenticated') {
        showFlash('⚠ 登录状态已失效，请重新登录')
      }
      return null
    }

    if (result.status !== 'accepted') {
      if (result.status !== 'stale') {
        showFlash('❌ 归档失败：' + (result.error || '请求未完成'))
      }
      return null
    }

    const stagingIndex = stagingRecords.value.findIndex(item => item.id === record.id)
    if (stagingIndex >= 0) stagingRecords.value.splice(stagingIndex, 1)
    rememberProcessedStaging(record, {
      status: 'archived',
      domainKey,
      detectedDomainKey: record.detectedDomainKey || record.domainKey || null,
      resolvedDomainKey: result.resolvedDomainKey || domainKey,
      targetKind: result.targetKind || (['expense', 'income'].includes(domainKey) ? domainKey : 'data'),
      targetRecordId: result.targetRecordId,
      targetReference: result.targetReference || null,
      resolvedAction: 'archived',
      resolvedAt: new Date().toISOString(),
    })
    invalidateRecordExpressionPlan(record.id)
    invalidateRecordExpressionPlan(result.targetRecordId)
    showFlash(result.refreshStatus === 'failed'
      ? '✓ 已归档；列表刷新失败，请稍后刷新查看'
      : '✓ 已归档到' + domain.name)
    return { ...result, kind: domainKey }
  }
  function buildUniversalRecordTitle(domainKey, payload, record) {
    return buildUniversalRecordTitleFromAdapter(domainKey, payload, record)
  }

  async function openProcessedStagingRecord(record) {
    if (!record?.targetRecordId || record.status !== 'archived') return false
    const targetId = record.targetRecordId
    if (record.targetKind === 'repayment_cycle') {
      const cycle = repaymentCycles.value.find(item => item.id === targetId)
      const account = cycle && accounts.value.find(item => item.id === cycle.accountId)
      if (!cycle || !account) {
        showFlash('还款账期暂时无法读取，请刷新后重试')
        return false
      }
      await openAccountDetail(account)
      return true
    }
    const targetKind = ['expense', 'income', 'data'].includes(record.targetKind)
      ? record.targetKind
      : null
    if (!targetKind) {
      showFlash('归档目标类型未知，请从中转站重新确认')
      return false
    }

    const localRecord = targetKind === 'expense'
      ? bills.value.find(item => item.id === targetId)
      : targetKind === 'income'
        ? incomeRecords.value.find(item => item.id === targetId)
          || recentIncomeRecords.value.find(item => item.id === targetId)
        : dataRecords.value.find(item => item.id === targetId)
    if (localRecord) {
      await openRecordDetail(targetKind === 'data' ? 'universal' : targetKind, localRecord)
      return true
    }

    const result = await recordRepository.getRecordByTarget({
      targetKind,
      targetRecordId: targetId,
    })
    if (result.status === 'accepted' && result.record) {
      await openRecordDetail(targetKind === 'data' ? 'universal' : targetKind, result.record)
      return true
    }
    showFlash(result.status === 'failed'
      ? `记录读取失败：${humanizeDbError(result.error)}`
      : '归档后的记录已不存在')
    return false
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
    accountModal.billDay = ''
    accountModal.paymentDueDay = ''
    accountModal.autoDebitAccountId = null
    accountModal.autoConfirmRepayment = false
    accountModal.isDefaultExpense = false
    accountModal.isDefaultIncome = false
    accountModal.isArchived = false
    accountModal.commandKey = `create-account-${Date.now()}-${++accountCommandSequence}`
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
    accountModal.billDay = account.billDay == null ? '' : String(account.billDay)
    accountModal.paymentDueDay = account.paymentDueDay == null ? '' : String(account.paymentDueDay)
    accountModal.autoDebitAccountId = account.autoDebitAccountId || null
    accountModal.autoConfirmRepayment = !!account.autoConfirmRepayment
    accountModal.isDefaultExpense = !!account.isDefaultExpense
    accountModal.isDefaultIncome = !!account.isDefaultIncome
    accountModal.isArchived = !!account.isArchived
    accountModal.commandKey = null
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
    if (init < 0) return '初始余额不能小于 0'
    const billDay = accountModal.billDay === '' ? null : Number(accountModal.billDay)
    if (billDay != null && (!Number.isInteger(billDay) || billDay < 1 || billDay > 31)) return '账单日必须是 1-31 之间的整数'
    const dueDay = accountModal.paymentDueDay === '' ? null : Number(accountModal.paymentDueDay)
    if (dueDay != null && (!Number.isInteger(dueDay) || dueDay < 1 || dueDay > 31)) return '还款日必须是 1-31 之间的整数'
    return ''
  }

  function convergeCanonicalAccount(account) {
    if (!account?.id) return
    accounts.value = accounts.value.map((item) => {
      if (item.id === account.id) return account
      const next = { ...item }
      if (account.isDefaultExpense) next.isDefaultExpense = false
      if (account.isDefaultIncome) next.isDefaultIncome = false
      if (account.isArchived && next.autoDebitAccountId === account.id) next.autoDebitAccountId = null
      return next
    })
    const index = accounts.value.findIndex(item => item.id === account.id)
    if (index < 0) accounts.value.unshift(account)
    if (selectedAccount.value?.id) {
      const selectedCanonical = accounts.value.find(item => item.id === selectedAccount.value.id)
      if (selectedCanonical) selectedAccount.value = selectedCanonical
    }
  }

  function accountWriteError(result) {
    if (result?.reason === 'account_type_transition_blocked') return '该账户已有流水、账单或引用，不能直接切换资产/负债类型'
    if (result?.reason === 'invalid_auto_debit_account') return '自动扣款账户必须是本人未归档的资产账户'
    if (result?.reason === 'account_not_found') return '账户不存在或当前登录状态无权操作'
    if (result?.reason === 'account_command_conflict') return '该账户正在执行另一项操作，请稍后重试'
    return humanizeDbError(result?.error || result?.reason || '账户操作失败')
  }

  async function saveAccount() {
    return runLockedAction('account', async () => {
      if (!currentUserId.value) { showWarn('请先登录'); return null }
      const err = validateAccountForm()
      if (err) { showWarn(err); return null }
      const accountType = normalizeAccountType(accountModal.type)
      const liability = ['credit_card', 'credit_line'].includes(accountType)
      const isEdit = accountModal.mode === 'edit' && !!accountModal.id
      const command = {
        accountId: isEdit ? accountModal.id : null,
        commandKey: isEdit ? null : accountModal.commandKey,
        name: accountModal.name.trim(),
        type: accountType,
        institution: accountModal.institution.trim() || null,
        last4: accountModal.last4 ? String(accountModal.last4).trim() : null,
        initialBalance: parseFloat(accountModal.initialBalance || '0') || 0,
        billDay: liability && accountModal.billDay !== '' ? Number(accountModal.billDay) : null,
        paymentDueDay: liability && accountModal.paymentDueDay !== '' ? Number(accountModal.paymentDueDay) : null,
        autoDebitAccountId: liability ? (accountModal.autoDebitAccountId || null) : null,
        autoConfirmRepayment: liability ? !!accountModal.autoConfirmRepayment : false,
        isDefaultExpense: !!accountModal.isDefaultExpense,
        isDefaultIncome: !!accountModal.isDefaultIncome,
      }
      const result = await accountManagementFeature.save(command, {
        onAccepted: (account) => {
          convergeCanonicalAccount(account)
          closeAccountModal()
        },
        refresh: async (_account, { userId }) => {
          await refreshAccountsFromDB({ expectedUserId: userId, throwOnError: true })
        },
      })
      if (result.status === 'stale') return result
      if (result.status !== 'accepted') {
        showError(`${isEdit ? '保存' : '创建'}失败：${accountWriteError(result)}`)
        return result
      }
      if (result.refreshStatus === 'failed') showFlash(`✓ 账户已${isEdit ? '更新' : '创建'}，列表刷新失败，请稍后刷新页面`)
      else showFlash(isEdit ? '✓ 账户已更新' : '✓ 账户已创建')
      return result
    })
  }

  async function archiveAccount(account, archived = true) {
    if (!account?.id) return null
    const effect = archived
      ? '归档会清除默认项和未来自动扣款引用，但保留余额、流水和还款历史。'
      : '恢复后不会自动恢复默认项或自动扣款关系。'
    const ok = confirm(`确认${archived ? '归档' : '恢复'}账户「${account.name}」？${effect}`)
    if (!ok) return null
    return runLockedAction('account', async () => {
      const result = await accountManagementFeature.setArchived({ accountId: account.id, archived }, {
        onAccepted: canonicalAccount => convergeCanonicalAccount(canonicalAccount),
        refresh: async (_canonicalAccount, { userId }) => {
          await refreshAccountsFromDB({ expectedUserId: userId, throwOnError: true })
        },
      })
      if (result.status === 'stale') return result
      if (result.status !== 'accepted') {
        showError('操作失败：' + accountWriteError(result))
        return result
      }
      if (result.refreshStatus === 'failed') showFlash(`✓ 账户已${archived ? '归档' : '恢复'}，列表刷新失败，请稍后刷新页面`)
      else showFlash(archived ? '✓ 账户已归档' : '✓ 账户已恢复')
      return result
    })
  }

  async function loadAccountSourceSnapshot(account) {
    if (!account?.sourceRecordId || account.sourceRecordTable !== 'data_records') {
      return { status: 'accepted', reason: 'not_applicable', data: null, applicable: false }
    }
    const { data, error } = await sb.from('data_records')
      .select('id,title,summary,occurred_at,source_image_path,source_image_hash,payload_jsonb,snapshot_balance,snapshot_at,account_snapshot_kind')
      .eq('id', account.sourceRecordId)
      .maybeSingle()
    if (error) {
      console.warn('加载账户来源快照失败:', error.message)
      return { status: 'failed', reason: 'service_error', data: null, error: error.message }
    }
    if (!data) return { status: 'accepted', reason: 'not_found', data: null }
    const payload = data.payload_jsonb || {}
    const imageUrl = await getSignedImageUrl(data.source_image_path)
    const snapshot = {
      id: data.id,
      title: data.title || '来源快照',
      summary: data.summary || '',
      occurredAt: data.occurred_at,
      imagePath: data.source_image_path || '',
      imageUrl,
      imageLoadError: Boolean(data.source_image_path && !imageUrl),
      imageHash: data.source_image_hash || '',
      snapshotBalance: data.snapshot_balance ?? payload.snapshot_balance ?? null,
      snapshotAt: data.snapshot_at || data.occurred_at || null,
      accountSnapshotKind: data.account_snapshot_kind || payload.account_snapshot_kind || null,
      payload,
    }
    if (snapshot.imageLoadError) {
      return { status: 'failed', reason: 'image_signing_failed', data: snapshot, error: '来源快照图片加载失败' }
    }
    return { status: 'accepted', reason: 'loaded', data: snapshot }
  }

  function applyAccountDetailResult(result) {
    if (!result || result.status === 'stale' || !result.sections) return result
    if (selectedAccount.value?.id !== result.accountId) return { status: 'stale', reason: 'account_changed' }
    const { entries, payments, repaymentCycles: cycles, sourceSnapshot } = result.sections
    if (entries.status === 'accepted' || entries.data.length) selectedAccountEntries.value = entries.data
    if (payments.status === 'accepted' || payments.data.length) selectedAccountPayments.value = payments.data
    if (cycles.status === 'accepted' || cycles.data.length) {
      repaymentCycles.value = [
        ...repaymentCycles.value.filter(cycle => cycle.accountId !== result.accountId),
        ...cycles.data,
      ]
    }
    if (sourceSnapshot.status === 'accepted' || sourceSnapshot.data) {
      selectedAccountSourceSnapshot.value = sourceSnapshot.data
    }
    return result
  }

  async function loadAccountEntries(accountId) {
    const account = accounts.value.find(item => item.id === accountId)
      || (selectedAccount.value?.id === accountId ? selectedAccount.value : null)
    if (!account) return { status: 'failed', reason: 'account_not_found' }
    const cycleMonth = `${currentYear.value}-${String(currentMonth.value).padStart(2, '0')}`
    const result = await accountDetailFeature.load(account, {
      ensureCycles: isLiabilityAccount(account),
      cycleMonth,
    })
    if (result.status === 'stale') return result
    return applyAccountDetailResult(result)
  }

  async function openAccountDetail(account) {
    if (!account?.id) return { status: 'failed', reason: 'account_not_found' }
    const accountChanged = selectedAccount.value?.id !== account.id
    selectedAccount.value = account
    if (accountChanged) {
      selectedAccountEntries.value = []
      selectedAccountPayments.value = []
      selectedAccountSourceSnapshot.value = null
    }
    const result = await loadAccountEntries(account.id)
    if (result.status !== 'stale') navigateTo('account-detail')
    return result
  }

  async function refreshAccountDetail() {
    if (!selectedAccount.value?.id) return { status: 'failed', reason: 'account_not_found' }
    const latest = accounts.value.find(account => account.id === selectedAccount.value.id)
    if (latest) selectedAccount.value = latest
    const result = await loadAccountEntries(selectedAccount.value.id)
    return result
  }

  function convergeRepaymentCycle(cycle, { selectCycleMonth = false } = {}) {
    if (!cycle?.id) return
    const idx = repaymentCycles.value.findIndex(item => item.id === cycle.id)
    if (idx >= 0) repaymentCycles.value[idx] = cycle
    else repaymentCycles.value.unshift(cycle)
    if (!selectCycleMonth || !/^\d{4}-\d{2}$/.test(cycle.cycleMonth || '')) return
    const [year, month] = cycle.cycleMonth.split('-').map(Number)
    if (Number.isInteger(year) && Number.isInteger(month)) {
      currentYear.value = year
      currentMonth.value = month
    }
  }

  async function refreshRepaymentAccounts(expectedUserId) {
    const listResult = await refreshAccountsFromDB({ expectedUserId, throwOnError: true })
    if (listResult.status === 'stale') throw new Error('账户列表刷新已过期')
    if (selectedAccount.value?.id) {
      const detailResult = await refreshAccountDetail()
      if (detailResult.status !== 'accepted') {
        throw new Error(detailResult.status === 'partial' ? '账户详情仅部分刷新成功' : '账户详情刷新失败')
      }
    }
  }

  async function confirmRepaymentCyclePaid(cycle, options = {}) {
    if (!cycle?.id) return false
    const lockKey = `repayment-cycle:${cycle.id}`
    const wasPending = !!actionState[lockKey]
    if (!wasPending) actionState[lockKey] = true
    const paidAmount = Number(options.paidAmount ?? cycle.statementAmount ?? 0)
    const debitAccountId = options.debitAccountId || cycle.autoDebitAccountId || null
    const expectedUserId = currentUserId.value
    try {
      const result = await repaymentFeature.confirm({
        cycleId: cycle.id,
        accountId: cycle.accountId,
        paidAmount,
        debitAccountId,
        status: options.status ?? 'paid',
        note: options.note || '手动确认已还清',
      }, {
        onAccepted: accepted => convergeRepaymentCycle(accepted.cycle),
        refresh: () => refreshRepaymentAccounts(expectedUserId),
      })
      if (result.status === 'stale') return false
      if (result.status === 'rejected') {
        const message = result.reason === 'unauthenticated'
          ? '登录状态已失效，请重新登录'
          : result.reason === 'repayment_conflict'
            ? '当前账单已有还款操作进行中'
            : '待还金额异常，暂时不能确认'
        showFlash(message)
        return false
      }
      if (result.status !== 'accepted') {
        showFlash('确认还款失败：' + humanizeDbError(result.error))
        return false
      }
      if (result.refreshStatus === 'failed') {
        showFlash('✓ 已确认还款；账户列表刷新失败，请稍后刷新页面')
        return true
      }
      showFlash(debitAccountId ? '✓ 已确认还款并记录扣款' : '✓ 已确认还款')
      return true
    } finally {
      if (!wasPending) actionState[lockKey] = false
    }
  }

  async function revokeLiabilityPayment(payment) {
    if (!payment?.id) return false
    const ok = confirm(`确认撤销这笔还款记录？\n金额：¥${Number(payment.amount || 0).toFixed(2)}\n撤销后会作废关联账户流水，并恢复账单待还金额。`)
    if (!ok) return false
    const lockKey = `liability-payment:${payment.id}`
    const wasPending = !!actionState[lockKey]
    if (!wasPending) actionState[lockKey] = true
    const expectedUserId = currentUserId.value
    try {
      const result = await repaymentFeature.revoke({
        paymentId: payment.id,
        cycleId: payment.statementId,
        accountId: payment.accountId,
        reason: '用户撤销还款',
      }, {
        onAccepted: accepted => convergeRepaymentCycle(accepted.cycle, { selectCycleMonth: true }),
        refresh: () => refreshRepaymentAccounts(expectedUserId),
      })
      if (result.status === 'stale') return false
      if (result.status === 'rejected') {
        const message = result.reason === 'unauthenticated'
          ? '登录状态已失效，请重新登录'
          : result.reason === 'repayment_conflict'
            ? '当前账单已有还款操作进行中'
            : '还款记录不完整，暂时不能撤销'
        showFlash(message)
        return false
      }
      if (result.status !== 'accepted') {
        showFlash('撤销还款失败：' + humanizeDbError(result.error))
        return false
      }
      if (result.refreshStatus === 'failed') {
        showFlash('✓ 已撤销还款；账户列表刷新失败，请稍后刷新页面')
        return true
      }
      showFlash('✓ 已撤销还款')
      return true
    } finally {
      if (!wasPending) actionState[lockKey] = false
    }
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

  async function repairEmptyAccountSnapshotBalances(accountRows = accounts.value) {
    if (!currentUserId.value) return
    const candidates = (accountRows || []).filter(account => (
      !account.isArchived
      && Number(account.initialBalance || 0) === 0
      && Number(account.currentBalance || 0) === 0
    ))
    if (!candidates.length) return

    const accountIds = candidates.map(account => account.id)
    const sourceRecordIds = candidates.map(account => account.sourceRecordId).filter(Boolean)
    const sourceSnapshotQuery = sourceRecordIds.length
      ? sb.from('data_records')
        .select('id,linked_account_id,occurred_at,created_at,snapshot_balance,payload_jsonb')
        .in('id', sourceRecordIds)
      : Promise.resolve({ data: [], error: null })
    const [{ data: entryRows, error: entryError }, sourceSnapshotResult, { data: linkedSnapshots, error: linkedSnapshotError }] = await Promise.all([
      sb.from('account_entries')
        .select('account_id')
        .in('account_id', accountIds)
        .eq('is_voided', false)
        .neq('entry_type', 'snapshot_initialization'),
      sourceSnapshotQuery,
      sb.from('data_records')
        .select('id,linked_account_id,occurred_at,created_at,snapshot_balance,payload_jsonb')
        .in('linked_account_id', accountIds),
    ])
    if (entryError) {
      console.warn('检查空账户快照流水失败，跳过自动回填:', entryError.message)
      return
    }
    if (sourceSnapshotResult.error) {
      console.warn('读取账户来源快照失败，将回退账户快照字段:', sourceSnapshotResult.error.message)
    }
    if (linkedSnapshotError) {
      console.warn('读取账户关联快照失败，将回退账户快照字段:', linkedSnapshotError.message)
    }

    const activeEntryCounts = new Map()
    ;(entryRows || []).forEach(row => {
      activeEntryCounts.set(row.account_id, (activeEntryCounts.get(row.account_id) || 0) + 1)
    })
    const snapshotById = new Map((sourceSnapshotResult.data || []).map(row => [row.id, row]))
    const latestSnapshotByAccountId = new Map()
    ;(linkedSnapshots || []).forEach(row => {
      const previous = latestSnapshotByAccountId.get(row.linked_account_id)
      const rowTime = row.occurred_at || row.created_at || ''
      const previousTime = previous?.occurred_at || previous?.created_at || ''
      if (!previous || rowTime >= previousTime) latestSnapshotByAccountId.set(row.linked_account_id, row)
    })

    for (const account of candidates) {
      const snapshot = snapshotById.get(account.sourceRecordId) || latestSnapshotByAccountId.get(account.id)
      const payload = snapshot?.payload_jsonb || {}
      const amount = snapshot?.snapshot_balance
        ?? payload.snapshot_balance
        ?? payload.amount
        ?? account.snapshotBalance
      const activeEntryCount = activeEntryCounts.get(account.id) || 0
      if (!shouldAdoptSnapshotAsOpeningBalance(account, activeEntryCount, amount)) continue

      const { data, error } = await sb.from('accounts')
        .update({
          initial_balance: Number(amount),
          current_balance: Number(amount),
          updated_at: new Date().toISOString(),
        })
        .eq('id', account.id)
        .eq('user_id', currentUserId.value)
        .eq('initial_balance', 0)
        .eq('current_balance', 0)
        .select('*')
        .maybeSingle()
      if (error) {
        console.warn('回填账户快照余额失败:', error.message)
        continue
      }
      if (data) {
        const idx = accounts.value.findIndex(item => item.id === data.id)
        if (idx >= 0) accounts.value[idx] = mapAccountRow(data)
      }
    }
  }

  async function refreshAccountsFromDB({ expectedUserId = currentUserId.value, throwOnError = false } = {}) {
    const result = await accountRepository.listAccounts()
    if (result.status !== 'accepted') {
      console.warn('刷新账户失败:', result.error)
      accountListState.value = { status: 'failed', error: result.error || '账户列表读取失败' }
      if (throwOnError) throw new Error(result.error || '账户列表读取失败')
      return { status: 'failed', error: result.error || '账户列表读取失败' }
    }
    if (expectedUserId && currentUserId.value !== expectedUserId) return { status: 'stale' }
    accounts.value = result.rows
    accountListState.value = { status: 'accepted', error: null }
    if (expectedUserId && currentUserId.value !== expectedUserId) return { status: 'stale' }
    return { status: 'accepted' }
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

  function convergeAccountBinding(kind, record) {
    invalidateRecordExpressionPlan(record.id)
    if (kind === 'income') {
      upsertFinanceRecord(incomeRecords.value, record)
      upsertFinanceRecord(recentIncomeRecords.value, record)
      unboundRecords.value = {
        ...unboundRecords.value,
        incomes: (unboundRecords.value.incomes || []).filter(item => item.id !== record.id),
      }
      return
    }
    upsertFinanceRecord(bills.value, record)
    unboundRecords.value = {
      ...unboundRecords.value,
      expenses: (unboundRecords.value.expenses || []).filter(item => item.id !== record.id),
    }
  }

  async function refreshAccountBindingViews(userId) {
    await refreshAccountsFromDB({ expectedUserId: userId, throwOnError: true })
    await loadUnboundRecords({ expectedUserId: userId, throwOnError: true })
  }

  async function bindRecordToAccount(kind, record, accountId) {
    const result = await accountBindingFeature.bind(kind, record, accountId, {
      onAccepted: ({ record: canonicalRecord }) => convergeAccountBinding(kind, canonicalRecord),
      refresh: async (_accepted, { userId }) => refreshAccountBindingViews(userId),
    })
    if (result.status === 'stale') return false
    if (result.status !== 'accepted') {
      const message = result.reason === 'binding_conflict'
        ? '这条记录正在绑定其他账户，请稍后再试'
        : humanizeDbError(result.error || '请重新登录后再试')
      showFlash('补绑失败：' + message)
      return false
    }
    if (detailRecord.value?.id === result.record.id) await openRecordDetail(kind, result.record)
    if (result.refreshStatus === 'failed') showFlash('✓ 已补绑账户并生成流水，账户或列表刷新失败，请稍后刷新页面')
    else showFlash('✓ 已补绑账户并生成流水')
    return true
  }

  function recommendedUnboundRecords(kind = 'all') {
    const records = []
    if (kind === 'all' || kind === 'expense') {
      for (const record of unboundRecords.value.expenses || []) {
        const recommendation = recommendAccountForRecord('expense', record)
        if (recommendation?.accountId) records.push({ kind: 'expense', record, recommendation })
      }
    }
    if (kind === 'all' || kind === 'income') {
      for (const record of unboundRecords.value.incomes || []) {
        const recommendation = recommendAccountForRecord('income', record)
        if (recommendation?.accountId) records.push({ kind: 'income', record, recommendation })
      }
    }
    return records
  }

  async function batchBindRecommendedUnboundRecords(kind = 'all', selected = null) {
    const candidates = selected || recommendedUnboundRecords(kind)
    if (!candidates.length) {
      showFlash('当前没有可批量补绑的推荐记录')
      return false
    }
    if (!selected) {
      const sample = candidates.slice(0, 3).map(item => {
        const title = item.kind === 'expense' ? item.record.name : item.record.source
        return `- ${title || '未命名记录'} → ${item.recommendation.account.name}`
      }).join('\n')
      const ok = confirm(`确认批量补绑 ${candidates.length} 条推荐记录？\n\n${sample}${candidates.length > 3 ? '\n...' : ''}\n\n只会处理已有推荐账户的记录。`)
      if (!ok) return false
    }
    return runLockedAction('batchBindUnbound', async () => {
      const result = await accountBindingFeature.bindBatch(candidates.map(item => ({
        kind: item.kind,
        record: item.record,
        accountId: item.recommendation.accountId,
      })), {
        onAccepted: ({ record: canonicalRecord }, item) => convergeAccountBinding(item.kind, canonicalRecord),
        refresh: async (_summary, { userId }) => refreshAccountBindingViews(userId),
      })
      if (result.status === 'stale') return false
      if (result.successCount === 0) {
        showFlash(`补绑失败：${result.failedCount || candidates.length} 条记录均未完成`)
        return false
      }
      const refreshSuffix = result.refreshStatus === 'failed' ? '；账户或列表刷新失败，请刷新页面后再继续' : ''
      if (result.failedCount > 0) showFlash(`已补绑 ${result.successCount} 条，${result.failedCount} 条失败${refreshSuffix}`)
      else showFlash(`✓ 已批量补绑 ${result.successCount} 条${refreshSuffix}`)
      return true
    })
  }

  function convergeWalletSnapshot(result) {
    const accountIndex = accounts.value.findIndex(item => item.id === result.account.id)
    if (accountIndex >= 0) accounts.value[accountIndex] = result.account
    else accounts.value.unshift(result.account)

    if (result.cycle?.id) {
      const cycleIndex = repaymentCycles.value.findIndex(item => item.id === result.cycle.id)
      if (cycleIndex >= 0) repaymentCycles.value[cycleIndex] = result.cycle
      else repaymentCycles.value.unshift(result.cycle)
    }
    if (selectedAccount.value?.id === result.account.id) {
      selectedAccount.value = result.account
      if (result.payment?.id && !selectedAccountPayments.value.some(item => item.id === result.payment.id)) {
        selectedAccountPayments.value.unshift(result.payment)
      }
    }

    const recordIndex = dataRecords.value.findIndex(item => item.id === result.recordId)
    if (recordIndex >= 0) {
      const current = dataRecords.value[recordIndex]
      dataRecords.value[recordIndex] = {
        ...current,
        payload: {
          ...(current.payload || {}),
          linked_account_id: result.linkedAccountId,
        },
      }
    }
    invalidateRecordExpressionPlan(result.recordId)
  }

  async function refreshWalletSnapshotViews(userId) {
    const result = await loadData(0, true)
    if (currentUserId.value !== userId) return { status: 'stale' }
    if (!result?.ok) throw new Error(result?.error?.message || '账户或记录刷新失败')
    return { status: 'accepted' }
  }

  function reportWalletSnapshotResult(result, successMessage) {
    if (result.status === 'stale') return
    if (result.status !== 'accepted') {
      const messages = {
        wallet_snapshot_conflict: '这条快照正在执行另一项关联，请稍后再试',
        snapshot_link_conflict: '这条快照已经关联到其他账户',
        account_kind_mismatch: '快照类型与目标账户不兼容',
        account_archived: '已归档账户不能接收快照',
      }
      showFlash('快照处理失败：' + (messages[result.reason] || humanizeDbError(result.error || result.reason)))
      return
    }
    if (result.reason === 'needs_confirmation') {
      showFlash('账户已关联，账期或还款需要确认')
    } else if (result.refreshStatus === 'failed') {
      showFlash('账户已关联，但列表刷新失败，请稍后刷新页面')
    } else {
      showFlash(successMessage)
    }
  }

  async function createAccountFromWalletSnapshot(record) {
    if (!record || record.domainKey !== 'wallet') {
      const result = { status: 'rejected', reason: 'invalid_input' }
      reportWalletSnapshotResult(result, '')
      return result
    }
    const result = await walletSnapshotFeature.apply(
      { operation: 'create', recordId: record.id },
      {
        onAccepted: convergeWalletSnapshot,
        refresh: (_accepted, { userId }) => refreshWalletSnapshotViews(userId),
      },
    )
    reportWalletSnapshotResult(result, '✓ 已从快照创建账户')
    return result
  }

  async function linkWalletSnapshotToAccount(record, accountId) {
    if (!record || record.domainKey !== 'wallet' || !accountId) {
      const result = { status: 'rejected', reason: 'invalid_input' }
      reportWalletSnapshotResult(result, '')
      return result
    }
    const result = await walletSnapshotFeature.apply(
      { operation: 'link', recordId: record.id, accountId },
      {
        onAccepted: convergeWalletSnapshot,
        refresh: (_accepted, { userId }) => refreshWalletSnapshotViews(userId),
      },
    )
    reportWalletSnapshotResult(result, '✓ 已关联账户')
    return result
  }

  async function loadUnboundRecords({ expectedUserId = currentUserId.value, throwOnError = false } = {}) {
    unboundRecordsLoading.value = true
    const padM = String(currentMonth.value).padStart(2, '0')
    const start = `${currentYear.value}-${padM}-01`
    const lastDay = new Date(currentYear.value, currentMonth.value, 0).getDate()
    const end = `${currentYear.value}-${padM}-${String(lastDay).padStart(2, '0')}`

    const result = await recordRepository.listUnboundRecords({ start, end, limit: 100 })
    if (expectedUserId && currentUserId.value !== expectedUserId) return { status: 'stale' }
    unboundRecordsLoading.value = false

    if (result.status !== 'accepted') {
      console.warn('加载未绑定记录失败:', result.error)
      if (throwOnError) throw new Error(result.error || '未绑定记录加载失败')
      showFlash('未绑定记录加载失败')
      return result
    }

    unboundRecords.value = {
      expenses: result.expenses,
      incomes: result.incomes,
    }
    return result
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
    pageScrollPositions['domain-detail'] = 0
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
    const imagePath = record.image_path || record.image_url || null
      || (kind === 'universal' ? record.imagePath : null)
    // Open the detail shell immediately. Signing a source image is a separate
    // network operation and must not delay the user's first meaningful view.
    detailRecord.value = {
      id: record.id,
      kind,
      domainId: kind === 'universal' ? record.domainKey : kind,
      imagePath,
      imageUrl: null,
      imageLoadError: false,
      raw: { ...record },
    }
    navigateTo('record-detail')
    if (imagePath) {
      const recordId = record.id
      getSignedImageUrl(imagePath).then((imageUrl) => {
        if (detailRecord.value?.id !== recordId) return
        detailRecord.value = {
          ...detailRecord.value,
          imageUrl,
          imageLoadError: !imageUrl,
        }
      }).catch(() => {
        if (detailRecord.value?.id !== recordId) return
        detailRecord.value = { ...detailRecord.value, imageLoadError: true }
      })
    }
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
    if (!(key in settingsState)) return { ok: false, error: new Error(`未知设置项：${key}`) }
    if (!currentUserId.value) {
      showFlash('请先登录')
      return { ok: false, error: new Error('请先登录') }
    }
    const next = !settingsState[key]
    const result = await settingsFeature.update(currentUserId.value, key, next)
    if (result.ok) {
      showFlash(next ? '✓ 已开启' : '✓ 已关闭')
    } else if (!result.stale) {
      showFlash('⚠️ 设置保存失败：' + humanizeDbError(result.error))
    }
    return result
  }

  // 用于非布尔设置项（如 imageRetentionDays）
  async function setSetting(key, value, { successMessage = '✓ 已保存', errorPrefix = '⚠️ 设置保存失败：' } = {}) {
    if (!(key in settingsState)) return { ok: false, error: new Error(`未知设置项：${key}`) }
    if (!currentUserId.value) {
      showFlash('请先登录')
      return { ok: false, error: new Error('请先登录') }
    }
    const result = await settingsFeature.update(currentUserId.value, key, value)
    if (result.ok) {
      if (successMessage) showFlash(successMessage)
    } else if (!result.stale) {
      showFlash(errorPrefix + humanizeDbError(result.error))
    }
    return result
  }

  async function setSettings(patch, { successMessage = '✓ 已保存', errorPrefix = '⚠️ 设置保存失败：' } = {}) {
    if (!currentUserId.value) {
      showFlash('请先登录')
      return { ok: false, error: new Error('请先登录') }
    }
    const result = await settingsFeature.updateMany(currentUserId.value, patch)
    if (result.ok) {
      if (successMessage) showFlash(successMessage)
    } else if (!result.stale) {
      showFlash(errorPrefix + humanizeDbError(result.error))
    }
    return result
  }

  // 同时更新 keep_source_images 和 image_retention_days 两个字段
  async function setRetention(keepSource, retentionDays) {
    return setSettings({
      keepSourceImages: keepSource,
      imageRetentionDays: retentionDays,
    }, { successMessage: '✓ 留存策略已更新' })
  }

  async function deleteRecordThroughBackend(recordKind, recordId) {
    const { data: { session } } = await sb.auth.getSession()
    if (!session?.access_token) throw new Error('登录状态已失效，请重新登录')

    const response = await fetch(`${SUPABASE_URL}/functions/v1/ingest-receipt`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session.access_token}`,
        'apikey': SUPABASE_ANON_KEY,
      },
      body: JSON.stringify({
        action: 'delete_record',
        record_kind: recordKind,
        record_id: recordId,
      }),
    })
    const result = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(result.error || `删除请求失败（${response.status}）`)
    invalidateRecordExpressionPlan(recordId)
    return result
  }

  async function confirmDelete() {
    const { type, id } = deleteConfirm
    deleteConfirm.open = false
    try {
      if (type === 'bill') {
        if (pendingModal.open && pendingModal.bill?.id === id) closePendingModal()
        const result = await deleteRecordThroughBackend('expense', id)
        await refreshAccountsFromDB()
        if (detailRecord.value?.id === id) goBack()
        // 本地移除，避免全量刷新
        const billIdx = bills.value.findIndex(b => b.id === id)
        if (billIdx >= 0) bills.value.splice(billIdx, 1)
        const pendingBillIdx = pendingBills.value.findIndex(b => b.id === id)
        if (pendingBillIdx >= 0) pendingBills.value.splice(pendingBillIdx, 1)
        showFlash(result.cleanup_pending ? '✓ 记录已删除，原图将在后台清理' : '✓ 已删除')
      } else if (type === 'income') {
        const result = await deleteRecordThroughBackend('income', id)
        await refreshAccountsFromDB()
        // 本地移除
        const incIdx = incomeRecords.value.findIndex(r => r.id === id)
        if (incIdx >= 0) incomeRecords.value.splice(incIdx, 1)
        const rIncIdx = recentIncomeRecords.value.findIndex(r => r.id === id)
        if (rIncIdx >= 0) recentIncomeRecords.value.splice(rIncIdx, 1)
        if (incomeModal.open && incomeModal.id === id) closeIncomeModal()
        if (detailRecord.value?.id === id) goBack()
        showFlash(result.cleanup_pending ? '✓ 记录已删除，原图将在后台清理' : '✓ 已删除')
      } else if (type === 'universal') {
        const result = await deleteRecordThroughBackend('data', id)
        // 本地移除
        const drIdx = dataRecords.value.findIndex(r => r.id === id)
        if (drIdx >= 0) dataRecords.value.splice(drIdx, 1)
        if (universalModal.open && universalModal.id === id) closeUniversalModal()
        if (detailRecord.value?.id === id) goBack()
        showFlash(result.cleanup_pending ? '✓ 记录已删除，原图将在后台清理' : '✓ 已删除')
      }
    } catch (e) {
      showFlash('❌ 删除失败：' + e.message)
    }
  }

  return {
    currentYear, currentMonth, currentPage, monthLabel,
    pageHistory, pageScrollPositions, currentUserId, currentUserEmail, isLoggedIn,
    loading, loadError, loadErrorDetail,
    bills, incomeRecords, recentIncomeRecords, transportRecords, stagingRecords, processedStagingRecords, dataRecords, accounts, financeVocabulary, repaymentCycles,
    selectedAccount, selectedAccountEntries, selectedAccountPayments, selectedAccountSourceSnapshot, accountEntriesLoading,
    accountListState, accountDetailState,
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
    detailRecord, recordExpressionPlanCache, activeDomainId,
    pendingModal,
    incomeModal,
    expenseModal,
    universalModal,
    incomeCatMap,
    dailySummary, dailySummaryLoading, dailySummaryError, loadDailySummary,
    aiInsight, aiInsightLoading, aiInsightError, aiInsightCached,
    generateAiInsight, loadLatestAiInsight,
    loadData, resetUserData, changeMonth, showFlash,
    initializeAuth, signIn, signUp, signOut,
    openPendingModal, closePendingModal, confirmEntry, confirmStagingRepayment,
    hasPendingChanges, resetPendingChanges,
    markPendingImageUnavailable,
    openIncomeModal, openIncomeEditModal, openIncomeStagingModal, closeIncomeModal, confirmIncome,
    hasIncomeChanges, resetIncomeChanges, markIncomeImageUnavailable,
    openExpenseModal, openExpenseEditModal, openExpenseStagingModal, closeExpenseModal, confirmExpense,
    hasExpenseChanges, resetExpenseChanges, markExpenseImageUnavailable,
    openUniversalModal, openUniversalRepairFromStaging, openUniversalEditModal, closeUniversalModal, confirmUniversalRecord,
    createAccountFromWalletSnapshot, linkWalletSnapshotToAccount,
    accountModal, openAccountModalForCreate, openAccountModalForEdit, closeAccountModal, saveAccount, archiveAccount,
    openAccountDetail, refreshAccountDetail, loadAccountEntries, openAccountEntrySource,
    confirmRepaymentCyclePaid, revokeLiabilityPayment,
    openUnboundRecordsPage, loadUnboundRecords,
    upsertAccountEntry, voidAccountEntries, refreshAccountsFromDB, defaultAccountIdForKind,
    pendingAccountReview, balanceImpactPreview,
    recommendAccountForRecord, accountBindingExplanation, bindRecordToRecommendedAccount, bindRecordToAccount,
    recommendedUnboundRecords, batchBindRecommendedUnboundRecords,
    hasUniversalChanges, resetUniversalChanges, markUniversalImageUnavailable, getUniversalDomainMeta,
    getDomainRegistryStatus,
    openImgFull, closeImgFull, openDataRecordImage,
    deleteConfirm, openDeleteConfirm, closeDeleteConfirm, confirmDelete,
    discardStagingRecord, retryStagingRecord, canRetryStagingRecord: stagingRetryFeature.canRetry, archiveStagingRecord, openProcessedStagingRecord,
    openDomainPage, openDayDetail, showMoreDailyCards, openRecordDetail, closeRecordDetail, openDetailEditor, refreshDetailRecord,
    navigateTo, goBack,
    settingsState, toggleSetting, setSetting, setSettings, setRetention, loadUserSettings, loadFinanceVocabulary,
    actionState, isActionPending, isPendingEntrySaving,
    refreshIfStale, loadRecordExpressionPlan, ackRecordExpressionPlan, submitExpressionFeedback,
  }
}
