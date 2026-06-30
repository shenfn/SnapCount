<template>
  <div class="top-bar">
    <span class="title">AI 识别链路追踪台</span>
    <span class="version-tag">V0.5</span>

    <BatchSelector
      :model-value="currentRunId"
      :runs="runs"
      @update:model-value="$emit('update:currentRunId', $event)"
    />

    <div class="stats" v-if="summary">
      <span class="stat-item stat-success">
        {{ successCount }} 成功
      </span>
      <span class="stat-item stat-duplicate" v-if="duplicateCount > 0">
        {{ duplicateCount }} 去重
      </span>
      <span class="stat-item stat-error" v-if="failedCount > 0">
        {{ failedCount }} 失败
      </span>
      <span class="stat-item stat-total">{{ totalCount }} 张图</span>
    </div>

    <div class="spacer"></div>

    <button class="upload-btn" @click="$emit('open-upload')">
      <span class="upload-icon">+</span> 上传测试
    </button>

    <div class="view-toggle">
      <button
        :class="{ on: viewMode === 'user' }"
        @click="$emit('update:viewMode', 'user')"
      >用户视角</button>
      <button
        :class="{ on: viewMode === 'dev' }"
        @click="$emit('update:viewMode', 'dev')"
      >开发视角</button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import BatchSelector from './BatchSelector.vue'

const props = defineProps({
  runs: { type: Array, default: () => [] },
  currentRunId: { type: String, default: '' },
  summary: { type: Object, default: null },
  viewMode: { type: String, default: 'dev' },
})

defineEmits(['update:currentRunId', 'update:viewMode', 'open-upload'])

// 统计数据：优先从 summary.json 获取，回退从 traces 列表计算
const totalCount = computed(() => {
  if (props.summary?.total_cases != null) return props.summary.total_cases
  return props.summary?.cases?.length ?? 0
})

const successCount = computed(() => {
  if (props.summary?.success_cases != null) return props.summary.success_cases
  // 回退：从 cases 中统计 status === 'done' 或 'success'
  return props.summary?.cases?.filter(c => c.success || c.status === 'done' || c.status === 'success').length ?? 0
})

const failedCount = computed(() => {
  if (props.summary?.failed_cases != null) return props.summary.failed_cases
  return 0
})

// 去重数需要从 cases 中计算（summary.json 没有直接字段）
const duplicateCount = computed(() => {
  const cases = props.summary?.cases
  if (!Array.isArray(cases)) return 0
  return cases.filter(c => c.status === 'duplicate' || (!c.success && c.message?.includes('归档'))).length
})
</script>

<style scoped>
.top-bar {
  display: flex;
  align-items: center;
  padding: 0 var(--space-lg);
  height: 48px;
  flex-shrink: 0;
  background: var(--bg-panel);
  border-bottom: 1px solid var(--border);
  gap: var(--space-md);
}

.title {
  font-size: 14px;
  font-weight: 700;
  white-space: nowrap;
}

.version-tag {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 999px;
  background: rgba(88, 166, 255, 0.15);
  color: var(--accent-blue);
  white-space: nowrap;
}

.stats {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  font-size: 12px;
}

.stat-item {
  padding: 2px 8px;
  border-radius: var(--radius-sm);
  white-space: nowrap;
}

.stat-success {
  background: rgba(63, 185, 80, 0.15);
  color: var(--accent-green);
}

.stat-duplicate {
  background: rgba(210, 153, 34, 0.15);
  color: var(--accent-yellow);
}

.stat-error {
  background: rgba(248, 81, 73, 0.15);
  color: var(--accent-red);
}

.stat-total {
  color: var(--text-secondary);
}

.spacer {
  flex: 1;
}

.upload-btn {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  font-size: 12px;
  padding: 4px 12px;
  border-radius: var(--radius-md);
  background: var(--accent-blue);
  color: #fff;
  border: none;
  cursor: pointer;
  font-family: var(--font-sans);
  font-weight: 600;
  white-space: nowrap;
  transition: opacity 0.12s;
}

.upload-btn:hover {
  opacity: 0.9;
}

.upload-icon {
  font-size: 14px;
  font-weight: 700;
}

.view-toggle {
  display: inline-flex;
  background: var(--bg-base);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 2px;
}

.view-toggle button {
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

.view-toggle button.on {
  background: var(--accent-blue);
  color: #fff;
}

.view-toggle button:hover:not(.on) {
  color: var(--text-primary);
}
</style>
