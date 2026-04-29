<template>
  <div class="page active">
    <div class="topbar">
      <h1>收入</h1>
      <div class="month-nav">
        <button class="month-nav-btn" @click="store.changeMonth(-1)">‹</button>
        <span class="month-nav-label">{{ store.monthLabel.value }}</span>
        <button class="month-nav-btn" @click="store.changeMonth(1)">›</button>
      </div>
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
    <div class="card">
      <div v-if="!store.incomeRecords.value.length" class="empty" style="padding:20px">
        <div class="e-icon">📋</div><p>暂无记录</p>
      </div>
      <div v-for="r in store.incomeRecords.value" :key="r.id" class="income-item">
        <div class="income-icon">{{ r.icon }}</div>
        <div class="bill-info">
          <div class="bill-name">{{ r.source || store.incomeCatMap[r.cat]?.label }}</div>
          <div class="bill-meta">{{ store.incomeCatMap[r.cat]?.label }} · {{ r.date }}</div>
        </div>
        <div class="income-amount">+¥{{ r.amount.toFixed(2) }}</div>
      </div>
    </div>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { inject, computed } from 'vue'

const store = inject('store')

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
</script>
