<template>
  <div class="metric-strip" :style="cssVars" :class="`cols-${cols}`">
    <div
      v-for="(item, index) in metrics"
      :key="item.label"
      class="metric-cell"
      :class="{ accent: item.accent, muted: item.muted }"
      :style="{ animationDelay: `${index * 50}ms` }"
    >
      <div class="metric-label">{{ item.label }}</div>
      <div class="metric-value-row">
        <span class="metric-value" :class="{ small: item.small }">{{ item.value }}</span>
        <span
          v-if="item.delta != null"
          class="metric-delta"
          :class="deltaClass(item.delta)"
        >{{ deltaText(item.delta) }}</span>
      </div>
      <div v-if="item.hint" class="metric-hint">{{ item.hint }}</div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  metrics: {
    type: Array,
    required: true,
    // [{ label, value, delta?, accent?, muted?, hint?, small? }]
  },
  color: { type: String, default: '#2d6a4f' },
  cols: { type: Number, default: 4 }, // 4 or 2
})

const cssVars = computed(() => ({
  '--domain-color': props.color,
  '--domain-color-soft': hexAlpha(props.color, 0.10),
  '--domain-color-mid':  hexAlpha(props.color, 0.20),
}))

function deltaClass(delta) {
  if (typeof delta === 'string') return 'neutral'
  if (delta > 0) return 'up'
  if (delta < 0) return 'down'
  return 'neutral'
}
function deltaText(delta) {
  if (typeof delta === 'string') return delta
  const sign = delta > 0 ? '+' : ''
  if (Math.abs(delta) >= 1) return `${sign}${Math.round(delta)}%`
  return `${sign}${(delta * 100).toFixed(1)}%`
}

function hexAlpha(hex, alpha) {
  const h = hex.replace('#', '')
  const f = h.length === 3 ? h.split('').map(c => c + c).join('') : h
  const r = parseInt(f.slice(0, 2), 16)
  const g = parseInt(f.slice(2, 4), 16)
  const b = parseInt(f.slice(4, 6), 16)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}
</script>

<style scoped>
.metric-strip {
  display: grid;
  gap: 10px;
  margin: 0 16px 16px;
}
.metric-strip.cols-4 {
  grid-template-columns: repeat(4, 1fr);
}
.metric-strip.cols-2 {
  grid-template-columns: repeat(2, 1fr);
}

.metric-cell {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 12px 12px 11px;
  position: relative;
  overflow: hidden;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
  animation: metric-fade-in 0.4s cubic-bezier(0.22, 0.61, 0.36, 1) both;
  transition: transform 0.18s ease, box-shadow 0.18s ease;
}
.metric-cell.accent {
  background:
    linear-gradient(135deg, var(--domain-color-soft) 0%, transparent 80%),
    var(--bg-card);
  border-color: var(--domain-color-mid);
}
.metric-cell.muted {
  opacity: 0.65;
}
.metric-cell::after {
  content: '';
  position: absolute;
  left: 12px;
  bottom: 11px;
  right: 12px;
  height: 2px;
  background: linear-gradient(90deg, var(--domain-color-mid) 0%, transparent 100%);
  opacity: 0;
  transition: opacity 0.18s ease;
}
.metric-cell.accent::after { opacity: 0.45; }

.metric-label {
  font-size: 10px;
  letter-spacing: 0.6px;
  color: var(--text3);
  font-weight: 600;
  text-transform: uppercase;
  margin-bottom: 6px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.metric-value-row {
  display: flex;
  align-items: baseline;
  gap: 5px;
  flex-wrap: wrap;
}
.metric-value {
  font-family: var(--font-num);
  font-size: 18px;
  font-weight: 800;
  color: var(--text);
  letter-spacing: -0.4px;
  line-height: 1.05;
  word-break: break-all;
}
.metric-value.small {
  font-size: 14px;
}
.metric-cell.accent .metric-value {
  color: var(--domain-color);
}

.metric-delta {
  font-family: var(--font-num);
  font-size: 10px;
  font-weight: 700;
  padding: 2px 6px;
  border-radius: 4px;
  letter-spacing: 0.2px;
}
.metric-delta.up {
  color: #047857;
  background: rgba(16, 185, 129, 0.12);
}
.metric-delta.down {
  color: #b91c1c;
  background: rgba(239, 68, 68, 0.10);
}
.metric-delta.neutral {
  color: var(--text2);
  background: var(--surface2);
}

.metric-hint {
  margin-top: 4px;
  font-size: 10px;
  color: var(--text3);
  letter-spacing: 0.3px;
}

@keyframes metric-fade-in {
  0%   { opacity: 0; transform: translateY(6px); }
  100% { opacity: 1; transform: translateY(0); }
}
@media (prefers-reduced-motion: reduce) {
  .metric-cell { animation: none; }
}
</style>
