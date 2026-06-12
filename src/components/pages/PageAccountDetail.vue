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
          <div class="account-hero-caption">{{ heroCaption }}</div>
          <div v-if="isLiability" class="account-hero-subline">
            <span>{{ cycleAmountLabel }}</span>
            <span>{{ cycleScopeLabel }}</span>
          </div>
        </div>
        <div class="account-hero-mark">{{ isLiability ? '还' : '钱' }}</div>
      </section>

      <section v-if="sourceSnapshot" class="account-source-card">
        <div class="account-source-main">
          <div class="wallet-account-section-title">来源快照</div>
          <div class="account-source-title">{{ sourceSnapshot.title }}</div>
          <div class="account-source-meta">
            {{ formatDateTimeLabel(sourceSnapshot.occurredAt) || '时间未知' }}
            <span v-if="sourceSnapshot.payload?.due_date"> · {{ sourceSnapshot.payload.due_date }} 还款</span>
          </div>
          <div class="account-source-summary">{{ sourceSnapshot.summary || sourceSnapshotHint }}</div>
        </div>
        <button
          v-if="sourceSnapshot.imageUrl"
          class="account-source-thumb"
          @click="store.openImgFull(sourceSnapshot.imageUrl)"
        >
          <img :src="sourceSnapshot.imageUrl" alt="来源快照截图" />
        </button>
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

      <section v-if="isLiability" class="account-repayment-panel">
        <div class="wallet-account-section-title">还款计划</div>
        <div class="account-repayment-status" :class="repaymentStatus.tone">
          <strong>{{ repaymentStatus.label }}</strong>
          <span>{{ repaymentStatus.desc }}</span>
        </div>
        <div class="account-repayment-list">
          <div v-if="activeCycle" class="account-repayment-row highlight">
            <span>本期状态</span>
            <strong>{{ cycleStatusLabel(activeCycle) }}</strong>
          </div>
          <div v-if="activeCycle" class="account-repayment-row">
            <span>本期应还</span>
            <strong>{{ formatAccountCurrency(cycleStatementAmount(activeCycle)) }}</strong>
          </div>
          <div v-if="activeCycle" class="account-repayment-row">
            <span>已还 / 剩余</span>
            <strong>{{ formatAccountCurrency(activeCycle.paidAmount) }} / {{ formatAccountCurrency(cycleRemainingAmount(activeCycle)) }}</strong>
          </div>
          <div class="account-repayment-row">
            <span>周期结束日</span>
            <strong>{{ account.billDay ? `每月${account.billDay}日` : '未设置' }}</strong>
          </div>
          <div class="account-repayment-row">
            <span>还款日</span>
            <strong>{{ account.paymentDueDay ? `每月${account.paymentDueDay}日` : '未设置' }}</strong>
          </div>
          <div class="account-repayment-row">
            <span>最近待还</span>
            <strong>{{ nextDueDateLabel }}</strong>
          </div>
          <div class="account-repayment-row">
            <span>自动扣款</span>
            <strong>{{ autoDebitLabel }}</strong>
          </div>
          <div class="account-repayment-row">
            <span>自动确认</span>
            <strong>{{ account.autoConfirmRepayment ? '高置信度截图可自动确认' : '需手动确认' }}</strong>
          </div>
        </div>
        <div v-if="canConfirmActiveCycle" class="account-repayment-actions">
          <div class="account-repayment-mode">
            <button
              class="account-repayment-mode-btn"
              :class="{ active: repaymentMode === 'full' }"
              @click="repaymentMode = 'full'"
            >
              还清本期
            </button>
            <button
              class="account-repayment-mode-btn"
              :class="{ active: repaymentMode === 'partial' }"
              @click="repaymentMode = 'partial'"
            >
              记录部分还款
            </button>
          </div>
          <label v-if="repaymentMode === 'partial'" class="account-repayment-input">
            <span>本次还款金额</span>
            <input
              v-model="partialRepaymentAmount"
              inputmode="decimal"
              placeholder="例如 50.00"
            />
          </label>
          <button
            class="account-repayment-primary"
            :disabled="isRepaymentSubmitting || !repaymentConfirmAmount"
            @click="confirmActiveCyclePaid"
          >
            {{ repaymentPrimaryText }}
          </button>
          <div class="account-repayment-hint">
            {{ repaymentConfirmSummary }}
            <template v-if="repaymentDebitLabel">同步从「{{ repaymentDebitLabel }}」扣款。</template>
            <template v-else>未设置自动扣款账户，仅减少当前欠款。</template>
          </div>
          <div class="account-repayment-preview">
            <div>
              <span>负债账户</span>
              <strong>{{ accountTitleText }} -{{ formatAccountCurrency(repaymentLiabilityDecrease) }}</strong>
            </div>
            <div v-if="repaymentDebitLabel">
              <span>扣款账户</span>
              <strong>{{ repaymentDebitLabel }} -{{ formatAccountCurrency(repaymentConfirmAmount) }}</strong>
            </div>
            <div v-if="repaymentOverpaymentAmount > 0">
              <span>待确认溢缴</span>
              <strong>{{ formatAccountCurrency(repaymentOverpaymentAmount) }}</strong>
            </div>
          </div>
        </div>
      </section>

      <section v-if="isLiability && activeCycle" class="account-statement-panel">
        <div class="account-statement-head">
          <div>
            <div class="wallet-account-section-title">账单解释</div>
            <div class="account-statement-sub">{{ statementExplainText }}</div>
          </div>
          <button
            v-if="statementEvidence"
            class="account-statement-evidence-btn"
            @click="openStatementEvidence"
          >
            看截图
          </button>
        </div>
        <div class="account-statement-grid">
          <div>
            <span>账单来源</span>
            <strong>{{ cycleSourceLabel(activeCycle) }}</strong>
          </div>
          <div>
            <span>账单周期</span>
            <strong>{{ statementPeriodLabel }}</strong>
          </div>
          <div>
            <span>还款日</span>
            <strong>{{ activeCycle.dueDate || '待补' }}</strong>
          </div>
          <div>
            <span>识别置信度</span>
            <strong>{{ cycleConfidenceLabel(activeCycle) }}</strong>
          </div>
        </div>
        <div class="account-statement-flow">
          <div class="account-statement-flow-title">账单活动流</div>
          <button
            v-for="item in statementActivityItems"
            :key="item.key"
            class="account-activity-row"
            :class="item.tone"
            @click="openActivityItem(item)"
          >
            <div class="account-activity-dot"></div>
            <div class="account-activity-main">
              <div class="account-activity-title">{{ item.title }}</div>
              <div class="account-activity-meta">{{ item.meta }}</div>
              <div v-if="item.note" class="account-activity-note">{{ item.note }}</div>
            </div>
            <div class="account-activity-side">{{ item.amount }}</div>
          </button>
        </div>
      </section>

      <section v-if="isLiability && activePayments.length" class="account-payment-panel">
        <div class="wallet-account-section-title">最近还款记录</div>
        <div class="account-payment-list">
          <div v-for="payment in activePayments" :key="payment.id" class="account-payment-row">
            <div>
              <div class="account-payment-title">{{ paymentSourceLabel(payment) }}</div>
              <div class="account-payment-meta">
                {{ formatDateTimeLabel(payment.paidAt) || '--' }}
                <span v-if="payment.note"> · {{ payment.note }}</span>
                <span v-if="payment.overpaymentAmount > 0"> · 待确认溢缴 {{ formatAccountCurrency(payment.overpaymentAmount) }}</span>
              </div>
            </div>
            <div class="account-payment-side">
              <strong>{{ formatAccountCurrency(payment.amount) }}</strong>
              <button
                v-if="payment.status === 'confirmed'"
                class="account-payment-revoke"
                :disabled="store.isActionPending(`liability-payment:${payment.id}`)"
                @click="revokePayment(payment)"
              >
                撤销
              </button>
            </div>
          </div>
        </div>
        <button
          v-if="voidedPayments.length"
          class="account-voided-toggle"
          @click="showVoidedPayments = !showVoidedPayments"
        >
          {{ showVoidedPayments ? '收起' : '展开' }}已作废还款（{{ voidedPayments.length }}）
        </button>
        <div v-if="showVoidedPayments" class="account-payment-list voided">
          <div v-for="payment in voidedPayments" :key="payment.id" class="account-payment-row voided">
            <div>
              <div class="account-payment-title">{{ paymentSourceLabel(payment) }}</div>
              <div class="account-payment-meta">
                {{ formatDateTimeLabel(payment.paidAt) || '--' }}
                <span v-if="payment.note"> · {{ payment.note }}</span>
              </div>
            </div>
            <div class="account-payment-side">
              <strong>{{ formatAccountCurrency(payment.amount) }}</strong>
            </div>
          </div>
        </div>
      </section>

      <section v-else-if="isLiability && voidedPayments.length" class="account-payment-panel">
        <button
          class="account-voided-toggle"
          @click="showVoidedPayments = !showVoidedPayments"
        >
          {{ showVoidedPayments ? '收起' : '展开' }}已作废还款（{{ voidedPayments.length }}）
        </button>
        <div v-if="showVoidedPayments" class="account-payment-list voided">
          <div v-for="payment in voidedPayments" :key="payment.id" class="account-payment-row voided">
            <div>
              <div class="account-payment-title">{{ paymentSourceLabel(payment) }}</div>
              <div class="account-payment-meta">
                {{ formatDateTimeLabel(payment.paidAt) || '--' }}
                <span v-if="payment.note"> · {{ payment.note }}</span>
              </div>
            </div>
            <div class="account-payment-side">
              <strong>{{ formatAccountCurrency(payment.amount) }}</strong>
            </div>
          </div>
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
const payments = computed(() => store.selectedAccountPayments?.value || [])
const sourceSnapshot = computed(() => store.selectedAccountSourceSnapshot?.value || null)
const showVoided = ref(false)
const showVoidedPayments = ref(false)
const repaymentMode = ref('full')
const partialRepaymentAmount = ref('')
const isLiability = computed(() => isLiabilityAccount(account.value))
const activeEntries = computed(() => entries.value.filter(entry => !entry.isVoided))
const voidedEntries = computed(() => entries.value.filter(entry => entry.isVoided))
const todayKey = localDateKey(new Date())
const selectedMonthKey = computed(() => `${store.currentYear.value}-${String(store.currentMonth.value).padStart(2, '0')}`)
const currentRealMonthKey = localDateKey(new Date()).slice(0, 7)
const selectedIsCurrentMonth = computed(() => selectedMonthKey.value === currentRealMonthKey)
const accountCycles = computed(() => {
  const accountId = account.value?.id
  if (!accountId) return []
  return (store.repaymentCycles?.value || [])
    .filter(cycle => cycle.accountId === accountId)
    .sort((a, b) => String(a.dueDate || '9999-99-99').localeCompare(String(b.dueDate || '9999-99-99')))
})
const selectedMonthCycle = computed(() => {
  return accountCycles.value.find(cycle => cycle.cycleMonth === selectedMonthKey.value) || null
})
const nextActionableCycle = computed(() => {
  const openStatuses = new Set(['pending', 'due_today', 'overdue_unconfirmed', 'partial_paid', 'carried_over'])
  const upcoming = accountCycles.value
    .filter(cycle => openStatuses.has(cycle.status))
    .filter(cycle => {
      if (cycle.status === 'historical_unconfirmed') return false
      if (cycle.status === 'partial_paid' || cycle.status === 'carried_over') return true
      if (!cycle.dueDate) return false
      return cycle.dueDate >= todayKey
    })
  return upcoming[0] || null
})
const activeCycle = computed(() => selectedMonthCycle.value || null)
const cycleIsSelectedMonth = computed(() => !!activeCycle.value && activeCycle.value.cycleMonth === selectedMonthKey.value)
const canConfirmActiveCycle = computed(() => {
  if (!activeCycle.value) return false
  return ['pending', 'due_today', 'overdue_unconfirmed', 'partial_paid', 'carried_over'].includes(activeCycle.value.status)
})

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
const heroCaption = computed(() => {
  if (!isLiability.value) return '当前账户余额'
  const currentTotalHint = selectedIsCurrentMonth.value
    ? '当前总欠款估算'
    : `当前总欠款估算，非${selectedMonthKey.value}历史余额`
  if (!activeCycle.value) return `${currentTotalHint}；${selectedMonthKey.value} 暂无账单`
  return `${currentTotalHint}；${cycleScopeLabel.value}${cycleRemainingText.value}`
})
const cycleRemainingText = computed(() => {
  if (!activeCycle.value) return ''
  const remaining = cycleRemainingAmount(activeCycle.value)
  if (activeCycle.value.status === 'paid') return '已还清'
  return `剩余 ${formatAccountCurrency(remaining)}`
})
const cycleAmountLabel = computed(() => {
  if (!activeCycle.value) return `${selectedMonthKey.value} 无账单`
  const prefix = cycleIsSelectedMonth.value ? '所选月份' : '账单'
  if (activeCycle.value.status === 'paid') return `${prefix} 已还清`
  return `${prefix}待还 ${formatAccountCurrency(cycleRemainingAmount(activeCycle.value))}`
})
const cycleScopeLabel = computed(() => {
  if (!activeCycle.value) return `${selectedMonthKey.value} 账单`
  return `${activeCycle.value.cycleMonth} 账单`
})
const sourceSnapshotHint = computed(() => {
  if (!sourceSnapshot.value) return ''
  const amount = sourceSnapshot.value.snapshotBalance == null ? null : formatAccountCurrency(sourceSnapshot.value.snapshotBalance)
  if (amount) return `识别快照余额 ${amount}`
  return '这张截图是当前账户的创建或校准来源'
})
const activeNet = computed(() => entries.value.reduce((sum, entry) => {
  if (entry.isVoided || entry.entryType === 'snapshot_initialization') return sum
  return sum + (entry.direction === 'in' ? entry.amount : -entry.amount)
}, 0))
const nextDueDate = computed(() => normalizeDueDate(account.value?.paymentDueDay, todayKey))
const nextDueDateLabel = computed(() => {
  if (nextActionableCycle.value?.dueDate) {
    const suffix = nextActionableCycle.value.status === 'paid' ? '已还清' : daysUntilLabel(nextActionableCycle.value.dueDate)
    return `${nextActionableCycle.value.dueDate.slice(5)}（${suffix}）`
  }
  return nextDueDate.value ? `规则：${nextDueDate.value.slice(5)}（${daysUntilLabel(nextDueDate.value)}）` : '待补还款日'
})
const repaymentConfirmAmount = computed(() => {
  if (!activeCycle.value) return 0
  if (repaymentMode.value === 'partial') {
    const amount = Number(String(partialRepaymentAmount.value || '').replace(',', '.'))
    if (!Number.isFinite(amount) || amount <= 0) return 0
    return Math.round(amount * 100) / 100
  }
  const remainingAmount = cycleRemainingAmount(activeCycle.value)
  if (remainingAmount > 0) return remainingAmount
  return cycleStatementAmount(activeCycle.value) || Number(account.value?.currentBalance || 0)
})
const repaymentStatusToSubmit = computed(() => {
  if (!activeCycle.value) return 'paid'
  if (repaymentMode.value === 'full') return 'paid'
  const amount = Number(repaymentConfirmAmount.value || 0)
  const remaining = cycleRemainingAmount(activeCycle.value)
  if (remaining > 0 && amount >= remaining) return 'paid'
  if (activeCycle.value.minPaymentAmount && amount >= Number(activeCycle.value.minPaymentAmount)) return 'minimum_paid'
  return 'partial_paid'
})
const repaymentOverpaymentAmount = computed(() => {
  const amount = Number(repaymentConfirmAmount.value || 0)
  const currentBalance = Number(account.value?.currentBalance || 0)
  if (!Number.isFinite(amount) || !Number.isFinite(currentBalance)) return 0
  return Math.max(amount - currentBalance, 0)
})
const repaymentLiabilityDecrease = computed(() => {
  return Math.max(Number(repaymentConfirmAmount.value || 0) - repaymentOverpaymentAmount.value, 0)
})
const repaymentConfirmSummary = computed(() => {
  if (!activeCycle.value) return ''
  const amount = formatAccountCurrency(repaymentConfirmAmount.value)
  const remaining = cycleRemainingAmount(activeCycle.value)
  const currentBalance = Number(account.value?.currentBalance || 0)
  if (repaymentOverpaymentAmount.value > 0) {
    return `会将 ${amount} 记为还款，其中 ${formatAccountCurrency(repaymentOverpaymentAmount.value)} 超过当前总欠款，会标记为待确认溢缴；`
  }
  if (repaymentConfirmAmount.value > remaining && repaymentConfirmAmount.value <= currentBalance) {
    return `会将 ${amount} 记为还款，超出本期剩余的部分视为提前还未出账欠款；`
  }
  return `会将 ${amount} 记为本期还款；`
})
const repaymentDebitAccount = computed(() => {
  const id = activeCycle.value?.autoDebitAccountId || account.value?.autoDebitAccountId
  if (!id) return null
  return (store.accounts?.value || []).find(item => item.id === id) || null
})
const repaymentDebitLabel = computed(() => repaymentDebitAccount.value ? accountTitle(repaymentDebitAccount.value) : '')
const isRepaymentSubmitting = computed(() => activeCycle.value ? store.isActionPending(`repayment-cycle:${activeCycle.value.id}`) : false)
const repaymentPrimaryText = computed(() => {
  if (isRepaymentSubmitting.value) return '正在确认...'
  return repaymentMode.value === 'partial' ? '记录本次还款' : '确认本期已还清'
})
const activePayments = computed(() => payments.value.filter(payment => payment.status !== 'voided'))
const voidedPayments = computed(() => payments.value.filter(payment => payment.status === 'voided'))
const statementEvidence = computed(() => {
  const evidenceId = activeCycle.value?.evidenceRecordId
  if (evidenceId) {
    const record = (store.dataRecords?.value || []).find(item => item.id === evidenceId)
    if (record) return record
  }
  if (sourceSnapshot.value && sourceSnapshot.value.id === evidenceId) return sourceSnapshot.value
  return null
})
const statementPeriodLabel = computed(() => {
  if (!activeCycle.value) return '暂无周期'
  if (activeCycle.value.statementStartDate && activeCycle.value.statementEndDate) {
    return `${activeCycle.value.statementStartDate.slice(5)} 至 ${activeCycle.value.statementEndDate.slice(5)}`
  }
  return activeCycle.value.cycleMonth ? `${activeCycle.value.cycleMonth} 账单` : '未识别周期'
})
const statementExplainText = computed(() => {
  if (!activeCycle.value) return ''
  const source = cycleSourceLabel(activeCycle.value)
  const amount = formatAccountCurrency(cycleStatementAmount(activeCycle.value))
  const due = activeCycle.value.dueDate ? `，还款日 ${activeCycle.value.dueDate.slice(5)}` : ''
  return `${source}确认本期应还 ${amount}${due}`
})
const statementActivityItems = computed(() => {
  if (!activeCycle.value) return []
  const cycle = activeCycle.value
  const items = [{
    key: `cycle:${cycle.id}`,
    kind: 'cycle',
    at: cycle.createdAt || cycle.updatedAt || '',
    title: `${cycleSourceLabel(cycle)}生成账单`,
    meta: [cycle.cycleMonth, statementPeriodLabel.value, cycle.dueDate ? `${cycle.dueDate.slice(5)}还款` : '待补还款日'].filter(Boolean).join(' · '),
    note: cycle.note || '',
    amount: formatAccountCurrency(cycleStatementAmount(cycle)),
    tone: 'statement',
  }]

  payments.value
    .filter(payment => payment.statementId === cycle.id)
    .forEach(payment => {
      items.push({
        key: `payment:${payment.id}`,
        kind: 'payment',
        payment,
        at: payment.paidAt || payment.createdAt || '',
        title: paymentSourceLabel(payment),
        meta: `${payment.status === 'voided' ? '已作废 · ' : ''}${formatDateTimeLabel(payment.paidAt) || '时间未知'}`,
        note: payment.note || '',
        amount: `-${formatAccountCurrency(payment.amount)}`,
        tone: payment.status === 'voided' ? 'voided' : 'payment',
      })
    })

  entries.value
    .filter(entry => {
      if (entry.sourceTable === 'liability_payments') {
        return payments.value.some(payment => payment.id === entry.sourceId && payment.statementId === cycle.id)
      }
      if (entry.sourceTable === 'data_records' && cycle.evidenceRecordId) return entry.sourceId === cycle.evidenceRecordId
      return false
    })
    .forEach(entry => {
      items.push({
        key: `entry:${entry.id}`,
        kind: 'entry',
        entry,
        at: entry.occurredAt || entry.createdAt || '',
        title: entryTypeLabel(entry),
        meta: `${entry.isVoided ? '已作废 · ' : ''}${formatDateTimeLabel(entry.occurredAt) || '时间未知'}`,
        note: entry.note || sourceLabel(entry),
        amount: `${entry.direction === 'in' ? '+' : '-'}${formatAccountCurrency(entry.amount)}`,
        tone: entry.isVoided ? 'voided' : entry.entryType === 'adjustment' ? 'adjustment' : 'ledger',
      })
    })

  return items.sort((a, b) => String(b.at || '').localeCompare(String(a.at || '')))
})
const autoDebitLabel = computed(() => {
  const id = account.value?.autoDebitAccountId
  if (!id) return '未设置'
  const debit = (store.accounts?.value || []).find(item => item.id === id)
  return debit ? accountTitle(debit) : '已设置'
})
const repaymentStatus = computed(() => {
  if (activeCycle.value?.status === 'paid') return { label: `${activeCycle.value.cycleMonth} 已还清`, desc: '当前显示的是所选月份账单，不是最近待还', tone: 'ok' }
  if (cycleIsSelectedMonth.value && activeCycle.value?.dueDate && activeCycle.value.dueDate < todayKey) {
    return { label: `${activeCycle.value.cycleMonth} 已过还款日`, desc: '这是所选月份的历史账单，请按实际情况确认是否已还', tone: 'warn' }
  }
  if (!activeCycle.value) {
    const next = nextActionableCycle.value
    if (next?.dueDate) return { label: `${selectedMonthKey.value} 暂无账单`, desc: `最近待还是 ${next.cycleMonth}，${daysUntilLabel(next.dueDate)}`, tone: 'muted' }
    return { label: `${selectedMonthKey.value} 暂无账单`, desc: '该月份没有识别到账单或系统估算记录', tone: 'muted' }
  }
  if (!account.value?.paymentDueDay) return { label: '待补还款日', desc: '设置后首页会显示具体待还日期', tone: 'muted' }
  if (!nextDueDate.value) return { label: '待补还款日', desc: '设置后首页会显示具体待还日期', tone: 'muted' }
  if (nextDueDate.value === todayKey) return { label: '今日待还', desc: '建议确认是否已还款或自动扣款', tone: 'warn' }
  return { label: '待还计划已设置', desc: `${daysUntilLabel(nextDueDate.value)}需要确认还款`, tone: 'ok' }
})

function signedCurrency(value) {
  return `${value >= 0 ? '+' : '-'}${formatAccountCurrency(Math.abs(value))}`
}

function cycleStatementAmount(cycle) {
  if (!cycle) return 0
  const amount = Number(cycle.statementAmount)
  return Number.isFinite(amount) ? amount : 0
}

function cycleRemainingAmount(cycle) {
  if (!cycle) return 0
  const remaining = Number(cycle.remainingAmount)
  if (Number.isFinite(remaining)) return remaining
  return cycleStatementAmount(cycle)
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
  if (entry.sourceTable === 'liability_payments') return '关联还款记录'
  return entry.sourceTable
}

function paymentSourceLabel(payment) {
  const labels = {
    screenshot: '截图确认还款',
    manual: '手动确认还款',
    auto_debit_assumed: '自动扣款确认',
    system_match: '系统匹配还款',
  }
  if (payment.status === 'voided') return '已作废还款'
  if (payment.status === 'pending_review') return '待确认还款'
  return labels[payment.source] || '还款记录'
}

function cycleSourceLabel(cycle) {
  const labels = {
    screenshot: '截图账单',
    manual: '手动确认',
    system: '系统估算',
    reconciliation: '余额校准',
  }
  return labels[cycle?.source] || '账单'
}

function cycleConfidenceLabel(cycle) {
  if (cycle?.confidence == null) return '未记录'
  return `${Math.round(Number(cycle.confidence || 0) * 100)}%`
}

function openStatementEvidence() {
  const record = statementEvidence.value
  if (!record) return
  if (record.imageUrl) {
    store.openImgFull(record.imageUrl)
    return
  }
  if (sourceSnapshot.value?.id === record.id && sourceSnapshot.value.imageUrl) {
    store.openImgFull(sourceSnapshot.value.imageUrl)
    return
  }
  if (store.openDataRecordImage && record.imagePath) {
    store.openDataRecordImage(record)
    return
  }
  store.openRecordDetail?.('universal', record)
}

function openActivityItem(item) {
  if (item.kind === 'entry' && item.entry) {
    store.openAccountEntrySource(item.entry)
    return
  }
  if (item.kind === 'cycle') {
    openStatementEvidence()
  }
}

function cycleStatusLabel(cycle) {
  const labels = {
    draft_estimated: '系统估算',
    pending: '待还',
    due_today: '今日待还',
    overdue_unconfirmed: '已过期，待确认',
    partial_paid: '部分已还',
    minimum_paid: '已还最低',
    carried_over: '剩余结转',
    paid: '已还清',
    ignored: '已忽略',
    historical_unconfirmed: '历史待确认',
    reconciled: '已对账',
    replaced: '已被替代',
    reopened: '重新估算中',
  }
  return labels[cycle?.status] || '待还'
}

async function confirmActiveCyclePaid() {
  if (!activeCycle.value) return
  if (repaymentMode.value === 'partial' && repaymentConfirmAmount.value <= 0) {
    if (store.showFlash) store.showFlash('请输入有效的还款金额')
    else alert('请输入有效的还款金额')
    return
  }
  await store.confirmRepaymentCyclePaid(activeCycle.value, {
    paidAmount: repaymentConfirmAmount.value,
    debitAccountId: repaymentDebitAccount.value?.id || null,
    status: repaymentStatusToSubmit.value,
    note: repaymentMode.value === 'partial' ? '手动记录部分还款' : '手动确认已还清',
  })
  if (repaymentMode.value === 'partial') partialRepaymentAmount.value = ''
}

async function revokePayment(payment) {
  await store.revokeLiabilityPayment(payment)
}

function normalizeDueDate(day, today) {
  const dueDay = Number(day)
  if (!Number.isFinite(dueDay) || dueDay <= 0) return null
  const base = new Date(`${today}T00:00:00`)
  const current = makeDate(base.getFullYear(), base.getMonth() + 1, dueDay)
  if (current >= base) return localDateKey(current)
  return localDateKey(makeDate(base.getFullYear(), base.getMonth() + 2, dueDay))
}

function makeDate(year, month, day) {
  return new Date(year, month - 1, Math.min(day, new Date(year, month, 0).getDate()))
}

function localDateKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

function daysUntilLabel(dateKey) {
  const today = new Date(`${todayKey}T00:00:00`)
  const target = new Date(`${dateKey}T00:00:00`)
  const days = Math.round((target - today) / 86400000)
  if (days === 0) return '今天'
  if (days === 1) return '明天'
  if (days === -1) return '昨天'
  if (days < 0) return `已过${Math.abs(days)}天`
  return `${days}天后`
}
</script>
