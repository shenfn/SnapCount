<template>
  <div class="page active">
    <div class="topbar">
      <h1>收入</h1>
      <MonthPicker />
    </div>

    <div class="income-hero">
      <div class="label">本月总收入</div>
      <div class="amount">¥{{ store.totalIncome.value.toFixed(2) }}</div>
      <div class="income-hero-row">
        <div class="income-hero-col">
          <div class="ih-label">笔数</div>
          <div class="ih-val">{{ store.incomeRecords.value.length }} 笔</div>
        </div>
        <div class="income-hero-col">
          <div class="ih-label">本月结余</div>
          <div class="ih-val">¥{{ store.netBalance.value.toLocaleString() }}</div>
        </div>
      </div>
    </div>

    <div class="sec-title">{{ scopedDayTitle }}收入概览 <span>{{ scopedDayLabel }}</span></div>
    <div class="today-strip">
      <div class="today-card">
        <div class="today-label">{{ scopedDayTitle }}收入</div>
        <div class="today-value income">¥{{ todayIncome.toFixed(2) }}</div>
        <div class="today-meta">{{ todayIncomeCount }} 笔 · {{ todayTopSource }}</div>
      </div>
      <div class="today-card">
        <div class="today-label">本月最高来源</div>
        <div class="today-value income">¥{{ topSourceAmount.toFixed(2) }}</div>
        <div class="today-meta">{{ topSourceName }}</div>
      </div>
      <div class="today-card highlight">
        <div class="today-label">本月最高单笔</div>
        <div class="today-value income">¥{{ maxIncomeAmount.toFixed(2) }}</div>
        <div class="today-meta">{{ maxIncomeLabel }}</div>
      </div>
    </div>

    <div class="sec-title">收入来源 <span @click="store.openIncomeModal()">＋ 添加</span></div>
    <div class="card">
      <div v-if="!incomeChartData.length" class="empty" style="padding:20px">
        <div class="e-icon">💰</div><p>本月暂无收入</p>
      </div>
      <div v-for="item in incomeChartData" :key="item.cat" class="chart-row">
        <div class="chart-label">{{ item.label }}</div>
        <div class="chart-bar-wrap">
          <div class="chart-bar" :style="{ width: item.pct + '%', background: '#1565C0' }"></div>
        </div>
        <div class="chart-val">¥{{ item.amount.toFixed(0) }}</div>
      </div>
    </div>

    <div class="sec-title">本月记录</div>
    <div v-if="!store.incomeRecords.value.length" class="card">
      <div class="empty" style="padding:20px">
        <div class="e-icon">📋</div><p>暂无记录</p>
      </div>
    </div>
    <div v-for="group in groupedIncome" :key="group.date" class="bill-group">
      <div class="bill-date bill-date-summary">
        <span>{{ group.date }}</span>
        <strong>+¥{{ group.total.toFixed(2) }}</strong>
      </div>
      <div class="card" style="padding:0 16px">
        <div v-for="r in group.items" :key="r.id" class="income-item" @click="store.openIncomeEditModal(r)">
          <div class="income-icon">{{ r.icon }}</div>
          <div class="bill-info">
            <div class="bill-name">{{ r.source || store.incomeCatMap[r.cat]?.label }}</div>
            <div class="bill-meta">{{ store.incomeCatMap[r.cat]?.label }} · {{ r.date }}{{ r.image_path ? ' · 有截图' : '' }}</div>
          </div>
          <div class="income-amount">+¥{{ r.amount.toFixed(2) }}</div>
        </div>
      </div>
    </div>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { inject, computed } from 'vue'
import { buildScopedDayKey, formatDateKeyLabel, getLocalDateKey } from '../../utils/helpers'
import MonthPicker from '../MonthPicker.vue'

const store = inject('store')

const realTodayKey = computed(() => getLocalDateKey())
const scopedDayKey = computed(() => buildScopedDayKey(store.currentYear.value, store.currentMonth.value))
const scopedDayLabel = computed(() => formatDateKeyLabel(scopedDayKey.value))
const scopedDayTitle = computed(() => scopedDayKey.value === realTodayKey.value ? '今日' : '当日')

const todayIncomeRecords = computed(() => store.incomeRecords.value.filter(r => r.dateRaw === scopedDayKey.value))
const todayIncome = computed(() => todayIncomeRecords.value.reduce((sum, item) => sum + item.amount, 0))
const todayIncomeCount = computed(() => todayIncomeRecords.value.length)
const todayTopRecord = computed(() => todayIncomeRecords.value.reduce((max, item) => item.amount > (max?.amount || 0) ? item : max, null))
const todayTopSource = computed(() => todayTopRecord.value ? `最高 ${todayTopRecord.value.source || '收入'}` : `${scopedDayLabel.value}暂无收入`)

const sourceTotals = computed(() => {
  const grouped = {}
  store.incomeRecords.value.forEach(r => {
    const name = r.source || store.incomeCatMap[r.cat]?.label || '收入'
    grouped[name] = (grouped[name] || 0) + r.amount
  })
  const entries = Object.entries(grouped).sort((a, b) => b[1] - a[1])
  return entries.map(([name, amount]) => ({ name, amount }))
})

const topSourceName = computed(() => sourceTotals.value[0]?.name || '暂无来源')
const topSourceAmount = computed(() => sourceTotals.value[0]?.amount || 0)

const maxIncome = computed(() => store.incomeRecords.value.reduce((max, item) => item.amount > (max?.amount || 0) ? item : max, null))
const maxIncomeAmount = computed(() => maxIncome.value?.amount || 0)
const maxIncomeLabel = computed(() => maxIncome.value
  ? `${maxIncome.value.source || store.incomeCatMap[maxIncome.value.cat]?.label} · ${maxIncome.value.date}`
  : '本月暂无收入')

const incomeChartData = computed(() => {
  const grouped = {}
  store.incomeRecords.value.forEach(r => {
    grouped[r.cat] = (grouped[r.cat] || 0) + r.amount
  })
  const entries = Object.entries(grouped).sort((a, b) => b[1] - a[1])
  const maxAmt = entries[0]?.[1] || 1
  return entries.map(([cat, amount]) => ({
    cat,
    label: store.incomeCatMap[cat]?.label || cat,
    amount,
    pct: amount / maxAmt * 100,
  }))
})

const groupedIncome = computed(() => {
  const map = {}
  store.incomeRecords.value.forEach(record => {
    if (!map[record.date]) map[record.date] = { date: record.date, total: 0, items: [] }
    map[record.date].items.push(record)
    map[record.date].total += record.amount
  })
  return Object.values(map)
})
</script>
