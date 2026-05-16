<template>
  <div class="page active">
    <div class="home-header">
      <div class="home-greeting">
        <div class="greeting-text">个人数据平台</div>
        <div class="greeting-date">{{ todayLabel }}</div>
      </div>
      <MonthPicker />
    </div>

    <!-- 今日结构化概览 -->
    <div class="today-overview" v-if="!store.todaySummary.value.isEmpty">
      <div class="today-overview-header">
        <span class="today-overview-date">{{ todayDayLabel }}</span>
      </div>
      <div class="today-overview-grid">
        <div class="today-overview-row" v-if="store.todaySummary.value.expenseCount">
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
        <div class="today-overview-row" v-if="store.todaySummary.value.incomeCount">
          <div class="today-overview-icon income">💰</div>
          <div class="today-overview-content">
            <div class="today-overview-label">收入 ¥{{ store.todaySummary.value.incomeTotal.toFixed(2) }}</div>
            <div class="today-overview-detail">{{ store.todaySummary.value.incomeCount }} 笔</div>
          </div>
        </div>
        <div class="today-overview-row" v-for="s in store.todaySummary.value.sportItems" :key="'sport-'+s.title" @click="store.openDomainPage('sport')">
          <div class="today-overview-icon sport">🏃</div>
          <div class="today-overview-content">
            <div class="today-overview-label">{{ s.title }}</div>
            <div class="today-overview-detail">{{ sportSummary(s) }}</div>
          </div>
        </div>
        <div class="today-overview-row" v-for="s in store.todaySummary.value.sleepItems" :key="'sleep-'+s.title" @click="store.openDomainPage('sleep')">
          <div class="today-overview-icon sleep">🌙</div>
          <div class="today-overview-content">
            <div class="today-overview-label">{{ s.title }}</div>
            <div class="today-overview-detail">{{ sleepSummary(s) }}</div>
          </div>
        </div>
        <div class="today-overview-row" v-if="store.todaySummary.value.foodCount" @click="store.openDomainPage('food')">
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
      <div class="section-title">本周支出趋势</div>
      <div class="section-action" @click="store.navigateTo('report')">报告 ›</div>
    </div>
    <DomainTrendPanel
      :values="weekData"
      :labels="weekLabels"
      :full-labels="weekFullLabels"
      :today-index="todayIdx"
      color="#C2410C"
      currency
      :show-stats="true"
      title=""
      scope="本周"
    />

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

    <div class="section-header">
      <div class="section-title">最新动态</div>
      <div class="section-action" @click="store.navigateTo('pending')">待处理 ›</div>
    </div>
    <div class="home-timeline">
      <div v-if="!store.homeTimeline.value.length" class="empty-state">
        <div class="empty-title">还没有平台记录</div>
        <div class="empty-desc">从一张截图开始，后续会逐步沉淀成多数据域资产。</div>
      </div>
      <template v-for="group in store.visibleTimelineGroups.value" :key="group.key">
        <div v-if="group.isCollapsed" class="timeline-expander" @click="store.timelineExpanded.value = true">
          <span>{{ group.label }}</span>
          <span class="timeline-expander-arrow">▸</span>
        </div>
        <template v-else>
          <div class="timeline-group-label">{{ group.label }}</div>
          <div
            v-for="item in group.items"
            :key="item.id"
            class="timeline-item"
            @click="handleTimelineClick(item)"
          >
            <div class="timeline-marker" :style="{ background: `${item.color}18`, color: item.color }">
              {{ timelineMark(item.kind) }}
            </div>
            <div class="timeline-content">
              <div class="timeline-title-row">
                <div class="timeline-title">
                  {{ item.title }}
                  <span v-if="isCrossDayEntry(item)" class="timeline-month-tag">补录</span>
                </div>
                <div class="timeline-value">{{ item.amountLabel }}</div>
              </div>
              <div class="timeline-sub">{{ item.subtitle }}</div>
              <div class="timeline-time">{{ timeLabel(item) }}</div>
            </div>
          </div>
        </template>
      </template>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
import { computeWeekData } from '../../utils/helpers'
import MonthPicker from '../MonthPicker.vue'
import DomainTrendPanel from '../domain/DomainTrendPanel.vue'

const store = inject('store')
const weekLabels = ['一', '二', '三', '四', '五', '六', '日']
const dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

const today = new Date()
const todayLabel = `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日`
const todayDayLabel = `${today.getMonth() + 1}月${today.getDate()}日 ${dayNames[today.getDay()]}`
const todayIdx = today.getDay() === 0 ? 6 : today.getDay() - 1

const weekFullLabels = computed(() => {
  const monday = new Date(today)
  monday.setDate(today.getDate() - (today.getDay() === 0 ? 6 : today.getDay() - 1))
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(monday)
    d.setDate(monday.getDate() + i)
    return `周${weekLabels[i]} ${d.getMonth() + 1}/${d.getDate()}`
  })
})

const weekData = computed(() => computeWeekData(store.bills.value))

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

function timelineMark(kind) {
  const map = { expense: '支', income: '收', staging: '待', universal: '域' }
  return map[kind] || '记'
}

function extractDatePart(value) {
  if (!value) return ''
  return String(value).slice(0, 10)
}

function isSameDay(d1, d2) {
  return extractDatePart(d1) === extractDatePart(d2)
}

function isCrossDayEntry(item) {
  const occ = item.occurredTime
  const upl = item.uploadTime
  if (!occ || !upl) return false
  return !isSameDay(occ, upl)
}

function fmtTimeOnly(value) {
  if (!value) return ''
  const s = String(value)
  // 如果包含 T，取时间部分
  if (s.includes('T')) {
    const t = s.split('T')[1]
    return t.slice(0, 5)
  }
  // 如果是 HH:MM 格式直接返回
  if (/^\d{2}:\d{2}/.test(s)) return s.slice(0, 5)
  // 尝试作为完整时间戳解析
  const d = new Date(s)
  if (!isNaN(d.getTime())) {
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
  }
  return ''
}

function fmtMonthDay(value) {
  const d = new Date(String(value).slice(0, 10) + 'T00:00:00')
  if (isNaN(d.getTime())) return ''
  return `${d.getMonth() + 1}月${d.getDate()}日`
}

function timeLabel(item) {
  const occ = item.occurredTime
  const upl = item.uploadTime

  if (item.kind === 'staging') {
    const t = occ || upl
    return t ? `截图于 ${fmtMonthDay(t)} ${fmtTimeOnly(t)}` : ''
  }

  // 支出
  if (item.kind === 'expense') {
    if (occ && upl && !isSameDay(occ, upl)) {
      return `消费于 ${fmtMonthDay(occ)} ${fmtTimeOnly(occ)} · 上传于 ${fmtMonthDay(upl)} ${fmtTimeOnly(upl)}`
    }
    const t = occ || upl
    if (t) return `消费于 ${fmtTimeOnly(t)}`
    return ''
  }

  // 收入
  if (item.kind === 'income') {
    if (occ && upl && !isSameDay(occ, upl)) {
      return `发生于 ${fmtMonthDay(occ)} · 上传于 ${fmtMonthDay(upl)}`
    }
    return occ ? `发生于 ${fmtMonthDay(occ)}` : ''
  }

  // 通用记录
  if (item.kind === 'universal') {
    if (occ && upl && !isSameDay(occ, upl)) {
      return `发生于 ${fmtMonthDay(occ)} ${fmtTimeOnly(occ)} · 上传于 ${fmtMonthDay(upl)}`
    }
    const t = occ || upl
    if (t) return `发生于 ${fmtMonthDay(t)} ${fmtTimeOnly(t)}`
    return ''
  }

  return ''
}

function handleTimelineClick(item) {
  if (item.kind === 'staging') {
    store.navigateTo('pending')
    return
  }
  if (item.kind === 'income' && item.raw) {
    store.openRecordDetail('income', item.raw)
    return
  }
  if (item.kind === 'expense' && item.raw) {
    store.openRecordDetail('expense', item.raw)
    return
  }
  if (item.kind === 'universal' && item.raw) {
    store.openRecordDetail('universal', item.raw)
  }
}
</script>
