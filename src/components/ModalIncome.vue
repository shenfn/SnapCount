<template>
  <div class="modal-overlay" :class="{ open: store.incomeModal.open }" @click.self="sheet.tryClose">
    <div class="modal-sheet" ref="sheetEl"
      :class="{ swiping: sheet.isSwiping.value, closing: sheet.isClosing.value }"
      @touchstart="sheet.onTouchStart"
      @touchmove="sheet.onTouchMove"
      @touchend="sheet.onTouchEnd">
      <div class="sheet-drag-zone">
        <div class="sheet-handle"></div>
      </div>
      <div class="sheet-header">
        <div class="sheet-title">添加收入</div>
        <div class="sheet-sub">手动录入收入记录</div>
      </div>

      <div class="sheet-body" ref="bodyEl">
      <div class="amount-input-wrap">
        <span class="amount-prefix">¥</span>
        <input type="number" class="amount-input" v-model="store.incomeModal.amount"
          placeholder="0.00" min="0.01" step="0.01">
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">收入类型</div>
        <div class="sel-grid">
          <div v-for="item in incomeTypes" :key="item.val" class="sel-chip"
            :class="{ selected: store.incomeModal.cat === item.val }"
            @click="store.incomeModal.cat = item.val">
            {{ item.label }}
            <span v-if="item.hot" class="hot-badge">常用</span>
          </div>
        </div>
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">来源名称（可选）</div>
        <input type="text" class="sheet-input" v-model="store.incomeModal.source"
          placeholder="如：XX公司、接单项目名…" maxlength="50">
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">到账日期</div>
        <input type="date" class="sheet-input" v-model="store.incomeModal.date"
          :max="today">
      </div>

      <div class="sel-section" style="margin-top:12px">
        <div class="sel-label">备注（可选）</div>
        <input type="text" class="sheet-input" v-model="store.incomeModal.note"
          placeholder="备注信息…" maxlength="100">
      </div>
      </div>

      <div class="sheet-footer">
      <button class="confirm-btn" style="background:#1565C0"
        :disabled="!store.incomeModal.amount || !store.incomeModal.cat || !store.incomeModal.date"
        @click="store.confirmIncome()">确认保存</button>
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
import { computed, inject } from 'vue'
import { useBottomSheet } from '../composables/useBottomSheet'
const store = inject('store')
const today = new Date().toISOString().slice(0, 10)

const sheet = useBottomSheet(
  computed(() => store.incomeModal.open),
  store.closeIncomeModal,
  {
    hasChanges: () => !!(store.incomeModal.amount || store.incomeModal.source || store.incomeModal.note || store.incomeModal.cat !== 'salary'),
    resetChanges: () => {
      store.incomeModal.amount = ''
      store.incomeModal.source = ''
      store.incomeModal.note = ''
      store.incomeModal.cat = 'salary'
    },
  }
)
const sheetEl = sheet.sheetEl
const bodyEl = sheet.bodyEl

const incomeTypes = [
  { val: 'salary',        label: '💼 工资',     hot: true },
  { val: 'bonus',         label: '🎁 奖金' },
  { val: 'freelance',     label: '💻 兼职' },
  { val: 'investment',    label: '📈 投资收益' },
  { val: 'reimbursement', label: '🧾 报销' },
  { val: 'other',         label: '💰 其他' },
]
</script>
