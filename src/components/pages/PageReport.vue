<template>
  <div class="page active">
    <div class="topbar">
      <h1>消费报告</h1>
      <div class="sub">本月数据截至今日</div>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-label">总支出</div>
        <div class="stat-val red">¥{{ store.totalExpense.value.toFixed(0) }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">记录笔数</div>
        <div class="stat-val">{{ store.doneBills.value.length }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">最大单笔</div>
        <div class="stat-val red">¥{{ maxBill.amount?.toFixed(0) || 0 }}</div>
        <div class="stat-change">{{ maxBill.cat }} · {{ maxBill.platform }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">日均支出</div>
        <div class="stat-val">¥{{ dailyAvg }}</div>
      </div>
    </div>

    <div class="sec-title">各平台消费</div>
    <div class="card">
      <div v-if="!store.platformChartData.value.length" class="empty" style="padding:20px">
        <p>本月暂无数据</p>
      </div>
      <div v-for="p in store.platformChartData.value" :key="p.name" class="chart-row">
        <div class="chart-label">{{ p.name }}</div>
        <div class="chart-bar-wrap">
          <div class="chart-bar" :style="{ width: p.pct + '%' }"></div>
        </div>
        <div class="chart-val">¥{{ p.amount.toFixed(0) }}</div>
      </div>
    </div>

    <div class="sec-title">支付方式分布</div>
    <div class="card">
      <div v-if="!store.payChartData.value.length" class="empty" style="padding:20px">
        <p>本月暂无数据</p>
      </div>
      <div v-for="p in store.payChartData.value" :key="p.name" class="chart-row">
        <div class="chart-label">{{ p.name }}</div>
        <div class="chart-bar-wrap">
          <div class="chart-bar" :style="{ width: p.pct + '%' }"></div>
        </div>
        <div class="chart-val">{{ p.pct }}%</div>
      </div>
    </div>

    <div class="sec-title">大额交通汇总</div>
    <div class="card">
      <div v-if="!store.transportRecords.value.length" class="empty" style="padding:20px">
        <div class="e-icon">✈️</div><p>本月暂无大额交通支出</p>
      </div>
      <div v-for="r in store.transportRecords.value" :key="r.id" class="transport-row">
        <div class="transport-info">
          <div class="transport-label">{{ r.type }} {{ r.desc ? '· ' + r.desc : '' }}</div>
          <div class="transport-sub">{{ r.date }}</div>
        </div>
        <div class="transport-amount">-¥{{ r.amount.toFixed(2) }}</div>
      </div>
      <div v-if="store.transportRecords.value.length"
        style="border-top:0.5px solid var(--border); padding-top:12px; margin-top:4px; display:flex; justify-content:space-between;">
        <div style="font-size:13px; font-weight:500;">合计</div>
        <div style="font-size:16px; font-weight:600; color:var(--danger)">¥{{ transportTotal.toFixed(2) }}</div>
      </div>
    </div>

    <div class="sec-title">先用后付汇总</div>
    <div class="card">
      <div v-if="!creditData.length" class="empty" style="padding:20px">
        <p>本月暂无先用后付记录</p>
      </div>
      <div v-for="item in creditData" :key="item.name"
        style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
        <div style="font-size:13px; color:var(--text2)">{{ item.name }}</div>
        <div style="font-size:16px; font-weight:600; color:var(--danger)">¥{{ item.amount.toFixed(0) }}</div>
      </div>
      <div v-if="creditData.length"
        style="border-top:0.5px solid var(--border); padding-top:12px; display:flex; justify-content:space-between;">
        <div style="font-size:14px; font-weight:500;">合计待还</div>
        <div style="font-size:18px; font-weight:600; color:var(--danger)">¥{{ creditTotal.toFixed(0) }}</div>
      </div>
    </div>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { inject, computed } from 'vue'

const store = inject('store')

const dailyAvg = computed(() => {
  const days = new Date(store.currentYear.value, store.currentMonth.value, 0).getDate()
  return (store.totalExpense.value / days).toFixed(0)
})

const maxBill = computed(() => {
  if (!store.doneBills.value.length) return {}
  return store.doneBills.value.reduce((a, b) => a.amount > b.amount ? a : b)
})

const transportTotal = computed(() =>
  store.transportRecords.value.reduce((s, r) => s + r.amount, 0)
)

const creditPayments = ['花呗', '京东白条', '美团月付', '先用后付', '拼多多先用后付']

const creditData = computed(() => {
  const grouped = {}
  store.doneBills.value.forEach(b => {
    if (creditPayments.some(p => b.payment?.includes(p.replace('先用后付', '')))) {
      grouped[b.payment] = (grouped[b.payment] || 0) + b.amount
    }
  })
  return Object.entries(grouped).map(([name, amount]) => ({ name, amount }))
})

const creditTotal = computed(() => creditData.value.reduce((s, i) => s + i.amount, 0))
</script>
