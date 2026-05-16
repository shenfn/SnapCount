<template>
  <div class="distribution" :style="cssVars">
    <div class="distribution-header">
      <div class="distribution-title">{{ title }}</div>
      <div v-if="topLabel" class="distribution-top">{{ topLabel }}</div>
    </div>

    <div v-if="!items.length" class="distribution-empty">
      <div class="distribution-empty-icon">◇</div>
      <div class="distribution-empty-title">{{ emptyTitle }}</div>
      <div v-if="emptyDesc" class="distribution-empty-desc">{{ emptyDesc }}</div>
    </div>

    <div v-else class="distribution-list">
      <div
        v-for="(item, index) in items"
        :key="item.name"
        class="distribution-row"
        :style="{ animationDelay: `${index * 50}ms` }"
      >
        <div class="distribution-rank" :class="rankClass(index)">{{ index + 1 }}</div>
        <div class="distribution-main">
          <div class="distribution-row-top">
            <div class="distribution-name" :title="item.name">{{ item.name }}</div>
            <div class="distribution-display">{{ item.display }}</div>
          </div>
          <div class="distribution-track">
            <div
              class="distribution-fill"
              :class="{ 'is-top': index === 0 }"
              :style="{ width: `${Math.max(item.pct || 0, 2)}%` }"
            ></div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  items: { type: Array, required: true },     // [{ name, value?, pct, display }]
  color: { type: String, default: '#2d6a4f' },
  title: { type: String, default: '维度分布' },
  topLabel: { type: String, default: '' },     // 右上角标签如 'Top 6'
  emptyTitle: { type: String, default: '还没有可分析的数据' },
  emptyDesc: { type: String, default: '' },
})

const cssVars = computed(() => ({
  '--domain-color': props.color,
  '--domain-color-soft': hexAlpha(props.color, 0.10),
  '--domain-color-mid':  hexAlpha(props.color, 0.30),
  '--domain-color-deep': hexAlpha(props.color, 0.85),
}))

function rankClass(idx) {
  if (idx === 0) return 'rank-1'
  if (idx === 1) return 'rank-2'
  if (idx === 2) return 'rank-3'
  return ''
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
.distribution {
  margin: 0 16px 16px;
  padding: 16px 16px 12px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 16px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04), 0 6px 16px rgba(33, 37, 41, 0.04);
}
.distribution-header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 12px;
}
.distribution-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: 0.2px;
}
.distribution-top {
  font-size: 11px;
  color: var(--domain-color);
  font-weight: 600;
  letter-spacing: 0.5px;
  background: var(--domain-color-soft);
  padding: 3px 9px;
  border-radius: 999px;
}

.distribution-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.distribution-row {
  display: flex;
  align-items: center;
  gap: 10px;
  animation: dist-fade-in 0.42s cubic-bezier(0.22, 0.61, 0.36, 1) both;
}
.distribution-rank {
  width: 22px;
  height: 22px;
  border-radius: 7px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--font-num);
  font-size: 11px;
  font-weight: 700;
  color: var(--text3);
  background: var(--surface2);
  flex-shrink: 0;
  letter-spacing: -0.5px;
}
.distribution-rank.rank-1 {
  color: #b45309;
  background: linear-gradient(135deg, rgba(251, 191, 36, 0.20) 0%, rgba(217, 119, 6, 0.14) 100%);
}
.distribution-rank.rank-2 {
  color: #6b7280;
  background: linear-gradient(135deg, rgba(209, 213, 219, 0.40) 0%, rgba(156, 163, 175, 0.20) 100%);
}
.distribution-rank.rank-3 {
  color: #9a3412;
  background: linear-gradient(135deg, rgba(251, 146, 60, 0.18) 0%, rgba(194, 65, 12, 0.12) 100%);
}

.distribution-main {
  flex: 1;
  min-width: 0;
}
.distribution-row-top {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 5px;
}
.distribution-name {
  font-size: 13px;
  color: var(--text);
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 60%;
}
.distribution-display {
  font-family: var(--font-num);
  font-size: 12px;
  font-weight: 700;
  color: var(--text2);
  flex-shrink: 0;
}

.distribution-track {
  height: 6px;
  border-radius: 4px;
  background: var(--surface2);
  overflow: hidden;
  position: relative;
}
.distribution-fill {
  height: 100%;
  border-radius: 4px;
  background: var(--domain-color-mid);
  transition: width 0.5s cubic-bezier(0.22, 0.61, 0.36, 1);
  animation: dist-fill 0.65s cubic-bezier(0.22, 0.61, 0.36, 1) both;
}
.distribution-fill.is-top {
  background: linear-gradient(90deg, var(--domain-color) 0%, var(--domain-color-deep) 100%);
}

.distribution-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 24px 12px 18px;
  text-align: center;
}
.distribution-empty-icon {
  font-size: 26px;
  color: var(--text3);
  opacity: 0.45;
  margin-bottom: 8px;
}
.distribution-empty-title {
  font-size: 13px;
  font-weight: 700;
  color: var(--text2);
  margin-bottom: 4px;
}
.distribution-empty-desc {
  font-size: 11px;
  color: var(--text3);
  line-height: 1.5;
  max-width: 240px;
}

@keyframes dist-fade-in {
  0%   { opacity: 0; transform: translateX(-6px); }
  100% { opacity: 1; transform: translateX(0); }
}
@keyframes dist-fill {
  0%   { width: 0; }
}
@media (prefers-reduced-motion: reduce) {
  .distribution-row,
  .distribution-fill { animation: none; }
}
</style>
