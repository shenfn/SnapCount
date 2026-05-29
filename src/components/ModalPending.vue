<template>
  <div class="modal-overlay" :class="{ open: store.pendingModal.open }" @click.self="tryClose">
    <div class="modal-sheet" ref="sheetEl"
      :class="{ swiping: isSwiping, closing: isClosing, unsaved: showUnsaved }"
      @touchstart="onTouchStart"
      @touchmove="onTouchMove"
      @touchend="onTouchEnd">
      <div class="sheet-drag-zone">
        <div class="sheet-handle"></div>
      </div>
      <div class="sheet-header">
        <div class="sheet-title">{{ store.pendingModal.bill?.status === 'done' ? '编辑账单信息' : '补充账单信息' }}</div>
        <div class="sheet-sub">{{ store.pendingModal.bill?.date }} {{ store.pendingModal.bill?.time }} · 截图识别</div>
      </div>

      <div class="sheet-body" ref="bodyEl">
        <div class="amount-edit-wrap">
          <span class="amount-edit-prefix" :class="{ income: store.pendingModal.entryType === 'income' }">
            {{ store.pendingModal.entryType === 'income' ? '+¥' : '-¥' }}
          </span>
          <input type="number" class="amount-edit-input" v-model="store.pendingModal.amount"
            :class="{ income: store.pendingModal.entryType === 'income' }"
            min="0.01" max="999999.99" step="0.01" placeholder="0.00">
        </div>

        <div class="thumb-wrap">
          <div v-if="store.pendingModal.bill?.image_url" style="width:100%" @click="store.openImgFull(store.pendingModal.bill.image_url)">
            <img :src="store.pendingModal.bill.image_url"
              @error="store.markPendingImageUnavailable()"
              style="width:100%; max-height:160px; object-fit:contain; background:#f0f0f0; display:block;">
            <div style="text-align:center; padding:6px 0; font-size:11px; color:var(--text3);">👆 点击放大原图</div>
          </div>
          <template v-else-if="store.pendingModal.bill?.imageLoadError">
            <span>⚠️</span><span>截图文件不可用或已删除</span>
          </template>
          <template v-else>
            <span>🖼</span><span>无截图预览</span>
          </template>
        </div>

        <div class="sel-section" style="margin-top:12px">
          <div class="sel-label">{{ store.pendingModal.entryType === 'income' ? '来源名称（可选）' : '商家名称（可选）' }}</div>
          <input type="text" class="sheet-input" v-model="store.pendingModal.merchantName"
            :placeholder="store.pendingModal.entryType === 'income' ? '如：转账方、项目名、平台收益…' : '如：麦当劳、京东购物…'" maxlength="50">
        </div>

        <div class="sel-section" style="margin-top:16px">
          <div class="sel-label">记录类型</div>
          <div class="seg-control">
            <button :class="{ active: store.pendingModal.entryType === 'expense' }"
              @click="store.pendingModal.entryType = 'expense'">支出</button>
            <button :class="{ active: store.pendingModal.entryType === 'income' }"
              @click="store.pendingModal.entryType = 'income'">收入</button>
          </div>
        </div>

        <template v-if="store.pendingModal.entryType === 'expense'">
        <div class="sel-section">
          <div class="sel-label">消费渠道</div>
          <div class="sel-grid">
            <div v-for="p in platforms" :key="p.val" class="sel-chip"
              :class="{ selected: store.pendingModal.platform === p.val }"
              @click="store.pendingModal.platform = p.val">
              {{ p.label }}
              <span v-if="p.hot" class="hot-badge">常用</span>
            </div>
          </div>
        </div>

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
        </template>

        <template v-else>
        <div class="sel-section" style="margin-top:16px">
          <div class="sel-label">收入类型</div>
          <div class="sel-grid">
            <div v-for="item in incomeTypes" :key="item.val" class="sel-chip"
              :class="{ selected: store.pendingModal.incomeCategory === item.val }"
              @click="store.pendingModal.incomeCategory = item.val">
              {{ item.label }}
              <span v-if="item.hot" class="hot-badge">常用</span>
            </div>
          </div>
        </div>
        </template>

        <AccountPicker
          :label="store.pendingModal.entryType === 'income' ? '到账账户' : '出资账户'"
          :kind="store.pendingModal.entryType"
          :selected-id="store.pendingModal.accountId"
          :unbound="store.pendingModal.accountUnbound"
          @update:selectedId="store.pendingModal.accountId = $event"
          @update:unbound="store.pendingModal.accountUnbound = $event"
        />
      </div>

      <div class="sheet-footer">
        <button class="confirm-btn"
          :disabled="store.pendingModal.entryType === 'expense'
            ? (!store.pendingModal.platform || !store.pendingModal.category || !store.pendingModal.payment)
            : !store.pendingModal.incomeCategory"
          @click="doSave">确认保存</button>
        <button class="delete-bill-btn"
          @click="store.openDeleteConfirm('bill', store.pendingModal.bill?.id, store.pendingModal.bill?.image_path)">
          🗑 删除此账单
        </button>
      </div>

      <div v-if="showUnsaved" class="unsaved-bar">
        <span class="unsaved-text">内容未保存，确认退出？</span>
        <button class="unsaved-cancel" @click="showUnsaved = false">继续编辑</button>
        <button class="unsaved-confirm" @click="doForceClose">退出</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { inject, ref, watch, onUnmounted } from 'vue'
import AccountPicker from './AccountPicker.vue'
const store = inject('store')

const sheetEl = ref(null)
const bodyEl = ref(null)
const showUnsaved = ref(false)
const isSwiping = ref(false)
const isClosing = ref(false)
const swipeDir = ref(null)

let touchStartY = 0
let touchStartX = 0
let touchStartTime = 0
let bodyScrollY = 0
let originalBodyOverflow = ''
let originalBodyPosition = ''
let originalBodyTop = ''
let originalBodyWidth = ''

function lockBodyScroll() {
  bodyScrollY = window.scrollY
  originalBodyOverflow = document.body.style.overflow
  originalBodyPosition = document.body.style.position
  originalBodyTop = document.body.style.top
  originalBodyWidth = document.body.style.width
  document.body.style.overflow = 'hidden'
  document.body.style.position = 'fixed'
  document.body.style.top = `-${bodyScrollY}px`
  document.body.style.width = '100%'
}

function unlockBodyScroll() {
  document.body.style.overflow = originalBodyOverflow
  document.body.style.position = originalBodyPosition
  document.body.style.top = originalBodyTop
  document.body.style.width = originalBodyWidth
  window.scrollTo(0, bodyScrollY)
}

watch(() => store.pendingModal.open, open => {
  if (open) { lockBodyScroll(); showUnsaved.value = false }
  else unlockBodyScroll()
})

onUnmounted(unlockBodyScroll)

function isScrollAtTop() {
  if (!bodyEl.value) return true
  return bodyEl.value.scrollTop <= 1
}

function isInteractiveTarget(target) {
  return !!target.closest('input, button, img, .sel-chip, .thumb-wrap, .confirm-btn, .delete-bill-btn, .unsaved-bar')
}

function tryClose() {
  if (store.hasPendingChanges()) {
    showUnsaved.value = true
    return
  }
  store.closePendingModal()
}

function doForceClose() {
  showUnsaved.value = false
  store.resetPendingChanges()
  store.closePendingModal()
}

function doSave() {
  store.confirmEntry()
  showUnsaved.value = false
}

function animateClose(direction) {
  if (!sheetEl.value) return
  isClosing.value = true
  swipeDir.value = direction
  sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
  if (direction === 'down') {
    sheetEl.value.style.transform = 'translateY(110%)'
  } else if (direction === 'right') {
    sheetEl.value.style.transform = 'translateX(110%)'
  }
  setTimeout(() => {
    if (store.hasPendingChanges()) {
      showUnsaved.value = true
      sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
      sheetEl.value.style.transform = ''
      isClosing.value = false
      swipeDir.value = null
    } else {
      store.closePendingModal()
      if (sheetEl.value) {
        sheetEl.value.style.transition = ''
        sheetEl.value.style.transform = ''
      }
      isClosing.value = false
      swipeDir.value = null
    }
  }, 280)
}

function onTouchStart(e) {
  if (!isInteractiveTarget(e.target)) {
    showUnsaved.value = false
  }
  isSwiping.value = false
  isClosing.value = false
  swipeDir.value = null
  touchStartY = e.touches[0].clientY
  touchStartX = e.touches[0].clientX
  touchStartTime = Date.now()
  if (sheetEl.value) sheetEl.value.style.transition = 'none'
}

function onTouchMove(e) {
  if (isClosing.value) return
  const deltaY = e.touches[0].clientY - touchStartY
  const deltaX = e.touches[0].clientX - touchStartX
  const absX = Math.abs(deltaX)
  const absY = Math.abs(deltaY)

  if (absX < 8 && absY < 8) return

  if (absX > absY * 1.5 && absX > 20) {
    if (isInteractiveTarget(e.target)) return
    e.preventDefault()
    isSwiping.value = true
    swipeDir.value = 'right'
    if (sheetEl.value) {
      sheetEl.value.style.transform = `translateX(${Math.min(absX, window.innerWidth * 0.6)}px)`
    }
    return
  }

  if (absY > absX * 1.2 && deltaY > 0) {
    if (!isScrollAtTop()) return
    if (isInteractiveTarget(e.target)) return
    e.preventDefault()
    isSwiping.value = true
    swipeDir.value = 'down'
    if (sheetEl.value) {
      sheetEl.value.style.transform = `translateY(${Math.min(deltaY, window.innerHeight * 0.5)}px)`
    }
  }
}

function onTouchEnd(e) {
  if (!isSwiping.value || !sheetEl.value) {
    isSwiping.value = false
    swipeDir.value = null
    return
  }

  if (swipeDir.value === 'right') {
    const deltaX = Math.abs(e.changedTouches[0].clientX - touchStartX)
    const elapsed = Math.max(1, Date.now() - touchStartTime)
    const velocity = deltaX / elapsed
    const shouldClose = deltaX > 80 || velocity > 0.4
    if (shouldClose) {
      animateClose('right')
    } else {
      sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
      sheetEl.value.style.transform = ''
    }
  } else if (swipeDir.value === 'down') {
    const deltaY = e.changedTouches[0].clientY - touchStartY
    const elapsed = Math.max(1, Date.now() - touchStartTime)
    const velocity = deltaY / elapsed
    const distanceThreshold = Math.max(100, window.innerHeight * 0.22)
    const shouldClose = deltaY > distanceThreshold || velocity > 0.5
    if (shouldClose) {
      animateClose('down')
    } else {
      sheetEl.value.style.transition = 'transform 0.28s cubic-bezier(0.32,0,0.67,0)'
      sheetEl.value.style.transform = ''
    }
  }

  isSwiping.value = false
  swipeDir.value = null
}

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

const incomeTypes = [
  { val: 'salary',        label: '💼 工资', hot: true },
  { val: 'bonus',         label: '🎁 奖金' },
  { val: 'freelance',     label: '💻 兼职' },
  { val: 'investment',    label: '📈 投资收益' },
  { val: 'reimbursement', label: '🧾 报销' },
  { val: 'other',         label: '💰 其他' },
]
</script>
