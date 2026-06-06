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

function openRecord(item) {
  if (item.kind === 'expense') store.openExpenseEditModal(item.raw)
  if (item.kind === 'income') store.openIncomeEditModal(item.raw)
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
