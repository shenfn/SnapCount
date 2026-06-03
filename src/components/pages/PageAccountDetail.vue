<template>
  <div class="page active account-detail-page">
    <div class="detail-header">
      <button class="detail-back" @click="store.goBack()">‹</button>
      <div class="detail-header-info">
        <div class="detail-header-title">{{ accountTitleText }}</div>
        <div class="domain-detail-header-sub">{{ accountSubtitle }}</div>
      </div>
      <button v-if="account" class="detail-more" @click="store.openAccountModalForEdit(account)">编</button>
    </div>

    <div v-if="account" class="account-detail-content">
      <section class="account-hero-card" :class="{ liability: isLiability }">
        <div>
          <div class="account-hero-kicker">{{ isLiability ? 'LIABILITY ACCOUNT' : 'ASSET ACCOUNT' }}</div>
          <div class="account-hero-balance">{{ formatAccountCurrency(account.currentBalance) }}</div>
          <div class="account-hero-caption">{{ isLiability ? '当前待还欠款' : '当前账户余额' }}</div>
        </div>
        <div class="account-hero-mark">{{ isLiability ? '还' : '钱' }}</div>
      </section>

      <section class="account-detail-grid">
        <div class="account-stat-card">
          <span>初始余额</span>
          <strong>{{ formatAccountCurrency(account.initialBalance) }}</strong>
        </div>
        <div class="account-stat-card">
          <span>有效流水净额</span>
          <strong :class="{ positive: activeNet >= 0, negative: activeNet < 0 }">{{ signedCurrency(activeNet) }}</strong>
        </div>
        <div class="account-stat-card">
          <span>账户类型</span>
          <strong>{{ typeLabel }}</strong>
        </div>
        <div class="account-stat-card">
          <span>有效流水数</span>
          <strong>{{ activeEntries.length }}</strong>
        </div>
      </section>

      <section class="account-entry-panel">
        <div class="account-entry-header">
          <div>
            <div class="wallet-account-section-title">最近账户流水</div>
            <div class="account-entry-sub">有效流水影响余额，作废流水仅保留审计痕迹</div>
          </div>
          <button class="wallet-snapshot-action-btn secondary" @click="store.refreshAccountDetail()">刷新</button>
        </div>

        <div v-if="store.accountEntriesLoading.value" class="wallet-account-empty">正在加载流水...</div>
        <div v-else-if="!activeEntries.length && !voidedEntries.length" class="wallet-account-empty">还没有账户流水</div>
        <button
          v-for="entry in activeEntries"
          v-else
          :key="entry.id"
          class="account-entry-row"
          @click="store.openAccountEntrySource(entry)"
        >
          <div class="account-entry-main">
            <div class="account-entry-title">
              {{ entryTypeLabel(entry) }}
            </div>
            <div class="account-entry-meta">
              {{ formatDateTimeLabel(entry.occurredAt) || '--' }}
              <span v-if="entry.note"> · {{ entry.note }}</span>
            </div>
            <div class="account-entry-source">{{ sourceLabel(entry) }}</div>
          </div>
          <div class="account-entry-amount" :class="{ positive: entry.direction === 'in', negative: entry.direction === 'out' }">
            {{ entry.direction === 'in' ? '+' : '-' }}{{ formatAccountCurrency(entry.amount) }}
          </div>
        </button>

        <button
          v-if="voidedEntries.length"
          class="account-voided-toggle"
          @click="showVoided = !showVoided"
        >
          {{ showVoided ? '收起' : '展开' }}已作废流水（{{ voidedEntries.length }}）
        </button>

        <button
          v-for="entry in showVoided ? voidedEntries : []"
          :key="entry.id"
          class="account-entry-row voided"
          @click="store.openAccountEntrySource(entry)"
        >
          <div class="account-entry-main">
            <div class="account-entry-title">
              {{ entryTypeLabel(entry) }}
              <span class="account-entry-voided">已作废</span>
            </div>
            <div class="account-entry-meta">
              {{ formatDateTimeLabel(entry.occurredAt) || '--' }}
              <span v-if="entry.note"> · {{ entry.note }}</span>
            </div>
            <div class="account-entry-source">{{ sourceLabel(entry) }}</div>
          </div>
          <div class="account-entry-amount" :class="{ positive: entry.direction === 'in', negative: entry.direction === 'out' }">
            {{ entry.direction === 'in' ? '+' : '-' }}{{ formatAccountCurrency(entry.amount) }}
          </div>
        </button>
      </section>
    </div>
  </div>
</template>

<script setup>
import { computed, inject, ref } from 'vue'
import { accountTitle, formatAccountCurrency, isLiabilityAccount } from '../../adapters/domain/accountAdapter'
import { formatDateTimeLabel } from '../../utils/helpers'

const store = inject('store')
const account = computed(() => store.selectedAccount.value)
const entries = computed(() => store.selectedAccountEntries.value || [])
const showVoided = ref(false)
const isLiability = computed(() => isLiabilityAccount(account.value))
const activeEntries = computed(() => entries.value.filter(entry => !entry.isVoided))
const voidedEntries = computed(() => entries.value.filter(entry => entry.isVoided))

const typeLabels = {
  cash: '现金',
  wallet_balance: '钱包余额',
  debit_card: '储蓄卡',
  credit_card: '信用卡',
  credit_line: '花呗/白条/月付',
  other: '其他',
}

const accountTitleText = computed(() => accountTitle(account.value))
const typeLabel = computed(() => typeLabels[account.value?.type] || account.value?.type || '--')
const accountSubtitle = computed(() => {
  if (!account.value) return ''
  const parts = [typeLabel.value]
  if (account.value.institution) parts.push(account.value.institution)
  if (account.value.isArchived) parts.push('已归档')
  return parts.join(' · ')
})
const activeNet = computed(() => entries.value.reduce((sum, entry) => {
  if (entry.isVoided || entry.entryType === 'snapshot_initialization') return sum
  return sum + (entry.direction === 'in' ? entry.amount : -entry.amount)
}, 0))

function signedCurrency(value) {
  return `${value >= 0 ? '+' : '-'}${formatAccountCurrency(Math.abs(value))}`
}

function entryTypeLabel(entry) {
  const labels = {
    expense: '支出',
    income: '收入',
    transfer: '转账',
    adjustment: '余额校准',
    opening_balance: '初始余额',
    snapshot_initialization: '快照初始化',
  }
  return labels[entry.entryType] || entry.entryType || '账户流水'
}

function sourceLabel(entry) {
  if (!entry.sourceTable) return '无关联来源'
  if (entry.sourceTable === 'transactions') return '关联支出记录'
  if (entry.sourceTable === 'income_records') return '关联收入记录'
  if (entry.sourceTable === 'data_records') return '关联钱包快照'
  return entry.sourceTable
}
</script>
