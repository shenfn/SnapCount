<template>
  <div v-if="feedback" class="ai-feedback-card" :class="[bandClass, { compact }]">
    <div class="ai-feedback-head">
      <div class="ai-feedback-icon">{{ feedback.icon || '✨' }}</div>
      <div class="ai-feedback-main">
        <div class="ai-feedback-kicker">{{ kicker }}</div>
        <div class="ai-feedback-title">{{ feedback.badge || '即时反馈' }}</div>
      </div>
      <div class="ai-feedback-band">{{ bandLabel }}</div>
    </div>
    <div v-if="feedback.emotion_line" class="ai-feedback-emotion">{{ feedback.emotion_line }}</div>
    <div v-if="feedback.utility_line" class="ai-feedback-action">{{ feedback.utility_line }}</div>
    <button
      v-if="feedback.detail_reason && compact"
      type="button"
      class="ai-feedback-toggle"
      @click="showReason = !showReason"
    >{{ showReason ? '收起依据' : '为什么这么说' }}</button>
    <div v-if="feedback.detail_reason && (!compact || showReason)" class="ai-feedback-reason">
      <span>判断依据</span>{{ feedback.detail_reason }}
    </div>
    <div v-if="timingLabel" class="ai-feedback-meta">
      <span>{{ timingLabel }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'

const props = defineProps({
  feedback: { type: Object, default: null },
  compact: { type: Boolean, default: false },
  kicker: { type: String, default: 'AI 即时反馈' },
})

const showReason = ref(false)

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
</style>