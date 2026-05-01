<template>
  <div class="page active">
    <div class="page-title">报告</div>
    <div class="page-subtitle">先展示当前已经稳定的数据域，后续跨域分析会在运动、睡眠、阅读数据积累后逐步打开。</div>

    <div class="report-summary">
      <div class="report-summary-card">
        <div class="report-summary-label">本月消费概览</div>
        <div class="report-summary-value">¥ {{ store.totalExpense.value.toFixed(2) }}</div>
        <div class="report-summary-change">已记录 {{ store.doneBills.value.length }} 笔支出 · 大额交通 {{ store.transportRecords.value.length }} 笔</div>
      </div>
    </div>

    <div class="stat-grid">
      <div class="stat-card">
        <div class="stat-label">本月收入</div>
        <div class="stat-value">¥ {{ store.totalIncome.value.toFixed(0) }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">月度结余</div>
        <div class="stat-value">¥ {{ store.netBalance.value.toFixed(0) }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">最高单笔支出</div>
        <div class="stat-value">¥ {{ maxBill.amount?.toFixed(0) || 0 }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">日均支出</div>
        <div class="stat-value">¥ {{ dailyAvg }}</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">分类排行</div>
    </div>
    <div class="report-category-list">
      <div v-if="!categoryRank.length" class="empty-state">
        <div class="empty-title">本月暂无消费数据</div>
        <div class="empty-desc">有支出记录后，这里会自动生成分类排行。</div>
      </div>
      <div v-for="(item, index) in categoryRank" :key="item.cat" class="report-category-item">
        <div class="report-category-rank" :class="{ top: index < 3 }">{{ index + 1 }}</div>
        <div class="report-category-info">
          <div class="report-category-name">{{ item.label }}</div>
          <div class="report-category-bar">
            <div class="report-category-bar-fill" :style="{ width: `${item.pct}%` }"></div>
          </div>
        </div>
        <div class="report-category-amount">¥{{ item.amount.toFixed(0) }}</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">消费渠道</div>
    </div>
    <div class="card platform-card">
      <div v-if="!store.platformChartData.value.length" class="empty-state compact">
        <div class="empty-title">暂无渠道数据</div>
      </div>
      <div v-for="item in store.platformChartData.value" :key="item.name" class="chart-row">
        <div class="chart-label">{{ item.name }}</div>
        <div class="chart-bar-wrap">
          <div class="chart-bar" :style="{ width: `${item.pct}%` }"></div>
        </div>
        <div class="chart-val">¥{{ item.amount.toFixed(0) }}</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">支付方式</div>
    </div>
    <div class="card platform-card">
      <div v-if="!store.payChartData.value.length" class="empty-state compact">
        <div class="empty-title">暂无支付方式数据</div>
      </div>
      <div v-for="item in store.payChartData.value" :key="item.name" class="chart-row">
        <div class="chart-label">{{ item.name }}</div>
        <div class="chart-bar-wrap">
          <div class="chart-bar alt" :style="{ width: `${item.pct}%` }"></div>
        </div>
        <div class="chart-val">{{ item.pct }}%</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">跨域分析</div>
    </div>
    <div class="report-cross-intro">
      <div class="report-cross-icon">联</div>
      <div class="report-cross-title">跨域洞察将在数据积累后开启</div>
      <div class="report-cross-desc">当前消费和收入域已经可用，运动、睡眠、阅读等记录域接入后，这里会开始生成真正的跨域分析卡片。</div>
    </div>

    <div class="report-cross-card">
      <div class="cross-card-title">收入 × 支出结构</div>
      <div class="cross-card-finding">当前结余 {{ netStatus }}</div>
      <div class="cross-card-meta">基于本月 {{ store.incomeRecords.value.length }} 条收入记录和 {{ store.doneBills.value.length }} 条支出记录</div>
    </div>

    <div class="report-cross-card disabled">
      <div class="cross-card-title">运动 × 消费</div>
      <div class="cross-card-finding">数据积累中，还未接入运动记录正式入库链路</div>
      <div class="cross-card-meta">阶段 2 完成后可开始输出相关性分析</div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'

const store = inject('store')

const dailyAvg = computed(() => {
  const days = new Date(store.currentYear.value, store.currentMonth.value, 0).getDate()
  return (store.totalExpense.value / days).toFixed(0)
})

const maxBill = computed(() => {
  if (!store.doneBills.value.length) return {}
  return store.doneBills.value.reduce((a, b) => (a.amount > b.amount ? a : b))
})

const categoryRank = computed(() => {
  const grouped = {}
  store.doneBills.value.forEach(bill => {
    const key = bill.cat || '其他'
    grouped[key] = (grouped[key] || 0) + bill.amount
  })
  const entries = Object.entries(grouped).sort((a, b) => b[1] - a[1])
  const max = entries[0]?.[1] || 1
  return entries.map(([cat, amount]) => ({
    cat,
    label: cat,
    amount,
    pct: Math.round((amount / max) * 100),
  }))
})

const netStatus = computed(() => {
  if (store.netBalance.value > 0) return `¥${store.netBalance.value.toFixed(2)} 净流入`
  if (store.netBalance.value < 0) return `¥${Math.abs(store.netBalance.value).toFixed(2)} 净流出`
  return '本月收支持平'
})
</script>
