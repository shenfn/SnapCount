<template>
  <div class="modal-overlay" :class="{ open: store.accountModal.open }" @click.self="store.closeAccountModal()">
    <div class="modal-sheet">
      <div class="sheet-drag-zone"><div class="sheet-handle"></div></div>
      <div class="sheet-header">
        <div class="sheet-title">{{ store.accountModal.mode === 'edit' ? '编辑账户' : '新建账户' }}</div>
        <div class="sheet-sub">{{ store.accountModal.mode === 'edit' ? '调整账户信息与默认归属' : '建立一个可绑定收支的账户' }}</div>
      </div>

      <div class="sheet-body">
        <div class="sel-section">
          <div class="sel-label">账户名称 *</div>
          <input type="text" class="sheet-input" v-model="store.accountModal.name"
            placeholder="如：招行储蓄、中信白金卡、现金…" maxlength="30">
        </div>

        <div class="sel-section" style="margin-top:14px">
          <div class="sel-label">账户类型</div>
          <div class="sel-grid">
            <div v-for="t in accountTypes" :key="t.val" class="sel-chip"
              :class="{ selected: store.accountModal.type === t.val }"
              @click="store.accountModal.type = t.val">{{ t.label }}</div>
          </div>
        </div>

        <div class="sel-section" style="margin-top:14px">
          <div class="sel-label">机构名称（可选）</div>
          <input type="text" class="sheet-input" v-model="store.accountModal.institution"
            placeholder="如：招商银行、支付宝…" maxlength="30">
        </div>

        <div class="sel-section" style="margin-top:14px">
          <div class="sel-label">尾号 4 位（可选）</div>
          <input type="text" class="sheet-input" v-model="store.accountModal.last4"
            placeholder="如 1234" maxlength="4" inputmode="numeric">
        </div>

        <div class="sel-section" style="margin-top:14px">
          <div class="sel-label">{{ isLiability ? '初始欠款（信用卡用正数）' : '初始余额' }}</div>
          <input type="number" class="sheet-input" v-model="store.accountModal.initialBalance"
            placeholder="0.00" step="0.01" :disabled="store.accountModal.mode === 'edit'">
          <div v-if="store.accountModal.mode === 'edit'" class="hint-text">初始余额建账后不可修改，避免破坏历史流水基线</div>
        </div>

        <div v-if="isLiability" class="liability-settings">
          <div class="liability-settings-title">还款设置</div>
          <div class="liability-settings-grid">
            <div class="sel-section">
              <div class="sel-label">账单周期结束日</div>
              <input type="number" class="sheet-input" v-model="store.accountModal.billDay"
                placeholder="如 18" min="1" max="31" step="1" inputmode="numeric">
            </div>
            <div class="sel-section">
              <div class="sel-label">还款日</div>
              <input type="number" class="sheet-input" v-model="store.accountModal.paymentDueDay"
                placeholder="如 10" min="1" max="31" step="1" inputmode="numeric">
            </div>
          </div>
          <div class="sel-section" style="margin-top:12px">
            <div class="sel-label">自动扣款账户（可选）</div>
            <select class="sheet-input" v-model="store.accountModal.autoDebitAccountId">
              <option :value="null">未设置</option>
              <option v-for="account in debitAccounts" :key="account.id" :value="account.id">
                {{ account.name }}{{ account.last4 ? `（${account.last4}）` : '' }}
              </option>
            </select>
          </div>
          <label class="default-row-item liability-auto-confirm">
            <input type="checkbox" v-model="store.accountModal.autoConfirmRepayment">
            <span>高置信度还款截图可自动确认</span>
          </label>
          <div class="hint-text">例如京东白条“记账周期 5.19-6.18”，这里填 18；还款日填 28。部分还款、最低还款和结转账单后续会进入“待确认”状态，不会直接自动清零。</div>
        </div>

        <div class="sel-section default-row" style="margin-top:14px">
          <label class="default-row-item">
            <input type="checkbox" v-model="store.accountModal.isDefaultExpense">
            <span>设为默认支出账户</span>
          </label>
          <label class="default-row-item">
            <input type="checkbox" v-model="store.accountModal.isDefaultIncome">
            <span>设为默认收入账户</span>
          </label>
        </div>

        <div v-if="store.accountModal.mode === 'edit'" class="sel-section default-row" style="margin-top:14px">
          <label class="default-row-item">
            <input type="checkbox" v-model="store.accountModal.isArchived">
            <span>归档（隐藏于候选列表）</span>
          </label>
        </div>
      </div>

      <div class="sheet-footer">
        <button class="confirm-btn" style="background:#1565C0"
          :disabled="!store.accountModal.name || store.isActionPending('account')"
          @click="store.saveAccount()">{{ store.isActionPending('account') ? '保存中...' : (store.accountModal.mode === 'edit' ? '保存修改' : '创建账户') }}</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
const store = inject('store')

const accountTypes = [
  { val: 'wallet_balance', label: '钱包余额' },
  { val: 'debit_card', label: '储蓄/借记' },
  { val: 'credit_card', label: '信用卡' },
  { val: 'credit_line', label: '花呗/白条/月付' },
  { val: 'wechat', label: '微信' },
  { val: 'alipay', label: '支付宝' },
  { val: 'cash', label: '现金' },
  { val: 'other', label: '其他' },
]

const isLiability = computed(() => ['credit_card', 'credit_line'].includes(store.accountModal.type))
const debitAccounts = computed(() => (store.accounts?.value || [])
  .filter(account => !account.isArchived && !['credit_card', 'credit_line'].includes(account.type))
)
</script>

<style scoped>
.default-row { display: flex; flex-direction: column; gap: 10px; }
.default-row-item { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--text2, #555); }
.hint-text { font-size: 11px; color: var(--text3, #888); margin-top: 4px; }
.liability-settings {
  margin-top: 14px;
  padding: 12px;
  border: 1px solid rgba(245, 158, 11, 0.22);
  border-radius: 12px;
  background: rgba(255, 251, 235, 0.72);
}
.liability-settings-title {
  font-size: 13px;
  font-weight: 700;
  color: #92400e;
  margin-bottom: 10px;
}
.liability-settings-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
.liability-auto-confirm {
  margin-top: 12px;
}
</style>
