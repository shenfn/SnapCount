<template>
  <div class="modal-overlay" :class="{ open: store.expenseModal.open }" @click.self="sheet.tryClose">
    <div class="modal-sheet" ref="sheetEl"
      :class="{ swiping: sheet.isSwiping.value, closing: sheet.isClosing.value }"
      @touchstart="sheet.onTouchStart"
      @touchmove="sheet.onTouchMove"
      @touchend="sheet.onTouchEnd">
      <div class="sheet-drag-zone">
        <div class="sheet-handle"></div>
      </div>
      <div class="sheet-header">
        <div class="sheet-title">{{ store.expenseModal.mode === 'staging' ? '核对并收下' : (store.expenseModal.mode === 'edit' ? '编辑支出' : '添加支出') }}</div>
        <div class="sheet-sub">{{ store.expenseModal.mode === 'staging' ? '只改需要调整的字段，确认后自动处理下一条' : (store.expenseModal.mode === 'edit' ? '调整支出信息与截图' : '手动补录一笔消费') }}</div>
      </div>

      <div class="sheet-body" ref="bodyEl">
      <div class="amount-input-wrap compact">
        <span class="amount-prefix expense">-¥</span>
        <input type="number" class="amount-input expense" v-model="store.expenseModal.amount"
          placeholder="0.00" min="0.01" step="0.01">
      </div>

      <div v-if="store.expenseModal.mode !== 'create'" class="thumb-wrap">
        <div v-if="store.expenseModal.imageUrl" style="width:100%" @click="store.openImgFull(store.expenseModal.imageUrl)">
          <img :src="store.expenseModal.imageUrl"
            @error="store.markExpenseImageUnavailable()"
            style="width:100%; max-height:160px; object-fit:contain; background:#f0f0f0; display:block;">
          <div style="text-align:center; padding:6px 0; font-size:11px; color:var(--text3);">点击放大原图</div>
        </div>
        <template v-else-if="store.expenseModal.imageLoadError">
          <span>!</span><span>截图文件不可用或已删除</span>
        </template>
        <template v-else>
          <span>□</span><span>无截图预览</span>
        </template>
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">商家名称（可选）</div>
        <input type="text" class="sheet-input" v-model="store.expenseModal.merchantName"
          placeholder="如：麦当劳、京东购物…" maxlength="50">
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">消费渠道</div>
        <div class="sel-grid">
          <button v-for="p in platforms" :key="p.val" type="button" class="sel-chip"
            :class="{ selected: store.expenseModal.platform === p.val }"
            @click="selectFinanceOption('platform', p.val)">
            {{ p.label }}
            <span v-if="p.hot" class="hot-badge">常用</span>
          </button>
          <button type="button" class="sel-chip finance-custom-trigger"
            :aria-expanded="customOptionKind === 'platform'"
            @click="openCustomOption('platform')">＋ 自定义渠道</button>
        </div>
        <div v-if="customOptionKind === 'platform'" class="finance-custom-option">
          <input v-model="customOptionValue" type="text" maxlength="30" placeholder="输入其他消费渠道"
            aria-label="自定义消费渠道" @keydown.enter.prevent="applyCustomOption">
          <button type="button" :disabled="!customOptionValue.trim()" @click="applyCustomOption">使用</button>
        </div>
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">消费分类</div>
        <div class="sel-grid">
          <button v-for="c in categories" :key="c.val" type="button" class="sel-chip"
            :class="{ selected: store.expenseModal.category === c.val }"
            @click="selectFinanceOption('category', c.val)">
            {{ c.label }}
            <span v-if="c.hot" class="hot-badge">常用</span>
          </button>
        </div>
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">支付方式</div>
        <div class="sel-grid">
          <button v-for="p in payments" :key="p.val" type="button" class="sel-chip"
            :class="{ selected: store.expenseModal.payment === p.val }"
            @click="selectFinanceOption('payment', p.val)">
            {{ p.label }}
            <span v-if="p.hot" class="hot-badge">常用</span>
          </button>
          <button type="button" class="sel-chip finance-custom-trigger"
            :aria-expanded="customOptionKind === 'payment'"
            @click="openCustomOption('payment')">＋ 自定义方式</button>
        </div>
        <div v-if="customOptionKind === 'payment'" class="finance-custom-option">
          <input v-model="customOptionValue" type="text" maxlength="30" placeholder="输入其他支付方式"
            aria-label="自定义支付方式" @keydown.enter.prevent="applyCustomOption">
          <button type="button" :disabled="!customOptionValue.trim()" @click="applyCustomOption">使用</button>
        </div>
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">消费日期</div>
        <input type="date" class="sheet-input" v-model="store.expenseModal.date" :max="today">
      </div>

      <div class="sel-section" style="margin-top:12px">
        <div class="sel-label">消费时间（可选）</div>
        <input type="time" class="sheet-input" v-model="store.expenseModal.time">
      </div>

      <AccountPicker
        label="出资账户"
        kind="expense"
        :selected-id="store.expenseModal.accountId"
        :unbound="store.expenseModal.accountUnbound"
        :amount="store.expenseModal.amount"
        @update:selectedId="store.expenseModal.accountId = $event"
        @update:unbound="store.expenseModal.accountUnbound = $event"
      />

      <div class="sel-section" style="margin-top:12px">
        <div class="sel-label">备注（可选）</div>
        <input type="text" class="sheet-input" v-model="store.expenseModal.note"
          placeholder="备注信息…" maxlength="100">
      </div>
      </div>

      <div class="sheet-footer">
        <button class="confirm-btn"
          :disabled="!store.expenseModal.amount || !store.expenseModal.platform || !store.expenseModal.category || !store.expenseModal.payment || !store.expenseModal.date || store.isActionPending('expense')"
          @click="store.confirmExpense()">{{ store.isActionPending('expense') ? '保存中...' : (store.expenseModal.mode === 'staging' ? '确认并收下' : '确认保存') }}</button>
        <button v-if="store.expenseModal.mode === 'edit'" class="delete-bill-btn"
          @click="store.openDeleteConfirm('bill', store.expenseModal.id, store.expenseModal.imagePath)">
          删除此支出
        </button>
      </div>

      <div v-if="sheet.showUnsaved.value" class="unsaved-bar">
        <span class="unsaved-text">内容未保存，确认退出？</span>
        <button class="unsaved-cancel" @click="sheet.showUnsaved.value = false">继续编辑</button>
        <button class="unsaved-confirm" @click="sheet.doForceClose">退出</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, inject, ref, watch } from 'vue'
import { useBottomSheet } from '../composables/useBottomSheet'
import { getLocalDateKey } from '../utils/helpers'
import { buildAdaptiveFinanceOptions, normalizeFinanceOptionValue } from '../domains/financeReviewOptions'
import AccountPicker from './AccountPicker.vue'
const store = inject('store')
const today = getLocalDateKey()

const sheet = useBottomSheet(
  computed(() => store.expenseModal.open),
  store.closeExpenseModal,
  {
    hasChanges: store.hasExpenseChanges,
    resetChanges: store.resetExpenseChanges,
  }
)
const sheetEl = sheet.sheetEl
const bodyEl = sheet.bodyEl
const customOptionKind = ref('')
const customOptionValue = ref('')

const financeVocabulary = computed(() => store.financeVocabulary?.value || [])
const platforms = computed(() => buildAdaptiveFinanceOptions({
  kind: 'platform',
  currentValue: store.expenseModal.platform,
  vocabulary: financeVocabulary.value,
}))
const categories = computed(() => buildAdaptiveFinanceOptions({
  kind: 'category',
  currentValue: store.expenseModal.category,
  vocabulary: financeVocabulary.value,
}))
const payments = computed(() => buildAdaptiveFinanceOptions({
  kind: 'payment',
  currentValue: store.expenseModal.payment,
  vocabulary: financeVocabulary.value,
}))

function selectFinanceOption(kind, value) {
  const normalized = normalizeFinanceOptionValue(kind, value)
  if (!normalized) return
  store.expenseModal[kind] = normalized
  customOptionKind.value = ''
  customOptionValue.value = ''
}

function openCustomOption(kind) {
  if (customOptionKind.value === kind) {
    customOptionKind.value = ''
    customOptionValue.value = ''
    return
  }
  customOptionKind.value = kind
  customOptionValue.value = ''
}

function applyCustomOption() {
  if (!customOptionKind.value) return
  selectFinanceOption(customOptionKind.value, customOptionValue.value)
}

watch(() => store.expenseModal.open, open => {
  if (!open) return
  customOptionKind.value = ''
  customOptionValue.value = ''
})
</script>

<style scoped>
.sel-grid .finance-custom-trigger {
  border-style: dashed;
  color: var(--primary, #426e63);
  background: transparent;
}

.finance-custom-option {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 8px;
  margin-top: 9px;
}

.finance-custom-option input {
  min-width: 0;
  min-height: 40px;
  border: 1px solid var(--border, #d9ddd8);
  border-radius: 10px;
  padding: 8px 10px;
  color: var(--text1, #202a27);
  background: var(--surface, #fff);
  font: inherit;
  outline: none;
}

.finance-custom-option input:focus {
  border-color: var(--primary, #426e63);
  box-shadow: 0 0 0 3px rgba(66, 110, 99, 0.12);
}

.finance-custom-option button {
  min-width: 54px;
  border: 0;
  border-radius: 10px;
  padding: 0 12px;
  color: #fff;
  background: var(--primary, #426e63);
  font: inherit;
}

.finance-custom-option button:disabled {
  opacity: 0.42;
}
</style>
