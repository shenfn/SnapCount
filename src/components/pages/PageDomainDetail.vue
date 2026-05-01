<template>
  <div class="page active domain-detail-page">
    <div class="detail-header domain-detail-header">
      <button class="detail-back" @click="store.goBack()">‹</button>
      <div class="detail-header-info">
        <div class="detail-header-title">{{ domain.name }}</div>
        <div class="domain-detail-header-sub">{{ domain.isSystem ? '系统内置数据域' : '自定义数据域' }}</div>
      </div>
      <button class="detail-more" @click="store.showFlash('数据域配置将在模板阶段开放')">设</button>
    </div>

    <div class="domain-detail-hero" :style="{ '--domain-color': domain.color }">
      <div class="domain-detail-hero-top">
        <div class="domain-detail-mark" :style="{ background: `${domain.color}18`, color: domain.color }">{{ domain.icon }}</div>
        <div class="domain-detail-status">
          <span class="badge" :class="domain.recordCount ? 'badge-success' : 'badge-warning'">{{ domain.recordCount ? '运行中' : '待接入' }}</span>
        </div>
      </div>
      <div class="domain-detail-title-row">
        <div>
          <div class="domain-detail-kicker">Domain Workspace</div>
          <div class="domain-detail-title">{{ domain.name }}</div>
        </div>
        <div class="domain-detail-count">{{ domain.recordCount }}</div>
      </div>
      <div class="domain-detail-desc">{{ domain.description }}</div>
    </div>

    <div class="domain-metric-grid">
      <div v-for="item in metrics" :key="item.label" class="domain-metric">
        <div class="domain-metric-label">{{ item.label }}</div>
        <div class="domain-metric-value">{{ item.value }}</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">趋势</div>
      <div class="section-action">{{ trendScope }}</div>
    </div>
    <div class="domain-panel">
      <div class="domain-trend-bars">
        <div v-for="(item, index) in trendItems" :key="index" class="domain-trend-col">
          <div class="domain-trend-bar-wrap">
            <div
              class="domain-trend-bar"
              :style="{ height: `${Math.max(item.pct, item.value ? 12 : 4)}%`, background: domainBarColor }"
            ></div>
          </div>
          <div class="domain-trend-label">{{ item.label }}</div>
        </div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">维度分布</div>
      <div class="section-action">Top {{ dimensionItems.length || 0 }}</div>
    </div>
    <div class="domain-panel">
      <div v-if="!dimensionItems.length" class="empty-state compact">
        <div class="empty-title">还没有可分析的数据</div>
        <div class="empty-desc">模板接入后会自动生成分类、来源或状态分布。</div>
      </div>
      <div v-for="item in dimensionItems" :key="item.name" class="domain-dimension-row">
        <div class="domain-dimension-main">
          <div class="domain-dimension-name">{{ item.name }}</div>
          <div class="domain-dimension-track">
            <div class="domain-dimension-fill" :style="{ width: `${item.pct}%`, background: domainBarColor }"></div>
          </div>
        </div>
        <div class="domain-dimension-value">{{ item.display }}</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">最近记录</div>
      <div class="section-action">{{ recentRecords.length }} 条</div>
    </div>
    <div class="domain-record-list">
      <div v-if="!recentRecords.length" class="empty-state">
        <div class="empty-title">{{ domain.name }}暂无记录</div>
        <div class="empty-desc">这个数据域已经预留好展示结构，等截图识别链路接入后会自动填充。</div>
      </div>
      <div
        v-for="item in recentRecords"
        :key="item.id"
        class="domain-record-row"
        @click="openRecord(item)"
      >
        <div class="domain-record-icon" :style="{ background: `${domain.color}16`, color: domain.color }">{{ item.icon }}</div>
        <div class="domain-record-main">
          <div class="domain-record-title-row">
            <div class="domain-record-title">{{ item.title }}</div>
            <div class="domain-record-value" :class="item.kind">{{ item.value }}</div>
          </div>
          <div class="domain-record-sub">{{ item.subtitle }}</div>
          <div class="domain-record-date">{{ item.date }}</div>
        </div>
      </div>
    </div>

    <div class="domain-next-panel">
      <div class="domain-next-title">默认展示能力</div>
      <div class="domain-next-grid">
        <span v-for="capability in capabilities" :key="capability" class="domain-next-chip">{{ capability }}</span>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
import { computeWeekData, formatDateTimeLabel, incomeCatMap } from '../../utils/helpers'

const store = inject('store')

const domain = computed(() => {
  return store.domains.value.find(item => item.id === store.activeDomainId.value) || store.domains.value[0]
})

const domainBarColor = computed(() => `linear-gradient(180deg, ${domain.value.color} 0%, ${softenColor(domain.value.color)} 100%)`)

const metrics = computed(() => {
  if (domain.value.id === 'expense') {
    const maxBill = store.doneBills.value.reduce((max, item) => Math.max(max, item.amount), 0)
    return [
      { label: '本月总额', value: `¥${store.totalExpense.value.toFixed(0)}` },
      { label: '记录数', value: `${store.doneBills.value.length}` },
      { label: '今日支出', value: `¥${store.todayExpense.value.toFixed(0)}` },
      { label: '最高单笔', value: `¥${maxBill.toFixed(0)}` },
    ]
  }
  if (domain.value.id === 'income') {
    const maxIncome = store.incomeRecords.value.reduce((max, item) => Math.max(max, item.amount), 0)
    return [
      { label: '本月总额', value: `¥${store.totalIncome.value.toFixed(0)}` },
      { label: '记录数', value: `${store.incomeRecords.value.length}` },
      { label: '月度结余', value: `¥${store.netBalance.value.toFixed(0)}` },
      { label: '最高单笔', value: `¥${maxIncome.toFixed(0)}` },
    ]
  }
  return [
    { label: '记录数', value: `${universalRecords.value.length}` },
    { label: '模板状态', value: domain.value.recordCount ? '运行中' : '预留' },
    { label: '入库链路', value: domain.value.recordCount ? '已接入' : '待接入' },
    { label: '展示组件', value: '已就绪' },
  ]
})

const trendScope = computed(() => domain.value.recordCount ? '本周' : '模板预览')

const trendItems = computed(() => {
  const labels = ['一', '二', '三', '四', '五', '六', '日']
  let values = [0, 0, 0, 0, 0, 0, 0]
  if (domain.value.id === 'expense') values = computeWeekData(store.doneBills.value)
  if (domain.value.id === 'income') values = computeIncomeWeekData()
  if (!['expense', 'income'].includes(domain.value.id)) values = computeUniversalWeekData()
  const max = Math.max(...values, 1)
  return values.map((value, index) => ({
    label: labels[index],
    value,
    pct: Math.round((value / max) * 100),
  }))
})

const dimensionItems = computed(() => {
  if (domain.value.id === 'expense') {
    return buildDimension(store.doneBills.value.map(item => ({
      name: item.cat && item.cat !== '?' ? item.cat : '其他',
      amount: item.amount,
    })))
  }
  if (domain.value.id === 'income') {
    return buildDimension(store.incomeRecords.value.map(item => ({
      name: incomeCatMap[item.cat]?.label || '其他',
      amount: item.amount,
    })))
  }
  return buildDimension(universalRecords.value.map(item => ({
    name: universalDimensionName(item),
    amount: 1,
  })), false)
})

const recentRecords = computed(() => {
  if (domain.value.id === 'expense') {
    return store.doneBills.value.slice(0, 8).map(item => ({
      id: item.id,
      kind: 'expense',
      raw: item,
      icon: '支',
      title: item.name,
      subtitle: `${item.platform || '其他'} · ${item.cat || '其他'}`,
      value: `-¥${item.amount.toFixed(2)}`,
      date: item.createdAt ? formatDateTimeLabel(item.createdAt) : item.date,
    }))
  }
  if (domain.value.id === 'income') {
    return store.recentIncomeRecords.value.slice(0, 8).map(item => ({
      id: item.id,
      kind: 'income',
      raw: item,
      icon: '收',
      title: item.source || incomeCatMap[item.cat]?.label || '收入',
      subtitle: incomeCatMap[item.cat]?.label || '收入记录',
      value: `+¥${item.amount.toFixed(2)}`,
      date: item.createdAt ? formatDateTimeLabel(item.createdAt) : item.date,
    }))
  }
  return universalRecords.value.slice(0, 8).map(item => ({
    id: item.id,
    kind: 'universal',
    raw: item,
    icon: domain.value.shortName.slice(0, 1),
    title: item.title || domain.value.name,
    subtitle: item.summary || universalDimensionName(item),
    value: item.occurredAt ? '已归档' : '已记录',
    date: formatDateTimeLabel(item.occurredAt || item.createdAt),
  }))
})

const capabilities = computed(() => {
  if (domain.value.recordCount) return ['SummaryMetric', 'TrendLine', 'DimensionBars', 'RecentRecords', 'RecordDetail']
  return ['模板元数据', '空状态展示', '默认指标位', '最近记录位']
})

function openRecord(item) {
  if (item.kind === 'expense') store.openRecordDetail('expense', item.raw)
  if (item.kind === 'income') store.openRecordDetail('income', item.raw)
  if (item.kind === 'universal') store.openUniversalEditModal(item.raw)
}

const universalRecords = computed(() => {
  return store.dataRecords.value
    .filter(item => item.domainKey === domain.value.id)
    .sort((a, b) => ((b.occurredAt || b.createdAt || '').localeCompare(a.occurredAt || a.createdAt || '')))
})

function computeIncomeWeekData() {
  const result = [0, 0, 0, 0, 0, 0, 0]
  const today = new Date()
  const dow = today.getDay()
  const monday = new Date(today)
  monday.setDate(today.getDate() - (dow === 0 ? 6 : dow - 1))
  monday.setHours(0, 0, 0, 0)
  store.incomeRecords.value.forEach(item => {
    if (!item.dateRaw) return
    const d = new Date(item.dateRaw + 'T00:00:00')
    const diff = Math.round((d - monday) / 86400000)
    if (diff >= 0 && diff < 7) result[diff] += item.amount
  })
  return result
}

function buildDimension(list, currency = true) {
  const grouped = {}
  list.forEach(item => {
    grouped[item.name] = (grouped[item.name] || 0) + Number(item.amount || 0)
  })
  const entries = Object.entries(grouped).sort((a, b) => b[1] - a[1]).slice(0, 6)
  const max = entries[0]?.[1] || 1
  return entries.map(([name, amount]) => ({
    name,
    amount,
    pct: Math.round((amount / max) * 100),
    display: currency ? `¥${amount.toFixed(0)}` : `${amount.toFixed(0)} 条`,
  }))
}

function computeUniversalWeekData() {
  const result = [0, 0, 0, 0, 0, 0, 0]
  const today = new Date()
  const dow = today.getDay()
  const monday = new Date(today)
  monday.setDate(today.getDate() - (dow === 0 ? 6 : dow - 1))
  monday.setHours(0, 0, 0, 0)
  universalRecords.value.forEach(item => {
    const d = new Date(item.occurredAt || item.createdAt)
    if (Number.isNaN(d.getTime())) return
    d.setHours(0, 0, 0, 0)
    const diff = Math.round((d - monday) / 86400000)
    if (diff >= 0 && diff < 7) result[diff] += 1
  })
  return result
}

function universalDimensionName(item) {
  const payload = item.payload || {}
  if (domain.value.id === 'sport') return payload.sport_type || payload.activity_type || payload.source_app || '运动记录'
  if (domain.value.id === 'sleep') return payload.quality_level || payload.source_app || '睡眠记录'
  if (domain.value.id === 'reading') return payload.book_name || payload.source_app || '阅读记录'
  return item.title || domain.value.name
}

function softenColor(color) {
  const map = {
    '#C2410C': '#F97316',
    '#1565C0': '#38BDF8',
    '#B45309': '#FBBF24',
    '#4338CA': '#818CF8',
    '#0369A1': '#38BDF8',
  }
  return map[color] || color
}
</script>
