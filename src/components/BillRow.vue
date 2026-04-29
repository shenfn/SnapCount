<template>
  <div class="bill-item">
    <div class="bill-icon" :style="{ background: bill.iconBg }">{{ bill.icon }}</div>
    <div class="bill-info">
      <div class="bill-name">{{ bill.name }}</div>
      <div class="bill-meta">{{ bill.platform }} · {{ bill.date }} {{ bill.time }}</div>
    </div>
    <div style="text-align:right">
      <div class="bill-amount">-¥{{ bill.amount.toFixed(2) }}</div>
      <div class="tag" :class="bill.status === 'pending' ? 'tag-pending' : 'tag-done'">
        {{ bill.status === 'pending' ? '待补充' : bill.cat }}
      </div>
    </div>
  </div>
</template>

<script setup>
defineProps({ bill: Object })
</script>
