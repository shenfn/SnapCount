<template>
  <div class="page active detail-page">
    <div class="detail-header">
      <button class="detail-back" @click="store.closeRecordDetail()">‹</button>
      <div class="detail-header-info">
        <div class="detail-header-title">记录详情</div>
      </div>
      <button
        v-if="record"
        class="detail-more"
        @click="store.openDeleteConfirm(deleteType, record.id, record.imagePath)"
      >
        删
      </button>
    </div>

    <div v-if="record" class="record-detail-content">
      <div class="record-detail-image-card">
        <template v-if="record.imageUrl">
          <img :src="record.imageUrl" class="record-detail-image" @click="store.openImgFull(record.imageUrl)">
          <div class="record-detail-image-label">点击查看原始图片</div>
        </template>
        <div v-else class="record-detail-image-empty">
          <div class="record-detail-image-empty-mark">{{ emptyMark }}</div>
          <div class="record-detail-image-label">{{ record.imageLoadError ? '图片文件不可用' : '暂无图片预览' }}</div>
        </div>
      </div>

      <div class="record-detail-section">
        <div class="record-detail-section-title">基本信息</div>
        <div class="record-detail-field">
          <span class="field-label">数据域</span>
          <span class="field-value">
            <span class="badge" :class="domainBadgeClass">{{ domainLabel }}</span>
          </span>
        </div>
        <div class="record-detail-field">
          <span class="field-label">记录时间</span>
          <span class="field-value">{{ recordTime }}</span>
        </div>
        <div v-if="eventTime" class="record-detail-field">
          <span class="field-label">发生时间</span>
          <span class="field-value">{{ eventTime }}</span>
        </div>
        <div class="record-detail-field">
          <span class="field-label">来源</span>
          <span class="field-value">{{ sourceLabel }}</span>
        </div>
        <div v-if="record.kind === 'expense'" class="record-detail-field">
          <span class="field-label">状态</span>
          <span class="field-value">
            <span class="badge" :class="isPendingExpense ? 'badge-warning' : 'badge-success'">
              {{ isPendingExpense ? '待补充' : '已完成' }}
            </span>
          </span>
        </div>
      </div>

      <div class="record-detail-section">
        <div class="record-detail-section-title">抽取字段</div>
        <div v-for="field in fields" :key="field.label" class="record-detail-field" :class="{ stacked: field.multiline }">
          <span class="field-label">{{ field.label }}</span>
          <span class="field-value" :class="{ numeric: field.numeric, wrap: field.multiline }">{{ field.value }}</span>
        </div>
      </div>

      <div v-if="accountExplanation" class="record-account-card" :class="accountExplanation.status">
        <div class="record-account-mark">{{ accountExplanation.status === 'bound' ? '已' : accountExplanation.status === 'recommended' ? '荐' : '绑' }}</div>
        <div class="record-account-body">
          <div class="record-account-kicker">账户绑定</div>
          <div class="record-account-title">{{ accountExplanation.title }}</div>
          <div class="record-account-reason">{{ accountExplanation.reason }}</div>
        </div>
        <button
          v-if="accountExplanation.status === 'recommended'"
          class="record-account-bind-btn"
          :disabled="bindingAccount"
          @click="bindRecommendedAccount"
        >
          {{ bindingAccount ? '绑定中' : '一键绑定' }}
        </button>
      </div>

      <div v-if="foodDishes.length" class="record-detail-section">
        <div class="record-detail-section-title">
          菜品明细
          <span class="badge badge-warning record-detail-estimate-badge">估算值</span>
        </div>
        <div v-for="(d, i) in foodDishes" :key="i" class="record-detail-field stacked food-dish-field">
          <div class="food-dish-header">
            <span class="field-label food-dish-name">{{ d.name }}</span>
            <span class="field-value numeric">{{ d.calorie_kcal != null ? `${d.calorie_kcal} 千卡` : '--' }}</span>
          </div>
          <div class="food-dish-macros">
            <span v-if="d.estimated_grams != null">约 {{ d.estimated_grams }}g</span>
            <span v-if="d.protein_g != null">蛋白 {{ d.protein_g }}g</span>
            <span v-if="d.carb_g != null">碳水 {{ d.carb_g }}g</span>
            <span v-if="d.fat_g != null">脂肪 {{ d.fat_g }}g</span>
          </div>
        </div>
      </div>

      <AiFeedbackCard
        v-if="aiFeedback"
        ref="aiFeedbackCardRef"
        :key="aiFeedbackCardKey"
        :feedback="aiFeedback"
        :exposure-event-id="aiFeedbackExposureEventId"
        :reviewable="aiFeedbackReviewable"
        :review-unavailable="plannerReviewUnavailable"
        :review-retrying="plannerReviewRetrying"
        :review-state="feedbackReviewState"
        :submitting="feedbackReviewSubmitting"
        @retry-review="retryPlannerDelivery"
        @submit-review="submitFeedbackReview"
      />

      <div v-if="companionMessage" class="record-detail-companion">
        <div class="record-detail-companion-mark">💬</div>
        <div>
          <div class="record-detail-companion-title">AI 陪伴</div>
          <div class="record-detail-companion-text">{{ companionMessage }}</div>
        </div>
      </div>

      <div class="record-detail-section">
        <div class="record-detail-section-title">AI 摘要</div>
        <div class="record-detail-ai-summary">{{ aiSummary }}</div>
      </div>

      <div class="record-detail-actions">
        <button class="record-detail-btn secondary" @click="store.openDetailEditor()">{{ isPendingExpense ? '补充信息' : '编辑' }}</button>
        <button class="record-detail-btn danger" @click="store.openDeleteConfirm(deleteType, record.id, record.imagePath)">删除</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, inject, nextTick, ref, watch } from 'vue'
import AiFeedbackCard from '../AiFeedbackCard.vue'
import { getSystemDomainLabel } from '../../domains/registry'
import { formatDateTimeLabel } from '../../utils/helpers'
import { getRecordAiSummary, getRecordDetailFields, getRecordFoodDishes } from '../../domains/recordDetailAdapters'
import {
  createAbortError,
  isAbortError,
  retryWithBackoff,
  waitForVisibleElement,
} from '../../utils/expressionDelivery'

const PLAN_NOT_READY_RETRY_DELAYS = [250, 750, 1500]
const ACK_RETRY_DELAYS = [400, 1200]

const store = inject('store')

const record = computed(() => store.detailRecord.value)
const bindingAccount = ref(false)
const aiFeedbackCardRef = ref(null)
const feedbackReviewStates = ref({})
const plannerDeliveryStates = ref({})
let activePlannerDeliveryController = null
const deleteType = computed(() => {
  if (record.value?.kind === 'income') return 'income'
  if (record.value?.kind === 'universal') return 'universal'
  return 'bill'
})
const isPendingExpense = computed(() => record.value?.kind === 'expense' && record.value?.raw?.status === 'pending')
const domainMeta = computed(() => {
  if (!record.value) return null
  return store.domains.value.find(item => item.id === record.value.domainId) || null
})
const domainLabel = computed(() => {
  if (record.value?.kind === 'income') return getSystemDomainLabel('income')
  if (record.value?.kind === 'expense') return getSystemDomainLabel('expense')
  return domainMeta.value?.name || '通用记录'
})
const domainBadgeClass = computed(() => {
  if (record.value?.kind === 'income') return 'badge-income'
  if (record.value?.kind === 'expense') return 'badge-expense'
  return 'badge-primary'
})
const emptyMark = computed(() => {
  if (record.value?.kind === 'income') return '收'
  if (record.value?.kind === 'expense') return '支'
  return domainMeta.value?.shortName?.slice(0, 1) || '记'
})

const recordTime = computed(() => {
  if (!record.value?.raw) return '--'
  const raw = record.value.raw
  if (record.value.kind === 'universal') return formatDateTimeLabel(raw.payload?.time_context?.client_captured_at || raw.createdAt || raw.occurredAt) || '--'
  if (raw.createdAt) return formatDateTimeLabel(raw.createdAt)
  if (raw.dateRaw) return raw.time ? `${raw.date} ${raw.time}` : raw.date
  return '--'
})

const eventTime = computed(() => {
  if (!record.value?.raw || record.value.kind !== 'universal') return ''
  return formatDateTimeLabel(record.value.raw.occurredAt) || ''
})

const sourceLabel = computed(() => {
  if (!record.value?.raw) return '--'
  const raw = record.value.raw
  if (record.value.kind === 'income') return raw.sourceType === 'ai_scan' ? '截图识别' : '手动录入'
  if (record.value.kind === 'universal') return raw.source === 'staging' ? '中转站归档' : '截图识别'
  return raw.source === 'ai_scan' ? '截图识别' : '手动录入'
})

const fields = computed(() => getRecordDetailFields(store, record.value))
const accountExplanation = computed(() => {
  if (!record.value || !['expense', 'income'].includes(record.value.kind)) return null
  return store.accountBindingExplanation(record.value.kind, record.value.raw)
})
const foodDishes = computed(() => getRecordFoodDishes(record.value))
const legacyAiFeedback = computed(() => {
  const raw = record.value?.raw
  if (!raw) return null
  return raw.aiFeedback || raw.ai_feedback || raw.payload?.ai_feedback || raw.extracted?.ai_feedback || raw.extracted_json?.ai_feedback || null
})
const expectedExpressionRecordKind = computed(() => (
  record.value?.kind === 'universal' ? 'data' : record.value?.kind || ''
))
const recordExpressionPlan = computed(() => {
  const recordId = record.value?.id
  const plan = recordId ? store.recordExpressionPlanCache.value[recordId] || null : null
  return plan?.recordKind === expectedExpressionRecordKind.value ? plan : null
})
const plannerAiFeedback = computed(() => (
  recordExpressionPlan.value?.available ? recordExpressionPlan.value.feedback || null : null
))
const aiFeedback = computed(() => plannerAiFeedback.value || legacyAiFeedback.value)
const aiFeedbackExposureEventId = computed(() => (
  aiFeedback.value?.exposure_event_id || aiFeedback.value?.exposureEventId || ''
))
const aiFeedbackCardKey = computed(() => {
  const recordId = record.value?.id || 'none'
  const plan = recordExpressionPlan.value
  if (plan?.available && plan.feedback) {
    return `ai-feedback-${recordId}-planner-${plan.planToken}-${plan.candidateId}`
  }
  return `ai-feedback-${recordId}-legacy`
})
const aiFeedbackReviewable = computed(() => {
  if (!aiFeedback.value) return false
  if (!plannerAiFeedback.value) return true
  return Boolean(recordExpressionPlan.value?.acknowledged && aiFeedbackExposureEventId.value)
})
const plannerDeliveryState = computed(() => plannerDeliveryStates.value[aiFeedbackCardKey.value] || '')
const plannerReviewUnavailable = computed(() => (
  Boolean(plannerAiFeedback.value) && ['ack_failed', 'manual_retrying'].includes(plannerDeliveryState.value)
))
const plannerReviewRetrying = computed(() => plannerDeliveryState.value === 'manual_retrying')
const feedbackReviewState = computed(() => feedbackReviewStates.value[aiFeedbackCardKey.value] || '')
const feedbackReviewSubmitting = computed(() => feedbackReviewState.value === 'syncing')

function setFeedbackReviewState(reviewKey, state) {
  feedbackReviewStates.value = { ...feedbackReviewStates.value, [reviewKey]: state }
}

function setPlannerDeliveryState(deliveryKey, state) {
  plannerDeliveryStates.value = { ...plannerDeliveryStates.value, [deliveryKey]: state }
}
const companionMessage = computed(() => {
  const raw = record.value?.raw
  if (!raw) return ''
  const text = raw.companionMessage || raw.companion_message || raw.payload?.companion_message || ''
  if (aiFeedback.value?.emotion_line && text === aiFeedback.value.emotion_line) return ''
  return text
})
const aiSummary = computed(() => getRecordAiSummary(store, record.value, domainLabel.value))

function isCurrentVisibleDetail(recordId) {
  return store.currentPage.value === 'record-detail' && record.value?.id === recordId
}

function isCurrentPlannerDetail(recordId, plan) {
  const current = recordExpressionPlan.value
  return isCurrentVisibleDetail(recordId)
    && current?.planToken === plan?.planToken
    && current?.candidateId === plan?.candidateId
}

function feedbackCardElement() {
  return aiFeedbackCardRef.value?.$el || aiFeedbackCardRef.value || null
}

async function loadPlannerWithRetry(recordId, recordKind, signal) {
  return retryWithBackoff(
    () => store.loadRecordExpressionPlan(recordId, { recordKind, signal }),
    {
      delays: PLAN_NOT_READY_RETRY_DELAYS,
      signal,
      shouldRetryResult: plan => !plan?.available && plan?.reason === 'plan_not_ready',
      shouldRetryError: () => false,
    },
  )
}

async function acknowledgePlannerWhenVisible(recordId, plan, controller, { manual = false } = {}) {
  const deliveryKey = `ai-feedback-${recordId}-planner-${plan.planToken}-${plan.candidateId}`
  setPlannerDeliveryState(deliveryKey, manual ? 'manual_retrying' : 'waiting_visibility')
  try {
    await nextTick()
    const acknowledged = await retryWithBackoff(
      async () => {
        do {
          await waitForVisibleElement(feedbackCardElement(), { signal: controller.signal })
        } while (globalThis.document?.visibilityState !== 'visible')
        if (!isCurrentPlannerDetail(recordId, plan)) throw createAbortError()
        if (!manual) setPlannerDeliveryState(deliveryKey, 'acknowledging')
        return store.ackRecordExpressionPlan(recordId, { signal: controller.signal })
      },
      {
        delays: ACK_RETRY_DELAYS,
        signal: controller.signal,
        shouldRetryError: error => !isAbortError(error),
        onRetry: () => setPlannerDeliveryState(
          deliveryKey,
          manual ? 'manual_retrying' : 'waiting_visibility',
        ),
      },
    )
    if (acknowledged?.acknowledged && isCurrentPlannerDetail(recordId, plan)) {
      setPlannerDeliveryState(deliveryKey, 'ready')
    }
    return acknowledged
  } catch (error) {
    if (isAbortError(error) || controller.signal.aborted) return null
    if (isCurrentPlannerDetail(recordId, plan)) setPlannerDeliveryState(deliveryKey, 'ack_failed')
    throw error
  }
}

watch(
  () => [store.currentPage.value, record.value?.id || '', record.value?.kind || ''],
  async ([page, recordId, recordKind], _previous, onCleanup) => {
    if (page !== 'record-detail' || !recordId || !recordKind) return
    const controller = new AbortController()
    activePlannerDeliveryController = controller
    onCleanup(() => {
      controller.abort()
      if (activePlannerDeliveryController === controller) activePlannerDeliveryController = null
    })
    try {
      const plan = await loadPlannerWithRetry(recordId, recordKind, controller.signal)
      if (!isCurrentVisibleDetail(recordId) || !plan?.available || plan.acknowledged) return
      await acknowledgePlannerWhenVisible(recordId, plan, controller)
    } catch (error) {
      if (!isAbortError(error)) console.warn('交付记录表达计划失败:', error)
    }
  },
  { immediate: true },
)

async function retryPlannerDelivery() {
  const recordId = record.value?.id
  const plan = recordExpressionPlan.value
  const controller = activePlannerDeliveryController
  if (!recordId || !plan?.available || plan.acknowledged || !controller || controller.signal.aborted) return
  if (plannerDeliveryState.value !== 'ack_failed') return
  try {
    await acknowledgePlannerWhenVisible(recordId, plan, controller, { manual: true })
  } catch (error) {
    if (!isAbortError(error)) console.warn('重新确认记录表达曝光失败:', error)
  }
}

async function submitFeedbackReview({ choice, freeText, exposureEventId }) {
  const recordId = record.value?.id
  const reviewKey = aiFeedbackCardKey.value
  if (!recordId || !aiFeedbackReviewable.value || feedbackReviewStates.value[reviewKey] === 'syncing') return
  setFeedbackReviewState(reviewKey, 'syncing')
  store.showFlash('正在记录点评')
  try {
    await store.submitExpressionFeedback({ recordId, choice, freeText, exposureEventId })
    setFeedbackReviewState(reviewKey, 'submitted')
    if (record.value?.id === recordId && aiFeedbackCardKey.value === reviewKey) store.showFlash('已记录，将用于后续选择')
  } catch (error) {
    console.warn("提交 AI 点评失败:", error)
    setFeedbackReviewState(reviewKey, 'error')
    if (record.value?.id === recordId && aiFeedbackCardKey.value === reviewKey) store.showFlash('点评提交失败，请重试')
  }
}

async function bindRecommendedAccount() {
  if (!record.value) return
  bindingAccount.value = true
  try {
    await store.bindRecordToRecommendedAccount(record.value.kind, record.value.raw)
  } finally {
    bindingAccount.value = false
  }
}
</script>
