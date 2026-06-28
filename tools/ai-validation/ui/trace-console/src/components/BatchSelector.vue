<template>
  <div class="batch-selector">
    <select
      class="batch-select"
      :value="modelValue"
      @change="$emit('update:modelValue', $event.target.value)"
    >
      <option value="" disabled>选择批次...</option>
      <option v-for="run in runs" :key="run.run_id" :value="run.run_id">
        {{ run.run_id }}
        <template v-if="run.total_cases != null">
          ({{ run.success_cases }}/{{ run.total_cases }})
        </template>
      </option>
    </select>
  </div>
</template>

<script setup>
defineProps({
  modelValue: { type: String, default: '' },
  runs: { type: Array, default: () => [] },
})
defineEmits(['update:modelValue'])
</script>

<style scoped>
.batch-selector {
  display: inline-flex;
}

.batch-select {
  background: var(--bg-hover);
  color: var(--text-primary);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 3px 8px;
  font-size: 12px;
  font-family: var(--font-sans);
  cursor: pointer;
  outline: none;
  max-width: 220px;
}

.batch-select:hover {
  border-color: var(--accent-blue);
}

.batch-select:focus {
  border-color: var(--accent-blue);
}
</style>
