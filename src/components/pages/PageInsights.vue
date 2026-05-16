<template>
  <div class="page active insights-page">
    <div class="insights-top-bar">
      <button class="insights-back" @click="store.goBack()">‹ 返回</button>
      <div class="insights-range-group">
        <span
          v-for="opt in rangeOptions"
          :key="opt.value"
          class="insights-range"
          :class="{ active: range === opt.value }"
          @click="setRange(opt.value)"
        >{{ opt.label }}</span>
      </div>
    </div>

    <div class="page-title">联动分析</div>
    <div class="page-subtitle">跨域日聚合 · 最近 {{ range }} 天</div>

    <!-- 加载/空态 -->
    <div v-if="store.dailySummaryLoading.value && !rows.length" class="insights-loading">
      正在汇总你的多域数据…
    </div>
    <div v-else-if="!rows.length" class="insights-empty">
      <div class="insights-empty-title">暂无可分析数据</div>
      <div class="insights-empty-desc">先去录入一些消费、睡眠、饮食记录吧。</div>
    </div>

    <template v-else>
      <!-- 数据密度横条 -->
      <div class="insights-density">
        <div class="insights-density-title">数据覆盖率</div>
        <div class="insights-density-grid">
          <div v-for="d in densityList" :key="d.key" class="insights-density-item" :class="d.cls">
            <span class="insights-density-dot" :style="{ background: d.color }"></span>
            <span class="insights-density-label">{{ d.label }}</span>
            <span class="insights-density-value">{{ d.days }}/{{ range }} 天</span>
          </div>
        </div>
      </div>

      <!-- 顶部 Stat 卡片 -->
      <div class="insights-stat-row">
        <div v-for="s in statCards" :key="s.label" class="insights-stat-card" :style="{ '--accent': s.color }">
          <div class="insights-stat-label">{{ s.label }}</div>
          <div class="insights-stat-value" :style="{ color: s.color }">
            {{ s.value }}<span class="insights-stat-unit">{{ s.unit }}</span>
          </div>
          <div class="insights-stat-sub">{{ s.sub }}</div>
        </div>
      </div>

      <!-- 联动洞察占位（阶段 B 接 AI） -->
      <div class="insights-insight-box">
        <div class="insights-insight-title">联动观察</div>
        <div class="insights-insight-text" v-html="insightText"></div>
        <div class="insights-insight-foot">基于规则计算 · 后续将由 AI 输出更丰富的洞察</div>
      </div>

      <!-- 图表 1：睡眠 × 饮食 双 Y 轴 -->
      <div class="insights-panel">
        <div class="insights-panel-title">睡眠时长 × 饮食热量</div>
        <div class="insights-canvas-wrap">
          <canvas ref="chartSleepFood"></canvas>
        </div>
        <div v-if="sleepFoodOverlapDays < 3" class="insights-panel-note">
          样本仅 {{ sleepFoodOverlapDays }} 天同时有睡眠和饮食记录，关联结论暂不可靠
        </div>
      </div>

      <!-- 图表 2：收支堆叠 -->
      <div class="insights-panel">
        <div class="insights-panel-title">每日收支流水</div>
        <div class="insights-canvas-wrap">
          <canvas ref="chartFinance"></canvas>
        </div>
      </div>

      <!-- 图表 3：饮食热量趋势 -->
      <div class="insights-panel">
        <div class="insights-panel-title">饮食热量趋势</div>
        <div class="insights-canvas-wrap">
          <canvas ref="chartCalorie"></canvas>
        </div>
        <div class="insights-panel-note">阶段 B 接入运动消耗后，将演化为热量平衡（摄入-消耗）</div>
      </div>

      <!-- 日历卡片：最近 N 天每日多域汇总 -->
      <div class="insights-section-title">每日明细</div>
      <div class="insights-daily-grid">
        <div
          v-for="day in dayCards"
          :key="day.date"
          class="insights-day-card"
          :class="{ empty: !day.hasAny }"
        >
          <div class="insights-day-head">
            <span class="insights-day-date">{{ day.dateLabel }}</span>
            <span class="insights-day-weekday">{{ day.weekday }}</span>
          </div>
          <div v-for="row in day.rows" :key="row.label" class="insights-day-row">
            <span class="insights-day-row-label">
              <span class="insights-day-dot" :style="{ background: row.color }"></span>
              {{ row.label }}
            </span>
            <span class="insights-day-row-value">{{ row.value }}</span>
          </div>
          <div v-if="!day.rows.length" class="insights-day-empty">无记录</div>
        </div>
      </div>
    </template>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject, onMounted, onBeforeUnmount, nextTick, ref, watch } from 'vue'
import { Chart, registerables } from 'chart.js'
import { formatDuration } from '../../utils/format'

Chart.register(...registerables)

const store = inject('store')

// ───────────────────── 配置常量 ─────────────────────
const rangeOptions = [
  { value: 7, label: '7 天' },
  { value: 14, label: '14 天' },
  { value: 30, label: '30 天' },
]
const DOMAIN_COLOR = {
  expense:  '#ef4444',
  income:   '#10b981',
  sleep:    '#7c5cfc',
  sport:    '#0ea5e9',
  reading:  '#f59e0b',
  food:     '#fb7185',
}
const range = ref(14)

// ───────────────────── 数据加载 ─────────────────────
const rows = computed(() => store.dailySummary.value || [])

async function reload(force = false) {
  await store.loadDailySummary({ days: range.value, force })
  await nextTick()
  rebuildCharts()
}

function setRange(v) {
  if (range.value === v) return
  range.value = v
  reload(true)
}

onMounted(() => reload(false))
onBeforeUnmount(() => destroyCharts())

// 当外部刷新 dailySummary（比如 confirm 后）也重绘
watch(() => store.dailySummary.value, () => {
  nextTick(rebuildCharts)
})

// ───────────────────── 衍生数据 ─────────────────────
function num(x) { return Number(x) || 0 }

const denseData = computed(() => rows.value.map(r => ({
  date: r.date,
  expense: num(r.expense_total),
  expenseCount: num(r.expense_count),
  income: num(r.income_total),
  incomeCount: num(r.income_count),
  sleepMinutes: num(r.sleep_minutes),
  sleepScore: r.sleep_score_avg != null ? Number(r.sleep_score_avg) : null,
  sleepCount: num(r.sleep_count),
  sportMinutes: num(r.sport_minutes),
  sportCount: num(r.sport_count),
  readingMinutes: num(r.reading_minutes),
  readingCount: num(r.reading_count),
  foodCalories: num(r.food_calories),
  foodMeals: num(r.food_meals),
})))

// 数据覆盖率
const densityList = computed(() => {
  const total = range.value
  const c = { expense: 0, income: 0, sleep: 0, sport: 0, reading: 0, food: 0 }
  denseData.value.forEach(d => {
    if (d.expenseCount) c.expense++
    if (d.incomeCount) c.income++
    if (d.sleepCount) c.sleep++
    if (d.sportCount) c.sport++
    if (d.readingCount) c.reading++
    if (d.foodMeals) c.food++
  })
  const out = []
  const map = [
    ['expense', '消费'], ['income', '收入'], ['sleep', '睡眠'],
    ['sport', '运动'], ['food', '饮食'], ['reading', '阅读'],
  ]
  for (const [k, label] of map) {
    const days = c[k]
    const ratio = days / Math.max(total, 1)
    let cls = 'good'
    if (ratio < 0.2) cls = 'sparse'
    else if (ratio < 0.5) cls = 'medium'
    out.push({ key: k, label, days, color: DOMAIN_COLOR[k], cls })
  }
  return out
})

// Stat 卡片
const statCards = computed(() => {
  const totals = denseData.value.reduce((acc, d) => {
    acc.expense += d.expense
    acc.income += d.income
    acc.sleepMinutes += d.sleepMinutes
    acc.sleepDays += d.sleepCount ? 1 : 0
    acc.foodCalories += d.foodCalories
    acc.foodMeals += d.foodMeals
    acc.activeDays += (d.expenseCount || d.incomeCount || d.sleepCount || d.sportCount || d.readingCount || d.foodMeals) ? 1 : 0
    return acc
  }, { expense: 0, income: 0, sleepMinutes: 0, sleepDays: 0, foodCalories: 0, foodMeals: 0, activeDays: 0 })

  const avgSleepMin = totals.sleepDays ? totals.sleepMinutes / totals.sleepDays : 0
  const avgSleepHour = (avgSleepMin / 60).toFixed(1)

  return [
    { label: '总消费', value: `¥${totals.expense.toFixed(0)}`, unit: '', sub: `${range.value} 天内`, color: DOMAIN_COLOR.expense },
    { label: '总收入', value: `¥${totals.income.toFixed(0)}`, unit: '', sub: `${range.value} 天内`, color: DOMAIN_COLOR.income },
    { label: '平均睡眠', value: avgSleepHour, unit: '小时', sub: `${totals.sleepDays} 晚有数据`, color: DOMAIN_COLOR.sleep },
    { label: '饮食热量', value: totals.foodCalories.toFixed(0), unit: '千卡', sub: `${totals.foodMeals} 餐`, color: DOMAIN_COLOR.food },
    { label: '活跃天数', value: `${totals.activeDays}`, unit: `/${range.value}天`, sub: '至少一个域有记录', color: '#374151' },
  ]
})

// 联动洞察文本（基于规则的"伪 AI"，后续替换为真 AI）
const sleepFoodOverlapDays = computed(() => denseData.value.filter(d => d.sleepMinutes > 0 && d.foodCalories > 0).length)

const insightText = computed(() => {
  const data = denseData.value
  if (!data.length) return '暂无足够数据。'
  const parts = []

  const sleepDays = data.filter(d => d.sleepMinutes > 0)
  if (sleepDays.length >= 3) {
    const best = sleepDays.slice().sort((a, b) => (b.sleepScore || 0) - (a.sleepScore || 0))[0]
    const worst = sleepDays.slice().sort((a, b) => (a.sleepScore || 0) - (b.sleepScore || 0))[0]
    if (best?.sleepScore && worst?.sleepScore && best.sleepScore !== worst.sleepScore) {
      parts.push(
        `<strong>睡眠峰值</strong>在 ${best.date.slice(5)}（${formatDuration(best.sleepMinutes)}，评分 ${Math.round(best.sleepScore)}），` +
        `<strong>低谷</strong>在 ${worst.date.slice(5)}（${formatDuration(worst.sleepMinutes)}，评分 ${Math.round(worst.sleepScore)}）。`
      )
    }
  }

  const foodDays = data.filter(d => d.foodCalories > 0)
  if (foodDays.length >= 3) {
    const avgCal = Math.round(foodDays.reduce((s, d) => s + d.foodCalories, 0) / foodDays.length)
    const overshoot = foodDays.filter(d => d.foodCalories > 2000).length
    parts.push(`饮食日均 ${avgCal} 千卡，${overshoot}/${foodDays.length} 天超过 2000 千卡。`)
  }

  const overlap = sleepFoodOverlapDays.value
  if (overlap > 0) {
    parts.push(`<br><br>${range.value} 天中有 <strong>${overlap} 天</strong>同时拥有睡眠和饮食数据，这是当前最有价值的跨域交叉维度。`)
  }

  const totalExp = data.reduce((s, d) => s + d.expense, 0)
  const totalInc = data.reduce((s, d) => s + d.income, 0)
  if (totalExp > 0 || totalInc > 0) {
    const net = totalInc - totalExp
    parts.push(
      `<br>财务：累计支出 ¥${totalExp.toFixed(0)}，累计收入 ¥${totalInc.toFixed(0)}，` +
      `净 ${net >= 0 ? '流入' : '流出'} ¥${Math.abs(net).toFixed(0)}。`
    )
  }

  return parts.join('') || '记录还不够多，多录几天再看看吧。'
})

// 日历卡片
const dayCards = computed(() => {
  return denseData.value.slice().reverse().map(d => {
    const dateObj = new Date(d.date + 'T00:00:00+08:00')
    const weekday = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][dateObj.getDay()]
    const rows = []
    if (d.expense > 0) rows.push({ label: '支出', value: `¥${d.expense.toFixed(0)}`, color: DOMAIN_COLOR.expense })
    if (d.income > 0) rows.push({ label: '收入', value: `¥${d.income.toFixed(0)}`, color: DOMAIN_COLOR.income })
    if (d.sleepMinutes > 0) rows.push({
      label: '睡眠',
      value: formatDuration(d.sleepMinutes) + (d.sleepScore ? ` · ${Math.round(d.sleepScore)}分` : ''),
      color: DOMAIN_COLOR.sleep,
    })
    if (d.sportMinutes > 0) rows.push({ label: '运动', value: formatDuration(d.sportMinutes), color: DOMAIN_COLOR.sport })
    if (d.foodCalories > 0) rows.push({ label: '饮食', value: `${d.foodCalories.toFixed(0)}千卡 · ${d.foodMeals}餐`, color: DOMAIN_COLOR.food })
    if (d.readingMinutes > 0) rows.push({ label: '阅读', value: formatDuration(d.readingMinutes), color: DOMAIN_COLOR.reading })
    return {
      date: d.date,
      dateLabel: d.date.slice(5),
      weekday,
      hasAny: rows.length > 0,
      rows,
    }
  })
})

// ───────────────────── Chart.js ─────────────────────
const chartSleepFood = ref(null)
const chartFinance = ref(null)
const chartCalorie = ref(null)
const charts = ref({})

function destroyCharts() {
  Object.values(charts.value).forEach(c => { try { c.destroy() } catch (e) {} })
  charts.value = {}
}

function rebuildCharts() {
  destroyCharts()
  const data = denseData.value
  if (!data.length) return
  const labels = data.map(d => d.date.slice(5))

  // Chart.js 全局默认（淡化轴线）
  Chart.defaults.font.family = "'Helvetica Neue', 'PingFang SC', sans-serif"
  Chart.defaults.font.size = 11
  Chart.defaults.color = '#6b7280'

  // 1) 睡眠 × 饮食热量
  if (chartSleepFood.value) {
    charts.value.sleepFood = new Chart(chartSleepFood.value, {
      type: 'bar',
      data: {
        labels,
        datasets: [
          {
            label: '睡眠（小时）',
            data: data.map(d => d.sleepMinutes > 0 ? +(d.sleepMinutes / 60).toFixed(2) : null),
            backgroundColor: data.map(d => {
              const s = d.sleepScore || 0
              if (s >= 85) return '#7c5cfcAA'
              if (s >= 78) return '#7c5cfc77'
              return '#7c5cfc44'
            }),
            borderColor: '#7c5cfc',
            borderWidth: 1,
            borderRadius: 4,
            yAxisID: 'y',
            order: 2,
          },
          {
            label: '饮食热量（千卡）',
            data: data.map(d => d.foodCalories > 0 ? d.foodCalories : null),
            type: 'line',
            borderColor: DOMAIN_COLOR.food,
            backgroundColor: DOMAIN_COLOR.food + '22',
            borderWidth: 2.5,
            pointRadius: 3.5,
            pointBackgroundColor: DOMAIN_COLOR.food,
            tension: 0.32,
            fill: true,
            yAxisID: 'y1',
            spanGaps: true,
            order: 1,
          },
        ],
      },
      options: chartOptions({
        y: { position: 'left', title: { display: true, text: '小时', color: '#7c5cfc' }, suggestedMin: 0, suggestedMax: 10 },
        y1: { position: 'right', title: { display: true, text: '千卡', color: DOMAIN_COLOR.food }, grid: { display: false }, suggestedMin: 0 },
      }),
    })
  }

  // 2) 收支堆叠柱（支出取负）
  if (chartFinance.value) {
    charts.value.finance = new Chart(chartFinance.value, {
      type: 'bar',
      data: {
        labels,
        datasets: [
          {
            label: '支出',
            data: data.map(d => d.expense > 0 ? -d.expense : null),
            backgroundColor: DOMAIN_COLOR.expense,
            borderRadius: 4,
          },
          {
            label: '收入',
            data: data.map(d => d.income > 0 ? d.income : null),
            backgroundColor: DOMAIN_COLOR.income,
            borderRadius: 4,
          },
        ],
      },
      options: chartOptions({
        y: { stacked: true, ticks: { callback: v => '¥' + Math.abs(v) } },
        x: { stacked: true },
      }, {
        tooltip: { callbacks: { label: ctx => (ctx.raw < 0 ? '支出 ¥' + Math.abs(ctx.raw).toFixed(0) : '收入 ¥' + ctx.raw.toFixed(0)) } },
      }),
    })
  }

  // 3) 饮食热量趋势
  if (chartCalorie.value) {
    charts.value.calorie = new Chart(chartCalorie.value, {
      type: 'line',
      data: {
        labels,
        datasets: [
          {
            label: '饮食热量（千卡）',
            data: data.map(d => d.foodCalories > 0 ? d.foodCalories : null),
            borderColor: DOMAIN_COLOR.food,
            backgroundColor: DOMAIN_COLOR.food + '22',
            fill: true,
            tension: 0.32,
            pointRadius: 3,
            borderWidth: 2,
            spanGaps: true,
          },
        ],
      },
      options: chartOptions({
        y: { suggestedMin: 0, title: { display: true, text: '千卡' } },
      }),
    })
  }
}

function chartOptions(scaleOverrides = {}, pluginOverrides = {}) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: { labels: { usePointStyle: true, pointStyleWidth: 8, padding: 12, boxHeight: 8 } },
      tooltip: { padding: 10, displayColors: true, ...pluginOverrides.tooltip },
    },
    scales: {
      x: { grid: { display: false } },
      y: { grid: { color: '#f1f5f9' } },
      ...scaleOverrides,
    },
  }
}
</script>

<style scoped>
.insights-page {
  padding: 12px 16px 40px;
}
.insights-top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}
.insights-back {
  background: transparent;
  border: none;
  color: var(--text2);
  font-size: 15px;
  padding: 4px 6px;
  cursor: pointer;
}
.insights-back:active { color: var(--primary); }

.insights-range-group {
  display: inline-flex;
  background: rgba(255, 255, 255, 0.7);
  border: 1px solid var(--border);
  border-radius: 999px;
  padding: 3px;
}
.insights-range {
  font-size: 12px;
  font-weight: 600;
  padding: 6px 12px;
  border-radius: 999px;
  color: var(--text2);
  cursor: pointer;
  letter-spacing: 0.4px;
}
.insights-range.active {
  background: var(--primary);
  color: #fff;
  box-shadow: 0 1px 4px rgba(33, 79, 61, 0.18);
}

.insights-loading,
.insights-empty {
  padding: 36px 12px;
  text-align: center;
  color: var(--text2);
  font-size: 13px;
}
.insights-empty-title {
  font-size: 15px;
  color: var(--text);
  margin-bottom: 6px;
  font-weight: 600;
}

/* 数据密度 */
.insights-density {
  background: rgba(255, 255, 255, 0.84);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 14px 16px;
  margin-bottom: 16px;
}
.insights-density-title {
  font-size: 11px;
  letter-spacing: 1.2px;
  color: var(--text3);
  margin-bottom: 10px;
  text-transform: uppercase;
  font-weight: 700;
}
.insights-density-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px 16px;
}
.insights-density-item {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12.5px;
}
.insights-density-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
.insights-density-label {
  color: var(--text);
  font-weight: 500;
  flex: 1;
}
.insights-density-value {
  font-family: var(--font-num);
  font-weight: 700;
  color: var(--text2);
  font-size: 12px;
}
.insights-density-item.sparse .insights-density-value { color: #ef4444; }
.insights-density-item.medium .insights-density-value { color: #f59e0b; }
.insights-density-item.good   .insights-density-value { color: #10b981; }

/* Stat row */
.insights-stat-row {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
  margin-bottom: 16px;
}
.insights-stat-card {
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 14px;
  position: relative;
  overflow: hidden;
}
.insights-stat-card::before {
  content: '';
  position: absolute;
  inset: 0 0 auto 0;
  height: 2px;
  background: var(--accent);
  opacity: 0.85;
}
.insights-stat-label {
  font-size: 11px;
  letter-spacing: 1px;
  color: var(--text3);
  text-transform: uppercase;
  font-weight: 700;
  margin-bottom: 6px;
}
.insights-stat-value {
  font-family: var(--font-num);
  font-size: 24px;
  font-weight: 700;
  letter-spacing: -0.4px;
  line-height: 1.1;
}
.insights-stat-unit {
  font-size: 12px;
  font-weight: 500;
  color: var(--text2);
  margin-left: 3px;
}
.insights-stat-sub {
  margin-top: 4px;
  font-size: 11px;
  color: var(--text3);
}

/* Insight box */
.insights-insight-box {
  background: rgba(255, 255, 255, 0.94);
  border: 1px solid var(--border);
  border-left: 3px solid var(--primary);
  border-radius: 0 14px 14px 0;
  padding: 14px 18px 16px;
  margin-bottom: 18px;
}
.insights-insight-title {
  font-size: 11px;
  letter-spacing: 1.2px;
  color: var(--text3);
  text-transform: uppercase;
  font-weight: 700;
  margin-bottom: 8px;
}
.insights-insight-text {
  font-size: 13.5px;
  color: var(--text);
  line-height: 1.7;
}
.insights-insight-text strong {
  color: var(--primary);
  font-weight: 700;
}
.insights-insight-foot {
  margin-top: 10px;
  font-size: 11px;
  color: var(--text3);
}

/* Panels */
.insights-panel {
  background: rgba(255, 255, 255, 0.94);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 16px 18px 18px;
  margin-bottom: 14px;
}
.insights-panel-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  margin-bottom: 12px;
  letter-spacing: 0.3px;
}
.insights-canvas-wrap {
  position: relative;
  height: 220px;
}
.insights-panel-note {
  margin-top: 10px;
  font-size: 11px;
  color: var(--text3);
  letter-spacing: 0.3px;
}

.insights-section-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: 0.3px;
  margin: 6px 2px 12px;
}

/* Daily grid */
.insights-daily-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 10px;
}
.insights-day-card {
  background: rgba(255, 255, 255, 0.94);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 12px 14px 10px;
}
.insights-day-card.empty {
  opacity: 0.55;
}
.insights-day-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-bottom: 8px;
  margin-bottom: 6px;
  border-bottom: 1px dashed var(--border);
}
.insights-day-date {
  font-family: var(--font-num);
  font-weight: 700;
  font-size: 14px;
  color: var(--text);
}
.insights-day-weekday {
  font-size: 11px;
  color: var(--text3);
  letter-spacing: 0.6px;
}
.insights-day-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 3px 0;
  font-size: 12.5px;
}
.insights-day-row-label {
  color: var(--text2);
  display: flex;
  align-items: center;
  gap: 6px;
}
.insights-day-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
}
.insights-day-row-value {
  font-weight: 600;
  color: var(--text);
}
.insights-day-empty {
  font-size: 12px;
  color: var(--text3);
  padding: 2px 0;
}

@media (min-width: 520px) {
  .insights-stat-row { grid-template-columns: repeat(3, 1fr); }
  .insights-daily-grid { grid-template-columns: repeat(2, 1fr); }
}

.spacer { height: 60px; }
</style>
