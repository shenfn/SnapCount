<template>
  <div v-if="feedback" class="ai-feedback-card" :class="[bandClass, { compact, embedded, 'review-only': reviewOnly }]">
    <div v-if="!reviewOnly && !embedded" class="ai-feedback-head">
      <div class="ai-feedback-icon">{{ feedback.icon || '✨' }}</div>
      <div class="ai-feedback-main">
        <div class="ai-feedback-kicker">{{ kicker }}</div>
        <div class="ai-feedback-title">{{ feedback.badge || '即时反馈' }}</div>
      </div>
      <div class="ai-feedback-band">{{ bandLabel }}</div>
    </div>
    <div v-if="!reviewOnly && embedded && feedback.badge" class="ai-feedback-embedded-badge">{{ feedback.badge }}</div>
    <div v-if="!reviewOnly && showEmotion" class="ai-feedback-emotion">{{ feedback.emotion_line }}</div>
    <div v-if="!reviewOnly && feedback.utility_line" class="ai-feedback-action">{{ feedback.utility_line }}</div>
    <button
      v-if="!reviewOnly && feedback.detail_reason && compact"
      type="button"
      class="ai-feedback-toggle"
      @click="showReason = !showReason"
    >{{ showReason ? '收起依据' : '为什么这么说' }}</button>
    <div v-if="!reviewOnly && feedback.detail_reason && (!compact || showReason)" class="ai-feedback-reason">
      <span>判断依据</span>{{ feedback.detail_reason }}
    </div>
    <div v-if="!reviewOnly && timingLabel" class="ai-feedback-meta">
      <span>{{ timingLabel }}</span>
    </div>
    <div v-if="reviewable" class="ai-feedback-review">
      <div class="ai-feedback-review-title">点评这条反馈</div>
      <div v-if="reviewState === 'syncing'" class="ai-feedback-review-success" role="status" aria-live="polite">正在记录点评…</div>
      <div v-else-if="reviewState === 'submitted' && !editingReview" class="ai-feedback-review-submitted">
        <div class="ai-feedback-review-success" role="status" aria-live="polite">已记录，将用于后续选择</div>
        <button type="button" class="ai-feedback-review-edit" @click="startReviewEdit">修改点评</button>
      </div>
      <template v-else>
        <div class="ai-feedback-review-options">
          <button
            v-for="choice in reviewChoices"
            :key="choice.value"
            type="button"
            class="ai-feedback-review-chip"
            :class="{ active: selectedChoice === choice.value }"
            :disabled="submitting"
            :aria-pressed="selectedChoice === choice.value"
            @click="selectedChoice = choice.value"
          >{{ choice.label }}</button>
        </div>
        <template v-if="selectedChoice">
          <textarea v-model="reviewText" class="ai-feedback-review-text" maxlength="500" aria-label="点评补充原因（选填）" placeholder="可以补充原因（选填）"></textarea>
          <button type="button" class="ai-feedback-review-submit" :disabled="submitting" @click="submitReview">
            {{ submitting ? '提交中…' : '提交点评' }}
          </button>
        </template>
        <div v-if="reviewState === 'error'" class="ai-feedback-review-error">提交失败，请稍后重试</div>
      </template>
    </div>
    <div v-else-if="reviewUnavailable" class="ai-feedback-review ai-feedback-review-unavailable">
      <div class="ai-feedback-review-error">暂时无法点评</div>
      <button
        type="button"
        class="ai-feedback-review-retry"
        :disabled="reviewRetrying"
        @click="emit('retry-review')"
      >{{ reviewRetrying ? '重试中…' : '重试' }}</button>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue'

const props = defineProps({
  feedback: { type: Object, default: null },
  compact: { type: Boolean, default: false },
  kicker: { type: String, default: 'AI 即时反馈' },
  reviewable: { type: Boolean, default: false },
  reviewState: { type: String, default: '' },
  submitting: { type: Boolean, default: false },
  exposureEventId: { type: String, default: '' },
  reviewUnavailable: { type: Boolean, default: false },
  reviewRetrying: { type: Boolean, default: false },
  reviewOnly: { type: Boolean, default: false },
  embedded: { type: Boolean, default: false },
  primaryText: { type: String, default: '' },
})

const emit = defineEmits(['submit-review', 'retry-review'])

const showReason = ref(false)
const selectedChoice = ref('')
const reviewText = ref('')
const editingReview = ref(false)
const reviewChoices = [
  { value: 'helpful', label: '有帮助' },
  { value: 'good_angle', label: '这个角度不错' },
  { value: 'just_what_i_wanted', label: '正是我想看的' },
  { value: 'no_change_needed', label: '这次不用调整' },
  { value: 'incorrect', label: '说得不对' },
  { value: 'not_helpful', label: '没什么帮助' },
  { value: 'repetitive', label: '有点重复' },
  { value: 'style_dislike', label: '表达不喜欢' },
  { value: 'other', label: '其他' },
]

function startReviewEdit() {
  editingReview.value = true
}

function submitReview() {
  if (!selectedChoice.value || props.submitting) return
  emit('submit-review', {
    choice: selectedChoice.value,
    freeText: reviewText.value.trim(),
    exposureEventId: props.exposureEventId || '',
  })
}

watch(() => props.reviewState, (nextState, previousState) => {
  if (nextState === 'submitted' && previousState === 'syncing') {
    editingReview.value = false
  }
})

const bandClass = computed(() => {
  const band = props.feedback?.band
  if (!band) return 'band-neutral'
  return `band-${band}`
})

const bandLabel = computed(() => {
  const band = props.feedback?.band
  if (band === 'positive') return '正向'
  if (band === 'watch') return '留意'
  if (band === 'recover') return '兜底'
  if (band === 'ritual') return '时机'
  return '观察'
})

const timingLabel = computed(() => props.feedback?.timing_signal?.label || '')
const showEmotion = computed(() => {
  const emotion = String(props.feedback?.emotion_line || '').trim()
  return Boolean(emotion) && emotion !== String(props.primaryText || '').trim()
})
</script>

<style scoped>
.ai-feedback-card {
  padding: 16px;
  border-radius: 20px;
  border: 1px solid rgba(33, 79, 61, 0.13);
  background: rgba(255, 255, 255, 0.94);
  box-shadow: var(--shadow-md);
}

.ai-feedback-card.compact {
  padding: 14px;
  border-radius: 18px;
  box-shadow: none;
  border-color: rgba(33, 79, 61, 0.1);
}

.ai-feedback-card.review-only {
  padding: 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
}

.ai-feedback-card.review-only .ai-feedback-review {
  margin-top: 12px;
}

.ai-feedback-card.band-positive {
  border-color: rgba(22, 101, 52, 0.18);
  background: linear-gradient(135deg, rgba(220, 252, 231, 0.92), rgba(255, 255, 255, 0.96));
}

.ai-feedback-card.band-watch,
.ai-feedback-card.band-recover {
  border-color: rgba(180, 83, 9, 0.2);
  background: linear-gradient(135deg, rgba(254, 243, 199, 0.88), rgba(255, 255, 255, 0.96));
}

.ai-feedback-card.band-ritual {
  border-color: rgba(37, 99, 235, 0.18);
  background: linear-gradient(135deg, rgba(219, 234, 254, 0.88), rgba(255, 255, 255, 0.96));
}

.ai-feedback-card.embedded,
.ai-feedback-card.embedded.band-positive,
.ai-feedback-card.embedded.band-watch,
.ai-feedback-card.embedded.band-recover,
.ai-feedback-card.embedded.band-ritual {
  margin-top: 10px;
  padding: 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
}

.ai-feedback-embedded-badge {
  font-size: 12px;
  font-weight: 800;
  color: var(--primary);
}

.ai-feedback-head {
  display: flex;
  align-items: center;
  gap: 12px;
}

.ai-feedback-icon {
  width: 38px;
  height: 38px;
  display: grid;
  place-items: center;
  flex: 0 0 auto;
  border-radius: 14px;
  background: rgba(33, 79, 61, 0.09);
  font-size: 20px;
}

.ai-feedback-card.compact .ai-feedback-icon {
  width: 32px;
  height: 32px;
  font-size: 17px;
  border-radius: 12px;
}

.ai-feedback-main {
  min-width: 0;
  flex: 1;
}

.ai-feedback-kicker {
  font-size: 11px;
  font-weight: 700;
  color: var(--text3);
  letter-spacing: 0.2px;
}

.ai-feedback-title {
  margin-top: 2px;
  font-size: 17px;
  font-weight: 800;
  color: var(--text);
}

.ai-feedback-card.compact .ai-feedback-title {
  font-size: 15px;
}

.ai-feedback-band {
  flex: 0 0 auto;
  padding: 5px 9px;
  border-radius: 999px;
  background: rgba(33, 79, 61, 0.08);
  color: var(--primary);
  font-size: 12px;
  font-weight: 800;
}

.ai-feedback-emotion {
  margin-top: 14px;
  font-size: 15px;
  line-height: 1.55;
  font-weight: 700;
  color: var(--text);
}

.ai-feedback-card.compact .ai-feedback-emotion {
  margin-top: 10px;
  font-size: 14px;
  font-weight: 600;
}

.ai-feedback-action {
  margin-top: 8px;
  padding: 10px 12px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.72);
  font-size: 13px;
  line-height: 1.5;
  color: var(--text1);
}

.ai-feedback-card.compact .ai-feedback-action {
  padding: 8px 10px;
  font-size: 12px;
}

.ai-feedback-toggle {
  display: block;
  margin-top: 6px;
  padding: 0;
  border: 0;
  background: none;
  font-size: 12px;
  font-weight: 600;
  color: var(--primary);
  cursor: pointer;
  opacity: 0.8;
  line-height: 1.5;
}

.ai-feedback-toggle:hover {
  opacity: 1;
}

.ai-feedback-reason {
  margin-top: 10px;
  font-size: 12px;
  line-height: 1.5;
  color: var(--text2);
}

.ai-feedback-reason span {
  margin-right: 6px;
  font-weight: 800;
  color: var(--text);
}

.ai-feedback-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 10px;
}

.ai-feedback-meta span {
  padding: 4px 8px;
  border-radius: 999px;
  background: rgba(33, 79, 61, 0.08);
  font-size: 11px;
  font-weight: 700;
  color: var(--primary);
}
.ai-feedback-review {
  margin-top: 14px;
  padding-top: 12px;
  border-top: 1px solid rgba(33, 79, 61, 0.1);
}
.ai-feedback-review-title { font-size: 12px; font-weight: 800; color: var(--text2); }
.ai-feedback-review-options { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 9px; }
.ai-feedback-review-chip { border: 1px solid rgba(33,79,61,.14); border-radius: 999px; padding: 7px 10px; background: rgba(255,255,255,.72); color: var(--text1); font-size: 12px; cursor: pointer; }
.ai-feedback-review-chip.active { border-color: var(--primary); background: rgba(33,79,61,.1); color: var(--primary); font-weight: 800; }
.ai-feedback-review-text { width: 100%; min-height: 72px; margin-top: 10px; padding: 10px 12px; resize: vertical; border: 1px solid rgba(33,79,61,.14); border-radius: 12px; background: rgba(255,255,255,.78); color: var(--text); font: inherit; box-sizing: border-box; }
.ai-feedback-review-submit { margin-top: 8px; border: 0; border-radius: 12px; padding: 9px 14px; background: var(--primary); color: white; font-weight: 800; cursor: pointer; }
.ai-feedback-review-submit:disabled, .ai-feedback-review-chip:disabled { opacity: .55; cursor: default; }
.ai-feedback-review-success { margin-top: 8px; color: var(--primary); font-size: 13px; font-weight: 700; }
.ai-feedback-review-submitted { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.ai-feedback-review-edit { flex: 0 0 auto; margin-top: 8px; border: 0; padding: 6px 4px; background: none; color: var(--primary); font-size: 12px; font-weight: 800; cursor: pointer; }
.ai-feedback-review-edit:hover { text-decoration: underline; }
.ai-feedback-review-error { margin-top: 8px; color: #b45309; font-size: 12px; }
.ai-feedback-review-unavailable { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.ai-feedback-review-unavailable .ai-feedback-review-error { margin-top: 0; }
.ai-feedback-review-retry { border: 0; padding: 6px 4px; background: none; color: var(--primary); font-size: 12px; font-weight: 800; cursor: pointer; }
.ai-feedback-review-retry:disabled { opacity: .55; cursor: default; }

</style>
