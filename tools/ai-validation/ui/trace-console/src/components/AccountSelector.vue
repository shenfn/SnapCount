<template>
  <div class="account-selector">
    <!-- 模式切换 -->
    <div class="mode-toggle">
      <button
        :class="{ on: mode === 'local' }"
        @click="$emit('update:mode', 'local')"
      >本地</button>
      <button
        :class="{ on: mode === 'remote' }"
        @click="$emit('update:mode', 'remote')"
      >远程</button>
    </div>

    <!-- 账号选择（仅远程模式） -->
    <select
      v-if="mode === 'remote'"
      class="account-select"
      :value="accountKey"
      @change="$emit('update:accountKey', $event.target.value)"
    >
      <option value="" disabled>选择账号...</option>
      <option v-for="acc in accounts" :key="acc.key" :value="acc.key">
        {{ acc.label }}
      </option>
    </select>

    <!-- 记忆按钮（仅远程模式） -->
    <button
      v-if="mode === 'remote' && accountKey"
      class="memory-btn"
      @click="$emit('open-memory')"
      title="查看 AI 记忆上下文"
    >🧠 记忆</button>
  </div>
</template>

<script setup>
defineProps({
  mode: { type: String, default: 'local' }, // 'local' | 'remote'
  accounts: { type: Array, default: () => [] },
  accountKey: { type: String, default: '' },
})
defineEmits(['update:mode', 'update:accountKey', 'open-memory'])
</script>

<style scoped>
.account-selector {
  display: inline-flex;
  align-items: center;
  gap: var(--space-sm);
}

.mode-toggle {
  display: inline-flex;
  background: var(--bg-base);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 2px;
}

.mode-toggle button {
  padding: 3px 10px;
  border: none;
  background: transparent;
  color: var(--text-secondary);
  font-size: 12px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  transition: all 0.12s;
  font-family: var(--font-sans);
}

.mode-toggle button.on {
  background: var(--accent-blue);
  color: #fff;
}

.mode-toggle button:hover:not(.on) {
  color: var(--text-primary);
}

.account-select {
  background: var(--bg-hover);
  color: var(--text-primary);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 3px 8px;
  font-size: 12px;
  font-family: var(--font-sans);
  cursor: pointer;
  outline: none;
  max-width: 160px;
}

.account-select:hover {
  border-color: var(--accent-blue);
}

.account-select:focus {
  border-color: var(--accent-blue);
}

.memory-btn {
  font-size: 11px;
  padding: 3px 10px;
  border-radius: var(--radius-sm);
  background: rgba(139, 92, 246, 0.12);
  color: #a78bfa;
  border: 1px solid rgba(139, 92, 246, 0.25);
  cursor: pointer;
  font-family: var(--font-sans);
  white-space: nowrap;
  transition: all 0.12s;
}

.memory-btn:hover {
  background: rgba(139, 92, 246, 0.2);
  border-color: rgba(139, 92, 246, 0.4);
}
</style>
