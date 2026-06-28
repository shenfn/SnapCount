<template>
  <div class="user-output-panel" v-if="outputs.length > 0">
    <div class="panel-header">
      <span class="header-title">用户可见输出</span>
      <span class="header-desc">— 用户最终看到了什么</span>
    </div>

    <div class="output-cards">
      <div
        v-for="(output, idx) in outputs"
        :key="idx"
        class="output-card"
        :class="'type-' + output.output_type"
      >
        <!-- 卡片标题 -->
        <div class="card-title">{{ output.label }}</div>

        <!-- iOS 快捷指令通知 -->
        <template v-if="output.output_type === 'ios_shortcut_notification'">
          <div class="notification-text">{{ output.value }}</div>
        </template>

        <!-- App 伴随文案 -->
        <template v-else-if="output.output_type === 'app_companion_message'">
          <div class="companion-text">{{ output.value }}</div>
          <div class="card-meta" v-if="output.source_step">
            来源: {{ output.source_step }}
          </div>
        </template>

        <!-- App AI 弹窗反馈 -->
        <template v-else-if="output.output_type === 'app_ai_feedback' && typeof output.value === 'object'">
          <div class="feedback-card">
            <div class="feedback-header">
              <span class="feedback-icon" v-if="output.value.icon">{{ output.value.icon }}</span>
              <span class="feedback-badge" v-if="output.value.badge">{{ output.value.badge }}</span>
              <span
                class="feedback-band"
                v-if="output.value.band"
                :class="'band-' + output.value.band"
              >{{ output.value.band }}</span>
              <span class="feedback-score" v-if="output.value.internal_score != null">
                {{ output.value.internal_score }}分
              </span>
            </div>
            <div class="feedback-emotion" v-if="output.value.emotion_line">
              {{ output.value.emotion_line }}
            </div>
            <div class="feedback-utility" v-if="output.value.utility_line">
              {{ output.value.utility_line }}
            </div>
            <div class="feedback-detail" v-if="output.value.detail_reason">
              {{ output.value.detail_reason }}
            </div>
            <div class="feedback-meta">
              <span v-if="output.value.confidence != null">置信度 {{ output.value.confidence }}</span>
              <span v-if="output.value.source">· {{ output.value.source }}</span>
              <span v-if="output.value.timing_signal?.label">· {{ output.value.timing_signal.label }}</span>
            </div>
          </div>
        </template>

        <!-- 通用 JSON 展示（兜底） -->
        <template v-else>
          <JsonViewer :data="output.value" :max-length="1000" />
        </template>
      </div>

      <!-- 推断的记录摘要 -->
      <InferredSummary :trace="trace" />
    </div>
  </div>

  <!-- 无用户可见输出 -->
  <div class="user-output-panel empty" v-else>
    <div class="panel-header">
      <span class="header-title">用户可见输出</span>
    </div>
    <div class="empty-outputs">该样本无用户可见输出</div>
  </div>
</template>

<script setup>
import JsonViewer from './JsonViewer.vue'
import InferredSummary from './InferredSummary.vue'

const props = defineProps({
  outputs: { type: Array, default: () => [] },
  trace: { type: Object, default: null },
})
</script>

<style scoped>
.user-output-panel {
  border-top: 1px solid var(--border);
  background: rgba(88, 166, 255, 0.03);
  padding: var(--space-sm) var(--space-lg);
  flex-shrink: 0;
  max-height: 140px;
  overflow-y: auto;
}

.panel-header {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  margin-bottom: var(--space-sm);
}

.header-title {
  font-size: 12px;
  font-weight: 700;
  color: var(--accent-blue);
}

.header-desc {
  font-size: 12px;
  color: var(--text-muted);
}

.output-cards {
  display: flex;
  gap: var(--space-sm);
  min-height: 0;
}

.output-card {
  flex: 1;
  min-width: 0;
  padding: var(--space-sm) var(--space-md);
  border-radius: var(--radius-lg);
  background: var(--bg-panel);
  border: 1px solid var(--border);
  overflow: hidden;
}

.card-title {
  font-size: 11px;
  font-weight: 700;
  color: var(--text-secondary);
  margin-bottom: var(--space-xs);
}

.notification-text {
  font-size: 12px;
  line-height: 1.6;
  color: var(--text-primary);
  white-space: pre-wrap;
  max-height: 70px;
  overflow-y: auto;
}

.companion-text {
  font-size: 12px;
  color: var(--text-primary);
  line-height: 1.5;
}

.card-meta {
  font-size: 10px;
  color: var(--text-muted);
  margin-top: var(--space-xs);
}

.feedback-card {
  font-size: 12px;
}

.feedback-header {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  margin-bottom: var(--space-xs);
}

.feedback-icon {
  font-size: 14px;
}

.feedback-badge {
  font-weight: 700;
  color: var(--text-primary);
  font-size: 12px;
}

.feedback-band {
  font-size: 10px;
  padding: 1px 6px;
  border-radius: 8px;
  font-weight: 600;
}

.feedback-band.band-positive {
  background: rgba(63, 185, 80, 0.15);
  color: var(--accent-green);
}

.feedback-band.band-negative {
  background: rgba(248, 81, 73, 0.15);
  color: var(--accent-red);
}

.feedback-band.band-neutral {
  background: rgba(139, 148, 158, 0.15);
  color: var(--text-secondary);
}

.feedback-score {
  font-size: 11px;
  color: var(--text-muted);
}

.feedback-emotion {
  color: var(--text-primary);
  font-size: 12px;
  line-height: 1.5;
}

.feedback-utility {
  color: var(--text-secondary);
  font-size: 11px;
  margin-top: 2px;
}

.feedback-detail {
  color: var(--text-muted);
  font-size: 11px;
  margin-top: 2px;
}

.feedback-meta {
  font-size: 10px;
  color: var(--text-muted);
  margin-top: var(--space-xs);
  display: flex;
  gap: var(--space-xs);
}

.empty-outputs {
  font-size: 12px;
  color: var(--text-muted);
  padding: var(--space-md) 0;
  text-align: center;
}
</style>
