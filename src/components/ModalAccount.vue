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
          :disabled="!store.accountModal.name"
          @click="store.saveAccount()">{{ store.accountModal.mode === 'edit' ? '保存修改' : '创建账户' }}</button>
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
</script>

<style scoped>
.default-row { display: flex; flex-direction: column; gap: 10px; }
.default-row-item { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--text2, #555); }
.hint-text { font-size: 11px; color: var(--text3, #888); margin-top: 4px; }
</style>
