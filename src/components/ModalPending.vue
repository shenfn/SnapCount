<template>
  <div class="modal-overlay pending-modal-overlay" :class="{ open: store.pendingModal.open }" @click.self="tryClose">
    <div class="modal-sheet pending-repair-sheet" ref="sheetEl"
      :class="{ unsaved: showUnsaved }">
      <div class="sheet-drag-zone">
        <div class="sheet-handle"></div>
      </div>

      <header class="pending-stage-topbar">
        <button type="button" class="pending-stage-close" aria-label="关闭账单补全" @click="tryClose">×</button>
        <div class="pending-stage-state" :class="{ complete: isCompletedBill }">
          <i></i>{{ billStatusLabel }} · 账单补全
        </div>
        <div class="pending-stage-counter">{{ billPositionText }}</div>
      </header>

      <header class="sheet-header pending-sheet-header">
        <div class="pending-sheet-title-row">
          <div>
            <div class="sheet-title">{{ sheetTitle }}</div>
            <div class="sheet-sub">{{ sheetSubtitle }}</div>
          </div>
          <span class="pending-missing-count" :class="{ ready: !missingFields.length }">
            {{ headerStatusText }}
          </span>
        </div>
      </header>

      <div class="sheet-body pending-sheet-body" ref="bodyEl">
        <section class="pending-evidence-section"
          :class="{ 'has-open-fields': missingFields.length || showAllFields }"
          aria-labelledby="pending-evidence-title">
          <div class="pending-section-heading pending-evidence-heading">
            <div>
              <span class="pending-section-eyebrow" id="pending-evidence-title">证据底片</span>
              <strong>{{ evidenceLabel }}</strong>
            </div>
            <button v-if="store.pendingModal.bill?.image_url" type="button" class="pending-evidence-action"
              @click="store.openImgFull(store.pendingModal.bill.image_url)">
              查看原图
            </button>
          </div>

          <div class="pending-evidence-carousel">
            <button type="button" class="pending-evidence-page previous" :disabled="!canMoveBill(-1)" aria-label="上一笔账单" @click="requestMoveBill(-1)">‹</button>
            <div class="pending-evidence-frame">
              <div v-if="store.pendingModal.bill?.imageLoading" class="pending-evidence-stage pending-evidence-loading" aria-live="polite">
                <span class="pending-loading-mark" aria-hidden="true"></span>
                <strong>正在准备原图</strong>
                <span>文字信息已经可以先看</span>
              </div>
              <button v-else-if="store.pendingModal.bill?.image_url" type="button" class="pending-evidence-stage has-image"
                :class="{ 'is-loading': !evidenceImageReady }"
                @click="store.openImgFull(store.pendingModal.bill.image_url)">
                <span v-if="!evidenceImageReady" class="pending-evidence-image-loading" aria-live="polite">
                  <span class="pending-loading-mark" aria-hidden="true"></span>
                  <strong>正在加载原图</strong>
                </span>
                <img :src="store.pendingModal.bill.image_url" decoding="async" fetchpriority="high"
                  :alt="`${displayMerchant}账单原图`"
                  @load="evidenceImageReady = true"
                  @error="markEvidenceUnavailable">
                <span class="pending-evidence-badge">原图证据</span>
                <span class="pending-evidence-zoom">放大查看</span>
              </button>
              <div v-else class="pending-evidence-stage fact-stage">
                <div class="pending-fact-stage-head">
                  <span class="pending-fact-kicker">{{ store.pendingModal.bill?.imageLoadError ? '原图暂不可用' : '原图未保留' }}</span>
                  <span class="pending-fact-domain">账单事实</span>
                </div>
                <div class="pending-fact-main">
                  <strong>{{ displayMerchant }}</strong>
                  <span :class="{ income: store.pendingModal.entryType === 'income' }">{{ signedAmount }}</span>
                </div>
                <div class="pending-fact-rows">
                  <div v-for="row in factRows" :key="row.label" class="pending-fact-row">
                    <span>{{ row.label }}</span>
                    <strong>{{ row.value }}</strong>
                  </div>
                </div>
              </div>
            </div>
            <button type="button" class="pending-evidence-page next" :disabled="!canMoveBill(1)" aria-label="下一笔账单" @click="requestMoveBill(1)">›</button>
          </div>

          <div class="pending-evidence-meta" role="list" aria-label="账单时间信息">
            <div role="listitem">
              <span>账单时间</span>
              <strong>{{ recordTimeText }}</strong>
            </div>
            <div role="listitem">
              <span>导入时间</span>
              <strong>{{ uploadedTimeText }}</strong>
            </div>
          </div>
        </section>

        <div v-if="needsOverallReview" class="pending-overall-review" role="note">
          <strong>信息已经齐了</strong>
          <span>这次识别需要你看一眼；不对再点“调整”。</span>
        </div>

        <section v-if="missingFields.length || showAllFields"
          class="pending-form-section pending-review-fields"
          aria-labelledby="pending-review-title">
          <div class="pending-section-heading">
            <div>
              <span class="pending-section-eyebrow" id="pending-review-title">
                {{ showAllFields ? '调整账单信息' : '只补不确定的' }}
              </span>
              <strong>{{ showAllFields ? '核对并调整识别结果' : `需要你确认 ${missingFields.length} 项` }}</strong>
            </div>
            <span class="pending-section-note">补完后会进入财务统计</span>
          </div>

          <div v-if="showAllFields || missingFields.includes('金额')"
            class="pending-amount-field"
            :class="{ income: store.pendingModal.entryType === 'income' }">
            <span class="pending-amount-sign">{{ store.pendingModal.entryType === 'income' ? '+' : '-' }}¥</span>
            <input type="number" v-model="store.pendingModal.amount"
              aria-label="账单金额" min="0.01" max="999999.99" step="0.01" placeholder="0.00">
            <span class="pending-amount-unit">人民币</span>
          </div>

          <div v-if="showAllFields" class="pending-type-switch" role="group" aria-label="记录类型">
            <button type="button" :class="{ active: store.pendingModal.entryType === 'expense' }"
              @click="store.pendingModal.entryType = 'expense'">支出</button>
            <button type="button" :class="{ active: store.pendingModal.entryType === 'income' }"
              @click="store.pendingModal.entryType = 'income'">收入</button>
          </div>

          <label v-if="showAllFields" class="pending-text-field">
            <span>{{ store.pendingModal.entryType === 'income' ? '来源名称' : '商家名称' }}<small>可选</small></span>
            <input type="text" v-model="store.pendingModal.merchantName"
              :placeholder="store.pendingModal.entryType === 'income' ? '如：工资、转账方或项目名' : '如：麦当劳、京东购物'" maxlength="50">
          </label>

          <template v-if="store.pendingModal.entryType === 'expense'">
            <div v-if="showAllFields || !store.pendingModal.platform"
              class="pending-choice-group" :class="{ missing: !store.pendingModal.platform }">
              <div class="pending-choice-label"><span>消费渠道</span><em v-if="!store.pendingModal.platform">待补充</em></div>
              <div class="pending-choice-grid">
                <button v-for="p in platforms" :key="p.val" type="button" class="sel-chip"
                  :class="{ selected: store.pendingModal.platform === p.val }"
                  :aria-pressed="store.pendingModal.platform === p.val"
                  @click="selectFinanceOption('platform', p.val)">
                  {{ p.label }}<span v-if="p.hot" class="hot-badge">常用</span>
                </button>
                <button type="button" class="sel-chip pending-custom-trigger"
                  :aria-expanded="customOptionKind === 'platform'"
                  @click="openCustomOption('platform')">＋ 自定义渠道</button>
              </div>
              <div v-if="customOptionKind === 'platform'" class="pending-custom-option">
                <input v-model="customOptionValue" type="text" maxlength="30" placeholder="输入其他消费渠道"
                  aria-label="自定义消费渠道" @keydown.enter.prevent="applyCustomOption">
                <button type="button" :disabled="!customOptionValue.trim()" @click="applyCustomOption">使用</button>
              </div>
            </div>

            <div v-if="showAllFields || !store.pendingModal.category"
              class="pending-choice-group" :class="{ missing: !store.pendingModal.category }">
              <div class="pending-choice-label"><span>消费分类</span><em v-if="!store.pendingModal.category">待补充</em></div>
              <div class="pending-choice-grid">
                <button v-for="c in categories" :key="c.val" type="button" class="sel-chip"
                  :class="{ selected: store.pendingModal.category === c.val }"
                  :aria-pressed="store.pendingModal.category === c.val"
                  @click="selectFinanceOption('category', c.val)">{{ c.label }}</button>
              </div>
            </div>

            <div v-if="showAllFields || !store.pendingModal.payment"
              class="pending-choice-group" :class="{ missing: !store.pendingModal.payment }">
              <div class="pending-choice-label"><span>支付方式</span><em v-if="!store.pendingModal.payment">待补充</em></div>
              <div class="pending-choice-grid">
                <button v-for="p in payments" :key="p.val" type="button" class="sel-chip"
                  :class="{ selected: store.pendingModal.payment === p.val }"
                  :aria-pressed="store.pendingModal.payment === p.val"
                  @click="selectFinanceOption('payment', p.val)">
                  {{ p.label }}<span v-if="p.hot" class="hot-badge">常用</span>
                </button>
                <button type="button" class="sel-chip pending-custom-trigger"
                  :aria-expanded="customOptionKind === 'payment'"
                  @click="openCustomOption('payment')">＋ 自定义方式</button>
              </div>
              <div v-if="customOptionKind === 'payment'" class="pending-custom-option">
                <input v-model="customOptionValue" type="text" maxlength="30" placeholder="输入其他支付方式"
                  aria-label="自定义支付方式" @keydown.enter.prevent="applyCustomOption">
                <button type="button" :disabled="!customOptionValue.trim()" @click="applyCustomOption">使用</button>
              </div>
            </div>
          </template>

          <div v-else-if="showAllFields || !store.pendingModal.incomeCategory"
            class="pending-choice-group" :class="{ missing: !store.pendingModal.incomeCategory }">
            <div class="pending-choice-label"><span>收入类型</span><em v-if="!store.pendingModal.incomeCategory">待补充</em></div>
            <div class="pending-choice-grid">
              <button v-for="item in incomeTypes" :key="item.val" type="button" class="sel-chip"
                :class="{ selected: store.pendingModal.incomeCategory === item.val }"
                :aria-pressed="store.pendingModal.incomeCategory === item.val"
                @click="store.pendingModal.incomeCategory = item.val">
                {{ item.label }}<span v-if="item.hot" class="hot-badge">常用</span>
              </button>
            </div>
          </div>
        </section>

        <section class="pending-known-line" aria-label="已识别账单摘要">
          <div>
            <span>{{ needsOverallReview ? '请重点核对' : '已识别' }}</span>
            <strong>{{ recognizedSummary }}</strong>
          </div>
          <button type="button" :aria-expanded="showAllFields" @click="showAllFields = !showAllFields">
            {{ showAllFields ? '收起' : '调整' }}
          </button>
        </section>

        <section class="pending-account-section" aria-labelledby="pending-account-title">
          <div class="pending-account-summary">
            <div>
              <span id="pending-account-title">账户影响</span>
              <strong>{{ accountImpact.title }}</strong>
              <small>{{ accountImpact.detail }}</small>
            </div>
            <button type="button" :aria-expanded="showAccountPicker" @click="showAccountPicker = !showAccountPicker">
              {{ showAccountPicker ? '收起' : '更改' }}
            </button>
          </div>

          <AccountPicker v-if="showAccountPicker"
            :label="store.pendingModal.entryType === 'income' ? '到账账户' : '出资账户'"
            :kind="store.pendingModal.entryType"
            :selected-id="store.pendingModal.accountId"
            :unbound="store.pendingModal.accountUnbound"
            :amount="store.pendingModal.amount"
            @update:selectedId="store.pendingModal.accountId = $event"
            @update:unbound="store.pendingModal.accountUnbound = $event"
          />

          <div v-if="showAccountPicker && (review.candidates.length || review.reviewReason)"
            class="pending-account-review" aria-label="账户确认线索">
            <div class="pending-account-review-head">
              <strong>为什么推荐这个账户</strong>
              <span v-if="review.confidenceText">把握度 {{ review.confidenceText }}</span>
            </div>
            <div class="pending-account-review-reason">{{ review.reviewReason }}</div>
            <div v-if="review.hint?.rawText" class="pending-account-review-hint">
              原图线索：{{ review.hint.rawText }}
            </div>
            <div v-if="review.candidates.length" class="pending-account-review-list">
              <div v-for="candidate in review.candidates" :key="candidate.account.id" class="pending-account-review-item">
                <div>
                  <strong>{{ candidate.account.name }}</strong>
                  <span>{{ candidate.reason }}</span>
                </div>
                <em>{{ Math.round(candidate.score * 100) }}分 · {{ candidate.confidenceLabel }}</em>
              </div>
            </div>
          </div>
        </section>

        <AiFeedbackCard v-if="aiFeedback" :feedback="aiFeedback" compact class="pending-ai-feedback" />
      </div>

      <div class="sheet-footer pending-sheet-footer">
        <div class="pending-footer-actions">
          <button type="button" class="delete-bill-btn pending-delete-btn"
            @click="store.openDeleteConfirm('bill', store.pendingModal.bill?.id, store.pendingModal.bill?.image_path)">
            删除
          </button>
          <button type="button" class="confirm-btn pending-save-btn"
            :disabled="saveDisabled"
            @click="doSave">
            <span>{{ currentSavePending ? '保存中...' : saveLabel }}</span>
            <small>{{ saveSupportText }}</small>
          </button>
        </div>
      </div>

      <div v-if="showUnsaved" class="unsaved-bar">
        <span class="unsaved-text">内容未保存，确认退出？</span>
        <button type="button" class="unsaved-cancel" @click="showUnsaved = false">继续编辑</button>
        <button type="button" class="unsaved-confirm" @click="doForceClose">{{ pendingNavigationOffset ? '放弃并切换' : '退出' }}</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, inject, ref, watch, onUnmounted } from 'vue'
import AccountPicker from './AccountPicker.vue'
import AiFeedbackCard from './AiFeedbackCard.vue'
import { buildAdaptiveFinanceOptions, normalizeFinanceOptionValue } from '../domains/financeReviewOptions'
const store = inject('store')
const review = computed(() => store.pendingAccountReview(store.pendingModal.entryType, store.pendingModal.bill))
const evidenceImageReady = ref(false)
const pendingNavigationOffset = ref(0)
const showAllFields = ref(false)
const showAccountPicker = ref(false)
const customOptionKind = ref('')
const customOptionValue = ref('')

const aiFeedback = computed(() => {
  const bill = store.pendingModal.bill
  if (!bill) return null
  return bill.aiFeedback || bill.ai_feedback || bill.extracted_json?.ai_feedback || bill.payload?.ai_feedback || null
})

const isCompletedBill = computed(() => store.pendingModal.bill?.status === 'done')
const billQueue = computed(() => {
  const current = store.pendingModal.bill
  if (!current) return []
  if (isCompletedBill.value) return [current]
  const pending = store.pendingBills.value
  return pending.some(item => item.id === current.id) ? pending : [current, ...pending]
})
const billIndex = computed(() => billQueue.value.findIndex(item => item.id === store.pendingModal.bill?.id))
const billPositionText = computed(() => {
  const index = billIndex.value
  return index >= 0 ? `${index + 1} / ${billQueue.value.length}` : '1 / 1'
})
const sheetTitle = computed(() => {
  if (isCompletedBill.value) return '编辑账单信息'
  if (missingFields.value.length === 1) return `补上${missingFields.value[0]}`
  if (missingFields.value.length > 1) return `还差 ${missingFields.value.length} 项信息`
  return '核对后收下'
})
const sheetSubtitle = computed(() => {
  if (isCompletedBill.value) return '调整后会同步更新财务统计'
  if (store.pendingModal.entryType === 'income') return '补完整后会计入收入；选择账户后余额会同步'
  return '补完整后会正确归类；选择账户后余额会同步'
})
const billStatusLabel = computed(() => isCompletedBill.value ? '已入账' : '待补充')
const evidenceLabel = computed(() => {
  if (store.pendingModal.bill?.imageLoading) return '正在获取原图证据'
  if (store.pendingModal.bill?.image_url) return '以原图为准核对'
  if (store.pendingModal.bill?.imageLoadError) return '原图暂不可用，按文字核对'
  return '原图未保留，按文字核对'
})
const displayMerchant = computed(() => {
  const edited = String(store.pendingModal.merchantName || '').trim()
  const recognized = String(store.pendingModal.bill?.name || '').trim()
  if (edited) return edited
  if (recognized && recognized !== '未识别商家') return recognized
  return store.pendingModal.entryType === 'income' ? '未填写来源' : '未识别商家'
})
const signedAmount = computed(() => {
  const amount = Number(store.pendingModal.amount || store.pendingModal.bill?.amount || 0)
  const sign = store.pendingModal.entryType === 'income' ? '+' : '-'
  return `${sign}¥${Number.isFinite(amount) ? amount.toFixed(2) : '0.00'}`
})
const financeVocabulary = computed(() => store.financeVocabulary?.value || [])
const platforms = computed(() => buildAdaptiveFinanceOptions({
  kind: 'platform',
  currentValue: store.pendingModal.platform,
  vocabulary: financeVocabulary.value,
}))
const categories = computed(() => buildAdaptiveFinanceOptions({
  kind: 'category',
  currentValue: store.pendingModal.category,
  vocabulary: financeVocabulary.value,
}))
const payments = computed(() => buildAdaptiveFinanceOptions({
  kind: 'payment',
  currentValue: store.pendingModal.payment,
  vocabulary: financeVocabulary.value,
}))
const factRows = computed(() => {
  if (store.pendingModal.entryType === 'income') {
    return [
      { label: '收入类型', value: summaryOptionLabel(incomeTypes, store.pendingModal.incomeCategory) },
      { label: '记录状态', value: isCompletedBill.value ? '已入账' : '待补充' },
    ]
  }
  return [
    { label: '消费渠道', value: summaryOptionLabel(platforms.value, store.pendingModal.platform) },
    { label: '消费分类', value: summaryOptionLabel(categories.value, store.pendingModal.category) },
    { label: '支付方式', value: summaryOptionLabel(payments.value, store.pendingModal.payment) },
  ]
})
const recordTimeText = computed(() => {
  const bill = store.pendingModal.bill
  const parts = [bill?.date || bill?.dateRaw, bill?.time].filter(Boolean)
  return parts.length ? parts.join(' · ') : '未记录'
})
const uploadedTimeText = computed(() => formatDateTime(
  store.pendingModal.bill?.createdAt
    || store.pendingModal.bill?.created_at
    || store.pendingModal.bill?.uploadedAt
    || store.pendingModal.bill?.uploaded_at,
))
const missingFields = computed(() => {
  const fields = []
  const amount = Number(store.pendingModal.amount)
  if (!Number.isFinite(amount) || amount <= 0 || amount > 999999.99) fields.push('金额')
  if (store.pendingModal.entryType === 'income') {
    if (!store.pendingModal.incomeCategory) fields.push('收入类型')
    return fields
  }
  if (!store.pendingModal.platform) fields.push('消费渠道')
  if (!store.pendingModal.category) fields.push('消费分类')
  if (!store.pendingModal.payment) fields.push('支付方式')
  return fields
})
const needsOverallReview = computed(() => !isCompletedBill.value && missingFields.value.length === 0)
const headerStatusText = computed(() => {
  if (isCompletedBill.value) return '已入账'
  if (missingFields.value.length) return `${missingFields.value.length} 项待补`
  return '请核对'
})
const recognizedSummary = computed(() => {
  const parts = []
  const amount = Number(store.pendingModal.amount)
  if (Number.isFinite(amount) && amount > 0 && amount <= 999999.99) parts.push(`¥${amount.toFixed(2)}`)

  const merchant = String(displayMerchant.value || '').trim()
  if (merchant && !['未识别商家', '未填写来源'].includes(merchant)) parts.push(merchant)

  if (store.pendingModal.entryType === 'income') {
    if (store.pendingModal.incomeCategory) {
      parts.push(summaryOptionLabel(incomeTypes, store.pendingModal.incomeCategory))
    }
  } else {
    if (store.pendingModal.platform) parts.push(summaryOptionLabel(platforms.value, store.pendingModal.platform))
    if (store.pendingModal.category) parts.push(summaryOptionLabel(categories.value, store.pendingModal.category))
    if (store.pendingModal.payment) parts.push(summaryOptionLabel(payments.value, store.pendingModal.payment))
  }

  return parts.length ? parts.join(' · ') : '还没有可确认的信息'
})
const accountImpact = computed(() => store.balanceImpactPreview({
  kind: store.pendingModal.entryType,
  accountId: store.pendingModal.accountId,
  amount: store.pendingModal.amount,
  unbound: store.pendingModal.accountUnbound,
}))
const hasAnotherBill = computed(() => billQueue.value.some(item => item.id !== store.pendingModal.bill?.id))
const currentSavePending = computed(() => store.isPendingEntrySaving(store.pendingModal.bill?.id))
const saveDisabled = computed(() => currentSavePending.value || missingFields.value.length > 0)
const saveLabel = computed(() => {
  if (isCompletedBill.value) return '保存修改'
  return hasAnotherBill.value ? '补全并下一条' : '补全并收下'
})
const saveSupportText = computed(() => {
  if (currentSavePending.value) return hasAnotherBill.value ? '正在后台保存，马上进入下一条' : '正在后台保存最后一条'
  if (missingFields.value.length) return `还需要补充：${missingFields.value.join('、')}`
  if (isCompletedBill.value) return '更新已入账信息'
  return hasAnotherBill.value ? '保存后自动进入下一条' : '保存后完成本批处理'
})

function optionLabel(options, value) {
  if (!value) return '待补充'
  const match = options.find(item => item.val === value)
  return match?.label || value
}

function summaryOptionLabel(options, value) {
  return optionLabel(options, value).replace(/^[^\u3400-\u9fffA-Za-z0-9]+/, '')
}

function selectFinanceOption(kind, value) {
  const normalized = normalizeFinanceOptionValue(kind, value)
  if (!normalized) return
  store.pendingModal[kind] = normalized
  customOptionKind.value = ''
  customOptionValue.value = ''
}

function openCustomOption(kind) {
  if (customOptionKind.value === kind) {
    customOptionKind.value = ''
    customOptionValue.value = ''
    return
  }
  customOptionKind.value = kind
  customOptionValue.value = ''
}

function applyCustomOption() {
  if (!customOptionKind.value) return
  selectFinanceOption(customOptionKind.value, customOptionValue.value)
}

function formatDateTime(value) {
  if (!value) return '未记录'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return String(value)
  return new Intl.DateTimeFormat('zh-CN', {
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date)
}

function canMoveBill(offset) {
  if (currentSavePending.value) return false
  const nextIndex = billIndex.value + offset
  return nextIndex >= 0 && nextIndex < billQueue.value.length
}

function moveBill(offset) {
  if (!canMoveBill(offset)) return
  const nextBill = billQueue.value[billIndex.value + offset]
  if (nextBill) store.openPendingModal(nextBill)
}

function requestMoveBill(offset) {
  if (!canMoveBill(offset)) return
  if (store.hasPendingChanges()) {
    pendingNavigationOffset.value = offset
    showUnsaved.value = true
    return
  }
  moveBill(offset)
}

function warmEvidenceImage(url, onReady) {
  if (!url) return
  const image = new Image()
  image.decoding = 'async'
  image.onload = () => onReady?.()
  image.src = url
  if (image.complete && image.naturalWidth > 0) onReady?.()
}

function markEvidenceUnavailable() {
  evidenceImageReady.value = true
  store.markPendingImageUnavailable()
}

const sheetEl = ref(null)
const bodyEl = ref(null)
const showUnsaved = ref(false)
const isSwiping = ref(false)
const isClosing = ref(false)
const swipeDir = ref(null)

watch(() => store.pendingModal.bill?.id, () => {
  showAllFields.value = false
  showAccountPicker.value = false
  customOptionKind.value = ''
  customOptionValue.value = ''
  pendingNavigationOffset.value = 0
  showUnsaved.value = false
  if (bodyEl.value) bodyEl.value.scrollTop = 0
})

let touchStartY = 0
let touchStartX = 0
let touchStartTime = 0
let bodyScrollY = 0
let originalBodyOverflow = ''
let originalBodyPosition = ''
let originalBodyTop = ''
let originalBodyWidth = ''

function lockBodyScroll() {
  bodyScrollY = window.scrollY
  originalBodyOverflow = document.body.style.overflow
  originalBodyPosition = document.body.style.position
  originalBodyTop = document.body.style.top
  originalBodyWidth = document.body.style.width
  document.body.style.overflow = 'hidden'
  document.body.style.position = 'fixed'
  document.body.style.top = `-${bodyScrollY}px`
  document.body.style.width = '100%'
}

function unlockBodyScroll() {
  document.body.style.overflow = originalBodyOverflow
  document.body.style.position = originalBodyPosition
  document.body.style.top = originalBodyTop
  document.body.style.width = originalBodyWidth
  window.scrollTo(0, bodyScrollY)
}

watch(() => store.pendingModal.open, open => {
  if (open) {
    lockBodyScroll()
    showUnsaved.value = false
    pendingNavigationOffset.value = 0
  }
  else unlockBodyScroll()
})

watch(() => [store.pendingModal.bill?.id, store.pendingModal.bill?.image_url], ([billId, imageUrl]) => {
  evidenceImageReady.value = !imageUrl
  if (!billId || !imageUrl) return
  warmEvidenceImage(imageUrl, () => {
    if (store.pendingModal.bill?.id === billId) evidenceImageReady.value = true
  })
  const index = billIndex.value
  warmEvidenceImage(billQueue.value[index - 1]?.imageUrl)
  warmEvidenceImage(billQueue.value[index + 1]?.imageUrl)
})

onUnmounted(unlockBodyScroll)

function isScrollAtTop() {
  if (!bodyEl.value) return true
  return bodyEl.value.scrollTop <= 1
}

function isInteractiveTarget(target) {
  return !!target.closest('input, button, img, .sel-chip, .thumb-wrap, .confirm-btn, .delete-bill-btn, .unsaved-bar')
}

function tryClose() {
  pendingNavigationOffset.value = 0
  if (store.hasPendingChanges()) {
    showUnsaved.value = true
    return
  }
  store.closePendingModal()
}

function doForceClose() {
  const navigationOffset = pendingNavigationOffset.value
  showUnsaved.value = false
  pendingNavigationOffset.value = 0
  store.resetPendingChanges()
  if (navigationOffset) moveBill(navigationOffset)
  else store.closePendingModal()
}

async function doSave() {
  const currentBillId = store.pendingModal.bill?.id
  const currentIndex = billIndex.value
  const queueSnapshot = [...billQueue.value]
  const nextBill = queueSnapshot[currentIndex + 1]
    || queueSnapshot.find(item => item.id !== currentBillId)
    || null

  if (isCompletedBill.value) {
    const result = await store.confirmEntry()
    if (!result?.ok) return
  } else {
    void store.confirmEntry()
  }

  showUnsaved.value = false
  if (!store.pendingModal.open || store.pendingModal.bill?.id !== currentBillId) return
  if (nextBill) {
    if (bodyEl.value) bodyEl.value.scrollTop = 0
    void store.openPendingModal(nextBill)
    return
  }
  store.closePendingModal()
}

function animateClose(direction) {
  if (!sheetEl.value) return
  isClosing.value = true
  swipeDir.value = direction
  sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
  if (direction === 'down') {
    sheetEl.value.style.transform = 'translateY(110%)'
  } else if (direction === 'right') {
    sheetEl.value.style.transform = 'translateX(110%)'
  }
  setTimeout(() => {
    if (store.hasPendingChanges()) {
      showUnsaved.value = true
      sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
      sheetEl.value.style.transform = ''
      isClosing.value = false
      swipeDir.value = null
    } else {
      store.closePendingModal()
      if (sheetEl.value) {
        sheetEl.value.style.transition = ''
        sheetEl.value.style.transform = ''
      }
      isClosing.value = false
      swipeDir.value = null
    }
  }, 280)
}

function onTouchStart(e) {
  if (!isInteractiveTarget(e.target)) {
    showUnsaved.value = false
  }
  isSwiping.value = false
  isClosing.value = false
  swipeDir.value = null
  touchStartY = e.touches[0].clientY
  touchStartX = e.touches[0].clientX
  touchStartTime = Date.now()
  if (sheetEl.value) sheetEl.value.style.transition = 'none'
}

function onTouchMove(e) {
  if (isClosing.value) return
  const deltaY = e.touches[0].clientY - touchStartY
  const deltaX = e.touches[0].clientX - touchStartX
  const absX = Math.abs(deltaX)
  const absY = Math.abs(deltaY)

  if (absX < 8 && absY < 8) return

  if (absX > absY * 1.5 && absX > 20) {
    if (isInteractiveTarget(e.target)) return
    e.preventDefault()
    isSwiping.value = true
    swipeDir.value = 'right'
    if (sheetEl.value) {
      sheetEl.value.style.transform = `translateX(${Math.min(absX, window.innerWidth * 0.6)}px)`
    }
    return
  }

  if (absY > absX * 1.2 && deltaY > 0) {
    if (!isScrollAtTop()) return
    if (isInteractiveTarget(e.target)) return
    e.preventDefault()
    isSwiping.value = true
    swipeDir.value = 'down'
    if (sheetEl.value) {
      sheetEl.value.style.transform = `translateY(${Math.min(deltaY, window.innerHeight * 0.5)}px)`
    }
  }
}

function onTouchEnd(e) {
  if (!isSwiping.value || !sheetEl.value) {
    isSwiping.value = false
    swipeDir.value = null
    return
  }

  if (swipeDir.value === 'right') {
    const deltaX = Math.abs(e.changedTouches[0].clientX - touchStartX)
    const elapsed = Math.max(1, Date.now() - touchStartTime)
    const velocity = deltaX / elapsed
    const shouldClose = deltaX > 80 || velocity > 0.4
    if (shouldClose) {
      animateClose('right')
    } else {
      sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
      sheetEl.value.style.transform = ''
    }
  } else if (swipeDir.value === 'down') {
    const deltaY = e.changedTouches[0].clientY - touchStartY
    const elapsed = Math.max(1, Date.now() - touchStartTime)
    const velocity = deltaY / elapsed
    const distanceThreshold = Math.max(100, window.innerHeight * 0.22)
    const shouldClose = deltaY > distanceThreshold || velocity > 0.5
    if (shouldClose) {
      animateClose('down')
    } else {
      sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
      sheetEl.value.style.transform = ''
    }
  }

  isSwiping.value = false
  swipeDir.value = null
}

const incomeTypes = [
  { val: 'salary',        label: '💼 工资', hot: true },
  { val: 'bonus',         label: '🎁 奖金' },
  { val: 'freelance',     label: '💻 兼职' },
  { val: 'investment',    label: '📈 投资收益' },
  { val: 'reimbursement', label: '🧾 报销' },
  { val: 'other',         label: '💰 其他' },
]
</script>

<style scoped>
.pending-modal-overlay {
  background: rgba(23, 49, 45, 0.42);
  backdrop-filter: blur(6px);
}

.pending-repair-sheet {
  max-height: min(94vh, 860px);
  max-height: min(94dvh, 860px);
  border-radius: 28px 28px 0 0;
  background:
    radial-gradient(220px 180px at 92% 0%, rgba(220, 191, 116, 0.16), transparent 72%),
    linear-gradient(175deg, #f5f1e7 0%, #f1ecdf 100%);
  box-shadow: 0 -18px 50px rgba(23, 49, 45, 0.2);
}

.pending-sheet-header {
  padding: 10px 20px 12px;
  border-bottom: 1px solid rgba(66, 110, 99, 0.13);
  background: transparent;
}

.pending-sheet-kicker,
.pending-sheet-title-row,
.pending-section-heading,
.pending-evidence-meta,
.pending-fact-stage-head,
.pending-fact-main,
.pending-choice-label {
  display: flex;
  align-items: center;
}

.pending-sheet-kicker {
  justify-content: space-between;
  color: #6e7773;
  font-size: 11px;
  letter-spacing: 0;
}

.pending-sheet-status,
.pending-missing-count {
  display: inline-flex;
  align-items: center;
  min-height: 24px;
  padding: 4px 8px;
  border: 1px solid rgba(183, 101, 85, 0.22);
  border-radius: 8px;
  color: #9a5547;
  background: rgba(183, 101, 85, 0.08);
  font-size: 11px;
  letter-spacing: 0;
}

.pending-sheet-status.complete,
.pending-missing-count.ready {
  border-color: rgba(66, 110, 99, 0.2);
  color: #426e63;
  background: rgba(66, 110, 99, 0.08);
}

.pending-sheet-title-row {
  justify-content: space-between;
  gap: 16px;
  margin-top: 0;
}

.pending-sheet-title-row .sheet-title {
  color: #202a27;
  font-family: "Songti SC", "STSong", "Noto Serif SC", serif;
  font-size: 18px;
  font-weight: 600;
  letter-spacing: 0;
}

.pending-sheet-title-row .sheet-sub {
  max-width: 360px;
  margin-top: 3px;
  color: #6e7773;
  font-size: 11px;
  line-height: 1.45;
}

.pending-sheet-mark {
  display: grid;
  width: 42px;
  height: 42px;
  flex: 0 0 auto;
  place-items: center;
  border: 1px solid rgba(66, 110, 99, 0.18);
  border-radius: 14px;
  color: #426e63;
  font-size: 24px;
  line-height: 1;
  background: rgba(255, 255, 255, 0.34);
}

.pending-sheet-body {
  padding-bottom: 20px;
  scrollbar-width: thin;
  scrollbar-color: rgba(66, 110, 99, 0.25) transparent;
}

.pending-evidence-section,
.pending-form-section,
.pending-account-section {
  padding: 12px 20px 0;
}

.pending-evidence-section {
  container-type: inline-size;
}

.pending-section-heading {
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 8px;
}

.pending-section-heading > div {
  display: grid;
  gap: 3px;
  min-width: 0;
}

.pending-section-heading strong {
  color: #202a27;
  font-size: 15px;
  font-weight: 650;
}

.pending-section-eyebrow {
  color: #6e7773;
  font-size: 10px;
  letter-spacing: 0;
  line-height: 1.2;
}

.pending-section-note {
  flex: 0 0 auto;
  max-width: 48%;
  color: #6e7773;
  font-size: 11px;
  line-height: 1.35;
  text-align: right;
}

.pending-evidence-heading {
  margin-bottom: 7px;
}

.pending-evidence-action {
  border: 0;
  padding: 4px 0;
  color: #426e63;
  background: transparent;
  font: 600 12px/1.2 var(--font);
  cursor: pointer;
}

.pending-evidence-stage {
  position: relative;
  display: block;
  width: 100%;
  min-height: 220px;
  aspect-ratio: 4 / 3;
  max-height: min(40vh, 360px);
  overflow: hidden;
  border: 1px solid rgba(66, 110, 99, 0.16);
  border-radius: 20px;
  padding: 0;
  color: inherit;
  background: #e3dfd2;
  cursor: pointer;
}

.pending-evidence-stage.has-image {
  box-shadow: 0 10px 24px rgba(23, 49, 45, 0.1);
}

.pending-evidence-loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: #6e7773;
  background: rgba(255, 255, 255, 0.34);
  cursor: default;
}

.pending-evidence-loading strong {
  color: #202a27;
  font-size: 14px;
}

.pending-evidence-loading > span:last-child {
  max-width: 240px;
  font-size: 11px;
  line-height: 1.55;
  text-align: center;
}

.pending-loading-mark {
  width: 24px;
  height: 24px;
  border: 2px solid rgba(66, 110, 99, 0.2);
  border-top-color: #426e63;
  border-radius: 50%;
  animation: pending-image-spin 800ms linear infinite;
}

@keyframes pending-image-spin {
  to { transform: rotate(360deg); }
}

.pending-evidence-stage.has-image img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: #202a27;
}

.pending-evidence-badge,
.pending-evidence-zoom {
  position: absolute;
  display: inline-flex;
  align-items: center;
  min-height: 24px;
  padding: 4px 8px;
  border-radius: 8px;
  color: #f5f1e7;
  background: rgba(23, 49, 45, 0.72);
  font-size: 11px;
  line-height: 1;
}

.pending-evidence-badge {
  top: 10px;
  left: 10px;
}

.pending-evidence-zoom {
  right: 10px;
  bottom: 10px;
}

.pending-evidence-stage.fact-stage {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 16px;
  padding: 20px;
  text-align: left;
  background:
    linear-gradient(135deg, rgba(255, 255, 255, 0.52), transparent 52%),
    #e9e4d7;
  cursor: default;
}

.pending-evidence-section .pending-evidence-stage.fact-stage {
  height: auto;
  min-height: 0;
  max-height: none;
  aspect-ratio: auto;
  gap: 10px;
  padding: 14px 16px;
}

.pending-evidence-section .pending-evidence-stage.fact-stage .pending-fact-rows {
  gap: 5px;
}

.pending-evidence-section .pending-evidence-stage.fact-stage .pending-fact-row {
  padding-top: 6px;
}

.pending-fact-stage-head {
  justify-content: space-between;
  gap: 12px;
}

.pending-fact-kicker,
.pending-fact-domain {
  color: #6e7773;
  font-size: 11px;
}

.pending-fact-domain {
  padding: 4px 7px;
  border-radius: 7px;
  color: #426e63;
  background: rgba(66, 110, 99, 0.1);
}

.pending-fact-main {
  justify-content: space-between;
  gap: 14px;
}

.pending-fact-main strong {
  min-width: 0;
  overflow: hidden;
  color: #202a27;
  font-size: 18px;
  font-weight: 650;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pending-fact-main > span {
  flex: 0 0 auto;
  color: #b76555;
  font: 700 20px/1 var(--font-num);
  font-variant-numeric: tabular-nums;
}

.pending-fact-main > span.income {
  color: #426e63;
}

.pending-fact-rows {
  display: grid;
  gap: 8px;
}

.pending-fact-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  padding-top: 8px;
  border-top: 1px dashed rgba(66, 110, 99, 0.16);
  color: #6e7773;
  font-size: 12px;
}

.pending-fact-row strong {
  color: #202a27;
  font-weight: 600;
  text-align: right;
}

.pending-evidence-meta {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
  margin-top: 7px;
  border: 0;
  background: transparent;
}

.pending-evidence-meta > div {
  display: grid;
  gap: 1px;
  min-width: 0;
  padding: 0;
  background: transparent;
}

.pending-evidence-meta > div + div {
  border-left: 0;
}

.pending-evidence-meta span {
  color: #6e7773;
  font-size: 10px;
}

.pending-evidence-meta strong {
  color: #202a27;
  font-size: 11px;
  font-weight: 600;
  line-height: 1.35;
  overflow-wrap: anywhere;
}

.pending-ai-feedback {
  margin: 14px 20px 0;
}

.pending-overall-review {
  display: grid;
  gap: 2px;
  margin: 12px 20px 0;
  padding: 10px 0;
  border-top: 1px solid rgba(220, 191, 116, 0.34);
  border-bottom: 1px solid rgba(220, 191, 116, 0.34);
}

.pending-overall-review strong {
  color: #6f5826;
  font-size: 12px;
}

.pending-overall-review span {
  color: #6e7773;
  font-size: 11px;
  line-height: 1.4;
}

.pending-review-fields,
.pending-account-section {
  border-top: 1px solid rgba(66, 110, 99, 0.12);
}

.pending-review-fields {
  margin-top: 12px;
  padding-top: 14px;
}

.pending-amount-field {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 14px 16px;
  border: 1px solid rgba(183, 101, 85, 0.18);
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.52);
}

.pending-amount-field.income {
  border-color: rgba(66, 110, 99, 0.2);
}

.pending-amount-sign {
  color: #b76555;
  font: 700 28px/1 var(--font-num);
}

.pending-amount-field.income .pending-amount-sign {
  color: #426e63;
}

.pending-amount-field input {
  min-width: 0;
  flex: 1;
  border: 0;
  padding: 0;
  color: #202a27;
  background: transparent;
  font: 700 28px/1 var(--font-num);
  font-variant-numeric: tabular-nums;
  outline: none;
}

.pending-amount-unit {
  color: #6e7773;
  font-size: 11px;
}

.pending-type-switch {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px;
  margin-top: 10px;
  padding: 4px;
  border: 1px solid rgba(66, 110, 99, 0.12);
  border-radius: 12px;
  background: rgba(66, 110, 99, 0.06);
}

.pending-type-switch button {
  min-height: 36px;
  border: 0;
  border-radius: 9px;
  color: #6e7773;
  background: transparent;
  font: 600 13px/1 var(--font);
  cursor: pointer;
}

.pending-type-switch button.active {
  color: #f5f1e7;
  background: #426e63;
  box-shadow: 0 4px 10px rgba(66, 110, 99, 0.18);
}

.pending-text-field {
  display: grid;
  gap: 7px;
  margin-top: 14px;
}

.pending-text-field > span {
  color: #6e7773;
  font-size: 12px;
  font-weight: 600;
}

.pending-text-field small {
  margin-left: 5px;
  color: #9b978f;
  font-size: 10px;
  font-weight: 400;
}

.pending-text-field input {
  width: 100%;
  min-height: 44px;
  border: 1px solid rgba(66, 110, 99, 0.14);
  border-radius: 12px;
  padding: 11px 12px;
  color: #202a27;
  background: rgba(255, 255, 255, 0.5);
  font: 14px/1.3 var(--font);
  outline: none;
}

.pending-text-field input:focus,
.pending-amount-field:focus-within {
  border-color: #426e63;
  box-shadow: 0 0 0 3px rgba(66, 110, 99, 0.12);
}

.pending-choice-group {
  margin-top: 12px;
  padding: 13px;
  border: 1px solid rgba(66, 110, 99, 0.12);
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.3);
}

.pending-choice-group.missing {
  border-color: rgba(183, 101, 85, 0.28);
  background: rgba(183, 101, 85, 0.055);
}

.pending-choice-label {
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 10px;
  color: #202a27;
  font-size: 12px;
  font-weight: 650;
}

.pending-choice-label em {
  color: #b76555;
  font-size: 10px;
  font-style: normal;
  font-weight: 500;
}

.pending-choice-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 7px;
}

.pending-choice-grid .sel-chip {
  min-height: 34px;
  border: 1px solid rgba(66, 110, 99, 0.14);
  border-radius: 10px;
  padding: 7px 10px;
  color: #6e7773;
  background: rgba(245, 241, 231, 0.7);
  font: 12px/1.2 var(--font);
  cursor: pointer;
  transition: transform 160ms ease, border-color 160ms ease, background 160ms ease, color 160ms ease;
}

.pending-choice-grid .sel-chip:active {
  transform: scale(0.97);
}

.pending-choice-grid .sel-chip.selected {
  border-color: #426e63;
  color: #f5f1e7;
  background: #426e63;
}

.pending-choice-grid .hot-badge {
  margin-left: 4px;
  color: #8a6d2f;
  background: rgba(220, 191, 116, 0.2);
}

.pending-choice-grid .sel-chip.selected .hot-badge {
  color: #f5f1e7;
  background: rgba(245, 241, 231, 0.18);
}

.pending-choice-grid .pending-custom-trigger {
  border-style: dashed;
  color: #426e63;
  background: transparent;
}

.pending-custom-option {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 8px;
  margin-top: 9px;
}

.pending-custom-option input {
  min-width: 0;
  min-height: 38px;
  border: 1px solid rgba(66, 110, 99, 0.18);
  border-radius: 10px;
  padding: 8px 10px;
  color: #202a27;
  background: rgba(255, 255, 255, 0.58);
  font: 13px/1.3 var(--font);
  outline: none;
}

.pending-custom-option input:focus {
  border-color: #426e63;
  box-shadow: 0 0 0 3px rgba(66, 110, 99, 0.12);
}

.pending-custom-option button {
  min-width: 54px;
  border: 0;
  border-radius: 10px;
  padding: 0 12px;
  color: #f5f1e7;
  background: #426e63;
  font: 600 12px/1 var(--font);
}

.pending-custom-option button:disabled {
  opacity: 0.42;
}

.pending-account-review {
  display: grid;
  gap: 8px;
  margin: 18px 24px 0;
  padding: 14px;
  border: 1px solid rgba(220, 191, 116, 0.34);
  border-radius: 16px;
  background: rgba(220, 191, 116, 0.1);
}

.pending-known-line {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  margin: 14px 20px 0;
  padding: 12px 0;
  border-top: 1px solid rgba(66, 110, 99, 0.12);
  border-bottom: 1px solid rgba(66, 110, 99, 0.12);
}

.pending-known-line > div {
  display: grid;
  gap: 3px;
  min-width: 0;
}

.pending-known-line span,
.pending-account-summary span {
  color: #6e7773;
  font-size: 10px;
}

.pending-known-line strong {
  color: #202a27;
  font-size: 13px;
  font-weight: 650;
  line-height: 1.45;
  overflow-wrap: anywhere;
}

.pending-known-line button,
.pending-account-summary button {
  min-width: 48px;
  min-height: 32px;
  flex: 0 0 auto;
  border: 1px solid rgba(66, 110, 99, 0.16);
  border-radius: 9px;
  padding: 6px 10px;
  color: #426e63;
  background: rgba(66, 110, 99, 0.07);
  font: 600 12px/1 var(--font);
  cursor: pointer;
}

.pending-account-summary {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
}

.pending-account-summary > div {
  display: grid;
  gap: 2px;
  min-width: 0;
}

.pending-account-summary strong {
  color: #202a27;
  font-size: 13px;
  font-weight: 650;
  line-height: 1.35;
}

.pending-account-summary small {
  color: #6e7773;
  font-size: 10px;
  line-height: 1.4;
  overflow-wrap: anywhere;
}

.pending-account-section .pending-account-review {
  margin: 12px 0 0;
}

.pending-account-review-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.pending-account-review-head strong {
  color: #4f452d;
  font-size: 13px;
}

.pending-account-review-head span,
.pending-account-review-reason,
.pending-account-review-hint,
.pending-account-review-item span,
.pending-account-review-item em {
  color: #6e7773;
  font-size: 11px;
  line-height: 1.5;
}

.pending-account-review-list {
  display: grid;
  gap: 8px;
}

.pending-account-review-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 10px 12px;
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.48);
}

.pending-account-review-item strong {
  display: block;
  margin-bottom: 2px;
  color: #202a27;
  font-size: 12px;
}

.pending-account-review-item em {
  flex: 0 0 auto;
  color: #8a6d2f;
  font-style: normal;
  white-space: nowrap;
}

.pending-account-section :deep(.account-picker) {
  margin-top: 12px;
}

.pending-account-section :deep(.account-picker-header) {
  margin-bottom: 9px;
}

.pending-account-section :deep(.account-picker-label) {
  color: #202a27;
  font-size: 12px;
  font-weight: 650;
}

.pending-account-section :deep(.account-picker-create) {
  color: #426e63;
}

.pending-account-section :deep(.account-picker-list) {
  gap: 7px;
}

.pending-account-section :deep(.account-picker-chip) {
  min-width: 128px;
  border: 1px solid rgba(66, 110, 99, 0.14);
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.42);
}

.pending-account-section :deep(.account-picker-chip.selected) {
  border-color: #426e63;
  background: #426e63;
}

.pending-account-section :deep(.account-picker-chip.unbind) {
  border-color: rgba(183, 101, 85, 0.18);
  background: rgba(183, 101, 85, 0.08);
}

.pending-account-section :deep(.account-picker-chip.unbind.selected) {
  border-color: #b76555;
  background: #b76555;
}

.pending-account-section :deep(.account-picker-impact) {
  border: 1px solid rgba(66, 110, 99, 0.12);
  background: rgba(66, 110, 99, 0.08);
  color: #426e63;
}

.pending-account-section :deep(.account-picker-impact.unbound) {
  border-color: rgba(183, 101, 85, 0.18);
  background: rgba(183, 101, 85, 0.08);
  color: #9a5547;
}

.pending-sheet-footer {
  padding: 10px 20px calc(12px + env(safe-area-inset-bottom, 0px));
  border-top: 1px solid rgba(66, 110, 99, 0.13);
  background: rgba(245, 241, 231, 0.94);
  backdrop-filter: blur(12px);
}

.pending-footer-actions {
  display: flex;
  align-items: stretch;
  gap: 10px;
}

.pending-save-btn {
  display: grid;
  min-width: 0;
  min-height: 52px;
  flex: 1 1 auto;
  gap: 3px;
  border-radius: 14px;
  padding: 8px 14px;
  background: #426e63;
  box-shadow: 0 8px 16px rgba(66, 110, 99, 0.2);
  transition: transform 160ms ease, opacity 160ms ease, box-shadow 160ms ease;
}

.pending-save-btn span {
  font-size: 15px;
  font-weight: 650;
}

.pending-save-btn small {
  max-width: 100%;
  overflow: hidden;
  color: rgba(245, 241, 231, 0.76);
  font-size: 10px;
  font-weight: 400;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pending-save-btn:active:not(:disabled) {
  transform: translateY(1px) scale(0.99);
}

.pending-save-btn:disabled {
  cursor: not-allowed;
  opacity: 0.48;
  box-shadow: none;
}

.pending-delete-btn {
  width: auto;
  min-width: 64px;
  min-height: 52px;
  flex: 0 0 auto;
  margin-top: 0;
  border: 1px solid rgba(183, 101, 85, 0.22);
  border-radius: 14px;
  padding: 0 14px;
  color: #9a5547;
  background: transparent;
  font-size: 12px;
}

.pending-delete-btn:active {
  background: rgba(183, 101, 85, 0.08);
}

.pending-repair-sheet :focus-visible {
  outline: none;
  box-shadow: 0 0 0 3px rgba(66, 110, 99, 0.2);
}

@media (max-width: 380px) {
  .pending-sheet-header,
  .pending-evidence-section,
  .pending-form-section,
  .pending-account-section {
    padding-right: 18px;
    padding-left: 18px;
  }

  .pending-ai-feedback,
  .pending-account-review {
    margin-right: 18px;
    margin-left: 18px;
  }

  .pending-sheet-footer {
    padding-right: 18px;
    padding-left: 18px;
  }

  .pending-evidence-stage {
    min-height: 190px;
  }

  .pending-fact-main strong {
    font-size: 16px;
  }
}

.pending-modal-overlay {
  align-items: stretch;
  padding: 0;
  background: #dedfd6;
  backdrop-filter: none;
}

.pending-repair-sheet {
  width: min(100%, 760px);
  height: 100vh;
  height: 100dvh;
  max-height: none;
  margin: 0 auto;
  border-radius: 0;
  box-shadow: 0 0 44px rgba(23, 49, 45, 0.16);
  animation: pending-stage-enter 180ms ease-out;
}

@keyframes pending-stage-enter {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

.pending-repair-sheet .sheet-drag-zone {
  display: none;
}

.pending-stage-topbar {
  display: grid;
  grid-template-columns: 42px minmax(0, 1fr) 54px;
  align-items: center;
  min-height: calc(60px + env(safe-area-inset-top, 0px));
  padding: env(safe-area-inset-top, 0px) 18px 0;
  border-bottom: 1px solid rgba(66, 110, 99, 0.1);
  background: rgba(245, 241, 231, 0.96);
}

.pending-stage-close,
.pending-evidence-page {
  display: grid;
  place-items: center;
  border: 0;
  color: #426e63;
  background: rgba(66, 110, 99, 0.08);
}

.pending-stage-close {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  font: 300 30px/1 var(--font);
}

.pending-stage-state {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: center;
  gap: 7px;
  overflow: hidden;
  color: #8a6d2f;
  font-size: 13px;
  font-weight: 700;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pending-stage-state i {
  width: 7px;
  height: 7px;
  flex: 0 0 auto;
  border-radius: 50%;
  background: #dcbf74;
}

.pending-stage-state.complete {
  color: #426e63;
}

.pending-stage-state.complete i {
  background: #426e63;
}

.pending-stage-counter {
  color: #6e7773;
  font: 700 13px/1 var(--font-num);
  text-align: right;
}

.pending-sheet-header {
  padding-top: 10px;
}

.pending-sheet-body {
  min-height: 0;
  flex: 1 1 auto;
  overscroll-behavior: contain;
}

.pending-evidence-carousel {
  position: relative;
  display: block;
}

.pending-evidence-frame {
  min-width: 0;
}

.pending-evidence-page {
  position: absolute;
  top: 50%;
  z-index: 2;
  width: 34px;
  height: 48px;
  border-radius: 8px;
  font: 300 30px/1 var(--font);
  box-shadow: 0 5px 14px rgba(23, 49, 45, 0.12);
  transform: translateY(-50%);
}

.pending-evidence-page.previous {
  left: -12px;
}

.pending-evidence-page.next {
  right: -12px;
}

.pending-evidence-page:disabled {
  opacity: 0.22;
}

.pending-evidence-stage {
  width: 100%;
  height: min(52dvh, calc(100vw - 2.5rem));
  min-height: 0;
  max-height: none;
}

.pending-evidence-section.has-open-fields .pending-evidence-stage {
  height: min(52dvh, calc(100vw - 2.5rem));
  min-height: 0;
}

@supports (height: 1cqw) {
  .pending-evidence-stage,
  .pending-evidence-section.has-open-fields .pending-evidence-stage {
    height: min(52dvh, 100cqw);
  }
}

.pending-evidence-stage.has-image {
  position: relative;
  display: grid;
  place-items: center;
}

.pending-evidence-stage.has-image img {
  width: 100%;
  height: 100%;
  object-fit: contain;
  transition: opacity 180ms ease;
}

.pending-evidence-stage.has-image.is-loading img {
  opacity: 0;
}

.pending-evidence-image-loading {
  position: absolute;
  inset: 0;
  z-index: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-direction: column;
  gap: 10px;
  background: #f8f6ef;
  color: #6e7773;
  font-size: 11px;
}

.pending-sheet-footer {
  flex: 0 0 auto;
}

@media (max-width: 380px) {
  .pending-stage-topbar {
    padding-right: 14px;
    padding-left: 14px;
  }

  .pending-evidence-carousel {
    display: block;
  }

  .pending-evidence-page {
    width: 28px;
  }

  .pending-evidence-page.previous {
    left: -9px;
  }

  .pending-evidence-page.next {
    right: -9px;
  }

  .pending-evidence-stage {
    height: min(52dvh, calc(100vw - 2.25rem));
    min-height: 0;
  }

  .pending-evidence-section.has-open-fields .pending-evidence-stage {
    height: min(52dvh, calc(100vw - 2.25rem));
    min-height: 0;
  }
}

@media (max-height: 700px) {
  .pending-stage-topbar {
    min-height: calc(52px + env(safe-area-inset-top, 0px));
  }

  .pending-evidence-stage {
    height: min(48dvh, calc(100vw - 2.5rem));
    min-height: 0;
  }

  .pending-evidence-section.has-open-fields .pending-evidence-stage {
    height: min(48dvh, calc(100vw - 2.5rem));
    min-height: 0;
  }
}

.pending-evidence-section .pending-evidence-stage.fact-stage,
.pending-evidence-section.has-open-fields .pending-evidence-stage.fact-stage {
  height: auto;
  min-height: 0;
  max-height: none;
}
</style>
