<template>
  <div class="modal-overlay" :class="{ open: store.pendingModal.open }" @click.self="store.closePendingModal()">
    <div class="modal-sheet" ref="sheetEl">
      <div class="sheet-drag-zone"
        @touchstart.passive="onTouchStart"
        @touchmove="onTouchMove"
        @touchend="onTouchEnd">
        <div class="sheet-handle"></div>
      </div>
      <div class="sheet-header"
        @touchstart.passive="onTouchStart"
        @touchmove="onTouchMove"
        @touchend="onTouchEnd">
        <div class="sheet-title">{{ store.pendingModal.bill?.status === 'done' ? '编辑账单信息' : '补充账单信息' }}</div>
        <div class="sheet-sub">{{ store.pendingModal.bill?.date }} {{ store.pendingModal.bill?.time }} · 截图识别</div>
      </div>
      <!-- 金额（可修正 AI 识别错误） -->
      <div class="amount-edit-wrap">
        <span class="amount-edit-prefix">-¥</span>
        <input type="number" class="amount-edit-input" v-model="store.pendingModal.amount"
          min="0.01" max="999999.99" step="0.01" placeholder="0.00">
      </div>

      <!-- 截图预览 -->
      <div class="thumb-wrap">
        <div v-if="store.pendingModal.bill?.image_url" style="width:100%" @click="store.openImgFull(store.pendingModal.bill.image_url)">
          <img :src="store.pendingModal.bill.image_url"
            style="width:100%; max-height:160px; object-fit:contain; background:#f0f0f0; display:block;">
          <div style="text-align:center; padding:6px 0; font-size:11px; color:var(--text3);">👆 点击放大原图</div>
        </div>
        <template v-else>
          <span>🖼</span><span>无截图预览</span>
        </template>
      </div>

      <!-- 商家名称 -->
      <div class="sel-section" style="margin-top:12px">
        <div class="sel-label">商家名称（可选）</div>
        <input type="text" class="sheet-input" v-model="store.pendingModal.merchantName"
          placeholder="如：麦当劳、京东购物…" maxlength="50">
      </div>

      <!-- 消费平台 -->
      <div class="sel-section">
        <div class="sel-label">消费平台</div>
        <div class="sel-grid">
          <div v-for="p in platforms" :key="p.val" class="sel-chip"
            :class="{ selected: store.pendingModal.platform === p.val }"
            @click="store.pendingModal.platform = p.val">
            {{ p.label }}
            <span v-if="p.hot" class="hot-badge">常用</span>
          </div>
        </div>
      </div>

      <!-- 消费分类 -->
      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">消费分类</div>
        <div class="sel-grid">
          <div v-for="c in categories" :key="c.val" class="sel-chip"
            :class="{ selected: store.pendingModal.category === c.val }"
            @click="store.pendingModal.category = c.val">
            {{ c.label }}
          </div>
        </div>
      </div>

      <!-- 支付方式 -->
      <div class="sel-section" style="margin-top:16px">
        <div class="sel-label">支付方式</div>
        <div class="sel-grid">
          <div v-for="p in payments" :key="p.val" class="sel-chip"
            :class="{ selected: store.pendingModal.payment === p.val }"
            @click="store.pendingModal.payment = p.val">
            {{ p.label }}
            <span v-if="p.hot" class="hot-badge">常用</span>
          </div>
        </div>
      </div>

      <button class="confirm-btn"
        :disabled="!store.pendingModal.platform || !store.pendingModal.category || !store.pendingModal.payment"
        @click="store.confirmEntry()">确认保存</button>

      <button class="delete-bill-btn"
        @click="store.openDeleteConfirm('bill', store.pendingModal.bill?.id, store.pendingModal.bill?.image_url)">
        🗑 删除此账单
      </button>
    </div>
  </div>
</template>

<script setup>
import { inject, ref } from 'vue'
const store = inject('store')

const sheetEl = ref(null)
let touchStartY = 0

function onTouchStart(e) {
  touchStartY = e.touches[0].clientY
  if (sheetEl.value) sheetEl.value.style.transition = 'none'
}

function onTouchMove(e) {
  const delta = e.touches[0].clientY - touchStartY
  if (delta <= 0) return
  e.preventDefault()
  if (sheetEl.value) sheetEl.value.style.transform = `translateY(${delta}px)`
}

function onTouchEnd(e) {
  const delta = e.changedTouches[0].clientY - touchStartY
  if (!sheetEl.value) return
  sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
  if (delta > 80) {
    sheetEl.value.style.transform = 'translateY(110%)'
    setTimeout(() => {
      store.closePendingModal()
      if (sheetEl.value) sheetEl.value.style.transform = ''
    }, 280)
  } else {
    sheetEl.value.style.transform = 'translateY(0)'
  }
}

const platforms = [
  { val: '美团',  label: '🛵 美团',  hot: true },
  { val: '微信',  label: '💬 微信' },
  { val: '京东',  label: '📦 京东' },
  { val: '拼多多',label: '🛍 拼多多' },
  { val: '淘宝',  label: '🧡 淘宝' },
  { val: '抖音',  label: '🎵 抖音' },
  { val: '支付宝',label: '💙 支付宝' },
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
