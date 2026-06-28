<template>
  <div class="app-root">
    <!-- 阶段一：空壳布局，后续阶段填充组件 -->
    <div class="placeholder-bar">
      <span class="text-base font-bold mr-3">AI 识别链路追踪台</span>
      <span class="text-xs px-2 py-0.5 rounded-full" style="background:rgba(88,166,255,0.15);color:var(--accent-blue);">V0.5-dev</span>
    </div>
    <div class="placeholder-body">
      <p class="text-secondary text-sm" style="text-align:center;padding-top:40px;">
        骨架已就绪，等待组件迁移...
      </p>
    </div>
  </div>
</template>

<script setup>
// 阶段一：空壳，后续阶段引入组件
</script>

<style scoped>
.app-root {
  display: flex;
  flex-direction: column;
  height: 100vh;
}

.placeholder-bar {
  display: flex;
  align-items: center;
  padding: 0 var(--space-lg);
  height: 48px;
  flex-shrink: 0;
  background: var(--bg-panel);
  border-bottom: 1px solid var(--border);
}

.placeholder-body {
  flex: 1;
  overflow-y: auto;
}
</style>
