<template>
  <div class="empty-state">
    <div class="empty-icon">{{ icon }}</div>
    <div class="empty-title">{{ title }}</div>
    <div class="empty-desc" v-if="desc">{{ desc }}</div>
  </div>
</template>

<script setup>
defineProps({
  icon: { type: String, default: '📋' },
  title: { type: String, default: '暂无数据' },
  desc: { type: String, default: '' },
})
</script>

<style scoped>
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: var(--text-muted);
  text-align: center;
  padding: var(--space-xl);
}

.empty-icon {
  font-size: 32px;
  margin-bottom: var(--space-md);
}

.empty-title {
  font-size: 14px;
  font-weight: 600;
  margin-bottom: var(--space-xs);
}

.empty-desc {
  font-size: 12px;
  color: var(--text-muted);
  max-width: 320px;
  line-height: 1.6;
}
</style>
