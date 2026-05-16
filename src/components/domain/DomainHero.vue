<template>
  <div class="hero" :style="cssVars">
    <div class="hero-bg" aria-hidden="true">
      <div class="hero-bg-mark">{{ icon }}</div>
    </div>
    <div class="hero-top">
      <div class="hero-icon">{{ icon }}</div>
      <span class="hero-status" :class="statusClass">
        <span class="hero-status-dot"></span>{{ statusLabel }}
      </span>
    </div>
    <div class="hero-kicker" v-if="kicker">{{ kicker }}</div>
    <div class="hero-row">
      <div class="hero-name">{{ name }}</div>
      <div class="hero-count" v-if="recordCount != null">
        <span class="hero-count-num">{{ formattedCount }}</span>
        <span class="hero-count-label">条记录</span>
      </div>
    </div>
    <div v-if="description" class="hero-desc">{{ description }}</div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  name: { type: String, required: true },
  icon: { type: String, default: '◇' },
  description: { type: String, default: '' },
  color: { type: String, default: '#2d6a4f' },
  recordCount: { type: Number, default: null },
  status: { type: String, default: 'active' }, // active | running | waiting | archived
  kicker: { type: String, default: '' },        // 小型上标，如 'DOMAIN WORKSPACE'
})

const cssVars = computed(() => ({
  '--domain-color': props.color,
  '--domain-color-soft': hexAlpha(props.color, 0.10),
  '--domain-color-mid':  hexAlpha(props.color, 0.20),
  '--domain-color-ink':  hexAlpha(props.color, 0.95),
}))

const statusLabel = computed(() => {
  if (props.recordCount === 0) return '待接入'
  const map = { active: '运行中', running: '运行中', waiting: '待接入', archived: '已归档' }
  return map[props.status] || '运行中'
})
const statusClass = computed(() => {
  const lab = statusLabel.value
  if (lab === '运行中') return 'is-running'
  if (lab === '待接入') return 'is-waiting'
  return 'is-archived'
})

const formattedCount = computed(() => {
  const n = Number(props.recordCount || 0)
  if (n >= 10000) return `${(n / 10000).toFixed(1)}万`
  return String(n)
})

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
.hero {
  position: relative;
  margin: 0 16px 16px;
  padding: 22px 22px 20px;
  border-radius: 20px;
  background:
    linear-gradient(135deg, var(--domain-color-soft) 0%, transparent 70%),
    var(--bg-card);
  border: 1px solid var(--border);
  overflow: hidden;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04), 0 8px 24px rgba(33, 37, 41, 0.05);
  animation: hero-fade-in 0.5s cubic-bezier(0.22, 0.61, 0.36, 1) both;
}

.hero-bg {
  position: absolute;
  top: -20px;
  right: -10px;
  pointer-events: none;
  user-select: none;
}
.hero-bg-mark {
  font-size: 140px;
  line-height: 1;
  opacity: 0.06;
  color: var(--domain-color);
  filter: blur(0.5px);
  transform: rotate(-8deg);
}

.hero-top {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 14px;
}
.hero-icon {
  width: 44px;
  height: 44px;
  border-radius: 14px;
  background: var(--domain-color);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 22px;
  box-shadow: 0 6px 14px var(--domain-color-mid);
}
.hero-status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  font-weight: 600;
  padding: 4px 10px;
  border-radius: 999px;
  letter-spacing: 0.4px;
}
.hero-status-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
}
.hero-status.is-running {
  color: #047857;
  background: rgba(16, 185, 129, 0.10);
}
.hero-status.is-waiting {
  color: var(--text2);
  background: var(--surface2);
}
.hero-status.is-archived {
  color: var(--text3);
  background: var(--surface2);
}

.hero-kicker {
  position: relative;
  font-size: 10px;
  letter-spacing: 1.6px;
  color: var(--domain-color);
  font-weight: 700;
  text-transform: uppercase;
  margin-bottom: 4px;
  opacity: 0.85;
}

.hero-row {
  position: relative;
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 8px;
}
.hero-name {
  font-size: 24px;
  font-weight: 800;
  color: var(--text);
  letter-spacing: -0.4px;
  line-height: 1.15;
}
.hero-count {
  display: flex;
  align-items: baseline;
  gap: 4px;
  flex-shrink: 0;
}
.hero-count-num {
  font-family: var(--font-num);
  font-size: 28px;
  font-weight: 800;
  color: var(--domain-color);
  letter-spacing: -0.6px;
  line-height: 1;
}
.hero-count-label {
  font-size: 11px;
  color: var(--text3);
  font-weight: 500;
}

.hero-desc {
  position: relative;
  font-size: 12px;
  line-height: 1.55;
  color: var(--text2);
  max-width: 92%;
}

@keyframes hero-fade-in {
  0%   { opacity: 0; transform: translateY(6px); }
  100% { opacity: 1; transform: translateY(0); }
}
@media (prefers-reduced-motion: reduce) {
  .hero { animation: none; }
}
</style>
