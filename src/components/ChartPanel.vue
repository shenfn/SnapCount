<template>
  <div class="chart-panel" :class="['tier-' + tier]">
    <div class="chart-panel-head">
      <div class="chart-panel-title">{{ title }}</div>
      <span class="chart-panel-badge">{{ tierLabel }}</span>
    </div>

    <!-- placeholder：数据不足 -->
    <div v-if="tier === 'placeholder'" class="chart-panel-placeholder">
      <div class="chart-panel-placeholder-icon">○</div>
      <div class="chart-panel-placeholder-text">{{ seedHint }}</div>
    </div>

    <!-- light/solid：渲染图表 -->
    <div v-else class="chart-panel-canvas-wrap">
      <slot></slot>
    </div>

    <!-- 底部说明 -->
    <div v-if="$slots.note" class="chart-panel-note"><slot name="note"></slot></div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  title: { type: String, required: true },
  tier: { type: String, default: 'solid' }, // 'placeholder' | 'light' | 'solid'
  seedHint: { type: String, default: '数据再多一点，这里会长出图表' },
})

const tierLabel = computed(() => {
  switch (props.tier) {
    case 'placeholder': return '等待中'
    case 'light':       return '初步形态'
    default:            return '完整'
  }
})
</script>

<style scoped>
.chart-panel {
  background: rgba(255, 255, 255, 0.94);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 16px 18px 18px;
  margin-bottom: 14px;
  transition: opacity 0.2s ease;
}
.chart-panel.tier-light {
  background: rgba(255, 255, 255, 0.78);
}
.chart-panel.tier-light .chart-panel-canvas-wrap {
  opacity: 0.78;
}
.chart-panel.tier-placeholder {
  background: repeating-linear-gradient(
    135deg,
    rgba(255, 255, 255, 0.6),
    rgba(255, 255, 255, 0.6) 8px,
    rgba(0, 0, 0, 0.02) 8px,
    rgba(0, 0, 0, 0.02) 16px
  );
}

.chart-panel-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}
.chart-panel-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: 0.3px;
}
.chart-panel-badge {
  font-size: 10.5px;
  font-weight: 600;
  padding: 2px 9px;
  border-radius: 999px;
  background: rgba(33, 79, 61, 0.08);
  color: var(--primary);
  letter-spacing: 0.4px;
}
.chart-panel.tier-light .chart-panel-badge {
  background: rgba(245, 158, 11, 0.12);
  color: #b45309;
}
.chart-panel.tier-placeholder .chart-panel-badge {
  background: rgba(107, 114, 128, 0.1);
  color: #6b7280;
}

.chart-panel-canvas-wrap {
  position: relative;
  height: 220px;
}

.chart-panel-placeholder {
  height: 140px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: var(--text3);
}
.chart-panel-placeholder-icon {
  font-size: 36px;
  color: var(--text3);
  opacity: 0.4;
  font-weight: 200;
  line-height: 1;
}
.chart-panel-placeholder-text {
  font-size: 12.5px;
  color: var(--text2);
  text-align: center;
  max-width: 80%;
  line-height: 1.55;
  letter-spacing: 0.3px;
}

.chart-panel-note {
  margin-top: 10px;
  font-size: 11px;
  color: var(--text3);
  letter-spacing: 0.3px;
}
</style>
