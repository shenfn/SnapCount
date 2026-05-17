<template>
  <div class="page active">
    <div class="home-header">
      <div class="home-greeting">
        <div class="greeting-text">个人数据平台</div>
        <div class="greeting-date">{{ todayLabel }}</div>
      </div>
      <MonthPicker />
    </div>

    <div class="home-guide-strip">
      <button class="home-guide-pill" @click="scrollToSection('finance')">
        <span>净额</span>
        <strong>{{ finance.display.netWorthEstimate }}</strong>
      </button>
      <button class="home-guide-pill" @click="scrollToSection('today')">
        <span>今日</span>
        <strong>{{ finance.display.todayNet }}</strong>
      </button>
      <button class="home-guide-pill" @click="scrollToSection('finance')">
        <span>待还</span>
        <strong>{{ finance.display.liabilityTotal }}</strong>
      </button>
      <button class="home-guide-pill" @click="scrollToSection('daily')">
        <span>明细</span>
        <strong>{{ store.dailyCards.value.length }}天</strong>
      </button>
    </div>

    <section ref="financeSection" class="home-finance-section">
      <div class="section-header">
        <div class="section-title">财务状态</div>
        <div class="section-action" @click="store.navigateTo('report')">报告 ›</div>
      </div>
      <div class="finance-card">
        <div class="finance-card-top">
          <div>
            <div class="finance-kicker">{{ finance.statusLabel }}</div>
            <div class="finance-main-label">净额估算</div>
            <div class="finance-main-value">{{ finance.display.netWorthEstimate }}</div>
          </div>
          <button class="finance-badge" @click="store.openDomainPage('wallet')">钱包快照</button>
        </div>
        <div class="finance-split-grid">
          <div @click="store.openDomainPage('wallet')">
            <span>可用现金</span>
            <strong>{{ finance.display.availableCash }}</strong>
          </div>
          <div @click="store.openDomainPage('wallet')">
            <span>待还金额</span>
            <strong>{{ finance.display.liabilityTotal }}</strong>
          </div>
          <div @click="store.openDayDetail(todayKey, 'income')">
            <span>今日收入</span>
            <strong>{{ finance.display.todayIncome }}</strong>
          </div>
          <div @click="store.openDayDetail(todayKey, 'expense')">
            <span>今日支出</span>
            <strong>{{ finance.display.todayExpense }}</strong>
          </div>
        </div>
        <div class="finance-due-row" @click="openNearestLiability">
          <div>
            <div class="finance-due-label">最近待还</div>
            <div class="finance-due-name">{{ finance.nearestLiability?.accountName || '暂无待还' }}</div>
          </div>
          <div class="finance-due-value">
            <strong>{{ nearestLiabilityAmount }}</strong>
            <span>{{ nearestLiabilityDate }}</span>
          </div>
        </div>
        <div class="finance-trend">
          <div class="finance-trend-head">
            <span>近 7 日支出</span>
            <strong>{{ selectedTrendSummary }}</strong>
          </div>
          <div class="finance-bars">
            <div
              v-for="item in finance.sevenDayExpenseTrend"
              :key="item.dateKey"
              class="finance-bar-col"
              :class="{ selected: selectedTrendDateKey === item.dateKey }"
              @click="handleTrendClick(item)"
            >
              <div class="finance-bar-amount">¥{{ Math.round(item.amount) }}</div>
              <div class="finance-bar-wrap">
                <div
                  class="finance-bar"
                  :class="{ today: item.dateKey === todayKey, selected: selectedTrendDateKey === item.dateKey }"
                  :style="{ height: item.pct + '%' }"
                ></div>
              </div>
              <div class="finance-bar-label">{{ item.label }}</div>
            </div>
          </div>
          <div class="finance-trend-hint">{{ selectedTrendDateKey ? '再点选中柱子进入当天支出明细 ›' : '点柱子查看当天占比，再点进入明细' }}</div>
        </div>
      </div>
    </section>

    <!-- 今日结构化概览 -->
    <section ref="todaySection">
    <div class="today-overview" v-if="!store.todaySummary.value.isEmpty">
      <div class="today-overview-header">
        <span class="today-overview-date">{{ todayDayLabel }}</span>
      </div>
      <div class="today-overview-grid">
        <div class="today-overview-row" v-if="store.todaySummary.value.expenseCount" @click="store.openDayDetail(todayKey, 'expense')">
          <div class="today-overview-icon expense">💸</div>
          <div class="today-overview-content">
            <div class="today-overview-label">支出 ¥{{ store.todaySummary.value.expenseTotal.toFixed(2) }}</div>
            <div class="today-overview-detail">
              <template v-for="(count, platform, i) in store.todaySummary.value.expenseByPlatform" :key="platform">
                {{ platform }}×{{ count }}<span v-if="i < Object.keys(store.todaySummary.value.expenseByPlatform).length - 1"> · </span>
              </template>
            </div>
          </div>
        </div>
        <div class="today-overview-row pending-row" v-if="store.todaySummary.value.pendingExpenseCount"
          @click="store.navigateTo('pending')">
          <div class="today-overview-icon pending">⚠️</div>
          <div class="today-overview-content">
            <div class="today-overview-label">
              待补全 ¥{{ store.todaySummary.value.pendingExpenseTotal.toFixed(2) }}
            </div>
            <div class="today-overview-detail">
              {{ store.todaySummary.value.pendingExpenseCount }} 笔已识别金额，待补全分类 ›
            </div>
          </div>
        </div>
        <div class="today-overview-row" v-if="store.todaySummary.value.incomeCount" @click="store.openDayDetail(todayKey, 'income')">
          <div class="today-overview-icon income">💰</div>
          <div class="today-overview-content">
            <div class="today-overview-label">收入 ¥{{ store.todaySummary.value.incomeTotal.toFixed(2) }}</div>
            <div class="today-overview-detail">{{ store.todaySummary.value.incomeCount }} 笔</div>
          </div>
        </div>
        <div class="today-overview-row" v-for="s in store.todaySummary.value.sportItems" :key="'sport-'+s.title" @click="store.openDayDetail(todayKey, 'sport')">
          <div class="today-overview-icon sport">🏃</div>
          <div class="today-overview-content">
            <div class="today-overview-label">{{ s.title }}</div>
            <div class="today-overview-detail">{{ sportSummary(s) }}</div>
          </div>
        </div>
        <div class="today-overview-row" v-for="s in store.todaySummary.value.sleepItems" :key="'sleep-'+s.title" @click="store.openDayDetail(todayKey, 'sleep')">
          <div class="today-overview-icon sleep">🌙</div>
          <div class="today-overview-content">
            <div class="today-overview-label">{{ s.title }}</div>
            <div class="today-overview-detail">{{ sleepSummary(s) }}</div>
          </div>
        </div>
        <div class="today-overview-row" v-if="store.todaySummary.value.foodCount" @click="store.openDayDetail(todayKey, 'food')">
          <div class="today-overview-icon food">🍱</div>
          <div class="today-overview-content">
            <div class="today-overview-label">今日饮食</div>
            <div class="today-overview-detail">{{ store.todaySummary.value.foodCount }} 餐 · 约 {{ store.todaySummary.value.foodCalorieTotal }} 千卡（估算）</div>
          </div>
        </div>
      </div>
      <div class="today-overview-footer" v-if="store.todaySummary.value.stagingCount" @click="store.navigateTo('pending')">
        ⏳ {{ store.todaySummary.value.stagingCount }} 条截图待确认 ›
      </div>
    </div>

    <!-- 空态 -->
    <div v-if="store.todaySummary.value.isEmpty && !store.timelineGroups.value.length" class="empty-state" style="margin-top: 24px;">
      <div class="empty-title">今天还没有记录</div>
      <div class="empty-desc">从一张截图开始，后续会逐步沉淀成多数据域资产。</div>
    </div>
    </section>

    <div v-if="store.pendingSummary.value.total" class="home-pending-alert" @click="store.navigateTo('pending')">
      <div class="pending-alert-icon">
        待
        <div class="pending-alert-dot"></div>
      </div>
      <div class="pending-alert-content">
        <div class="pending-alert-title">{{ store.pendingSummary.value.total }} 条待处理记录</div>
        <div class="pending-alert-desc">
          {{ store.pendingSummary.value.routingFailed }} 条待分类 ·
          {{ store.pendingSummary.value.pendingReview }} 条待确认 ·
          {{ store.pendingSummary.value.aiError }} 条识别失败
        </div>
      </div>
      <div class="pending-alert-arrow">›</div>
    </div>

    <div class="section-header">
      <div class="section-title">已安装数据域</div>
      <div class="section-action" @click="store.navigateTo('domains')">全部 ›</div>
    </div>
    <div class="home-domains-grid">
      <div
        v-for="domain in store.domains.value"
        :key="domain.id"
        class="domain-quick-card"
        @click="store.openDomainPage(domain.id)"
      >
        <div class="domain-quick-icon" :style="{ background: `${domain.color}18`, color: domain.color }">
          {{ domain.icon }}
        </div>
        <div class="domain-quick-name">{{ domain.name }}</div>
        <div class="domain-quick-count">{{ domain.recordCount }} 条</div>
      </div>
    </div>

    <div ref="dailySection" class="section-header home-daily-header">
      <div>
        <div class="section-title">每日明细</div>
        <div class="home-daily-sub">按日期汇总本月所有数据</div>
      </div>
      <div class="section-action" @click="store.navigateTo('report')">报告 ›</div>
    </div>
    <div class="home-daily-grid">
      <div
        v-for="card in store.visibleDailyCards.value"
        :key="card.dateKey"
        class="home-daily-card"
        :class="{ empty: card.isEmpty }"
        @click="store.openDayDetail(card.dateKey)"
      >
        <div class="home-daily-card-head">
          <div class="home-daily-date">{{ card.monthDay }}</div>
          <div class="home-daily-week">{{ card.weekday.replace('周', '周') }}</div>
        </div>
        <div class="home-daily-divider"></div>
        <div v-if="card.rows.length" class="home-daily-lines">
          <div v-for="row in card.rows" :key="row.kind" class="home-daily-line">
            <span class="home-daily-dot" :style="{ background: row.color }"></span>
            <span class="home-daily-label">{{ row.label }}</span>
            <strong class="home-daily-value">{{ row.value }}</strong>
          </div>
        </div>
        <div v-else class="home-daily-empty">这天还没有记录</div>
      </div>
    </div>
    <button
      v-if="store.visibleDailyCards.value.length < store.dailyCards.value.length"
      class="home-daily-more"
      @click="store.showMoreDailyCards()"
    >
      查看更多日期
    </button>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject, ref, watch } from 'vue'
import MonthPicker from '../MonthPicker.vue'

const store = inject('store')
const dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
const financeSection = ref(null)
const todaySection = ref(null)
const dailySection = ref(null)
const selectedTrendDateKey = ref('')

const today = new Date()
const todayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`
const todayLabel = `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日`
const todayDayLabel = `${today.getMonth() + 1}月${today.getDate()}日 ${dayNames[today.getDay()]}`

const finance = computed(() => store.financeOverview.value)
const selectedTrendItem = computed(() => {
  return finance.value.sevenDayExpenseTrend.find(item => item.dateKey === selectedTrendDateKey.value)
    || finance.value.todayTrend
    || finance.value.sevenDayExpenseTrend[finance.value.sevenDayExpenseTrend.length - 1]
})
const selectedTrendSummary = computed(() => {
  const item = selectedTrendItem.value
  if (!item) return `今日占比 ${finance.value.todayExpenseShare}%`
  const total = finance.value.sevenDayExpenseTrend.reduce((sum, trend) => sum + trend.amount, 0)
  const share = total > 0 ? Math.round(item.amount / total * 100) : 0
  return `${item.dateKey === todayKey ? '今日' : item.dateKey.slice(5)}占比 ${share}%`
})
const nearestLiabilityAmount = computed(() => {
  const amount = finance.value.nearestLiability?.amount
  return amount ? `¥${Number(amount).toFixed(0)}` : '--'
})
const nearestLiabilityDate = computed(() => {
  const item = finance.value.nearestLiability
  if (!item) return '无待还'
  if (item.dueDate) return item.dueDate.slice(5)
  if (item.billDay) return `每月${item.billDay}号`
  return '待补还款日'
})

function scrollToSection(key) {
  const target = key === 'finance' ? financeSection.value : key === 'today' ? todaySection.value : dailySection.value
  target?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

function openNearestLiability() {
  const record = finance.value.nearestLiability?.raw
  if (record) {
    store.openRecordDetail('universal', record)
    return
  }
  store.openDomainPage('wallet')
}

function handleTrendClick(item) {
  if (selectedTrendDateKey.value === item.dateKey) {
    store.openDayDetail(item.dateKey, 'expense')
    return
  }
  selectedTrendDateKey.value = item.dateKey
}

watch(finance, value => {
  if (!selectedTrendDateKey.value && value?.todayTrend?.dateKey) selectedTrendDateKey.value = value.todayTrend.dateKey
}, { immediate: true })

function sportSummary(s) {
  const parts = []
  if (s.payload?.duration_minutes) parts.push(`${s.payload.duration_minutes}分钟`)
  if (s.payload?.distance_km) parts.push(`${s.payload.distance_km}km`)
  return parts.length ? parts.join(' · ') : s.summary
}

function sleepSummary(s) {
  const parts = []
  if (s.payload?.sleep_hours) parts.push(`${s.payload.sleep_hours}h`)
  if (s.payload?.quality_level) parts.push(s.payload.quality_level)
  return parts.length ? parts.join(' · ') : s.summary
}
</script>

<style scoped>
.home-guide-strip {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 8px;
  padding: 0 16px 10px;
}

.home-guide-pill {
  border: 1px solid rgba(26, 26, 24, 0.06);
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  padding: 9px 8px;
  font-family: var(--font);
  text-align: left;
  box-shadow: 0 6px 16px rgba(15, 23, 42, 0.035);
}

.home-guide-pill span {
  display: block;
  color: var(--text3);
  font-size: 11px;
  font-weight: 600;
}

.home-guide-pill strong {
  display: block;
  margin-top: 2px;
  color: #10100f;
  font-family: var(--font-num);
  font-size: 13px;
  font-weight: 900;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.home-finance-section {
  scroll-margin-top: 12px;
}

.finance-card {
  margin: 0 16px 18px;
  border: 1px solid rgba(26, 26, 24, 0.06);
  border-radius: 26px;
  background:
    radial-gradient(circle at 92% 8%, rgba(180, 83, 9, 0.12), transparent 30%),
    linear-gradient(145deg, #ffffff 0%, #fffaf3 100%);
  box-shadow: 0 16px 36px rgba(33, 37, 41, 0.08);
  padding: 20px;
}

.finance-card-top {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: flex-start;
}

.finance-kicker {
  display: inline-flex;
  border-radius: 999px;
  background: rgba(45, 106, 79, 0.1);
  color: var(--primary);
  padding: 4px 9px;
  font-size: 11px;
  font-weight: 800;
}

.finance-main-label {
  margin-top: 13px;
  color: var(--text2);
  font-size: 13px;
  font-weight: 700;
}

.finance-main-value {
  margin-top: 2px;
  color: #0b0b0a;
  font-family: var(--font-num);
  font-size: 36px;
  font-weight: 900;
  letter-spacing: -0.04em;
}

.finance-badge {
  flex: 0 0 auto;
  border: none;
  border-radius: 999px;
  background: #f4e5db;
  color: #a54f1d;
  padding: 7px 11px;
  font-size: 12px;
  font-weight: 800;
  font-family: var(--font);
  cursor: pointer;
}

.finance-split-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  margin-top: 16px;
}

.finance-split-grid div {
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  border: 1px solid rgba(26, 26, 24, 0.05);
  padding: 11px 12px;
  cursor: pointer;
  transition: transform 0.16s ease, border-color 0.16s ease;
}

.finance-split-grid div:active,
.finance-due-row:active,
.finance-bar-col:active,
.finance-badge:active {
  transform: scale(0.985);
}

.finance-split-grid span {
  display: block;
  color: var(--text3);
  font-size: 11px;
  font-weight: 700;
}

.finance-split-grid strong {
  display: block;
  margin-top: 3px;
  color: #111827;
  font-family: var(--font-num);
  font-size: 17px;
  font-weight: 900;
}

.finance-due-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: center;
  margin-top: 12px;
  border-radius: 18px;
  background: rgba(124, 58, 237, 0.08);
  padding: 13px 14px;
  cursor: pointer;
  transition: transform 0.16s ease;
}

.finance-due-label {
  color: #7c6f91;
  font-size: 11px;
  font-weight: 800;
}

.finance-due-name {
  margin-top: 3px;
  color: #1f163f;
  font-size: 15px;
  font-weight: 800;
}

.finance-due-value {
  text-align: right;
}

.finance-due-value strong {
  display: block;
  color: #1f163f;
  font-family: var(--font-num);
  font-size: 18px;
  font-weight: 900;
}

.finance-due-value span {
  display: block;
  margin-top: 2px;
  color: #7c6f91;
  font-size: 11px;
  font-weight: 700;
}

.finance-trend {
  margin-top: 16px;
  padding-top: 14px;
  border-top: 1px dashed #e8dfd5;
}

.finance-trend-head {
  display: flex;
  justify-content: space-between;
  color: var(--text2);
  font-size: 12px;
  font-weight: 700;
}

.finance-trend-head strong {
  color: #a54f1d;
}

.finance-bars {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  gap: 8px;
  align-items: end;
  margin-top: 14px;
}

.finance-bar-col {
  display: grid;
  gap: 5px;
  justify-items: center;
  cursor: pointer;
  transition: transform 0.16s ease;
}

.finance-bar-col.selected .finance-bar-amount,
.finance-bar-col.selected .finance-bar-label {
  color: #9a4d16;
  font-weight: 900;
}

.finance-bar-amount {
  color: var(--text2);
  font-family: var(--font-num);
  font-size: 11px;
  font-weight: 800;
}

.finance-bar-wrap {
  width: 100%;
  height: 74px;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}

.finance-bar {
  width: 22px;
  min-height: 5px;
  border-radius: 10px;
  background: linear-gradient(180deg, #ead9cf 0%, #f3e7df 100%);
}

.finance-bar.today {
  width: 28px;
  background: linear-gradient(180deg, #b45309 0%, #e4b79e 100%);
}

.finance-bar.selected {
  width: 30px;
  background: linear-gradient(180deg, #92400e 0%, #d69a74 100%);
  box-shadow: 0 8px 18px rgba(146, 64, 14, 0.22);
}

.finance-bar-label {
  color: #9b978f;
  font-size: 12px;
  font-weight: 800;
}

.finance-trend-hint {
  margin-top: 10px;
  color: #a56538;
  font-size: 12px;
  font-weight: 800;
  text-align: center;
}

.home-daily-header {
  align-items: flex-end;
  scroll-margin-top: 12px;
}

.home-daily-sub {
  margin-top: 3px;
  font-size: 12px;
  color: var(--text3);
  font-weight: 500;
}

.home-daily-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 12px;
  padding: 0 16px;
}

.home-daily-card {
  min-height: 0;
  border: 1px solid rgba(15, 23, 42, 0.06);
  border-radius: 22px;
  background: #fff;
  box-shadow: 0 10px 24px rgba(15, 23, 42, 0.055);
  padding: 18px 20px 18px;
  cursor: pointer;
  transition: transform 0.18s ease, box-shadow 0.18s ease;
}

.home-daily-card:active {
  transform: scale(0.985);
  box-shadow: 0 6px 16px rgba(15, 23, 42, 0.05);
}

.home-daily-card.empty {
  opacity: 0.72;
}

.home-daily-card-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.home-daily-date {
  font-family: var(--font-num);
  font-size: 24px;
  font-weight: 900;
  letter-spacing: -0.04em;
  color: #020617;
}

.home-daily-week {
  color: #8c877e;
  font-size: 15px;
  font-weight: 600;
}

.home-daily-divider {
  margin: 12px 0 14px;
  border-top: 1px dashed #e6e0d7;
}

.home-daily-lines {
  display: grid;
  gap: 9px;
}

.home-daily-line {
  display: grid;
  grid-template-columns: 12px minmax(52px, auto) minmax(0, 1fr);
  align-items: center;
  gap: 7px;
  min-width: 0;
}

.home-daily-dot {
  width: 8px;
  height: 8px;
  border-radius: 999px;
}

.home-daily-label {
  color: #4b5563;
  font-size: 15px;
  white-space: nowrap;
}

.home-daily-value {
  min-width: 0;
  justify-self: end;
  color: #020617;
  font-family: var(--font-num);
  font-size: 15px;
  font-weight: 900;
  text-align: right;
  overflow-wrap: anywhere;
  white-space: normal;
}

.home-daily-empty {
  color: var(--text3);
  font-size: 13px;
  line-height: 1.6;
}

.home-daily-more {
  display: block;
  width: calc(100% - 32px);
  margin: 14px 16px 0;
  border: 1px solid rgba(15, 23, 42, 0.08);
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  color: var(--text);
  padding: 13px 16px;
  font-size: 14px;
  font-weight: 700;
  font-family: var(--font);
}

</style>
