<template>
  <!-- 遮罩 -->
  <div class="drawer-mask" :class="{ on: open }" @click="$emit('close')"></div>

  <!-- 抽屉 -->
  <div class="drawer" :class="{ open: open }">
    <!-- 头部 -->
    <div class="drawer-header">
      <span class="drawer-title">
        {{ step?.name || '节点详情' }}
        <span class="drawer-duration" v-if="step?.duration_ms != null">
          · {{ formatDuration(step.duration_ms) }}
        </span>
      </span>
      <button class="close-btn" @click="$emit('close')">关闭</button>
    </div>

    <!-- 内容 -->
    <div class="drawer-body" v-if="step">
      <!-- 节点状态 -->
      <div class="status-row">
        <span class="status-label">状态:</span>
        <span class="status-value" :style="{ color: statusColor(step.status) }">
          {{ statusLabel(step.status) }}
        </span>
        <span class="visibility-badge" v-if="step.visibility_level === 'L0'">
          用户可见 (L0)
        </span>
        <span class="visibility-badge dev" v-else>
          {{ step.visibility_level }}
        </span>
      </div>

      <!-- 节点说明 -->
      <div class="note-box" v-if="stepNote">
        {{ stepNote }}
      </div>

      <!-- Artifact 引用 -->
      <div class="section" v-if="step.artifact_refs && step.artifact_refs.length > 0">
        <div class="section-title">Artifacts</div>
        <div class="artifact-chips">
          <span
            v-for="ref in step.artifact_refs"
            :key="ref"
            class="artifact-chip"
            @click="$emit('view-artifact', ref)"
          >{{ ref }}</span>
        </div>
      </div>

      <!-- 输入快照 -->
      <div class="section">
        <div class="section-title">输入</div>
        <JsonViewer
          v-if="hasInputData"
          :data="step.input_snapshot"
        />
        <div v-else class="empty-field">无输入数据</div>
      </div>

      <!-- 输出快照 -->
      <div class="section">
        <div class="section-title">输出</div>
        <JsonViewer
          v-if="hasOutputData"
          :data="step.output_snapshot"
        />
        <div v-else class="empty-field">无输出数据</div>
      </div>

      <!-- 损耗/转换说明 -->
      <div class="section" v-if="step.loss_or_transform_notes && step.loss_or_transform_notes.length > 0">
        <div class="section-title">转换/损耗说明</div>
        <ul class="loss-notes">
          <li v-for="(note, idx) in step.loss_or_transform_notes" :key="idx">{{ note }}</li>
        </ul>
      </div>
    </div>

    <!-- 空状态 -->
    <div class="drawer-empty" v-else>
      <div class="empty-icon">👆</div>
      <div class="empty-text">点击左侧时间线节点查看详情</div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import JsonViewer from './JsonViewer.vue'
import { formatDuration, getStatusColor, getStatusLabel } from '../lib/formatters.js'

const props = defineProps({
  open: { type: Boolean, default: false },
  step: { type: Object, default: null },
})

defineEmits(['close', 'view-artifact'])

// 节点说明
const stepNote = computed(() => {
  if (!props.step) return ''
  const notes = {
    upload_request: '总请求耗时含网络传输和 Edge Function 处理。',
    identity_resolve: '通过 upload_token 或 JWT 解析用户身份。',
    image_hash: 'SHA-256 用于精确去重，感知哈希用于相似图判断。',
    duplicate_check: '查询已识别记录，判断是否重复截图。',
    domain_dispatch: '根据 OCR 文本、source_app 和图片特征判断目标域。',
    prompt_build: '根据域类型和响应模式构造 prompt。',
    model_path: '根据 capture_kind 和图片特征选择视觉模型路径。',
    model_call: '调用 AI 视觉模型，获取原始返回。',
    model_parse: '从模型原始文本中提取 JSON。',
    normalize_validate: '根据域 schema 做字段类型转换和必填字段校验。',
    companion_feedback: '生成伴随文案和 AI 反馈。',
    archive_or_staging: '标准化成功写入业务表，失败写入中转站。',
    write_ai_log: '写入 ai_recognition_logs 表。',
    response_build: '构造最终接口响应。',
  }
  return notes[props.step.step_id] || ''
})

const hasInputData = computed(() => {
  const s = props.step?.input_snapshot
  return s && typeof s === 'object' && Object.keys(s).length > 0
})

const hasOutputData = computed(() => {
  const s = props.step?.output_snapshot
  return s && typeof s === 'object' && Object.keys(s).length > 0
})

function statusColor(status) {
  return getStatusColor(status)
}

function statusLabel(status) {
  return getStatusLabel(status)
}
</script>

<style scoped>
.drawer-mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.4);
  z-index: 39;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.2s;
}

.drawer-mask.on {
  opacity: 1;
  pointer-events: auto;
}

.drawer {
  position: fixed;
  top: 0;
  right: 0;
  bottom: 0;
  width: 420px;
  background: var(--bg-panel);
  border-left: 1px solid var(--border);
  transform: translateX(100%);
  transition: transform 0.2s ease;
  z-index: 40;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.drawer.open {
  transform: translateX(0);
}

.drawer-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-md) var(--space-lg);
  border-bottom: 1px solid var(--border);
  flex-shrink: 0;
}

.drawer-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
}

.drawer-duration {
  font-size: 12px;
  color: var(--text-secondary);
  font-weight: 400;
  font-family: var(--font-mono);
}

.close-btn {
  font-size: 12px;
  padding: 3px 10px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
}

.close-btn:hover {
  border-color: var(--accent-blue);
}

.drawer-body {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-md) var(--space-lg);
}

.status-row {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  margin-bottom: var(--space-md);
  font-size: 12px;
}

.status-label {
  color: var(--text-secondary);
}

.status-value {
  font-weight: 600;
}

.visibility-badge {
  font-size: 10px;
  padding: 2px 8px;
  border-radius: 10px;
  background: rgba(88, 166, 255, 0.15);
  color: var(--accent-blue);
  font-weight: 600;
}

.visibility-badge.dev {
  background: var(--bg-hover);
  color: var(--text-muted);
}

.note-box {
  margin-bottom: var(--space-md);
  padding: var(--space-sm) var(--space-md);
  border-radius: var(--radius-md);
  background: rgba(88, 166, 255, 0.07);
  border: 1px solid rgba(88, 166, 255, 0.15);
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.6;
}

.section {
  margin-bottom: var(--space-md);
}

.section-title {
  font-size: 12px;
  font-weight: 700;
  color: var(--text-secondary);
  margin-bottom: var(--space-xs);
}

.artifact-chips {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-xs);
}

.artifact-chip {
  display: inline-block;
  font-size: 10px;
  padding: 2px 8px;
  border-radius: 10px;
  cursor: pointer;
  background: rgba(188, 140, 255, 0.1);
  color: var(--accent-purple);
  border: 1px solid rgba(188, 140, 255, 0.25);
  transition: opacity 0.12s;
}

.artifact-chip:hover {
  opacity: 0.8;
}

.empty-field {
  font-size: 12px;
  color: var(--text-muted);
  font-style: italic;
  padding: var(--space-xs) 0;
}

.loss-notes {
  margin: 0;
  padding-left: var(--space-lg);
  font-size: 12px;
  color: var(--accent-yellow);
  line-height: 1.6;
}

.drawer-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.empty-icon {
  font-size: 28px;
  margin-bottom: var(--space-sm);
}

.empty-text {
  font-size: 13px;
}
</style>
