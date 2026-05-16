<template>
  <div class="trend-panel" :style="cssVars">
    <div class="trend-header">
      <div class="trend-title-group">
        <div class="trend-title">{{ title }}</div>
        <div v-if="subtitle" class="trend-subtitle">{{ subtitle }}</div>
      </div>
      <div v-if="scope" class="trend-scope">{{ scope }}</div>
    </div>

    <div v-if="!hasData" class="trend-empty">
      <div class="trend-empty-icon">📊</div>
      <div class="trend-empty-text">{{ emptyText }}</div>
    </div>

    <template v-else>
      <div class="trend-tooltip" :class="{ active: selectedIndex >= 0 }">
        <template v-if="selectedIndex >= 0">
          <span class="tt-label">{{ fullLabel(selectedIndex) }}</span>
          <span class="tt-value">{{ formatValue(values[selectedIndex]) }}</span>
          <span v-if="totalNonZero" class="tt-share">{{ shareText(selectedIndex) }}</span>
        </template>
        <template v-else>
          <span class="tt-hint">轻触柱子查看详情</span>
        </template>
      </div>

      <div class="trend-chart" @click.self="clearSelection">
        <div
          v-for="(value, index) in values"
          :key="index"
          class="trend-col"
          :class="{
            'is-today': index === todayIndex,
            'is-selected': index === selectedIndex,
            'is-empty': value === 0,
          }"
          :style="colStyle(index)"
          @click="selectBar(index)"
        >
          <div class="trend-col-value" v-if="value > 0">
            {{ shortValue(value) }}
          </div>
          <div class="trend-bar-wrap">
            <div
              class="trend-bar"
              :style="barStyle(value, index)"
            ></div>
          </div>
          <div class="trend-col-label">
            {{ labels[index] }}
            <span v-if="index === todayIndex" class="trend-today-dot"></span>
          </div>
        </div>
      </div>

      <div v-if="showStats && stats.length" class="trend-stats">
        <div
          v-for="stat in stats"
          :key="stat.label"
          class="trend-stat"
          :class="{ accent: stat.accent }"
        >
          <div class="trend-stat-value">{{ stat.value }}</div>
          <div class="trend-stat-label">{{ stat.label }}</div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { formatDuration } from '../../utils/format'

const props = defineProps({
  values: { type: Array, required: true },
  labels: { type: Array, default: () => ['一', '二', '三', '四', '五', '六', '日'] },
  fullLabels: { type: Array, default: null }, // 可选完整标签，如 '周一 5月12日'
  todayIndex: { type: Number, default: -1 },
  color: { type: String, default: '#2d6a4f' },
  unit: { type: String, default: '' },
  currency: { type: Boolean, default: false },
  duration: { type: Boolean, default: false }, // 时长场景：值为分钟数，使用 formatDuration 显示
  title: { type: String, default: '趋势' },
  subtitle: { type: String, default: '' },
  scope: { type: String, default: '' },
  showStats: { type: Boolean, default: false },
  emptyText: { type: String, default: '暂无数据' },
})
const emit = defineEmits(['select'])

const selectedIndex = ref(-1)

// 数据进入时清空选中（避免月份切换还高亮旧的）
watch(() => props.values, () => { selectedIndex.value = -1 })

const hasData = computed(() => props.values && props.values.some(v => v > 0))
const maxValue = computed(() => Math.max(...props.values, 0))
const totalNonZero = computed(() => props.values.reduce((sum, v) => sum + (v || 0), 0))

const cssVars = computed(() => ({
  '--domain-color': props.color,
  '--domain-color-soft': hexWithAlpha(props.color, 0.14),
  '--domain-color-mid':  hexWithAlpha(props.color, 0.32),
  '--domain-color-glow': hexWithAlpha(props.color, 0.22),
}))

function selectBar(index) {
  if (props.values[index] === 0) {
    selectedIndex.value = -1
    return
  }
  selectedIndex.value = selectedIndex.value === index ? -1 : index
  if (selectedIndex.value >= 0) emit('select', { index, value: props.values[index] })
}
function clearSelection() {
  selectedIndex.value = -1
}

function colStyle(index) {
  return {
    animationDelay: `${index * 40}ms`,
  }
}
function barStyle(value, index) {
  const max = maxValue.value || 1
  const ratio = value / max
  const heightPct = value === 0 ? 4 : Math.max(ratio * 100, 12)
  return { height: `${heightPct}%` }
}
function shortValue(v) {
  if (props.duration) return formatDuration(v, { short: true })
  if (props.currency) {
    if (v >= 10000) return `¥${(v / 10000).toFixed(1)}万`
    if (v >= 1000)  return `¥${Math.round(v)}`
    return `¥${v.toFixed(v < 10 && v % 1 !== 0 ? 1 : 0)}`
  }
  if (v >= 10000) return `${(v / 10000).toFixed(1)}万`
  return Number.isInteger(v) ? String(v) : v.toFixed(1)
}
function formatValue(v) {
  if (v == null) return '-'
  if (props.duration) return formatDuration(v)
  if (props.currency) return `¥ ${v.toFixed(2)}`
  if (props.unit)     return `${shortValue(v)} ${props.unit}`
  return shortValue(v)
}
function fullLabel(index) {
  if (props.fullLabels && props.fullLabels[index]) return props.fullLabels[index]
  return props.labels[index]
}
function shareText(index) {
  const total = totalNonZero.value
  if (!total) return ''
  const pct = Math.round(((props.values[index] || 0) / total) * 100)
  return `占比 ${pct}%`
}

const stats = computed(() => {
  if (!props.showStats) return []
  const total = totalNonZero.value
  const peak = maxValue.value
  const todayVal = props.todayIndex >= 0 ? props.values[props.todayIndex] || 0 : 0
  const todayShare = total ? Math.round((todayVal / total) * 100) : 0
  return [
    { label: '累计', value: formatValue(total), accent: true },
    { label: '最高单日', value: formatValue(peak) },
    { label: '今日占比', value: total ? `${todayShare}%` : '—' },
  ]
})

function hexWithAlpha(hex, alpha) {
  const h = hex.replace('#', '')
  const full = h.length === 3 ? h.split('').map(c => c + c).join('') : h
  const r = parseInt(full.slice(0, 2), 16)
  const g = parseInt(full.slice(2, 4), 16)
  const b = parseInt(full.slice(4, 6), 16)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}
</script>

<style scoped>
.trend-panel {
  background: var(--bg-card);
  border-radius: 16px;
  padding: 18px 18px 16px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04), 0 6px 16px rgba(33, 37, 41, 0.05);
  border: 1px solid var(--border);
  margin: 0 16px 16px;
}

.trend-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  margin-bottom: 6px;
}
.trend-title {
  font-size: 15px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: 0.2px;
}
.trend-subtitle {
  margin-top: 2px;
  font-size: 11px;
  color: var(--text3);
}
.trend-scope {
  font-size: 11px;
  color: var(--domain-color);
  font-weight: 600;
  background: var(--domain-color-soft);
  padding: 4px 10px;
  border-radius: 999px;
  letter-spacing: 0.4px;
}

.trend-tooltip {
  height: 22px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  margin: 4px 0 8px;
  font-size: 12px;
  font-family: var(--font-num);
  color: var(--text3);
  transition: color 0.2s ease;
}
.trend-tooltip.active {
  color: var(--text);
}
.tt-label {
  color: var(--text2);
  font-weight: 600;
}
.tt-value {
  color: var(--domain-color);
  font-weight: 700;
  font-size: 13px;
}
.tt-share {
  color: var(--text3);
  font-size: 11px;
}
.tt-hint {
  font-size: 11px;
  color: var(--text3);
  letter-spacing: 0.3px;
}

.trend-chart {
  display: flex;
  align-items: flex-end;
  gap: 4px;
  height: 132px;
  padding: 0 2px;
}
.trend-col {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
  height: 100%;
  cursor: pointer;
  animation: trend-rise 0.42s cubic-bezier(0.22, 0.61, 0.36, 1) both;
  transition: transform 0.18s ease;
}
.trend-col:active {
  transform: scale(0.96);
}
.trend-col-value {
  font-size: 10px;
  font-family: var(--font-num);
  font-weight: 700;
  color: var(--text2);
  height: 13px;
  line-height: 13px;
  letter-spacing: -0.2px;
  white-space: nowrap;
  transition: color 0.2s ease;
}
.trend-col.is-today .trend-col-value,
.trend-col.is-selected .trend-col-value {
  color: var(--domain-color);
}
.trend-bar-wrap {
  flex: 1;
  width: 100%;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  min-height: 0;
}
.trend-bar {
  width: 70%;
  max-width: 22px;
  min-height: 4px;
  border-radius: 6px 6px 3px 3px;
  background: var(--domain-color-soft);
  transition: background 0.18s ease, transform 0.18s ease, box-shadow 0.18s ease;
}
.trend-col.is-today .trend-bar {
  background: linear-gradient(180deg, var(--domain-color) 0%, var(--domain-color-mid) 100%);
  box-shadow: 0 0 0 0 var(--domain-color-glow);
}
.trend-col.is-selected .trend-bar {
  background: linear-gradient(180deg, var(--domain-color) 0%, var(--domain-color-mid) 100%);
  transform: scaleX(1.08);
  box-shadow: 0 4px 12px var(--domain-color-glow);
}
.trend-col.is-empty .trend-bar {
  background: var(--surface2);
  opacity: 0.7;
}
.trend-col-label {
  position: relative;
  font-size: 11px;
  color: var(--text3);
  font-weight: 500;
  letter-spacing: 0.5px;
}
.trend-col.is-today .trend-col-label {
  color: var(--domain-color);
  font-weight: 700;
}
.trend-today-dot {
  display: inline-block;
  width: 4px;
  height: 4px;
  border-radius: 50%;
  background: var(--domain-color);
  margin-left: 3px;
  vertical-align: middle;
}

.trend-stats {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
  margin-top: 14px;
  padding-top: 12px;
  border-top: 1px dashed var(--border);
}
.trend-stat {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
}
.trend-stat-value {
  font-family: var(--font-num);
  font-size: 15px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: -0.2px;
}
.trend-stat.accent .trend-stat-value {
  color: var(--domain-color);
}
.trend-stat-label {
  font-size: 11px;
  color: var(--text3);
  letter-spacing: 0.3px;
}

.trend-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  height: 132px;
  padding: 16px;
}
.trend-empty-icon {
  font-size: 28px;
  opacity: 0.45;
}
.trend-empty-text {
  font-size: 12px;
  color: var(--text3);
}

@keyframes trend-rise {
  0% {
    opacity: 0;
    transform: translateY(8px);
  }
  100% {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (prefers-reduced-motion: reduce) {
  .trend-col {
    animation: none;
  }
  .trend-bar,
  .trend-col-value {
    transition: none;
  }
}
</style>
