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
      <!-- 成长进度：每个域是一棵慢慢长起来的树 -->
      <div class="insights-growth">
        <div class="insights-growth-head">
          <span class="insights-growth-title">成长进度</span>
          <span class="insights-growth-overall">
            整体 · <strong>{{ overallMaturity.label }}</strong>
            <span v-if="!overallMaturity.isMax" class="insights-growth-overall-hint">
              再记 {{ overallMaturity.remainingToNext }} 天解锁
            </span>
          </span>
        </div>
        <div class="insights-growth-list">
          <div v-for="d in growthList" :key="d.key" class="insights-growth-item">
            <div class="insights-growth-item-head">
              <span class="insights-growth-dot" :style="{ background: d.color }"></span>
              <span class="insights-growth-label">{{ d.label }}</span>
              <span class="insights-growth-stage">{{ d.maturity.label }}</span>
            </div>
            <div class="insights-growth-bar">
              <div class="insights-growth-bar-fill" :style="{ width: d.pctOfNext + '%', background: d.color }"></div>
            </div>
            <div class="insights-growth-hint">{{ d.hint }}</div>
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

      <!-- 联动洞察（规则版） -->
      <div class="insights-insight-box" :class="'tone-' + overallMaturity.key">
        <div class="insights-insight-title">
          <span>{{ insightTitle }}</span>
          <span class="insights-insight-stage">{{ overallMaturity.label }}阶段</span>
        </div>
        <div class="insights-insight-text" v-html="insightText"></div>
        <div class="insights-insight-foot">即时规则计算</div>
      </div>

      <!-- AI 洞察（按需生成） -->
      <div class="insights-ai-box">
        <div class="insights-ai-head">
          <span class="insights-ai-title">AI 解读</span>
          <span v-if="store.aiInsight.value" class="insights-ai-meta">
            {{ store.aiInsightCached.value ? '缓存' : '刚生成' }} · {{ formatAiTime(store.aiInsight.value.generated_at) }}
          </span>
        </div>

        <!-- 未生成态 -->
        <div v-if="!store.aiInsight.value && !store.aiInsightLoading.value" class="insights-ai-empty">
          <div class="insights-ai-empty-icon">✨</div>
          <div class="insights-ai-empty-text">让 AI 通读你的 {{ range }} 天数据，写一段更懂你的解读。</div>
          <button class="insights-ai-cta" @click="onGenerateAi">生成 AI 解读</button>
        </div>

        <!-- 加载态 -->
        <div v-else-if="store.aiInsightLoading.value" class="insights-ai-loading">
          <div class="insights-ai-loading-spinner"></div>
          <div>AI 正在阅读你的数据…</div>
        </div>

        <!-- 已生成 -->
        <div v-else class="insights-ai-content">
          <div v-if="aiPayload.headline" class="insights-ai-headline">{{ aiPayload.headline }}</div>

          <div v-if="aiPayload.observations?.length" class="insights-ai-section">
            <div class="insights-ai-section-title">观察</div>
            <ul class="insights-ai-list">
              <li v-for="(o, i) in aiPayload.observations" :key="'o' + i">{{ o }}</li>
            </ul>
          </div>

          <div v-if="aiPayload.suggestions?.length" class="insights-ai-section">
            <div class="insights-ai-section-title">建议</div>
            <ul class="insights-ai-list">
              <li v-for="(s, i) in aiPayload.suggestions" :key="'s' + i">{{ s }}</li>
            </ul>
          </div>

          <div v-if="aiPayload.encouragement" class="insights-ai-encourage">{{ aiPayload.encouragement }}</div>

          <div class="insights-ai-actions">
            <button class="insights-ai-refresh" :disabled="store.aiInsightLoading.value" @click="onGenerateAi(true)">
              {{ store.aiInsightCached.value ? '强制刷新' : '重新生成' }}
            </button>
          </div>
        </div>

        <div v-if="store.aiInsightError.value" class="insights-ai-error">{{ store.aiInsightError.value }}</div>
      </div>

      <!-- 图表 1：睡眠 × 饮食 双 Y 轴 -->
      <ChartPanel
        title="睡眠时长 × 饮食热量"
        :tier="sleepFoodTier"
        :seed-hint="`等睡眠+饮食至少各记 3 天，会出现你的睡眠节奏图`"
      >
        <canvas ref="chartSleepFood"></canvas>
        <template #note>
          <span v-if="sleepFoodOverlapDays > 0 && sleepFoodOverlapDays < 7">
            {{ sleepFoodOverlapDays }} 天同时有两种数据，趋势刚开始显现
          </span>
        </template>
      </ChartPanel>

      <!-- 图表 2：收支堆叠 -->
      <ChartPanel
        title="每日收支流水"
        :tier="financeTier"
        :seed-hint="`记录几天消费或收入后，这里会出现日级流水图`"
      >
        <canvas ref="chartFinance"></canvas>
      </ChartPanel>

      <!-- 图表 3：饮食热量趋势 -->
      <ChartPanel
        title="饮食热量趋势"
        :tier="foodTier"
        :seed-hint="`记录 3 餐以上后，这里会画出你的热量曲线`"
      >
        <canvas ref="chartCalorie"></canvas>
        <template #note>接入运动消耗后将演化为热量平衡</template>
      </ChartPanel>

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
import { computed, inject, onMounted, onBeforeUnmount, nextTick, ref } from 'vue'
import { Chart, registerables } from 'chart.js'
import { formatDuration } from '../../utils/format'
import { getMaturity, getMaturityHint, getRenderTier } from '../../utils/maturity'
import ChartPanel from '../ChartPanel.vue'

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
  // 关键：loading 期间整块 ChartPanel 会被 v-if 卸载，旧 canvas 销毁但 chart 实例还在跑
  // animation，会抛 clipArea(null)。所以先 destroy。
  destroyCharts()
  await store.loadDailySummary({ days: range.value, force })
  // 双 nextTick：第一次让 v-else 模板渲染（ChartPanel 出现），第二次让 ChartPanel 内 v-else 渲染（canvas 出现）
  await nextTick()
  await nextTick()
  rebuildCharts()
}

function setRange(v) {
  if (range.value === v) return
  range.value = v
  // 切换 range 时清空当前 AI 显示，下次按需生成
  store.aiInsight.value = null
  store.aiInsightCached.value = false
  reload(true)
  store.loadLatestAiInsight({ days: v })
}

onMounted(async () => {
  await reload(false)
  // 顺路拉一下最近 AI 缓存（不阻塞）
  store.loadLatestAiInsight({ days: range.value })
})
onBeforeUnmount(() => destroyCharts())

// AI 操作
async function onGenerateAi(force = false) {
  try {
    await store.generateAiInsight({ days: range.value, force })
  } catch (e) {
    // store 已写入 error，前端兜底
  }
}

const aiPayload = computed(() => store.aiInsight.value?.payload_jsonb || {})

function formatAiTime(iso) {
  if (!iso) return ''
  const t = new Date(iso).getTime()
  const diff = Date.now() - t
  if (diff < 60_000) return '刚刚'
  if (diff < 3600_000) return Math.floor(diff / 60_000) + ' 分钟前'
  if (diff < 86400_000) return Math.floor(diff / 3600_000) + ' 小时前'
  return new Date(iso).toISOString().slice(5, 10)
}

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

// 各域「有数据天数」汇总
const domainDays = computed(() => {
  const c = { expense: 0, income: 0, sleep: 0, sport: 0, reading: 0, food: 0 }
  denseData.value.forEach(d => {
    if (d.expenseCount) c.expense++
    if (d.incomeCount) c.income++
    if (d.sleepCount) c.sleep++
    if (d.sportCount) c.sport++
    if (d.readingCount) c.reading++
    if (d.foodMeals) c.food++
  })
  return c
})

// 成长进度列表（取代原密度表）
const DOMAIN_LABELS = [
  ['expense', '消费'], ['income', '收入'], ['sleep', '睡眠'],
  ['sport', '运动'], ['food', '饮食'], ['reading', '阅读'],
]
const growthList = computed(() => {
  const days = domainDays.value
  return DOMAIN_LABELS.map(([k, label]) => {
    const n = days[k]
    const m = getMaturity(n)
    const pctOfNext = m.isMax
      ? 100
      : Math.min(100, Math.round((n / Math.max(m.nextTarget, 1)) * 100))
    return {
      key: k,
      label,
      color: DOMAIN_COLOR[k],
      days: n,
      maturity: m,
      pctOfNext,
      hint: getMaturityHint(label, n),
    }
  })
})

// 整体成熟度：取「至少一个域有数据」的总活跃天数
const overallActiveDays = computed(() =>
  denseData.value.filter(d =>
    d.expenseCount || d.incomeCount || d.sleepCount || d.sportCount || d.readingCount || d.foodMeals
  ).length
)
const overallMaturity = computed(() => getMaturity(overallActiveDays.value))

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

// 联动洞察文本（规则版，按成熟度调口吻）
const sleepFoodOverlapDays = computed(() => denseData.value.filter(d => d.sleepMinutes > 0 && d.foodCalories > 0).length)

const insightTitle = computed(() => {
  switch (overallMaturity.value.key) {
    case 'seed':    return '这是你的开始'
    case 'sprout':  return '轮廓浮现'
    case 'growing': return '趋势正在显现'
    case 'mature':  return '可见跨域关联'
    default:        return '个人基准线'
  }
})

const insightText = computed(() => {
  const data = denseData.value
  if (!data.length) return '还没有任何记录。去首页随手记上一笔吧。'
  const m = overallMaturity.value
  const parts = []

  // 阶段一句话（控制口吻）
  const stageLine = ({
    seed:    `你的记录才刚开始。我在记下每一天，等越多数据进来，能看出的东西就越多。`,
    sprout:  `已经能看到你的一些轮廓。现阶段只描述不下结论，避免样本太少误判。`,
    growing: `趋势正在出现。一些节奏性的东西开始可见。`,
    mature:  `数据量足以添加跨域观察。现在能看到哪些事情是联动发生的。`,
    rich:    `你已经有了稳定的个人基准线。下面是基于这个基准的观察。`,
  })[m.key]
  parts.push(stageLine)

  // 包含活跃天数
  parts.push(`<br><br>近 ${range.value} 天里，你有 <strong>${overallActiveDays.value} 天</strong>至少记录了一个域。`)

  // 足够成熟才说极值
  const sleepDays = data.filter(d => d.sleepMinutes > 0)
  if (sleepDays.length >= 3) {
    const best = sleepDays.slice().sort((a, b) => (b.sleepScore || 0) - (a.sleepScore || 0))[0]
    const worst = sleepDays.slice().sort((a, b) => (a.sleepScore || 0) - (b.sleepScore || 0))[0]
    if (best?.sleepScore && worst?.sleepScore && best.sleepScore !== worst.sleepScore) {
      parts.push(
        ` 睡眠最好是 ${best.date.slice(5)}（${formatDuration(best.sleepMinutes)}，评分 ${Math.round(best.sleepScore)}），` +
        `最差是 ${worst.date.slice(5)}（${formatDuration(worst.sleepMinutes)}，评分 ${Math.round(worst.sleepScore)}）。`
      )
    }
  }

  const foodDays = data.filter(d => d.foodCalories > 0)
  if (foodDays.length >= 3) {
    const avgCal = Math.round(foodDays.reduce((s, d) => s + d.foodCalories, 0) / foodDays.length)
    const overshoot = foodDays.filter(d => d.foodCalories > 2000).length
    parts.push(` 饮食日均 ${avgCal} 千卡${overshoot > 0 ? `，其中 ${overshoot} 天超过 2000 千卡` : ''}。`)
  }

  // 成熟阶段才提跨域关联
  const overlap = sleepFoodOverlapDays.value
  if ((m.key === 'mature' || m.key === 'rich') && overlap >= 7) {
    parts.push(` <br><br>你有 <strong>${overlap} 天</strong>同时记了睡眠和饮食——这是现在最可靠的跨域观察口。`)
  } else if (overlap > 0 && overlap < 7) {
    parts.push(` 现在 ${overlap} 天同时有睡眠和饮食记录，这个交叉维度还在长大。`)
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

// ───────────────────── 图表 tier 计算 ─────────────────────
// tier = placeholder/light/solid，给 ChartPanel 用
const sleepFoodTier = computed(() => {
  const days = Math.min(domainDays.value.sleep, domainDays.value.food)
  return getRenderTier(days)
})
const financeTier = computed(() => {
  const days = Math.max(domainDays.value.expense, domainDays.value.income)
  return getRenderTier(days)
})
const foodTier = computed(() => getRenderTier(domainDays.value.food))

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
        tooltip: { callbacks: { label: ctx => {
          if (ctx.raw == null) return ''
          return ctx.raw < 0 ? '支出 ¥' + Math.abs(ctx.raw).toFixed(0) : '收入 ¥' + ctx.raw.toFixed(0)
        } } },
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

/* 成长进度（取代原密度表） */
.insights-growth {
  background: rgba(255, 255, 255, 0.94);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 14px 16px 12px;
  margin-bottom: 16px;
}
.insights-growth-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 12px;
  gap: 8px;
}
.insights-growth-title {
  font-size: 11px;
  letter-spacing: 1.2px;
  color: var(--text3);
  text-transform: uppercase;
  font-weight: 700;
}
.insights-growth-overall {
  font-size: 11.5px;
  color: var(--text2);
  letter-spacing: 0.3px;
}
.insights-growth-overall strong {
  color: var(--primary);
  font-weight: 700;
  margin-right: 4px;
}
.insights-growth-overall-hint {
  margin-left: 6px;
  color: var(--text3);
  font-size: 10.5px;
}
.insights-growth-list {
  display: grid;
  grid-template-columns: 1fr;
  gap: 12px;
}
.insights-growth-item {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.insights-growth-item-head {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 12.5px;
}
.insights-growth-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  flex-shrink: 0;
}
.insights-growth-label {
  font-weight: 600;
  color: var(--text);
  flex: 1;
}
.insights-growth-stage {
  font-size: 10.5px;
  font-weight: 600;
  letter-spacing: 0.4px;
  color: var(--text3);
  padding: 1px 8px;
  background: rgba(0, 0, 0, 0.04);
  border-radius: 999px;
}
.insights-growth-bar {
  height: 4px;
  background: rgba(0, 0, 0, 0.05);
  border-radius: 999px;
  overflow: hidden;
}
.insights-growth-bar-fill {
  height: 100%;
  border-radius: 999px;
  transition: width 0.4s ease;
}
.insights-growth-hint {
  font-size: 10.5px;
  color: var(--text3);
  letter-spacing: 0.2px;
  padding-left: 14px;
}
@media (min-width: 520px) {
  .insights-growth-list { grid-template-columns: repeat(2, 1fr); column-gap: 22px; }
}

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
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}
.insights-insight-title > span:first-child {
  font-size: 14px;
  color: var(--text);
  font-weight: 700;
  letter-spacing: 0.2px;
}
.insights-insight-stage {
  font-size: 10.5px;
  font-weight: 600;
  letter-spacing: 0.4px;
  color: var(--primary);
  background: rgba(33, 79, 61, 0.08);
  padding: 2px 9px;
  border-radius: 999px;
}
.insights-insight-box.tone-seed { border-left-color: #9ca3af; }
.insights-insight-box.tone-sprout { border-left-color: #f59e0b; }
.insights-insight-box.tone-growing { border-left-color: #0ea5e9; }
.insights-insight-box.tone-mature { border-left-color: #2d6a4f; }
.insights-insight-box.tone-rich { border-left-color: #7c5cfc; }
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

/* 图表由 ChartPanel 组件接管，不在此处定义 */

/* AI 解读区 */
.insights-ai-box {
  background: linear-gradient(135deg, rgba(124, 92, 252, 0.05) 0%, rgba(33, 79, 61, 0.04) 100%);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 16px 18px 18px;
  margin-bottom: 18px;
  position: relative;
}
.insights-ai-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 12px;
}
.insights-ai-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: 0.3px;
}
.insights-ai-meta {
  font-size: 10.5px;
  color: var(--text3);
  letter-spacing: 0.3px;
}

.insights-ai-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 20px 12px 8px;
  text-align: center;
}
.insights-ai-empty-icon {
  font-size: 24px;
  filter: hue-rotate(220deg);
}
.insights-ai-empty-text {
  font-size: 12.5px;
  color: var(--text2);
  line-height: 1.6;
  max-width: 88%;
}
.insights-ai-cta {
  margin-top: 8px;
  background: linear-gradient(135deg, #7c5cfc 0%, #5b3ee0 100%);
  color: #fff;
  border: none;
  padding: 9px 24px;
  border-radius: 999px;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.4px;
  cursor: pointer;
  box-shadow: 0 2px 8px rgba(124, 92, 252, 0.25);
  transition: transform 0.15s ease, box-shadow 0.15s ease;
}
.insights-ai-cta:active {
  transform: scale(0.96);
}

.insights-ai-loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 24px 12px 12px;
  color: var(--text2);
  font-size: 12.5px;
}
.insights-ai-loading-spinner {
  width: 26px;
  height: 26px;
  border: 2px solid rgba(124, 92, 252, 0.2);
  border-top-color: #7c5cfc;
  border-radius: 50%;
  animation: ai-spin 0.8s linear infinite;
}
@keyframes ai-spin {
  to { transform: rotate(360deg); }
}

.insights-ai-content {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.insights-ai-headline {
  font-size: 15px;
  font-weight: 700;
  color: var(--text);
  line-height: 1.5;
  letter-spacing: 0.2px;
  padding: 6px 0 4px;
}
.insights-ai-section-title {
  font-size: 10.5px;
  letter-spacing: 1.2px;
  font-weight: 700;
  color: #7c5cfc;
  text-transform: uppercase;
  margin-bottom: 6px;
}
.insights-ai-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.insights-ai-list li {
  position: relative;
  padding-left: 14px;
  font-size: 13px;
  color: var(--text);
  line-height: 1.6;
}
.insights-ai-list li::before {
  content: '·';
  position: absolute;
  left: 4px;
  top: -1px;
  color: #7c5cfc;
  font-weight: 700;
  font-size: 16px;
}
.insights-ai-encourage {
  font-size: 12.5px;
  color: var(--text2);
  font-style: italic;
  line-height: 1.7;
  padding-top: 6px;
  border-top: 1px dashed rgba(0, 0, 0, 0.06);
  letter-spacing: 0.2px;
}
.insights-ai-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 4px;
}
.insights-ai-refresh {
  background: transparent;
  border: 1px solid rgba(124, 92, 252, 0.4);
  color: #7c5cfc;
  font-size: 11.5px;
  font-weight: 600;
  padding: 4px 14px;
  border-radius: 999px;
  cursor: pointer;
  letter-spacing: 0.3px;
}
.insights-ai-refresh:disabled {
  opacity: 0.4;
  cursor: default;
}

.insights-ai-error {
  margin-top: 10px;
  padding: 8px 12px;
  background: rgba(239, 68, 68, 0.08);
  border-radius: 8px;
  color: #b91c1c;
  font-size: 12px;
  line-height: 1.5;
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
