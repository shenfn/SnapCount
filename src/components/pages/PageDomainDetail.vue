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

    <DomainHero
      :name="domain.name"
      :icon="domain.icon"
      :description="domain.description"
      :color="domain.color"
      :record-count="domain.recordCount"
      kicker="DOMAIN WORKSPACE"
    />

    <div v-if="domain.id === 'wallet'" class="wallet-action-row">
      <button class="domain-wallet-add" @click="store.openAccountModalForCreate()">＋ 新建账户</button>
      <button class="domain-wallet-add subtle" @click="store.openUniversalModal('wallet')">👛 添加钱包快照</button>
    </div>

    <section v-if="domain.id === 'wallet'" class="wallet-account-panel">
      <div v-for="section in walletAccountSections" :key="section.key" class="wallet-account-section">
        <div class="wallet-account-section-title">{{ section.title }}</div>
        <div v-if="!section.items.length" class="wallet-account-empty">{{ section.empty }}</div>
        <div v-for="item in section.items" :key="item.id" class="wallet-account-card" @click="store.openAccountDetail(item.raw)">
          <div>
            <div class="wallet-account-name">{{ item.title }}<span v-if="item.raw?.isDefaultExpense" class="account-tag">默认支出</span><span v-if="item.raw?.isDefaultIncome" class="account-tag income">默认收入</span></div>
            <div class="wallet-account-subtitle">{{ item.subtitle }} · {{ item.snapshot }}</div>
          </div>
          <div class="wallet-account-value">{{ item.value }}</div>
        </div>
      </div>
    </section>

    <section v-if="domain.id === 'wallet' && unboundExpenses.length + unboundIncomes.length" class="wallet-account-panel">
      <div class="wallet-account-section-title">未绑定账户的记录（{{ unboundExpenses.length + unboundIncomes.length }}）</div>
      <div v-for="bill in unboundExpenses" :key="'ub-e-' + bill.id" class="wallet-account-card" @click="store.openExpenseEditModal(bill)">
        <div>
          <div class="wallet-account-name">{{ bill.name }}</div>
          <div class="wallet-account-subtitle">{{ bill.date }} · 支出 · 点击补绑账户</div>
        </div>
        <div class="wallet-account-value" style="color:#c62828">-¥{{ Number(bill.amount).toFixed(2) }}</div>
      </div>
      <div v-for="inc in unboundIncomes" :key="'ub-i-' + inc.id" class="wallet-account-card" @click="store.openIncomeEditModal(inc)">
        <div>
          <div class="wallet-account-name">{{ inc.source }}</div>
          <div class="wallet-account-subtitle">{{ inc.date }} · 收入 · 点击补绑账户</div>
        </div>
        <div class="wallet-account-value" style="color:#2e7d32">+¥{{ Number(inc.amount).toFixed(2) }}</div>
      </div>
    </section>

    <DomainMetricStrip
      :metrics="metricsAccented"
      :color="domain.color"
      :cols="4"
    />

    <DomainTrendPanel
      :values="trendValues"
      :labels="trendLabels"
      :today-index="todayIndex"
      :color="domain.color"
      :currency="trendIsCurrency"
      :duration="trendIsDuration"
      :unit="trendUnit"
      title="趋势"
      :scope="trendScope"
    />

    <DomainDistributionPanel
      :items="dimensionItems"
      :color="domain.color"
      title="维度分布"
      :top-label="dimensionItems.length ? `Top ${dimensionItems.length}` : ''"
      :empty-desc="'模板接入后会自动生成分类、来源或状态分布。'"
    />

    <DomainRecentRecordList
      :records="recentRecords"
      :color="domain.color"
      title="最近记录"
      :empty-icon="domain.icon"
      :empty-title="`${domain.name}暂无记录`"
      :empty-desc="'这个数据域已经预留好展示结构，等截图识别链路接入后会自动填充。'"
      @select="openRecord"
    />

    <section v-if="domain.id === 'wallet' && unlinkedWalletSnapshots.length" class="wallet-snapshot-action-panel">
      <div class="wallet-account-section-title">未关联快照</div>
      <div
        v-for="record in unlinkedWalletSnapshots"
        :key="record.id"
        class="wallet-snapshot-action-card"
      >
        <div class="wallet-snapshot-action-main">
          <div>
            <div class="wallet-account-name">{{ record.title || record.payload?.account_name || '钱包快照' }}</div>
            <div class="wallet-account-subtitle">截图金额 ¥{{ Number(record.payload?.snapshot_balance ?? record.payload?.amount ?? 0).toFixed(2) }}</div>
          </div>
          <div class="wallet-snapshot-action-buttons">
            <button class="wallet-snapshot-action-btn" @click="store.createAccountFromWalletSnapshot(record)">创建账户</button>
            <button class="wallet-snapshot-action-btn secondary" @click="toggleSnapshotAccountPicker(record.id)">
              {{ expandedSnapshotId === record.id ? '收起' : '关联已有' }}
            </button>
          </div>
        </div>
        <div v-if="expandedSnapshotId === record.id" class="wallet-snapshot-account-picker">
          <div v-if="!availableAccounts.length" class="wallet-snapshot-account-empty">还没有可关联账户，请先创建账户</div>
          <button
            v-for="account in availableAccounts"
            :key="account.id"
            class="wallet-snapshot-account-option"
            @click="linkSnapshotToExistingAccount(record, account.id)"
          >
            <span>
              <strong>{{ accountTitle(account) }}</strong>
              <small>{{ account.institution || account.type }}</small>
            </span>
            <em>{{ formatAccountCurrency(account.currentBalance) }}</em>
          </button>
        </div>
      </div>
    </section>

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
import { computed, inject, ref } from 'vue'
import {
  getDomainCapabilities,
  getDomainDimensionItems,
  getDomainMetricItems,
  getDomainRecentRecords,
  getDomainTrendItems,
  getDomainTrendScope,
} from '../../domains/detailAdapters'
import { getDomainSchema, getDomainDisplay } from '../../domains/registry'
import { isDurationFact } from '../../utils/format'
import DomainHero from '../domain/DomainHero.vue'
import DomainMetricStrip from '../domain/DomainMetricStrip.vue'
import DomainTrendPanel from '../domain/DomainTrendPanel.vue'
import DomainDistributionPanel from '../domain/DomainDistributionPanel.vue'
import DomainRecentRecordList from '../domain/DomainRecentRecordList.vue'
import { getAccountSections } from '../../adapters/domain/walletAdapter'
import { accountTitle, formatAccountCurrency } from '../../adapters/domain/accountAdapter'

const store = inject('store')
const expandedSnapshotId = ref(null)

const today = new Date()
const todayIndex = today.getDay() === 0 ? 6 : today.getDay() - 1

const domain = computed(() => {
  return store.domains.value.find(item => item.id === store.activeDomainId.value) || store.domains.value[0]
})

const metrics = computed(() => getDomainMetricItems(store, domain.value))
// 第一个指标作为强调卡（可一目了然看到主指标）
const metricsAccented = computed(() => metrics.value.map((item, idx) => ({
  ...item,
  accent: idx === 0,
})))

const trendScope = computed(() => getDomainTrendScope(domain.value, store))
const trendItemsRaw = computed(() => getDomainTrendItems(store, domain.value))
const trendValues = computed(() => trendItemsRaw.value.map(item => item.value || 0))
const trendLabels = computed(() => trendItemsRaw.value.map(item => item.label))
const trendIsCurrency = computed(() => ['expense', 'income', 'wallet'].includes(domain.value.id))
const primaryFact = computed(() => {
  const schema = getDomainSchema(domain.value.id)
  const display = getDomainDisplay(domain.value.id)
  const key = display?.primary_fact || schema?.facts?.[0]?.key
  return schema?.facts?.find(f => f.key === key) || null
})
const trendIsDuration = computed(() => isDurationFact(primaryFact.value))
const trendUnit = computed(() => {
  if (trendIsCurrency.value) return ''
  if (trendIsDuration.value) return '' // formatDuration 自带单位
  return primaryFact.value?.unit || '条'
})

const dimensionItems = computed(() => getDomainDimensionItems(store, domain.value))
const recentRecords = computed(() => getDomainRecentRecords(store, domain.value))
const capabilities = computed(() => getDomainCapabilities(domain.value))
const walletAccountSections = computed(() => domain.value.id === 'wallet' ? getAccountSections(store) : [])
const availableAccounts = computed(() => {
  return (store.accounts?.value || []).filter(account => !account.isArchived)
})
const unboundExpenses = computed(() => {
  return (store.bills?.value || [])
    .filter(b => b.status === 'done' && !b.accountId)
    .slice(0, 20)
})
const unboundIncomes = computed(() => {
  return (store.incomeRecords?.value || [])
    .filter(r => !r.accountId)
    .slice(0, 20)
})
const unlinkedWalletSnapshots = computed(() => {
  if (domain.value.id !== 'wallet') return []
  return store.dataRecords.value
    .filter(record => record.domainKey === 'wallet')
    .filter(record => !record.payload?.linked_account_id)
    .slice(0, 5)
})

function openRecord(item) {
  if (item.kind === 'expense') store.openRecordDetail('expense', item.raw)
  if (item.kind === 'income') store.openRecordDetail('income', item.raw)
  if (item.kind === 'universal') store.openRecordDetail('universal', item.raw)
}

function toggleSnapshotAccountPicker(recordId) {
  expandedSnapshotId.value = expandedSnapshotId.value === recordId ? null : recordId
}

async function linkSnapshotToExistingAccount(record, accountId) {
  await store.linkWalletSnapshotToAccount(record, accountId)
  expandedSnapshotId.value = null
}
</script>

<style scoped>
.domain-wallet-add {
  flex: 1;
  border: none;
  border-radius: 14px;
  padding: 13px 16px;
  background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%);
  color: #fff;
  font-size: 14px;
  font-weight: 700;
  box-shadow: 0 12px 24px rgba(124, 58, 237, 0.22);
  cursor: pointer;
}
.domain-wallet-add.subtle {
  background: linear-gradient(135deg, #f5f4ef 0%, #ebe9e2 100%);
  color: #1A1A18;
  box-shadow: 0 6px 14px rgba(0,0,0,0.06);
}
.wallet-action-row {
  display: flex;
  gap: 8px;
  padding: 0 16px 14px;
}
.account-tag {
  display: inline-block;
  margin-left: 6px;
  padding: 2px 6px;
  font-size: 10px;
  background: #1565C0;
  color: #fff;
  border-radius: 6px;
  vertical-align: middle;
}
.account-tag.income { background: #2e7d32; }
:deep(.wallet-account-card) { cursor: pointer; }
</style>
