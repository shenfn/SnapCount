<template>
  <div class="page active day-detail-page">
    <div class="day-detail-header">
      <button class="day-detail-back" @click="store.goBack()">‹</button>
      <div>
        <div class="day-detail-title">{{ title }}</div>
        <div class="day-detail-sub">{{ kindLabel }} · {{ store.activeDayRecords.value.length }} 条记录 · {{ store.monthLabel.value }}</div>
      </div>
    </div>

    <div class="day-detail-summary-card">
      <div class="day-detail-summary-date">{{ monthDay }}</div>
      <div class="day-detail-summary-week">{{ weekday }}</div>
      <div class="day-detail-summary-lines">
        <div v-for="row in cardRows" :key="row.kind" class="day-detail-summary-line">
          <span class="day-dot" :style="{ background: row.color }"></span>
          <span>{{ row.label }}</span>
          <strong>{{ row.value }}</strong>
        </div>
      </div>
    </div>

    <div class="section-header day-detail-section-header">
      <div class="section-title">当天明细</div>
      <div class="section-action" @click="store.openDayDetail(todayKey)">回到今天</div>
    </div>

    <div class="day-record-list">
      <div v-if="!store.activeDayRecords.value.length" class="empty-state">
        <div class="empty-title">这一天还没有记录</div>
        <div class="empty-desc">有截图、手动记录或钱包快照后，会自动出现在这里。</div>
      </div>
      <div
        v-for="item in store.activeDayRecords.value"
        :key="item.id"
        class="day-record-item"
        @click="openRecord(item)"
      >
        <div class="day-record-mark" :style="{ background: `${item.color}18`, color: item.color }">{{ item.icon }}</div>
        <div class="day-record-main">
          <div class="day-record-top">
            <div class="day-record-title">{{ item.title }}</div>
            <div class="day-record-value">{{ item.value }}</div>
          </div>
          <div class="day-record-sub">{{ item.subtitle }}</div>
          <div class="day-record-time">{{ item.time || '全天' }}</div>
        </div>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'

const store = inject('store')
const dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
const today = new Date()
const todayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

const activeCard = computed(() => store.dailyCards.value.find(item => item.dateKey === store.activeDateKey.value) || null)
const title = computed(() => {
  if (!store.activeDateKey.value) return '每日明细'
  const d = new Date(`${store.activeDateKey.value}T00:00:00`)
  if (Number.isNaN(d.getTime())) return store.activeDateKey.value
  return `${d.getMonth() + 1}月${d.getDate()}日 ${dayNames[d.getDay()]}`
})
const monthDay = computed(() => store.activeDateKey.value?.slice(5) || '--')
const weekday = computed(() => activeCard.value?.weekday || '')
const cardRows = computed(() => activeCard.value?.rows || [])
const kindLabel = computed(() => {
  const map = {
    all: '全部',
    expense: '支出',
    income: '收入',
    sleep: '睡眠',
    sport: '运动',
    food: '饮食',
    reading: '阅读',
    wallet: '钱包',
    staging: '待处理',
  }
  return map[store.activeDayKind.value] || '全部'
})

function openRecord(item) {
  if (item.kind === 'staging') {
    store.navigateTo('pending')
    return
  }
  if (item.kind === 'income') {
    store.openRecordDetail('income', item.raw)
    return
  }
  if (item.kind === 'expense') {
    store.openRecordDetail('expense', item.raw)
    return
  }
  if (item.kind === 'universal') store.openRecordDetail('universal', item.raw)
}
</script>

<style scoped>
.day-detail-page {
  padding: 18px 16px calc(var(--nav-h) + env(safe-area-inset-bottom, 0px) + 56px);
}

.day-detail-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin: 8px 0 18px;
}

.day-detail-back {
  width: 36px;
  height: 36px;
  border: none;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.78);
  color: var(--text);
  font-size: 28px;
  line-height: 1;
  box-shadow: var(--shadow-sm);
}

.day-detail-title {
  font-size: 22px;
  font-weight: 800;
  color: #0f172a;
}

.day-detail-sub {
  margin-top: 2px;
  font-size: 12px;
  color: var(--text2);
}

.day-detail-summary-card {
  position: relative;
  border: 1px solid rgba(15, 23, 42, 0.06);
  border-radius: 24px;
  background: #fff;
  box-shadow: 0 12px 28px rgba(15, 23, 42, 0.06);
  padding: 22px 28px 24px;
}

.day-detail-summary-date {
  font-family: var(--font-num);
  font-size: 32px;
  font-weight: 900;
  letter-spacing: -0.04em;
  color: #020617;
}

.day-detail-summary-week {
  position: absolute;
  top: 26px;
  right: 28px;
  color: #8c877e;
  font-size: 18px;
  font-weight: 600;
}

.day-detail-summary-lines {
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px dashed #e5e0d8;
  display: grid;
  gap: 10px;
}

.day-detail-summary-line {
  display: grid;
  grid-template-columns: 12px 1fr auto;
  align-items: center;
  gap: 10px;
  font-size: 16px;
  color: #4b5563;
}

.day-detail-summary-line strong {
  font-size: 18px;
  color: #020617;
}

.day-dot {
  width: 9px;
  height: 9px;
  border-radius: 999px;
}

.day-detail-section-header {
  padding: 0;
  margin: 22px 0 12px;
}

.day-record-list {
  display: grid;
  gap: 10px;
}

.day-record-item {
  display: flex;
  gap: 12px;
  border: 1px solid rgba(15, 23, 42, 0.06);
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.82);
  padding: 14px;
  box-shadow: 0 8px 18px rgba(15, 23, 42, 0.04);
}

.day-record-mark {
  width: 38px;
  height: 38px;
  border-radius: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 800;
  flex: 0 0 auto;
}

.day-record-main {
  min-width: 0;
  flex: 1;
}

.day-record-top {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 8px 12px;
  align-items: start;
}

.day-record-title {
  min-width: 0;
  font-size: 15px;
  font-weight: 700;
  color: #111827;
  white-space: normal;
  word-break: break-word;
}

.day-record-value {
  font-family: var(--font-num);
  font-size: 15px;
  font-weight: 900;
  color: #020617;
  flex: 0 0 auto;
  text-align: right;
  white-space: nowrap;
  max-width: 36vw;
  overflow: hidden;
  text-overflow: ellipsis;
}

.day-record-sub {
  margin-top: 3px;
  font-size: 12px;
  color: var(--text2);
  white-space: normal;
  word-break: break-word;
  line-height: 1.45;
}

.day-record-time {
  margin-top: 5px;
  font-size: 11px;
  color: var(--text3);
}

@media (max-width: 390px) {
  .day-detail-summary-card {
    padding: 20px 18px 22px;
  }

  .day-detail-summary-week {
    position: static;
    margin-top: 4px;
    font-size: 15px;
  }

  .day-detail-summary-line {
    grid-template-columns: 12px minmax(0, 1fr);
    align-items: start;
  }

  .day-detail-summary-line strong {
    grid-column: 2;
    margin-top: 2px;
    font-size: 16px;
  }

  .day-record-item {
    padding: 14px 12px;
  }

  .day-record-top {
    grid-template-columns: 1fr;
    gap: 4px;
  }

  .day-record-value {
    text-align: left;
    max-width: none;
    overflow: visible;
    text-overflow: initial;
  }
}
</style>
