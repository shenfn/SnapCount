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

    <!-- 分类消费占比环图 M2 -->
    <div class="sec-title">分类消费占比</div>
    <div class="card">
      <div v-if="!catDonutData.length" class="empty" style="padding:20px">
        <p>本月暂无数据</p>
      </div>
      <div v-else class="donut-wrap">
        <svg width="120" height="120" viewBox="0 0 42 42">
          <circle cx="21" cy="21" r="15.9" fill="transparent"
            stroke="var(--surface2)" stroke-width="5" />
          <circle v-for="(seg, i) in donutSegments" :key="i"
            cx="21" cy="21" r="15.9" fill="transparent"
            :stroke="seg.color" stroke-width="5"
            :stroke-dasharray="seg.dash"
            :stroke-dashoffset="seg.offset"
            stroke-linecap="round" />
        </svg>
        <div class="donut-legend">
          <div v-for="item in catDonutData" :key="item.cat" class="legend-item">
            <div class="legend-dot" :style="{ background: item.color }"></div>
            <div class="legend-label">{{ item.label }}</div>
            <div class="legend-pct">{{ item.pct }}%</div>
          </div>
        </div>
      </div>
    </div>

    <!-- 每日支出折线图 M6 -->
    <div class="sec-title">每日支出趋势</div>
    <div class="card" style="padding:16px 12px 8px;">
      <div v-if="!dailyLineData.length" class="empty" style="padding:20px">
        <p>本月暂无数据</p>
      </div>
      <svg v-else :viewBox="`0 0 ${lineW} ${lineH + 20}`" style="width:100%;height:auto;display:block;">
        <!-- 日均参考线 -->
        <line x1="0" :y1="avgLineY" :x2="lineW" :y2="avgLineY"
          stroke="var(--accent)" stroke-width="0.8" stroke-dasharray="3,3" opacity="0.5" />
        <text :x="lineW - 2" :y="avgLineY - 3" text-anchor="end"
          fill="var(--accent)" font-size="8" opacity="0.7">日均 ¥{{ dailyAvgNum }}</text>
        <!-- 折线 -->
        <polyline :points="linePoints" fill="none" stroke="var(--accent)" stroke-width="1.5"
          stroke-linejoin="round" stroke-linecap="round" />
        <!-- 数据点 -->
        <circle v-for="(pt, i) in dailyLineData" :key="i"
          :cx="pt.x" :cy="pt.y" r="2" fill="var(--accent)" />
        <!-- X 轴日期标签(每5天) -->
        <text v-for="(pt, i) in dailyLineData" :key="'l'+i"
          v-show="i % 5 === 0 || i === dailyLineData.length - 1"
          :x="pt.x" :y="lineH + 14" text-anchor="middle"
          fill="var(--text3)" font-size="7">{{ pt.day }}</text>
      </svg>
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

// ── 分类消费占比环图 M2 ──
const catColors = ['#2D6A4F', '#40916C', '#52B788', '#74C69D', '#95D5B2', '#B7E4C7', '#D8F3DC', '#A7C4A0']
const catLabelMap = { food: '餐饮', shopping: '购物', transport: '出行', entertainment: '娱乐', life: '生活', health: '医疗', education: '教育', other: '其他' }

const catDonutData = computed(() => {
  const grouped = {}
  store.doneBills.value.forEach(b => {
    const c = b.cat && b.cat !== '?' ? b.cat : 'other'
    grouped[c] = (grouped[c] || 0) + b.amount
  })
  const total = Object.values(grouped).reduce((a, b) => a + b, 0) || 1
  return Object.entries(grouped)
    .sort((a, b) => b[1] - a[1])
    .map(([cat, amount], i) => ({
      cat,
      label: catLabelMap[cat] || cat,
      amount,
      pct: Math.round(amount / total * 100),
      color: catColors[i % catColors.length],
    }))
})

const donutSegments = computed(() => {
  const circ = 2 * Math.PI * 15.9
  let offset = circ * 0.25
  return catDonutData.value.map(item => {
    const len = (item.pct / 100) * circ
    const seg = { color: item.color, dash: `${len} ${circ - len}`, offset: offset }
    offset -= len
    return seg
  })
})

// ── 每日支出折线图 M6 ──
const lineW = 320
const lineH = 100

const dailyLineData = computed(() => {
  const y = store.currentYear.value
  const m = store.currentMonth.value
  const daysInMonth = new Date(y, m, 0).getDate()
  const byDay = new Array(daysInMonth).fill(0)
  store.doneBills.value.forEach(b => {
    if (!b.dateRaw) return
    const day = parseInt(b.dateRaw.slice(8, 10), 10)
    if (day >= 1 && day <= daysInMonth) byDay[day - 1] += b.amount
  })
  const maxVal = Math.max(...byDay, 1)
  const padX = 10
  const usableW = lineW - padX * 2
  return byDay.map((v, i) => ({
    day: i + 1,
    amount: v,
    x: padX + (daysInMonth > 1 ? (i / (daysInMonth - 1)) * usableW : usableW / 2),
    y: lineH - (v / maxVal) * (lineH - 10) - 5,
  }))
})

const dailyAvgNum = computed(() => {
  if (!dailyLineData.value.length) return 0
  const total = dailyLineData.value.reduce((s, d) => s + d.amount, 0)
  return Math.round(total / dailyLineData.value.length)
})

const avgLineY = computed(() => {
  if (!dailyLineData.value.length) return lineH / 2
  const maxVal = Math.max(...dailyLineData.value.map(d => d.amount), 1)
  return lineH - (dailyAvgNum.value / maxVal) * (lineH - 10) - 5
})

const linePoints = computed(() => dailyLineData.value.map(d => `${d.x},${d.y}`).join(' '))

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
