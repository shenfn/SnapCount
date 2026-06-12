<template>
  <div class="page active unbound-page">
    <div class="detail-header">
      <button class="detail-back" @click="store.goBack()">‹</button>
      <div class="detail-header-info">
        <div class="detail-header-title">未绑定账户</div>
        <div class="domain-detail-header-sub">{{ store.monthLabel.value }} · 补全真实账户来源</div>
      </div>
      <button class="detail-more" @click="store.loadUnboundRecords()">刷</button>
    </div>

    <section class="unbound-hero">
      <div>
        <div class="account-hero-kicker">账户覆盖率</div>
        <div class="unbound-hero-count">{{ visibleRecords.length }}</div>
        <div class="account-hero-caption">当前筛选下等待补全来源的记录</div>
      </div>
      <div class="unbound-hero-side">
        <span>支出 {{ expenses.length }}</span>
        <span>收入 {{ incomes.length }}</span>
      </div>
    </section>

    <div class="unbound-filter-row">
      <button
        v-for="item in filters"
        :key="item.value"
        class="unbound-filter-chip"
        :class="{ active: filter === item.value }"
        @click="filter = item.value"
      >
        {{ item.label }}
      </button>
    </div>

    <section v-if="batchCandidates.length" class="unbound-batch-panel">
      <div class="unbound-batch-head">
        <div>
          <div class="unbound-batch-title">可批量补绑 {{ batchCandidates.length }} 条</div>
          <div class="unbound-batch-desc">先按推荐账户预览，确认无误后再批量生成账户流水。</div>
        </div>
        <button
          class="unbound-batch-btn"
          @click="openPreview"
        >
          查看预览
        </button>
      </div>
    </section>

    <div v-if="previewOpen" class="unbound-preview-overlay" @click.self="previewOpen = false">
      <section class="unbound-preview-sheet">
        <div class="unbound-preview-head">
          <div>
            <div class="unbound-preview-kicker">BATCH REVIEW</div>
            <div class="unbound-preview-title">批量补绑预览</div>
            <div class="unbound-preview-desc">
              <label class="unbound-select-all-label" @click.stop>
                <input
                  type="checkbox"
                  :checked="selectedIds.size === batchCandidates.length && batchCandidates.length > 0"
                  :indeterminate="selectedIds.size > 0 && selectedIds.size < batchCandidates.length"
                  @change="toggleSelectAll"
                />
                全选 {{ selectedIds.size }}/{{ batchCandidates.length }} 条 · {{ batchGroups.length }} 个推荐账户
              </label>
            </div>
          </div>
          <button class="unbound-preview-close" @click="previewOpen = false">关闭</button>
        </div>
        <div class="unbound-batch-preview">
        <div
          v-for="group in batchGroups"
          :key="group.account.id"
          class="unbound-batch-group"
        >
          <div class="unbound-batch-group-head">
            <button class="unbound-batch-group-toggle" @click="toggleGroup(group.account.id)">
              <div>
                <strong>{{ group.account.name }}</strong>
                <span>{{ group.items.length }} 条 · 合计 ¥{{ group.total.toFixed(2) }}</span>
              </div>
              <em>{{ expandedGroups.has(group.account.id) ? '收起' : '展开' }}</em>
            </button>
            <label class="unbound-group-check" @click.stop>
              <input
                type="checkbox"
                :checked="isGroupAllSelected(group.account.id)"
                :indeterminate="isGroupSomeSelected(group.account.id)"
                @change="toggleGroupSelect(group.account.id)"
              />
            </label>
          </div>
          <div v-if="expandedGroups.has(group.account.id)" class="unbound-batch-items">
            <div
              v-for="item in group.items"
              :key="item.kind + '-' + item.record.id"
              class="unbound-batch-item"
            >
              <label class="unbound-item-check" @click.stop>
                <input
                  type="checkbox"
                  :checked="selectedIds.has(itemKey(item))"
                  @change="toggleSelect(itemKey(item))"
                />
              </label>
              <button class="unbound-item-content" @click="openBatchRecord(item)">
                <div>
                  <span>{{ item.kind === 'expense' ? '支出' : '收入' }}</span>
                  <strong>{{ item.kind === 'expense' ? (item.record.name || '未命名支出') : (item.record.source || '未命名收入') }}</strong>
                  <small>{{ item.record.date || item.record.dateRaw }} · {{ item.recommendation.reason }} · 点开看截图</small>
                </div>
                <em :class="item.kind">{{ item.kind === 'income' ? '+' : '-' }}¥{{ Number(item.record.amount || 0).toFixed(2) }}</em>
              </button>
            </div>
          </div>
        </div>
        <button
          class="unbound-batch-confirm"
          :disabled="store.isActionPending('batchBindUnbound') || selectedIds.size === 0"
          @click="confirmBatchBind"
        >
          {{ store.isActionPending('batchBindUnbound') ? '处理中' : `确认补绑已选 ${selectedIds.size} 条` }}
        </button>
      </div>
      </section>
    </div>

    <section class="unbound-list-panel">
      <div v-if="store.unboundRecordsLoading.value" class="wallet-account-empty">正在加载未绑定记录...</div>
      <div v-else-if="!visibleRecords.length" class="wallet-account-empty">这个月份已经没有待补绑记录</div>
      <div
        v-for="item in visibleRecords"
        v-else
        :key="item.kind + '-' + item.id"
        class="unbound-record-row"
        role="button"
        tabindex="0"
        @click="openRecord(item)"
        @keydown.enter="openRecord(item)"
      >
        <div class="unbound-record-main">
          <div class="unbound-record-title">{{ item.title }}</div>
          <div class="unbound-record-meta">{{ item.date }} · {{ item.kind === 'expense' ? '支出' : '收入' }}</div>
          <div v-if="item.explanation.account" class="unbound-record-recommendation">
            <span class="unbound-recommendation-dot"></span>
            <span>{{ item.explanation.account.name }}</span>
            <em>{{ item.explanation.reason }}</em>
          </div>
        </div>
        <div class="unbound-record-side">
          <div class="unbound-record-amount" :class="item.kind">
            {{ item.kind === 'income' ? '+' : '-' }}¥{{ Number(item.amount).toFixed(2) }}
          </div>
          <button
            class="unbound-bind-btn"
            :disabled="bindingKey === item.kind + '-' + item.id"
            @click.stop="bindRecommended(item)"
          >
            {{ bindingKey === item.kind + '-' + item.id ? '绑定中' : bindButtonLabel(item) }}
          </button>
        </div>
      </div>
    </section>
  </div>
</template>

<script setup>
import { computed, inject, ref } from 'vue'

const store = inject('store')
const filters = [
  { value: 'all', label: '全部' },
  { value: 'expense', label: '支出' },
  { value: 'income', label: '收入' },
]

const filter = computed({
  get: () => store.unboundRecordFilter.value,
  set: value => { store.unboundRecordFilter.value = value },
})
const bindingKey = ref('')
const previewOpen = ref(false)
const expandedGroups = ref(new Set())
const selectedIds = ref(new Set())

const expenses = computed(() => store.unboundRecords.value.expenses || [])
const incomes = computed(() => store.unboundRecords.value.incomes || [])
const visibleRecords = computed(() => {
  const expenseItems = expenses.value.map(item => ({
    kind: 'expense',
    id: item.id,
    title: item.name || '未命名支出',
    date: item.date,
    amount: item.amount,
    explanation: store.accountBindingExplanation('expense', item),
    raw: item,
  }))
  const incomeItems = incomes.value.map(item => ({
    kind: 'income',
    id: item.id,
    title: item.source || '未命名收入',
    date: item.date,
    amount: item.amount,
    explanation: store.accountBindingExplanation('income', item),
    raw: item,
  }))
  if (filter.value === 'expense') return expenseItems
  if (filter.value === 'income') return incomeItems
  return [...expenseItems, ...incomeItems].sort((a, b) => String(b.date).localeCompare(String(a.date)))
})
const batchCandidates = computed(() => store.recommendedUnboundRecords(filter.value))
const batchGroups = computed(() => {
  const map = new Map()
  batchCandidates.value.forEach(item => {
    const account = item.recommendation.account
    if (!account) return
    const prev = map.get(account.id) || { account, items: [], total: 0 }
    prev.items.push(item)
    prev.total += Number(item.record.amount || 0)
    map.set(account.id, prev)
  })
  return Array.from(map.values()).sort((a, b) => b.items.length - a.items.length || b.total - a.total)
})

function itemKey(item) {
  return `${item.kind}-${item.record.id}`
}

const selectedCandidates = computed(() =>
  batchCandidates.value.filter(item => selectedIds.value.has(itemKey(item)))
)

function isGroupAllSelected(accountId) {
  const group = batchGroups.value.find(g => g.account.id === accountId)
  if (!group) return false
  return group.items.every(item => selectedIds.value.has(itemKey(item)))
}

function isGroupSomeSelected(accountId) {
  const group = batchGroups.value.find(g => g.account.id === accountId)
  if (!group) return false
  const selected = group.items.filter(item => selectedIds.value.has(itemKey(item))).length
  return selected > 0 && selected < group.items.length
}

function openRecord(item) {
  if (item.kind === 'expense') store.openExpenseEditModal(item.raw)
  if (item.kind === 'income') store.openIncomeEditModal(item.raw)
}

function openBatchRecord(item) {
  previewOpen.value = false
  if (item.kind === 'expense') store.openExpenseEditModal(item.record)
  if (item.kind === 'income') store.openIncomeEditModal(item.record)
}

function toggleGroup(accountId) {
  const next = new Set(expandedGroups.value)
  if (next.has(accountId)) next.delete(accountId)
  else next.add(accountId)
  expandedGroups.value = next
}

function ensurePreviewExpanded() {
  if (!expandedGroups.value.size) {
    expandedGroups.value = new Set(batchGroups.value.map(group => group.account.id))
  }
}

function openPreview() {
  selectedIds.value = new Set(batchCandidates.value.map(itemKey))
  previewOpen.value = true
  ensurePreviewExpanded()
}

function toggleSelect(key) {
  const next = new Set(selectedIds.value)
  if (next.has(key)) next.delete(key)
  else next.add(key)
  selectedIds.value = next
}

function toggleGroupSelect(accountId) {
  const group = batchGroups.value.find(g => g.account.id === accountId)
  if (!group) return
  const next = new Set(selectedIds.value)
  const allSelected = group.items.every(item => next.has(itemKey(item)))
  group.items.forEach(item => {
    const key = itemKey(item)
    if (allSelected) next.delete(key)
    else next.add(key)
  })
  selectedIds.value = next
}

function toggleSelectAll() {
  if (selectedIds.value.size === batchCandidates.value.length) {
    selectedIds.value = new Set()
  } else {
    selectedIds.value = new Set(batchCandidates.value.map(itemKey))
  }
}

async function confirmBatchBind() {
  const ok = await store.batchBindRecommendedUnboundRecords(filter.value, selectedCandidates.value)
  if (ok) previewOpen.value = false
}

function bindButtonLabel(item) {
  if (!item.explanation?.account?.name) return '手动选择'
  return `绑定${item.explanation.account.name}`
}

async function bindRecommended(item) {
  bindingKey.value = `${item.kind}-${item.id}`
  try {
    await store.bindRecordToRecommendedAccount(item.kind, item.raw)
  } finally {
    bindingKey.value = ''
  }
}
</script>
