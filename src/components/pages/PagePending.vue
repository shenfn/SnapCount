<template>
  <div class="page active">
    <div class="topbar">
      <h1>待补充</h1>
      <div class="sub">
        {{ store.pendingBills.value.length ? `${store.pendingBills.value.length} 条记录信息不完整` : '全部已补充完毕' }}
      </div>
    </div>
    <div style="height:12px"></div>

    <div v-if="!store.pendingBills.value.length" class="empty">
      <div class="e-icon">✓</div><p>全部补充完毕</p>
    </div>

    <div v-for="b in store.pendingBills.value" :key="b.id" class="pending-item" @click="store.openPendingModal(b)">
      <div class="pending-row">
        <div>
          <div class="pending-amount">-¥{{ b.amount.toFixed(2) }}</div>
          <div class="pending-time">{{ b.date }} {{ b.time }} · 截图识别</div>
        </div>
        <div style="font-size:13px; color:var(--accent)">补充 ›</div>
      </div>
      <div class="pending-fields">
        <span class="field-chip" :class="b.platform === '?' ? 'field-missing' : 'field-ok'">
          {{ b.platform === '?' ? '? 平台未知' : '✓ ' + b.platform }}
        </span>
        <span class="field-chip" :class="b.cat === '?' ? 'field-missing' : 'field-ok'">
          {{ b.cat === '?' ? '? 分类未知' : '✓ ' + b.cat }}
        </span>
        <span class="field-chip" :class="b.payment === '?' ? 'field-missing' : 'field-ok'">
          {{ b.payment === '?' ? '? 支付未知' : '✓ ' + b.payment }}
        </span>
      </div>
    </div>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { inject } from 'vue'
const store = inject('store')
</script>
