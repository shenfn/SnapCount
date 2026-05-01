<template>
  <div class="page active">
    <div class="home-header">
      <div class="home-greeting">
        <div class="greeting-text">个人数据平台</div>
        <div class="greeting-date">{{ todayLabel }}</div>
      </div>
      <MonthPicker />
    </div>

    <div class="home-stats">
      <div class="stats-hero-card">
        <div class="stats-hero-label">本月支出</div>
        <div class="stats-hero-value">¥ {{ store.totalExpense.value.toFixed(2) }}</div>
        <div class="stats-hero-compare">已记录 {{ store.doneBills.value.length }} 笔支出 · 本月收入 ¥{{ store.totalIncome.value.toFixed(2) }}</div>
      </div>

      <div class="stats-row">
        <div class="stats-mini-card">
          <div class="stats-mini-icon income">入</div>
          <div>
            <div class="stats-mini-label">本月收入</div>
            <div class="stats-mini-value">¥ {{ store.totalIncome.value.toFixed(0) }}</div>
          </div>
        </div>
        <div class="stats-mini-card">
          <div class="stats-mini-icon balance">余</div>
          <div>
            <div class="stats-mini-label">本月结余</div>
            <div class="stats-mini-value">¥ {{ store.netBalance.value.toFixed(0) }}</div>
          </div>
        </div>
      </div>
    </div>

    <div v-if="store.pendingSummary.value.total" class="home-pending-alert" @click="store.currentPage.value = 'pending'">
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
      <div class="section-title">本周趋势</div>
      <div class="section-action" @click="store.currentPage.value = 'report'">报告 ›</div>
    </div>
    <div class="home-week-chart-wrap">
      <div class="home-week-chart-inner">
        <div class="week-bars platform-week-bars">
          <div v-for="(v, i) in weekData" :key="i" class="week-col">
            <div class="platform-week-bar-wrap">
              <div
                class="week-bar"
                :class="{ today: i === todayIdx }"
                :style="{ height: `${Math.max((v / weekMax) * 100, v > 0 ? 8 : 0)}%` }"
              ></div>
            </div>
            <div class="week-day">{{ weekLabels[i] }}</div>
          </div>
        </div>
      </div>
      <div class="home-week-stats">
        <div class="home-week-stat">
          <div class="home-week-stat-value">¥ {{ weekTotal.toFixed(0) }}</div>
          <div class="home-week-stat-label">本周累计</div>
        </div>
        <div class="home-week-stat">
          <div class="home-week-stat-value">¥ {{ weekPeak.toFixed(0) }}</div>
          <div class="home-week-stat-label">最高单日</div>
        </div>
        <div class="home-week-stat">
          <div class="home-week-stat-value">{{ todayWeekShare }}</div>
          <div class="home-week-stat-label">今日占比</div>
        </div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">已安装数据域</div>
      <div class="section-action" @click="store.currentPage.value = 'domains'">全部 ›</div>
    </div>
    <div class="home-domains-scroll">
      <div
        v-for="domain in store.domains.value"
        :key="domain.id"
        class="domain-quick-card"
        @click="store.currentPage.value = 'domains'"
      >
        <div class="domain-quick-icon" :style="{ background: `${domain.color}18`, color: domain.color }">
          {{ domain.icon }}
        </div>
        <div class="domain-quick-name">{{ domain.name }}</div>
        <div class="domain-quick-count">{{ domain.recordCount }} 条</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">最新时间线</div>
      <div class="section-action" @click="store.currentPage.value = 'pending'">待处理 ›</div>
    </div>
    <div class="home-timeline">
      <div v-if="!store.homeTimeline.value.length" class="empty-state">
        <div class="empty-title">还没有平台记录</div>
        <div class="empty-desc">从一张截图开始，后续会逐步沉淀成多数据域资产。</div>
      </div>
      <div
        v-for="item in store.homeTimeline.value"
        :key="item.id"
        class="timeline-item"
        @click="handleTimelineClick(item)"
      >
        <div class="timeline-marker" :style="{ background: `${item.color}18`, color: item.color }">
          {{ timelineMark(item.kind) }}
        </div>
        <div class="timeline-content">
          <div class="timeline-title-row">
            <div class="timeline-title">{{ item.title }}</div>
            <div class="timeline-value">{{ item.amountLabel }}</div>
          </div>
          <div class="timeline-sub">{{ item.subtitle }}</div>
          <div class="timeline-time">{{ formatDateTimeLabel(item.dateLabel) }}</div>
        </div>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
import { computeWeekData, formatDateTimeLabel } from '../../utils/helpers'
import MonthPicker from '../MonthPicker.vue'

const store = inject('store')
const weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']

const today = new Date()
const todayLabel = `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日`
const todayIdx = today.getDay() === 0 ? 6 : today.getDay() - 1

const weekData = computed(() => computeWeekData(store.bills.value))
const weekMax = computed(() => Math.max(...weekData.value, 1))
const weekTotal = computed(() => weekData.value.reduce((sum, value) => sum + value, 0))
const weekPeak = computed(() => Math.max(...weekData.value, 0))
const todayWeekShare = computed(() => {
  if (!weekTotal.value) return '0%'
  return `${Math.round(((weekData.value[todayIdx] || 0) / weekTotal.value) * 100)}%`
})

function timelineMark(kind) {
  const map = { expense: '支', income: '收', staging: '待' }
  return map[kind] || '记'
}

function handleTimelineClick(item) {
  if (item.kind === 'staging') {
    store.currentPage.value = 'pending'
    return
  }
  if (item.kind === 'income' && item.raw) {
    store.openIncomeEditModal(item.raw)
    return
  }
  if (item.kind === 'expense' && item.raw?.status === 'pending') {
    store.openPendingModal(item.raw)
    return
  }
  store.currentPage.value = 'domains'
}
</script>
