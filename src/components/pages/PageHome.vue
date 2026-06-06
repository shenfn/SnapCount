<template>
  <div class="page active">
    <div class="home-header">
      <div class="home-greeting">
        <div class="greeting-text">个人数据平台</div>
        <div class="greeting-date">{{ todayLabel }}</div>
      </div>
      <MonthPicker />
    </div>

    <div
      v-if="guidePills.length"
      class="home-guide-strip"
      :style="{ gridTemplateColumns: `repeat(${Math.max(guidePills.length, 1)}, minmax(0, 1fr))` }"
    >
      <button
        v-for="pill in guidePills"
        :key="pill.key"
        class="home-guide-pill"
        @click="scrollToSection(pill.section)"
      >
        <span>{{ pill.label }}</span>
        <strong>{{ pill.value }}</strong>
      </button>
    </div>

    <section class="home-layout-band">
      <div class="home-layout-summary">
        <div>
          <div class="home-layout-kicker">DASHBOARD LAYOUT</div>
          <div class="home-layout-title">{{ enabledWidgetCount }} 个首页组件已启用</div>
        </div>
        <button class="home-layout-btn" @click="layoutPanelOpen = true">管理组件</button>
      </div>
    </section>

    <div v-if="!orderedWidgets.length" class="home-layout-empty">
      <div class="home-layout-empty-title">首页组件已全部隐藏</div>
      <div class="home-layout-empty-desc">重新打开几个组件后，首页就会恢复成你自己的驾驶舱。</div>
      <button class="home-layout-empty-btn" @click="layoutPanelOpen = true">重新选择</button>
    </div>

    <template v-for="widget in orderedWidgets" :key="widget.key">
      <section v-if="widget.key === 'finance'" ref="financeSection" class="home-finance-section">
        <div class="section-header">
          <div class="section-title">财务状态</div>
          <div class="section-action" @click="store.navigateTo('report')">报告 ›</div>
        </div>
        <div class="finance-card">
          <div class="finance-card-top">
            <div>
              <div class="finance-kicker">{{ finance.statusLabel }}</div>
              <div class="finance-main-label">净额估算</div>
              <div class="finance-main-value">{{ finance.display.netWorthEstimate }}</div>
            </div>
            <button class="finance-badge" @click="store.openDomainPage('wallet')">钱包快照</button>
          </div>
          <div class="finance-split-grid">
            <div @click="store.openDomainPage('wallet')">
              <span>可用现金</span>
              <strong>{{ finance.display.availableCash }}</strong>
            </div>
            <div @click="store.openDomainPage('wallet')">
              <span>待还金额</span>
              <strong>{{ finance.display.liabilityTotal }}</strong>
            </div>
            <div @click="store.openDayDetail(todayKey, 'income')">
              <span>今日收入</span>
              <strong>{{ finance.display.todayIncome }}</strong>
            </div>
            <div @click="store.openDayDetail(todayKey, 'expense')">
              <span>今日支出</span>
              <strong>{{ finance.display.todayExpense }}</strong>
            </div>
          </div>
          <div class="finance-due-row" @click="openNearestLiability">
            <div>
              <div class="finance-due-label">最近待还</div>
              <div class="finance-due-name">{{ finance.nearestLiability?.accountName || '暂无待还' }}</div>
            </div>
            <div class="finance-due-value">
              <strong>{{ nearestLiabilityAmount }}</strong>
              <span>{{ nearestLiabilityDate }}</span>
            </div>
          </div>
          <div class="finance-trend">
            <div class="finance-trend-head">
              <span>近 7 日支出</span>
              <strong>{{ selectedTrendSummary }}</strong>
            </div>
            <div class="finance-bars">
              <div
                v-for="item in finance.sevenDayExpenseTrend"
                :key="item.dateKey"
                class="finance-bar-col"
                :class="{ selected: selectedTrendDateKey === item.dateKey }"
                @click="handleTrendClick(item)"
              >
                <div class="finance-bar-amount">¥{{ Math.round(item.amount) }}</div>
                <div class="finance-bar-wrap">
                  <div
                    class="finance-bar"
                    :class="{ today: item.dateKey === todayKey, selected: selectedTrendDateKey === item.dateKey }"
                    :style="{ height: item.pct + '%' }"
                  ></div>
                </div>
                <div class="finance-bar-label">{{ item.label }}</div>
              </div>
            </div>
            <div class="finance-trend-hint">{{ selectedTrendDateKey ? '再点选中柱子进入当天支出明细 ›' : '点柱子查看当天占比，再点进入明细' }}</div>
          </div>
        </div>
      </section>

      <section v-else-if="widget.key === 'today'" ref="todaySection">
        <div class="today-overview" v-if="!store.todaySummary.value.isEmpty">
          <div class="today-overview-header">
            <span class="today-overview-date">{{ todayDayLabel }}</span>
          </div>
          <div class="today-overview-grid">
            <div v-if="store.todaySummary.value.expenseCount" class="today-overview-row" @click="store.openDayDetail(todayKey, 'expense')">
              <div class="today-overview-icon expense">💸</div>
              <div class="today-overview-content">
                <div class="today-overview-label">支出 ¥{{ store.todaySummary.value.expenseTotal.toFixed(2) }}</div>
                <div class="today-overview-detail">
                  <template v-for="(count, platform, i) in store.todaySummary.value.expenseByPlatform" :key="platform">
                    {{ platform }}×{{ count }}<span v-if="i < Object.keys(store.todaySummary.value.expenseByPlatform).length - 1"> · </span>
                  </template>
                </div>
              </div>
            </div>
            <div
              v-if="store.todaySummary.value.pendingExpenseCount"
              class="today-overview-row pending-row"
              @click="store.navigateTo('pending')"
            >
              <div class="today-overview-icon pending">⚠️</div>
              <div class="today-overview-content">
                <div class="today-overview-label">待补全 ¥{{ store.todaySummary.value.pendingExpenseTotal.toFixed(2) }}</div>
                <div class="today-overview-detail">{{ store.todaySummary.value.pendingExpenseCount }} 笔已识别金额，待补全分类 ›</div>
              </div>
            </div>
            <div v-if="store.todaySummary.value.incomeCount" class="today-overview-row" @click="store.openDayDetail(todayKey, 'income')">
              <div class="today-overview-icon income">💰</div>
              <div class="today-overview-content">
                <div class="today-overview-label">收入 ¥{{ store.todaySummary.value.incomeTotal.toFixed(2) }}</div>
                <div class="today-overview-detail">{{ store.todaySummary.value.incomeCount }} 笔</div>
              </div>
            </div>
            <div
              v-for="s in store.todaySummary.value.sportItems"
              :key="'sport-' + s.title"
              class="today-overview-row"
              @click="store.openDayDetail(todayKey, 'sport')"
            >
              <div class="today-overview-icon sport">🏃</div>
              <div class="today-overview-content">
                <div class="today-overview-label">{{ s.title }}</div>
                <div class="today-overview-detail">{{ sportSummary(s) }}</div>
              </div>
            </div>
            <div
              v-for="s in store.todaySummary.value.sleepItems"
              :key="'sleep-' + s.title"
              class="today-overview-row"
              @click="store.openDayDetail(todayKey, 'sleep')"
            >
              <div class="today-overview-icon sleep">🌙</div>
              <div class="today-overview-content">
                <div class="today-overview-label">{{ s.title }}</div>
                <div class="today-overview-detail">{{ sleepSummary(s) }}</div>
              </div>
            </div>
            <div v-if="store.todaySummary.value.foodCount" class="today-overview-row" @click="store.openDayDetail(todayKey, 'food')">
              <div class="today-overview-icon food">🍱</div>
              <div class="today-overview-content">
                <div class="today-overview-label">今日饮食</div>
                <div class="today-overview-detail">{{ store.todaySummary.value.foodCount }} 餐 · 约 {{ store.todaySummary.value.foodCalorieTotal }} 千卡（估算）</div>
              </div>
            </div>
          </div>
          <div v-if="store.todaySummary.value.stagingCount" class="today-overview-footer" @click="store.navigateTo('pending')">
            ⏳ {{ store.todaySummary.value.stagingCount }} 条截图待确认 ›
          </div>
        </div>
        <div v-if="store.todaySummary.value.isEmpty && !store.timelineGroups.value.length" class="empty-state" style="margin-top: 24px;">
          <div class="empty-title">今天还没有记录</div>
          <div class="empty-desc">从一张截图开始，后续会逐步沉淀成多数据域资产。</div>
        </div>
      </section>

      <div
        v-else-if="widget.key === 'pending' && store.pendingSummary.value.total"
        ref="pendingSection"
        class="home-pending-alert"
        @click="store.navigateTo('pending')"
      >
        <div class="pending-alert-icon">
          待
          <div class="pending-alert-dot"></div>
        </div>
        <div class="pending-alert-content">
          <div class="pending-alert-title">{{ store.pendingSummary.value.total }} 条待处理记录</div>
          <div class="pending-alert-desc">
            {{ store.pendingSummary.value.routingFailed }} 条待分类 ·
            {{ store.pendingSummary.value.pendingReview }} 条待确认 ·
            {{ store.pendingSummary.value.aiError }} 条识别失败
          </div>
        </div>
        <div class="pending-alert-arrow">›</div>
      </div>

      <template v-else-if="widget.key === 'domains'">
        <div class="section-header">
          <div class="section-title">已安装数据域</div>
          <div class="section-action" @click="store.navigateTo('domains')">全部 ›</div>
        </div>
        <div class="home-domains-grid">
          <div
            v-for="domain in store.domains.value"
            :key="domain.id"
            class="domain-quick-card"
            @click="store.openDomainPage(domain.id)"
          >
            <div class="domain-quick-icon" :style="{ background: `${domain.color}18`, color: domain.color }">
              {{ domain.icon }}
            </div>
            <div class="domain-quick-name">{{ domain.name }}</div>
            <div class="domain-quick-count">{{ domain.recordCount }} 条</div>
          </div>
        </div>
      </template>

      <template v-else-if="widget.key === 'daily'">
        <div ref="dailySection" class="section-header home-daily-header">
          <div>
            <div class="section-title">每日明细</div>
            <div class="home-daily-sub">按日期汇总本月所有数据</div>
          </div>
          <div class="section-action" @click="store.navigateTo('report')">报告 ›</div>
        </div>
        <div class="home-daily-grid">
          <div
            v-for="card in store.visibleDailyCards.value"
            :key="card.dateKey"
            class="home-daily-card"
            :class="{ empty: card.isEmpty }"
            @click="store.openDayDetail(card.dateKey)"
          >
            <div class="home-daily-card-head">
              <div class="home-daily-date">{{ card.monthDay }}</div>
              <div class="home-daily-week">{{ card.weekday.replace('周', '周') }}</div>
            </div>
            <div class="home-daily-divider"></div>
            <div v-if="card.rows.length" class="home-daily-lines">
              <div v-for="row in card.rows" :key="row.kind" class="home-daily-line">
                <span class="home-daily-dot" :style="{ background: row.color }"></span>
                <span class="home-daily-label">{{ row.label }}</span>
                <strong class="home-daily-value">{{ row.value }}</strong>
              </div>
            </div>
            <div v-else class="home-daily-empty">这天还没有记录</div>
          </div>
        </div>
        <button
          v-if="store.visibleDailyCards.value.length < store.dailyCards.value.length"
          class="home-daily-more"
          @click="store.showMoreDailyCards()"
        >
          查看更多日期
        </button>
      </template>
    </template>

    <div v-if="layoutPanelOpen" class="home-layout-overlay" @click.self="layoutPanelOpen = false">
      <div class="home-layout-panel">
        <div class="home-layout-panel-head">
          <div>
            <div class="home-layout-kicker">DASHBOARD LAYOUT</div>
            <div class="home-layout-panel-title">首页组件</div>
          </div>
          <button class="home-layout-close" @click="layoutPanelOpen = false">完成</button>
        </div>

        <div class="home-layout-panel-list">
          <div v-for="(widget, index) in editableWidgets" :key="widget.key" class="home-layout-item">
            <div class="home-layout-item-main">
              <div class="home-layout-item-title">{{ widget.title }}</div>
              <div class="home-layout-item-desc">{{ widget.desc }}</div>
            </div>
            <div class="home-layout-item-actions">
              <label class="home-layout-switch">
                <input :checked="widget.enabled" type="checkbox" @change="toggleWidget(widget.key)">
                <span></span>
              </label>
              <button class="home-layout-order-btn" :disabled="index === 0" @click="moveWidget(widget.key, -1)">↑</button>
              <button class="home-layout-order-btn" :disabled="index === editableWidgets.length - 1" @click="moveWidget(widget.key, 1)">↓</button>
            </div>
          </div>
        </div>

        <div class="home-layout-panel-foot">
          <button class="home-layout-reset-btn" @click="resetWidgets">恢复默认</button>
        </div>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject, onMounted, ref, watch } from 'vue'
import MonthPicker from '../MonthPicker.vue'

const store = inject('store')
const dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
const financeSection = ref(null)
const todaySection = ref(null)
const pendingSection = ref(null)
const dailySection = ref(null)
const selectedTrendDateKey = ref('')
const layoutPanelOpen = ref(false)

const HOME_WIDGET_STORAGE_KEY = 'snapcount-home-widgets-v1'
const HOME_WIDGET_LIBRARY = [
  { key: 'finance', title: '财务状态', desc: '净额估算、待还与近 7 日支出趋势' },
  { key: 'today', title: '今日概览', desc: '当天消费、收入、运动、饮食与待处理摘要' },
  { key: 'pending', title: '待处理提醒', desc: '待分类、待确认、识别失败的截图提醒' },
  { key: 'domains', title: '数据域快捷入口', desc: '快速进入已安装数据域' },
  { key: 'daily', title: '每日明细', desc: '按日期查看本月全部沉淀记录' },
]

function createDefaultWidgets() {
  return HOME_WIDGET_LIBRARY.map((item, index) => ({
    ...item,
    enabled: true,
    order: index,
  }))
}

function normalizeWidgets(raw) {
  const defaults = createDefaultWidgets()
  if (!Array.isArray(raw) || !raw.length) return defaults
  const savedMap = new Map(raw.filter(Boolean).map(item => [item.key, item]))
  return defaults
    .map((item, index) => {
      const saved = savedMap.get(item.key) || {}
      return {
        ...item,
        enabled: typeof saved.enabled === 'boolean' ? saved.enabled : true,
        order: Number.isFinite(saved.order) ? saved.order : index,
      }
    })
    .sort((a, b) => a.order - b.order)
    .map((item, index) => ({ ...item, order: index }))
}

const editableWidgets = ref(createDefaultWidgets())

const today = new Date()
const todayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`
const todayLabel = `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日`
const todayDayLabel = `${today.getMonth() + 1}月${today.getDate()}日 ${dayNames[today.getDay()]}`

const finance = computed(() => store.financeOverview.value)
const orderedWidgets = computed(() => editableWidgets.value.filter(item => item.enabled).sort((a, b) => a.order - b.order))
const enabledWidgetCount = computed(() => orderedWidgets.value.length)
const visibleWidgetKeys = computed(() => new Set(orderedWidgets.value.map(item => item.key)))
const guidePills = computed(() => {
  const items = []
  if (visibleWidgetKeys.value.has('finance')) {
    items.push(
      { key: 'net', label: '净额', value: finance.value.display.netWorthEstimate, section: 'finance' },
      { key: 'liability', label: '待还', value: finance.value.display.liabilityTotal, section: 'finance' },
    )
  }
  if (visibleWidgetKeys.value.has('today')) {
    items.push({ key: 'today', label: '今日', value: finance.value.display.todayNet, section: 'today' })
  }
  if (visibleWidgetKeys.value.has('pending') && store.pendingSummary.value.total) {
    items.push({ key: 'pending', label: '待处理', value: `${store.pendingSummary.value.total}条`, section: 'pending' })
  }
  if (visibleWidgetKeys.value.has('daily')) {
    items.push({ key: 'daily', label: '明细', value: `${store.dailyCards.value.length}天`, section: 'daily' })
  }
  return items.slice(0, 4)
})

const selectedTrendItem = computed(() => {
  return finance.value.sevenDayExpenseTrend.find(item => item.dateKey === selectedTrendDateKey.value)
    || finance.value.todayTrend
    || finance.value.sevenDayExpenseTrend[finance.value.sevenDayExpenseTrend.length - 1]
})

const selectedTrendSummary = computed(() => {
  const item = selectedTrendItem.value
  if (!item) return `今日占比 ${finance.value.todayExpenseShare}%`
  const total = finance.value.sevenDayExpenseTrend.reduce((sum, trend) => sum + trend.amount, 0)
  const share = total > 0 ? Math.round(item.amount / total * 100) : 0
  return `${item.dateKey === todayKey ? '今日' : item.dateKey.slice(5)}占比 ${share}%`
})

const nearestLiabilityAmount = computed(() => {
  const amount = finance.value.nearestLiability?.amount
  return amount ? `¥${Number(amount).toFixed(0)}` : '--'
})

const nearestLiabilityDate = computed(() => {
  const item = finance.value.nearestLiability
  if (!item) return '无待还'
  if (item.dueDate) return item.dueDate.slice(5)
  if (item.billDay) return `每月${item.billDay}号`
  return '待补还款日'
})

onMounted(() => {
  if (typeof window === 'undefined') return
  try {
    const saved = JSON.parse(window.localStorage.getItem(HOME_WIDGET_STORAGE_KEY) || 'null')
    editableWidgets.value = normalizeWidgets(saved)
  } catch {
    editableWidgets.value = createDefaultWidgets()
  }
})

watch(editableWidgets, value => {
  if (typeof window === 'undefined') return
  window.localStorage.setItem(HOME_WIDGET_STORAGE_KEY, JSON.stringify(value))
}, { deep: true })

watch(finance, value => {
  if (!selectedTrendDateKey.value && value?.todayTrend?.dateKey) selectedTrendDateKey.value = value.todayTrend.dateKey
}, { immediate: true })

function resolveSectionRef(section) {
  const current = section === 'finance'
    ? financeSection.value
    : section === 'today'
      ? todaySection.value
      : section === 'pending'
        ? pendingSection.value
        : dailySection.value
  return Array.isArray(current) ? current[0] : current
}

function scrollToSection(section) {
  resolveSectionRef(section)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

function openNearestLiability() {
  const item = finance.value.nearestLiability
  const record = item?.raw
  if (record && item?.rawType === 'account') {
    store.openAccountDetail(record)
    return
  }
  if (record) {
    store.openRecordDetail('universal', record)
    return
  }
  store.openDomainPage('wallet')
}

function handleTrendClick(item) {
  if (selectedTrendDateKey.value === item.dateKey) {
    store.openDayDetail(item.dateKey, 'expense')
    return
  }
  selectedTrendDateKey.value = item.dateKey
}

function sportSummary(s) {
  const parts = []
  if (s.payload?.duration_minutes) parts.push(`${s.payload.duration_minutes}分钟`)
  if (s.payload?.distance_km) parts.push(`${s.payload.distance_km}km`)
  return parts.length ? parts.join(' · ') : s.summary
}

function sleepSummary(s) {
  const parts = []
  if (s.payload?.sleep_hours) parts.push(`${s.payload.sleep_hours}h`)
  if (s.payload?.quality_level) parts.push(s.payload.quality_level)
  return parts.length ? parts.join(' · ') : s.summary
}

function toggleWidget(key) {
  editableWidgets.value = editableWidgets.value.map(widget => (
    widget.key === key ? { ...widget, enabled: !widget.enabled } : widget
  ))
}

function moveWidget(key, delta) {
  const next = editableWidgets.value.slice().sort((a, b) => a.order - b.order)
  const index = next.findIndex(widget => widget.key === key)
  const targetIndex = index + delta
  if (index < 0 || targetIndex < 0 || targetIndex >= next.length) return
  const [moved] = next.splice(index, 1)
  next.splice(targetIndex, 0, moved)
  editableWidgets.value = next.map((widget, order) => ({ ...widget, order }))
}

function resetWidgets() {
  editableWidgets.value = createDefaultWidgets()
}
</script>

<style scoped>
.home-guide-strip {
  display: grid;
  gap: 8px;
  padding: 0 16px 10px;
}

.home-guide-pill {
  border: 1px solid rgba(26, 26, 24, 0.06);
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  padding: 9px 8px;
  font-family: var(--font);
  text-align: left;
  box-shadow: 0 6px 16px rgba(15, 23, 42, 0.035);
}

.home-guide-pill span {
  display: block;
  color: var(--text3);
  font-size: 11px;
  font-weight: 600;
}

.home-guide-pill strong {
  display: block;
  margin-top: 2px;
  color: #10100f;
  font-family: var(--font-num);
  font-size: 13px;
  font-weight: 900;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.home-layout-band {
  padding: 0 16px 12px;
}

.home-layout-summary {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 12px 14px;
  border-top: 1px solid rgba(26, 26, 24, 0.08);
  border-bottom: 1px solid rgba(26, 26, 24, 0.08);
}

.home-layout-kicker {
  color: #8b867d;
  font-size: 10px;
  font-weight: 800;
}

.home-layout-title {
  margin-top: 2px;
  color: #171614;
  font-size: 14px;
  font-weight: 800;
}

.home-layout-btn,
.home-layout-close,
.home-layout-reset-btn,
.home-layout-empty-btn {
  border: none;
  border-radius: 999px;
  font-family: var(--font);
  font-size: 12px;
  font-weight: 800;
}

.home-layout-btn,
.home-layout-close {
  padding: 8px 12px;
  background: #ece7de;
  color: #3f3a33;
}

.home-layout-empty {
  margin: 4px 16px 20px;
  padding: 18px;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.78);
  border: 1px solid rgba(26, 26, 24, 0.06);
}

.home-layout-empty-title {
  color: #11110f;
  font-size: 16px;
  font-weight: 900;
}

.home-layout-empty-desc {
  margin-top: 6px;
  color: var(--text2);
  font-size: 13px;
  line-height: 1.55;
}

.home-layout-empty-btn {
  margin-top: 14px;
  padding: 10px 14px;
  background: #1f2937;
  color: #fff;
}

.home-finance-section {
  scroll-margin-top: 12px;
}

.finance-card {
  margin: 0 16px 18px;
  border: 1px solid rgba(26, 26, 24, 0.06);
  border-radius: 26px;
  background:
    radial-gradient(circle at 92% 8%, rgba(180, 83, 9, 0.12), transparent 30%),
    linear-gradient(145deg, #ffffff 0%, #fffaf3 100%);
  box-shadow: 0 16px 36px rgba(33, 37, 41, 0.08);
  padding: 20px;
}

.finance-card-top {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: flex-start;
}

.finance-kicker {
  display: inline-flex;
  border-radius: 999px;
  background: rgba(45, 106, 79, 0.1);
  color: var(--primary);
  padding: 4px 9px;
  font-size: 11px;
  font-weight: 800;
}

.finance-main-label {
  margin-top: 13px;
  color: var(--text2);
  font-size: 13px;
  font-weight: 700;
}

.finance-main-value {
  margin-top: 2px;
  color: #0b0b0a;
  font-family: var(--font-num);
  font-size: 36px;
  font-weight: 900;
  letter-spacing: -0.04em;
}

.finance-badge {
  flex: 0 0 auto;
  border: none;
  border-radius: 999px;
  background: #f4e5db;
  color: #a54f1d;
  padding: 7px 11px;
  font-size: 12px;
  font-weight: 800;
  font-family: var(--font);
  cursor: pointer;
}

.finance-split-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  margin-top: 16px;
}

.finance-split-grid div {
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  border: 1px solid rgba(26, 26, 24, 0.05);
  padding: 11px 12px;
  cursor: pointer;
  transition: transform 0.16s ease, border-color 0.16s ease;
}

.finance-split-grid div:active,
.finance-due-row:active,
.finance-bar-col:active,
.finance-badge:active,
.home-layout-btn:active,
.home-layout-close:active,
.home-layout-reset-btn:active,
.home-layout-empty-btn:active {
  transform: scale(0.985);
}

.finance-split-grid span {
  display: block;
  color: var(--text3);
  font-size: 11px;
  font-weight: 700;
}

.finance-split-grid strong {
  display: block;
  margin-top: 3px;
  color: #111827;
  font-family: var(--font-num);
  font-size: 17px;
  font-weight: 900;
}

.finance-due-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: center;
  margin-top: 12px;
  border-radius: 18px;
  background: rgba(180, 83, 9, 0.08);
  padding: 13px 14px;
  cursor: pointer;
  transition: transform 0.16s ease;
}

.finance-due-label {
  color: #9a3412;
  font-size: 11px;
  font-weight: 800;
}

.finance-due-name {
  margin-top: 3px;
  color: #6c2d12;
  font-size: 15px;
  font-weight: 800;
}

.finance-due-value {
  text-align: right;
}

.finance-due-value strong {
  display: block;
  color: #6c2d12;
  font-family: var(--font-num);
  font-size: 18px;
  font-weight: 900;
}

.finance-due-value span {
  display: block;
  margin-top: 2px;
  color: #9a3412;
  font-size: 11px;
  font-weight: 700;
}

.finance-trend {
  margin-top: 16px;
  padding-top: 14px;
  border-top: 1px dashed #e8dfd5;
}

.finance-trend-head {
  display: flex;
  justify-content: space-between;
  color: var(--text2);
  font-size: 12px;
  font-weight: 700;
}

.finance-trend-head strong {
  color: #a54f1d;
}

.finance-bars {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  gap: 8px;
  align-items: end;
  margin-top: 14px;
}

.finance-bar-col {
  display: grid;
  gap: 5px;
  justify-items: center;
  cursor: pointer;
  transition: transform 0.16s ease;
}

.finance-bar-col.selected .finance-bar-amount,
.finance-bar-col.selected .finance-bar-label {
  color: #9a4d16;
  font-weight: 900;
}

.finance-bar-amount {
  color: var(--text2);
  font-family: var(--font-num);
  font-size: 11px;
  font-weight: 800;
}

.finance-bar-wrap {
  width: 100%;
  height: 74px;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}

.finance-bar {
  width: 22px;
  min-height: 5px;
  border-radius: 10px;
  background: linear-gradient(180deg, #ead9cf 0%, #f3e7df 100%);
}

.finance-bar.today {
  width: 28px;
  background: linear-gradient(180deg, #b45309 0%, #e4b79e 100%);
}

.finance-bar.selected {
  width: 30px;
  background: linear-gradient(180deg, #92400e 0%, #d69a74 100%);
  box-shadow: 0 8px 18px rgba(146, 64, 14, 0.22);
}

.finance-bar-label {
  color: #9b978f;
  font-size: 12px;
  font-weight: 800;
}

.finance-trend-hint {
  margin-top: 10px;
  color: #a56538;
  font-size: 12px;
  font-weight: 800;
  text-align: center;
}

.home-daily-header {
  align-items: flex-end;
  scroll-margin-top: 12px;
}

.home-daily-sub {
  margin-top: 3px;
  font-size: 12px;
  color: var(--text3);
  font-weight: 500;
}

.home-daily-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 12px;
  padding: 0 16px;
}

.home-daily-card {
  min-height: 0;
  border: 1px solid rgba(15, 23, 42, 0.06);
  border-radius: 22px;
  background: #fff;
  box-shadow: 0 10px 24px rgba(15, 23, 42, 0.055);
  padding: 18px 20px 18px;
  cursor: pointer;
  transition: transform 0.18s ease, box-shadow 0.18s ease;
}

.home-daily-card:active {
  transform: scale(0.985);
  box-shadow: 0 6px 16px rgba(15, 23, 42, 0.05);
}

.home-daily-card.empty {
  opacity: 0.72;
}

.home-daily-card-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.home-daily-date {
  font-family: var(--font-num);
  font-size: 24px;
  font-weight: 900;
  letter-spacing: -0.04em;
  color: #020617;
}

.home-daily-week {
  color: #8c877e;
  font-size: 15px;
  font-weight: 600;
}

.home-daily-divider {
  margin: 12px 0 14px;
  border-top: 1px dashed #e6e0d7;
}

.home-daily-lines {
  display: grid;
  gap: 9px;
}

.home-daily-line {
  display: grid;
  grid-template-columns: 12px minmax(52px, auto) minmax(0, 1fr);
  align-items: center;
  gap: 7px;
  min-width: 0;
}

.home-daily-dot {
  width: 8px;
  height: 8px;
  border-radius: 999px;
}

.home-daily-label {
  color: #4b5563;
  font-size: 15px;
  white-space: nowrap;
}

.home-daily-value {
  min-width: 0;
  justify-self: end;
  color: #020617;
  font-family: var(--font-num);
  font-size: 15px;
  font-weight: 900;
  text-align: right;
  overflow-wrap: anywhere;
  white-space: normal;
}

.home-daily-empty {
  color: var(--text3);
  font-size: 13px;
  line-height: 1.6;
}

.home-daily-more {
  display: block;
  width: calc(100% - 32px);
  margin: 14px 16px 0;
  border: 1px solid rgba(15, 23, 42, 0.08);
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  color: var(--text);
  padding: 13px 16px;
  font-size: 14px;
  font-weight: 700;
  font-family: var(--font);
}

.home-layout-overlay {
  position: fixed;
  inset: 0;
  z-index: 60;
  background: rgba(16, 16, 15, 0.28);
  display: flex;
  align-items: flex-end;
}

.home-layout-panel {
  width: 100%;
  max-width: 480px;
  margin: 0 auto;
  border-radius: 26px 26px 0 0;
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.98) 0%, rgba(250, 248, 243, 0.98) 100%);
  padding: 18px 16px calc(18px + env(safe-area-inset-bottom, 0px));
  box-shadow: 0 -18px 42px rgba(15, 23, 42, 0.16);
}

.home-layout-panel-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.home-layout-panel-title {
  margin-top: 2px;
  color: #13110f;
  font-size: 22px;
  font-weight: 900;
}

.home-layout-panel-list {
  display: grid;
  gap: 10px;
  margin-top: 16px;
}

.home-layout-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 14px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid rgba(26, 26, 24, 0.06);
}

.home-layout-item-main {
  min-width: 0;
}

.home-layout-item-title {
  color: #151412;
  font-size: 15px;
  font-weight: 850;
}

.home-layout-item-desc {
  margin-top: 4px;
  color: var(--text2);
  font-size: 12px;
  line-height: 1.45;
}

.home-layout-item-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: 0 0 auto;
}

.home-layout-switch {
  position: relative;
  display: inline-flex;
  width: 46px;
  height: 28px;
}

.home-layout-switch input {
  position: absolute;
  inset: 0;
  opacity: 0;
}

.home-layout-switch span {
  width: 100%;
  height: 100%;
  border-radius: 999px;
  background: #d9d4cb;
  position: relative;
  transition: background 0.2s ease;
}

.home-layout-switch span::after {
  content: '';
  position: absolute;
  top: 3px;
  left: 3px;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: #fff;
  box-shadow: 0 3px 8px rgba(15, 23, 42, 0.15);
  transition: transform 0.2s ease;
}

.home-layout-switch input:checked + span {
  background: #2d6a4f;
}

.home-layout-switch input:checked + span::after {
  transform: translateX(18px);
}

.home-layout-order-btn {
  width: 30px;
  height: 30px;
  border: none;
  border-radius: 10px;
  background: #ebe6de;
  color: #3a352f;
  font-size: 14px;
  font-weight: 900;
}

.home-layout-order-btn:disabled {
  opacity: 0.35;
}

.home-layout-panel-foot {
  margin-top: 14px;
  display: flex;
  justify-content: center;
}

.home-layout-reset-btn {
  padding: 10px 16px;
  background: #f2ede5;
  color: #4b4339;
}
</style>
