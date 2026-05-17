<template>
  <div class="page active report-page">
    <div class="page-title">报告</div>
    <div class="page-subtitle">数据洞察与趋势分析</div>
    <MonthPicker />

    <button class="report-insights-entry" @click="store.navigateTo('insights')">
      <span class="report-insights-entry-icon">联</span>
      <span class="report-insights-entry-main">
        <span class="report-insights-entry-title">跨域联动分析</span>
        <span class="report-insights-entry-sub">睡眠 × 饮食、收支流水、每日明细</span>
      </span>
      <span class="report-insights-entry-arrow">›</span>
    </button>

    <div class="report-domain-selector" @click.stop>
      <div class="report-selector-label">选择数据域</div>
      <div class="report-selector-wrap" @click="dropdownOpen = !dropdownOpen">
        <div class="report-selector-value">
          <span class="report-selector-icon" :style="{ background: `${activeMeta.color}18`, color: activeMeta.color }">{{ activeMeta.icon }}</span>
          <span>{{ activeMeta.name }}</span>
        </div>
        <span class="report-selector-arrow" :class="{ open: dropdownOpen }">⌄</span>
      </div>
      <div v-if="dropdownOpen" class="report-dropdown">
        <div
          v-for="domain in reportDomains"
          :key="domain.id"
          class="report-dropdown-item"
          :class="{ active: activeDomain === domain.id }"
          @click.stop="selectDomain(domain.id)"
        >
          <span class="report-selector-icon small" :style="{ background: `${domain.color}18`, color: domain.color }">{{ domain.icon }}</span>
          <span>{{ domain.name }}</span>
        </div>
        <div class="report-dropdown-divider"></div>
        <div
          class="report-dropdown-item"
          :class="{ active: activeDomain === 'cross' }"
          @click.stop="selectDomain('cross')"
        >
          <span class="report-selector-icon small" style="background:rgba(33,79,61,0.12);color:var(--primary)">联</span>
          <span>跨域分析</span>
        </div>
      </div>
    </div>

    <template v-if="activeDomain !== 'cross'">
      <div class="report-summary">
        <div class="report-summary-card" :style="{ background: activeData.summary.gradient }">
          <div class="report-summary-label">{{ activeData.summary.label }}</div>
          <div class="report-summary-value">{{ activeData.summary.value }}</div>
          <div class="report-summary-change">{{ activeData.summary.change }}</div>
        </div>
      </div>

      <div class="report-stat-grid report-stat-grid-proto">
        <div v-for="item in activeData.stats" :key="item.label" class="report-stat-card">
          <div class="report-stat-label">{{ item.label }}</div>
          <div class="report-stat-value">{{ item.value }}</div>
        </div>
      </div>

      <div class="section-header">
        <div class="section-title">趋势</div>
        <div class="detail-grain-group">
          <span class="detail-grain active">日</span>
          <span class="detail-grain">周</span>
          <span class="detail-grain">月</span>
        </div>
      </div>
      <div class="report-trend-panel">
        <div class="report-trend-chart">
          <div class="week-bars report-week-bars">
            <div v-for="(v, i) in activeData.trendData" :key="i" class="week-col">
              <div class="platform-week-bar-wrap">
                <div
                  class="week-bar report-week-bar"
                  :style="{ height: `${Math.max((v / activeData.trendMax) * 100, v > 0 ? 10 : 4)}%`, background: activeData.summary.barColor }"
                ></div>
              </div>
              <div class="week-day">{{ activeData.trendLabels[i] }}</div>
            </div>
          </div>
        </div>
      </div>

      <div class="section-header">
        <div class="section-title">{{ activeDomain === 'wallet' ? '账户与待还' : '分类排行' }}</div>
      </div>
      <div class="report-category-list report-category-list-v2">
        <div v-if="!activeData.categories.length" class="empty-state">
          <div class="empty-title">这个数据域还没有足够的记录</div>
          <div class="empty-desc">等后续有更多数据进来，这里会自动生成更完整的结构分布。</div>
        </div>
        <div v-for="(item, index) in activeData.categories" :key="item.name" class="report-category-item">
          <div class="report-category-rank" :class="{ top: index < 3 }">{{ index + 1 }}</div>
          <div class="report-category-info">
            <div class="report-category-name">{{ item.name }}</div>
            <div class="report-category-bar">
              <div class="report-category-bar-fill" :style="{ width: `${item.pct}%`, background: activeData.summary.barColor }"></div>
            </div>
          </div>
          <div class="report-category-amount">{{ item.display }}</div>
        </div>
      </div>

      <template v-if="activeData.platforms.length">
        <div class="section-header">
          <div class="section-title">{{ activeDomain === 'expense' ? '消费渠道' : '来源 App' }}</div>
        </div>
        <div class="report-detail-panel">
          <div v-for="item in activeData.platforms" :key="item.name" class="chart-row">
            <div class="chart-label">{{ item.name }}</div>
            <div class="chart-bar-wrap">
              <div class="chart-bar" :style="{ width: `${item.pct}%`, background: activeData.summary.barColor }"></div>
            </div>
            <div class="chart-val">{{ item.display }}</div>
          </div>
        </div>
      </template>

      <template v-if="activeData.paymentMethods.length">
        <div class="section-header">
          <div class="section-title">支付方式</div>
        </div>
        <div class="report-detail-panel">
          <div v-for="item in activeData.paymentMethods" :key="item.name" class="chart-row">
            <div class="chart-label">{{ item.name }}</div>
            <div class="chart-bar-wrap">
              <div class="chart-bar alt" :style="{ width: `${item.pct}%` }"></div>
            </div>
            <div class="chart-val">{{ item.display }}</div>
          </div>
        </div>
      </template>

      <template v-if="activeData.specialSummaries.length">
        <div class="section-header">
          <div class="section-title">专项汇总</div>
        </div>
        <div class="report-special-grid">
          <div v-for="item in activeData.specialSummaries" :key="item.label" class="report-special-card">
            <div class="report-special-icon" :style="{ background: `${item.color}18`, color: item.color }">{{ item.icon }}</div>
            <div class="report-special-main">
              <div class="report-special-label">{{ item.label }}</div>
              <div class="report-special-value">{{ item.value }}</div>
            </div>
          </div>
        </div>
      </template>
    </template>

    <template v-else>
      <div class="report-cross-intro">
        <div class="report-cross-icon">联</div>
        <div class="report-cross-title">跨域关联分析</div>
        <div class="report-cross-desc">发现不同数据域之间的隐藏关联</div>
      </div>

      <div class="report-cross-card">
        <div class="cross-card-title">收入 × 支出结构</div>
        <div class="cross-card-finding">当前 {{ netStatus }}</div>
        <div class="cross-card-meta">基于本月 {{ store.incomeRecords.value.length }} 条收入记录和 {{ store.doneBills.value.length }} 条支出记录</div>
      </div>

      <div class="report-cross-card">
        <div class="cross-card-title">运动 × 消费</div>
        <div class="cross-card-finding">运动记录尚未正式入库，暂时保留分析位</div>
        <div class="cross-card-meta">阶段 2 完成后可输出真实关联分析</div>
      </div>

      <div class="report-cross-card disabled">
        <div class="cross-card-title">阅读 × 消费</div>
        <div class="cross-card-finding">阅读记录模板已预留，等待真实数据接入</div>
        <div class="cross-card-meta">当前仅做交互占位，不输出误导性结论</div>
      </div>
    </template>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject, onMounted, onBeforeUnmount, ref } from 'vue'
import { getReportDomainDefinitions, getDomainSchema, getDomainDisplay } from '../../domains/registry'
import { computeWeekData, incomeCatMap } from '../../utils/helpers'
import { pickAdapter } from '../../adapters/domain'
import { isDurationFact } from '../../utils/format'
import MonthPicker from '../MonthPicker.vue'

const store = inject('store')
const activeDomain = ref('expense')
const dropdownOpen = ref(false)

const reportDomains = getReportDomainDefinitions()

function closeDropdownOnWindowClick() {
  dropdownOpen.value = false
}

onMounted(() => {
  window.addEventListener('click', closeDropdownOnWindowClick)
})

onBeforeUnmount(() => {
  window.removeEventListener('click', closeDropdownOnWindowClick)
})

function selectDomain(domainId) {
  activeDomain.value = domainId
  dropdownOpen.value = false
}

const activeMeta = computed(() => {
  if (activeDomain.value === 'cross') {
    return { name: '跨域分析', icon: '联', color: 'var(--primary)' }
  }
  return reportDomains.find(item => item.id === activeDomain.value) || reportDomains[0]
})

const expenseTrend = computed(() => computeWeekData(store.bills.value))
const incomeTrend = computed(() => {
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
})

const expenseCategories = computed(() => buildAmountRank(
  store.doneBills.value.map(item => ({
    name: item.cat && item.cat !== '?' ? item.cat : '其他',
    amount: item.amount,
  })),
  true
))

const incomeCategories = computed(() => buildAmountRank(
  store.incomeRecords.value.map(item => ({
    name: incomeCatMap[item.cat]?.label || '其他',
    amount: item.amount,
  })),
  true
))

const expensePlatforms = computed(() => normalizeChartList(
  store.platformChartData.value.map(item => ({
    name: item.name,
    amount: item.amount,
    pct: item.pct,
    display: `¥${item.amount.toFixed(0)}`,
  }))
))

const expensePayments = computed(() => normalizeChartList(
  store.payChartData.value.map(item => ({
    name: item.name,
    amount: item.amount,
    pct: item.pct,
    display: `${item.pct}%`,
  }))
))

const maxExpenseBill = computed(() => {
  if (!store.doneBills.value.length) return 0
  return store.doneBills.value.reduce((max, item) => Math.max(max, item.amount), 0)
})

const maxIncomeAmount = computed(() => {
  if (!store.incomeRecords.value.length) return 0
  return store.incomeRecords.value.reduce((max, item) => Math.max(max, item.amount), 0)
})

const universalRecords = computed(() => {
  return store.dataRecords.value.filter(item => item.domainKey === activeDomain.value)
})

const expenseData = computed(() => ({
  summary: {
    label: '本月消费概览',
    value: `¥ ${store.totalExpense.value.toFixed(2)}`,
    change: `已记录 ${store.doneBills.value.length} 笔支出 · 大额交通 ${store.transportRecords.value.length} 笔`,
    gradient: 'linear-gradient(135deg, #ef4444 0%, #dc2626 100%)',
    barColor: 'linear-gradient(180deg, #f97316 0%, #dc2626 100%)',
  },
  stats: [
    { label: '本月收入', value: `¥ ${store.totalIncome.value.toFixed(0)}` },
    { label: '月度结余', value: `¥ ${store.netBalance.value.toFixed(0)}` },
    { label: '最高单笔支出', value: `¥ ${maxExpenseBill.value.toFixed(0)}` },
    { label: '日均支出', value: `¥ ${Math.round(store.totalExpense.value / Math.max(new Date(store.currentYear.value, store.currentMonth.value, 0).getDate(), 1))}` },
  ],
  trendLabels: ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
  trendData: expenseTrend.value,
  trendMax: Math.max(...expenseTrend.value, 1),
  categories: expenseCategories.value,
  platforms: expensePlatforms.value,
  paymentMethods: expensePayments.value,
  specialSummaries: [
    { label: '大额交通（≥200元）', value: `¥ ${store.transportRecords.value.reduce((sum, item) => sum + item.amount, 0).toFixed(0)}`, icon: '交', color: '#0ea5e9' },
  ],
}))

const incomeData = computed(() => ({
  summary: {
    label: '本月收入概览',
    value: `¥ ${store.totalIncome.value.toFixed(2)}`,
    change: `已记录 ${store.incomeRecords.value.length} 笔收入 · 当前结余 ¥${store.netBalance.value.toFixed(2)}`,
    gradient: 'linear-gradient(135deg, #10b981 0%, #059669 100%)',
    barColor: 'linear-gradient(180deg, #34d399 0%, #059669 100%)',
  },
  stats: [
    { label: '记录笔数', value: `${store.incomeRecords.value.length}` },
    { label: '最高来源', value: incomeCategories.value[0]?.name || '暂无' },
    { label: '最高单笔', value: `¥ ${maxIncomeAmount.value.toFixed(0)}` },
    { label: '月度结余', value: `¥ ${store.netBalance.value.toFixed(0)}` },
  ],
  trendLabels: ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
  trendData: incomeTrend.value,
  trendMax: Math.max(...incomeTrend.value, 1),
  categories: incomeCategories.value,
  platforms: [],
  paymentMethods: [],
  specialSummaries: [],
}))

const placeholderData = computed(() => ({
  sport: {
    summary: {
      label: '运动记录概览',
      value: '0 条',
      change: '模板已预留，等待正式接入识别链路',
      gradient: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
      barColor: 'linear-gradient(180deg, #fbbf24 0%, #d97706 100%)',
    },
    stats: [
      { label: '记录笔数', value: '0' },
      { label: '当前状态', value: '待接入' },
      { label: '数据来源', value: '预留模板' },
      { label: '下一阶段', value: '截图入库' },
    ],
  },
  sleep: {
    summary: {
      label: '睡眠记录概览',
      value: '0 条',
      change: '睡眠域已预留，后续会和 AI 入库一起打通',
      gradient: 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)',
      barColor: 'linear-gradient(180deg, #818cf8 0%, #4f46e5 100%)',
    },
    stats: [
      { label: '记录天数', value: '0' },
      { label: '平均时长', value: '--' },
      { label: '来源状态', value: '待接入' },
      { label: '下一阶段', value: '正式入库' },
    ],
  },
  reading: {
    summary: {
      label: '阅读记录概览',
      value: '0 条',
      change: '阅读记录模板已就绪，后续会承接微信读书等来源',
      gradient: 'linear-gradient(135deg, #0ea5e9 0%, #0284c7 100%)',
      barColor: 'linear-gradient(180deg, #38bdf8 0%, #0284c7 100%)',
    },
    stats: [
      { label: '阅读记录', value: '0' },
      { label: '累计时长', value: '--' },
      { label: '来源状态', value: '待接入' },
      { label: '下一阶段', value: '模板联动' },
    ],
  },
  food: {
    summary: {
      label: '饮食记录概览',
      value: '0 餐',
      change: '拍照估算餐盘热量与三大营养素',
      gradient: 'linear-gradient(135deg, #ea580c 0%, #c2410c 100%)',
      barColor: 'linear-gradient(180deg, #fb923c 0%, #c2410c 100%)',
    },
    stats: [
      { label: '餐次记录', value: '0' },
      { label: '累计热量', value: '--' },
      { label: '识别来源', value: 'AI 拍照估算' },
      { label: '准确度提示', value: '±20-40%' },
    ],
  },
  wallet: {
    summary: {
      label: '钱包与待还概览',
      value: '0 条',
      change: '记录当前可用现金和花呗/白条/月付等待还款',
      gradient: 'linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%)',
      barColor: 'linear-gradient(180deg, #a78bfa 0%, #7c3aed 100%)',
    },
    stats: [
      { label: '快照记录', value: '0' },
      { label: '可用现金', value: '--' },
      { label: '短期待还', value: '--' },
      { label: '联动状态', value: 'AI 现金流' },
    ],
  },
}))

const activeData = computed(() => {
  if (activeDomain.value === 'income') return incomeData.value
  if (['sport', 'sleep', 'reading', 'food', 'wallet'].includes(activeDomain.value)) return universalData(activeDomain.value)
  return expenseData.value
})

const netStatus = computed(() => {
  if (store.netBalance.value > 0) return `净流入 ¥${store.netBalance.value.toFixed(2)}`
  if (store.netBalance.value < 0) return `净流出 ¥${Math.abs(store.netBalance.value).toFixed(2)}`
  return '本月收支持平'
})

function withEmptyDetail(base) {
  return {
    ...base,
    trendLabels: ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
    trendData: [0, 0, 0, 0, 0, 0, 0],
    trendMax: 1,
    categories: [],
    platforms: [],
    paymentMethods: [],
    specialSummaries: [],
  }
}

function universalData(domainKey) {
  const base = placeholderData.value[domainKey]
  const domainObj = reportDomains.find(d => d.id === domainKey) || { id: domainKey, name: base.summary.label }
  const adapter = pickAdapter(domainKey)

  // 没接入 adapter 时退回原占位
  if (!adapter) {
    return { ...base, ...withEmptyDetail(base) }
  }

  const records = universalRecords.value
  const count = records.length
  const metricItems = adapter.getMetricItems(store, domainObj)
  const trend = adapter.getTrend(store, domainObj)
  const distribution = adapter.getDistribution(store, domainObj)

  // 主 fact 元信息（用于 summary headline 单位 / 时长格式化）
  const schema = getDomainSchema(domainKey)
  const display = getDomainDisplay(domainKey)
  const primaryFact = schema?.facts?.find(f => f.key === display?.primary_fact) || schema?.facts?.[0]
  const headlineMetric = metricItems[0] || { value: `${count} 条` }

  return {
    summary: {
      ...base.summary,
      value: count ? headlineMetric.value : '0 条',
      change: count
        ? `已记录 ${count} 条 · ${headlineMetric.label || ''}`.trim()
        : base.summary.change,
    },
    stats: metricItems.map(item => ({ label: item.label, value: item.value })),
    trendLabels: trend.labels,
    trendData: trend.values,
    trendMax: Math.max(...trend.values, 1),
    categories: distribution.map(d => ({
      name: d.name,
      amount: d.value,
      pct: d.pct,
      display: d.display || (primaryFact && isDurationFact(primaryFact) ? `${d.value} 分钟` : `${d.value}`),
    })),
    platforms: [],
    paymentMethods: [],
    specialSummaries: count
      ? [{ label: '最近记录', value: records[0]?.title || '暂无', icon: domainObj.icon || '·', color: activeMeta.value.color }]
      : [],
  }
}

function buildAmountRank(list, currency = false, unit = '') {
  const grouped = {}
  list.forEach(item => {
    grouped[item.name] = (grouped[item.name] || 0) + Number(item.amount || 0)
  })
  const entries = Object.entries(grouped).sort((a, b) => b[1] - a[1])
  const max = entries[0]?.[1] || 1
  return entries.map(([name, amount]) => ({
    name,
    amount,
    pct: Math.round((amount / max) * 100),
    display: currency ? `¥${amount.toFixed(0)}` : `${formatNumber(amount)}${unit ? ` ${unit}` : ''}`,
  }))
}

function formatNumber(value) {
  const num = Number(value || 0)
  return Number.isInteger(num) ? String(num) : num.toFixed(1)
}

function normalizeChartList(list) {
  const max = Math.max(...list.map(item => item.pct || 0), 1)
  return list.map(item => ({
    ...item,
    pct: item.pct ? Math.round((item.pct / max) * 100) : 0,
  }))
}
</script>

<style scoped>
.report-insights-entry {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 12px;
  background: linear-gradient(135deg, rgba(33, 79, 61, 0.06) 0%, rgba(33, 79, 61, 0.02) 100%);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 14px 16px;
  margin: 12px 0 16px;
  cursor: pointer;
  text-align: left;
  transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease;
}
.report-insights-entry:active {
  transform: scale(0.985);
}
.report-insights-entry:hover {
  border-color: var(--primary-light, var(--primary));
  box-shadow: 0 2px 10px rgba(33, 79, 61, 0.06);
}
.report-insights-entry-icon {
  width: 38px;
  height: 38px;
  border-radius: 10px;
  background: var(--primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 15px;
  flex-shrink: 0;
  letter-spacing: 0.5px;
}
.report-insights-entry-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.report-insights-entry-title {
  font-size: 14.5px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: 0.2px;
}
.report-insights-entry-sub {
  font-size: 11.5px;
  color: var(--text2);
  letter-spacing: 0.2px;
}
.report-insights-entry-arrow {
  color: var(--text3);
  font-size: 18px;
  font-weight: 300;
  flex-shrink: 0;
}
</style>
