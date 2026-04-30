<template>
  <div class="page active">
    <div class="topbar">
      <h1>随手账</h1>
      <MonthPicker />
    </div>

    <!-- 支出总览 -->
    <div class="hero">
      <div class="label">本月总支出</div>
      <div class="amount">¥{{ store.totalExpense.value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }}</div>
      <div class="hero-row">
        <div class="hero-col">
          <div class="h-label">笔数</div>
          <div class="h-val">{{ store.doneBills.value.length }} 笔</div>
        </div>
        <div class="hero-col">
          <div class="h-label">日均</div>
          <div class="h-val">¥{{ dailyAvg }}</div>
        </div>
        <div class="hero-col">
          <div class="h-label">日均天数</div>
          <div class="h-val">{{ daysInMonth }} 天</div>
        </div>
      </div>
      <div class="hero-balance-row">
        <div class="hero-bal-col">
          <div class="hb-label">本月收入</div>
          <div class="hb-val">¥{{ store.totalIncome.value.toLocaleString() }}</div>
        </div>
        <div class="hero-bal-col">
          <div class="hb-label">本月结余</div>
          <div class="hb-val" :style="{ color: store.netBalance.value >= 0 ? '#4ADE80' : '#FCA5A5' }">
            ¥{{ store.netBalance.value.toLocaleString() }}
          </div>
        </div>
      </div>
    </div>

    <!-- 待补充提醒 -->
    <div v-if="store.pendingBills.value.length" class="pending-banner" @click="store.currentPage.value = 'pending'">
      <div class="pending-dot">{{ store.pendingBills.value.length }}</div>
      <div class="pending-text">
        <div class="pt">有 {{ store.pendingBills.value.length }} 条记录待补充</div>
        <div class="ps">信息不完整，点击逐一完善</div>
      </div>
      <div class="pending-arrow">›</div>
    </div>

    <div class="sec-title">今日收支概览</div>
    <div class="today-strip">
      <div class="today-card">
        <div class="today-label">今日支出</div>
        <div class="today-value expense">¥{{ todayExpenseDisplay }}</div>
        <div class="today-meta">{{ todayExpenseCount }} 笔 · {{ todayExpenseTop }}</div>
      </div>
      <div class="today-card">
        <div class="today-label">今日收入</div>
        <div class="today-value income">¥{{ todayIncomeDisplay }}</div>
        <div class="today-meta">{{ todayIncomeCount }} 笔 · {{ todayIncomeTop }}</div>
      </div>
      <div class="today-card highlight">
        <div class="today-label">今日结余</div>
        <div class="today-value" :class="todayNet >= 0 ? 'income' : 'expense'">
          {{ todayNet >= 0 ? '+' : '-' }}¥{{ Math.abs(todayNet).toFixed(2) }}
        </div>
        <div class="today-meta">{{ todayStatusText }}</div>
      </div>
    </div>

    <!-- 本周支出趋势 -->
    <div class="sec-title">本周支出趋势</div>
    <div class="card">
      <div style="display:flex; align-items:flex-end; gap:6px; height:80px; padding:0 4px;">
        <div v-for="(v, i) in weekData" :key="i"
          style="flex:1; display:flex; flex-direction:column; align-items:center; gap:4px; height:100%">
          <div style="flex:1; display:flex; align-items:flex-end; width:100%">
            <div :style="{
              width: '100%',
              height: Math.max(v / weekMax * 72, v > 0 ? 6 : 0) + 'px',
              borderRadius: '4px 4px 0 0',
              background: i === todayIdx ? 'var(--accent)' : 'var(--surface2)'
            }"></div>
          </div>
        </div>
      </div>
      <div style="display:flex; gap:6px; margin-top:6px;">
        <div v-for="(d, i) in weekLabels" :key="i"
          style="flex:1; text-align:center; font-size:10px;"
          :style="{ color: i === todayIdx ? 'var(--accent)' : 'var(--text3)' }">{{ d }}</div>
      </div>
      <div class="trend-summary">
        <div class="trend-pill">
          <span>本周累计</span>
          <strong>¥{{ weekTotal.toFixed(2) }}</strong>
        </div>
        <div class="trend-pill">
          <span>最高单日</span>
          <strong>{{ weekPeakLabel }}</strong>
        </div>
        <div class="trend-pill">
          <span>今日占比</span>
          <strong>{{ todayWeekShare }}</strong>
        </div>
      </div>
    </div>

    <!-- 最近记录 -->
    <div class="sec-title">最近记录 <span @click="store.currentPage.value = 'bills'">查看全部 ›</span></div>
    <div class="card">
      <div v-if="!store.recentEntries.value.length" class="empty">
        <div class="e-icon">📋</div><p>本月暂无记录</p>
      </div>
      <template v-for="entry in store.recentEntries.value.slice(0, 5)" :key="entry.entryKind + entry.id">
        <div v-if="entry.entryKind === 'income'" class="income-item compact" @click="store.openIncomeEditModal(entry)">
          <div class="income-icon">{{ entry.icon }}</div>
          <div class="bill-info">
            <div class="bill-name">{{ entry.source || store.incomeCatMap[entry.cat]?.label }}</div>
            <div class="bill-meta">{{ store.incomeCatMap[entry.cat]?.label }} · {{ entry.date }}</div>
          </div>
          <div class="income-amount">+¥{{ entry.amount.toFixed(2) }}</div>
        </div>
        <BillRow v-else :bill="entry" />
      </template>
    </div>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { inject, computed } from 'vue'
import { computeWeekData, getLocalDateKey } from '../../utils/helpers'
import BillRow from '../BillRow.vue'
import MonthPicker from '../MonthPicker.vue'

const store = inject('store')
const weekLabels = ['周一','周二','周三','周四','周五','周六','周日']
const todayIdx = computed(() => { const d = new Date().getDay(); return d === 0 ? 6 : d - 1 })
const weekData = computed(() => computeWeekData(store.bills.value))
const weekMax = computed(() => Math.max(...weekData.value, 1))
const daysInMonth = computed(() => new Date(store.currentYear.value, store.currentMonth.value, 0).getDate())
const dailyAvg = computed(() => (store.totalExpense.value / daysInMonth.value).toFixed(0))
const todayKey = computed(() => getLocalDateKey())

const todayBills = computed(() => store.doneBills.value.filter(b => b.dateRaw === todayKey.value))
const todayIncomes = computed(() => store.recentIncomeRecords.value.filter(r => r.dateRaw === todayKey.value))

const todayExpense = computed(() => todayBills.value.reduce((sum, item) => sum + item.amount, 0))
const todayIncome = computed(() => todayIncomes.value.reduce((sum, item) => sum + item.amount, 0))
const todayNet = computed(() => todayIncome.value - todayExpense.value)

const topExpenseBill = computed(() => todayBills.value.reduce((max, item) => item.amount > (max?.amount || 0) ? item : max, null))
const topIncomeRecord = computed(() => todayIncomes.value.reduce((max, item) => item.amount > (max?.amount || 0) ? item : max, null))

const todayExpenseDisplay = computed(() => todayExpense.value.toFixed(2))
const todayIncomeDisplay = computed(() => todayIncome.value.toFixed(2))
const todayExpenseCount = computed(() => todayBills.value.length)
const todayIncomeCount = computed(() => todayIncomes.value.length)
const todayExpenseTop = computed(() => topExpenseBill.value ? `最高 ${topExpenseBill.value.name}` : '暂无支出')
const todayIncomeTop = computed(() => topIncomeRecord.value ? `最高 ${topIncomeRecord.value.source || '收入'}` : '暂无收入')
const todayStatusText = computed(() => {
  if (!todayBills.value.length && !todayIncomes.value.length) return '今天还没有新增记录'
  if (todayNet.value > 0) return '今天是净流入'
  if (todayNet.value < 0) return '今天是净流出'
  return '今天收支持平'
})

const weekTotal = computed(() => weekData.value.reduce((sum, value) => sum + value, 0))
const weekPeak = computed(() => {
  let max = 0
  let idx = 0
  weekData.value.forEach((value, index) => {
    if (value > max) {
      max = value
      idx = index
    }
  })
  return { max, idx }
})
const weekPeakLabel = computed(() => weekPeak.value.max > 0
  ? `${weekLabels[weekPeak.value.idx]} ¥${weekPeak.value.max.toFixed(0)}`
  : '本周暂无支出')
const todayWeekShare = computed(() => weekTotal.value > 0
  ? `${Math.round(((weekData.value[todayIdx.value] || 0) / weekTotal.value) * 100)}%`
  : '0%')
</script>
