import { ref, reactive, computed } from 'vue'
import { sb } from '../lib/supabase'
import {
  formatDate, formatMonthLabel, mapTransaction,
  incomeCatMap, catCodeMap, payAliasMap,
} from '../utils/helpers'

export function useStore() {
  const currentYear = ref(new Date().getFullYear())
  const currentMonth = ref(new Date().getMonth() + 1)
  const currentPage = ref('home')

  const bills = ref([])
  const incomeRecords = ref([])
  const transportRecords = ref([])

  const currentFilter = ref('all')
  const loading = ref(false)
  const loadError = ref('')
  const flashMsg = ref('')
  const flashVisible = ref(false)
  let flashTimer = null

  const imgOverlay = reactive({ open: false, src: '' })

  const pendingModal = reactive({
    open: false,
    bill: null,
    merchantName: '',
    amount: '',
    platform: null,
    category: null,
    payment: null,
  })

  const incomeModal = reactive({
    open: false,
    cat: 'salary',
    amount: '',
    source: '',
    note: '',
    date: '',
  })

  const deleteConfirm = reactive({
    open: false,
    type: null,
    id: null,
    imagePath: null,
  })

  const monthLabel = computed(() => formatMonthLabel(currentYear.value, currentMonth.value))

  const doneBills = computed(() => bills.value.filter(b => b.status === 'done'))
  const pendingBills = computed(() => bills.value.filter(b => b.status === 'pending'))

  const totalExpense = computed(() => doneBills.value.reduce((s, b) => s + b.amount, 0))
  const totalIncome = computed(() => incomeRecords.value.reduce((s, r) => s + r.amount, 0))
  const netBalance = computed(() => totalIncome.value - totalExpense.value)

  const filteredBills = computed(() => {
    if (currentFilter.value === 'all') return bills.value
    return bills.value.filter(b => b.cat === currentFilter.value)
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
        time: '',
        icon: incomeCatMap[r.category]?.icon || '💰',
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
    pendingModal.merchantName = bill.name !== '未识别商家' ? bill.name : ''
    pendingModal.amount = String(bill.amount)
    pendingModal.platform = bill.platform !== '?' ? bill.platform : null
    pendingModal.category = catCodeMap[bill.cat] || (bill.cat !== '?' ? bill.cat : null)
    pendingModal.payment = payAliasMap[bill.payment] || (bill.payment !== '?' ? bill.payment : null)
    pendingModalInitial = {
      merchantName: pendingModal.merchantName,
      amount: pendingModal.amount,
      platform: pendingModal.platform,
      category: pendingModal.category,
      payment: pendingModal.payment,
    }
  }

  function hasPendingChanges() {
    if (!pendingModalInitial) return false
    return pendingModal.merchantName !== pendingModalInitial.merchantName
      || pendingModal.amount !== pendingModalInitial.amount
      || pendingModal.platform !== pendingModalInitial.platform
      || pendingModal.category !== pendingModalInitial.category
      || pendingModal.payment !== pendingModalInitial.payment
  }

  function resetPendingChanges() {
    if (!pendingModalInitial) return
    pendingModal.merchantName = pendingModalInitial.merchantName
    pendingModal.amount = pendingModalInitial.amount
    pendingModal.platform = pendingModalInitial.platform
    pendingModal.category = pendingModalInitial.category
    pendingModal.payment = pendingModalInitial.payment
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

  async function confirmEntry() {
    if (!pendingModal.platform || !pendingModal.category || !pendingModal.payment) return
    const amt = parseFloat(pendingModal.amount)
    if (!amt || amt <= 0 || amt > 999999.99) { alert('请输入有效金额（0.01 ~ 999999.99）'); return }
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
    incomeModal.cat = 'salary'
    incomeModal.amount = ''
    incomeModal.source = ''
    incomeModal.note = ''
    incomeModal.date = new Date().toISOString().slice(0, 10)
  }

  function closeIncomeModal() {
    incomeModal.open = false
  }

  async function confirmIncome() {
    const amt = parseFloat(incomeModal.amount)
    if (!amt || amt <= 0 || amt > 999999.99) { alert('请输入有效金额（0.01 ~ 999999.99）'); return }
    if (!incomeModal.cat) { alert('请选择收入类型'); return }
    if (!incomeModal.date) { alert('请选择到账日期'); return }
    const source = incomeModal.source.trim() || (incomeCatMap[incomeModal.cat]?.label || '收入')
    const { error } = await sb.from('income_records').insert({
      category: incomeModal.cat,
      source_name: source,
      amount: amt,
      income_date: incomeModal.date,
      note: incomeModal.note.trim() || null,
    })
    if (error) { alert('保存失败：' + error.message); return }
    closeIncomeModal()
    showFlash('✓ 收入已记录')
    await loadData()
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

  async function confirmDelete() {
    const { type, id, imagePath } = deleteConfirm
    deleteConfirm.open = false
    try {
      if (type === 'bill') {
        if (pendingModal.open && pendingModal.bill?.id === id) closePendingModal()
        const { error } = await sb.from('transactions').delete().eq('id', id)
        if (error) throw new Error(error.message)
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
        showFlash('✓ 已删除')
      }
      await loadData()
    } catch (e) {
      showFlash('❌ 删除失败：' + e.message)
    }
  }

  return {
    currentYear, currentMonth, currentPage, monthLabel,
    loading, loadError,
    bills, incomeRecords, transportRecords,
    doneBills, pendingBills, filteredBills,
    totalExpense, totalIncome, netBalance,
    platformChartData, payChartData,
    currentFilter,
    flashMsg, flashVisible,
    imgOverlay,
    pendingModal,
    incomeModal,
    incomeCatMap,
    loadData, changeMonth, showFlash,
    openPendingModal, closePendingModal, confirmEntry,
    hasPendingChanges, resetPendingChanges,
    markPendingImageUnavailable,
    openIncomeModal, closeIncomeModal, confirmIncome,
    openImgFull, closeImgFull,
    deleteConfirm, openDeleteConfirm, closeDeleteConfirm, confirmDelete,
  }
}
