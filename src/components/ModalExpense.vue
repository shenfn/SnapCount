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
        <div class="sheet-title">{{ store.expenseModal.mode === 'edit' ? '编辑支出' : '添加支出' }}</div>
        <div class="sheet-sub">{{ store.expenseModal.mode === 'edit' ? '调整支出信息与截图' : '手动补录一笔消费' }}</div>
      </div>

      <div class="sheet-body" ref="bodyEl">
      <div class="amount-input-wrap compact">
        <span class="amount-prefix expense">-¥</span>
        <input type="number" class="amount-input expense" v-model="store.expenseModal.amount"
          placeholder="0.00" min="0.01" step="0.01">
      </div>

      <div v-if="store.expenseModal.mode === 'edit'" class="thumb-wrap">
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
          <div v-for="p in platforms" :key="p.val" class="sel-chip"
            :class="{ selected: store.expenseModal.platform === p.val }"
            @click="store.expenseModal.platform = p.val">
            {{ p.label }}
            <span v-if="p.hot" class="hot-badge">常用</span>
          </div>
        </div>
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">消费分类</div>
        <div class="sel-grid">
          <div v-for="c in categories" :key="c.val" class="sel-chip"
            :class="{ selected: store.expenseModal.category === c.val }"
            @click="store.expenseModal.category = c.val">
            {{ c.label }}
          </div>
        </div>
      </div>

      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">支付方式</div>
        <div class="sel-grid">
          <div v-for="p in payments" :key="p.val" class="sel-chip"
            :class="{ selected: store.expenseModal.payment === p.val }"
            @click="store.expenseModal.payment = p.val">
            {{ p.label }}
            <span v-if="p.hot" class="hot-badge">常用</span>
          </div>
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

      <div class="sel-section" style="margin-top:12px">
        <div class="sel-label">备注（可选）</div>
        <input type="text" class="sheet-input" v-model="store.expenseModal.note"
          placeholder="备注信息…" maxlength="100">
      </div>
      </div>

      <div class="sheet-footer">
        <button class="confirm-btn"
          :disabled="!store.expenseModal.amount || !store.expenseModal.platform || !store.expenseModal.category || !store.expenseModal.payment || !store.expenseModal.date"
          @click="store.confirmExpense()">确认保存</button>
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
import { computed, inject } from 'vue'
import { useBottomSheet } from '../composables/useBottomSheet'
const store = inject('store')
const today = new Date().toISOString().slice(0, 10)

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

const platforms = [
  { val: '美团',  label: '🛵 美团',  hot: true },
  { val: '微信',  label: '💬 微信' },
  { val: '线下消费', label: '🏪 线下消费', hot: true },
  { val: '京东',  label: '📦 京东' },
  { val: '拼多多',label: '🛍 拼多多' },
  { val: '淘宝',  label: '🧡 淘宝' },
  { val: '抖音',  label: '🎵 抖音' },
  { val: '支付宝',label: '💙 支付宝' },
  { val: '其他', label: '💰 其他' },
]

const categories = [
  { val: '餐饮', label: '🍜 餐饮' },
  { val: '购物', label: '🛒 购物' },
  { val: '出行', label: '🚗 出行' },
  { val: '娱乐', label: '🎮 娱乐' },
  { val: '生活', label: '🏠 生活' },
  { val: '其他', label: '📌 其他' },
]

const payments = [
  { val: '微信支付', label: '💚 微信支付', hot: true },
  { val: '花呗',    label: '🔵 花呗' },
  { val: '支付宝',  label: '🔷 支付宝' },
  { val: '银行卡',  label: '💳 银行卡' },
  { val: '京东白条',label: '🟡 京东白条' },
  { val: '美团月付',label: '🔴 美团月付' },
  { val: '先用后付',label: '⚡ 先用后付' },
]
</script>
