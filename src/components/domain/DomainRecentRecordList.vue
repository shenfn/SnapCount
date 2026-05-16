<template>
  <div class="record-list" :style="cssVars">
    <div class="record-list-header">
      <div class="record-list-title">{{ title }}</div>
      <div v-if="records.length" class="record-list-count">{{ records.length }} 条</div>
    </div>

    <div v-if="!records.length" class="record-empty">
      <div class="record-empty-icon">{{ emptyIcon }}</div>
      <div class="record-empty-title">{{ emptyTitle }}</div>
      <div v-if="emptyDesc" class="record-empty-desc">{{ emptyDesc }}</div>
    </div>

    <div v-else class="record-rows">
      <div
        v-for="(item, index) in records"
        :key="item.id"
        class="record-row"
        :style="{ animationDelay: `${Math.min(index, 8) * 35}ms` }"
        @click="$emit('select', item)"
      >
        <div class="record-mark"><span>{{ item.icon || '·' }}</span></div>
        <div class="record-main">
          <div class="record-row-top">
            <div class="record-title" :title="item.title">{{ item.title }}</div>
            <div class="record-value" :class="valueClass(item)">{{ item.value }}</div>
          </div>
          <div v-if="item.subtitle" class="record-sub">{{ item.subtitle }}</div>
          <div v-if="item.date" class="record-date">{{ item.date }}</div>
        </div>
        <div class="record-arrow">›</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  records: { type: Array, required: true },
  // [{ id, kind?, icon, title, subtitle?, value, date?, raw? }]
  color: { type: String, default: '#2d6a4f' },
  title: { type: String, default: '最近记录' },
  emptyIcon: { type: String, default: '◇' },
  emptyTitle: { type: String, default: '还没有记录' },
  emptyDesc: { type: String, default: '后续接入后这里会自动填充。' },
})
defineEmits(['select'])

const cssVars = computed(() => ({
  '--domain-color': props.color,
  '--domain-color-soft': hexAlpha(props.color, 0.10),
  '--domain-color-mid':  hexAlpha(props.color, 0.20),
}))

function valueClass(item) {
  if (item.kind === 'expense') return 'expense'
  if (item.kind === 'income') return 'income'
  return 'neutral'
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
.record-list {
  margin: 0 16px 16px;
}
.record-list-header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin: 0 4px 10px;
}
.record-list-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: 0.2px;
}
.record-list-count {
  font-size: 11px;
  color: var(--text3);
  font-weight: 600;
  letter-spacing: 0.4px;
}

.record-rows {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.record-row {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 14px 12px 14px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  cursor: pointer;
  overflow: hidden;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
  transition: transform 0.18s ease, box-shadow 0.18s ease, border-color 0.18s ease;
  animation: row-fade-in 0.4s cubic-bezier(0.22, 0.61, 0.36, 1) both;
}
.record-row::before {
  content: '';
  position: absolute;
  left: 0;
  top: 12px;
  bottom: 12px;
  width: 3px;
  border-radius: 0 3px 3px 0;
  background: var(--domain-color);
  opacity: 0.7;
  transition: opacity 0.18s ease, width 0.18s ease;
}
.record-row:hover {
  border-color: var(--domain-color-mid);
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04), 0 4px 14px rgba(33, 37, 41, 0.06);
}
.record-row:hover::before {
  opacity: 1;
  width: 4px;
}
.record-row:active {
  transform: scale(0.99);
}

.record-mark {
  width: 36px;
  height: 36px;
  border-radius: 11px;
  background: var(--domain-color-soft);
  color: var(--domain-color);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 16px;
  font-weight: 700;
  flex-shrink: 0;
}

.record-main {
  flex: 1;
  min-width: 0;
}
.record-row-top {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 3px;
}
.record-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: 0.1px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.record-value {
  font-family: var(--font-num);
  font-size: 14px;
  font-weight: 700;
  flex-shrink: 0;
  letter-spacing: -0.2px;
}
.record-value.expense { color: #b91c1c; }
.record-value.income  { color: #047857; }
.record-value.neutral { color: var(--domain-color); }

.record-sub {
  font-size: 11px;
  color: var(--text2);
  margin-bottom: 2px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.record-date {
  font-size: 10px;
  color: var(--text3);
  font-family: var(--font-num);
  letter-spacing: 0.3px;
}

.record-arrow {
  color: var(--text3);
  font-size: 18px;
  font-weight: 300;
  flex-shrink: 0;
  transition: transform 0.18s ease, color 0.18s ease;
}
.record-row:hover .record-arrow {
  color: var(--domain-color);
  transform: translateX(2px);
}

.record-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 28px 16px 24px;
  background: var(--bg-card);
  border: 1px dashed var(--border2);
  border-radius: 14px;
  text-align: center;
}
.record-empty-icon {
  font-size: 28px;
  color: var(--text3);
  opacity: 0.4;
  margin-bottom: 10px;
}
.record-empty-title {
  font-size: 13px;
  color: var(--text2);
  font-weight: 700;
  margin-bottom: 4px;
}
.record-empty-desc {
  font-size: 11px;
  color: var(--text3);
  line-height: 1.5;
  max-width: 260px;
}

@keyframes row-fade-in {
  0%   { opacity: 0; transform: translateY(6px); }
  100% { opacity: 1; transform: translateY(0); }
}
@media (prefers-reduced-motion: reduce) {
  .record-row { animation: none; }
}
</style>
