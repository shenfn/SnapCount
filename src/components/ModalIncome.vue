<template>
  <div class="modal-overlay" :class="{ open: store.incomeModal.open }" @click.self="store.closeIncomeModal()">
    <div class="modal-sheet">
      <div class="sheet-handle"></div>
      <div class="sheet-header">
        <div class="sheet-title">添加收入</div>
        <div class="sheet-sub">手动录入收入记录</div>
      </div>

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

      <div class="sel-section" style="margin-top:12px">
        <div class="sel-label">备注（可选）</div>
        <input type="text" class="sheet-input" v-model="store.incomeModal.note"
          placeholder="备注信息…" maxlength="100">
      </div>

      <button class="confirm-btn" style="background:#1565C0" @click="store.confirmIncome()">确认保存</button>
    </div>
  </div>
</template>

<script setup>
import { inject } from 'vue'
const store = inject('store')

const incomeTypes = [
  { val: 'salary',        label: '💼 工资',     hot: true },
  { val: 'bonus',         label: '🎁 奖金' },
  { val: 'freelance',     label: '💻 兼职' },
  { val: 'investment',    label: '📈 投资收益' },
  { val: 'reimbursement', label: '🧾 报销' },
  { val: 'other',         label: '💰 其他' },
]
</script>
