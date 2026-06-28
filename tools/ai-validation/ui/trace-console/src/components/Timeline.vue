<template>
  <div class="timeline-panel">
    <!-- 概览信息条 -->
    <div class="overview-bar" v-if="trace">
      <span class="overview-file">{{ trace.case?.test_case_file || '—' }}</span>
      <span class="overview-status" :style="{ color: statusColor(trace.status) }">
        {{ statusLabel(trace.status) }}
      </span>
      <span class="overview-meta">{{ trace.case?.test_case_domain || '—' }}</span>
      <span class="overview-meta" v-if="trace.model_context?.model_name">
        {{ trace.model_context.model_provider }} · {{ trace.model_context.model_name }}
      </span>
      <span class="overview-meta" v-if="trace.trace_id">
        trace: <code>{{ shortId(trace.trace_id) }}</code>
      </span>
      <span class="overview-meta" v-if="trace.ai_log_id">
        log: <code>{{ shortId(trace.ai_log_id) }}</code>
      </span>
    </div>

    <!-- 总请求耗时（独立显示，不混入节点流） -->
    <div class="total-duration-section" v-if="trace">
      <div class="total-label">总请求耗时</div>
      <div class="total-value" :class="totalDurationClass">
        {{ formatDuration(trace._total_duration_ms) }}
      </div>
    </div>

    <!-- 慢节点排行（排除 upload_request） -->
    <div class="slow-nodes-section" v-if="trace && trace._slow_nodes.length > 0">
      <div class="section-title">慢节点排行 · 排除上传耗时</div>
      <div class="slow-nodes-list">
        <div
          v-for="(node, idx) in trace._slow_nodes"
          :key="node.step_id"
          class="slow-node-item"
          :class="{ 'rank-1': idx === 0 }"
        >
          <span class="rank-num">{{ idx + 1 }}</span>
          <span class="slow-node-name">{{ node.name }}</span>
          <div class="slow-node-bar-wrapper">
            <div
              class="slow-node-bar"
              :style="{
                width: slowNodeBarWidth(node.duration_ms) + '%',
                background: idx === 0 ? 'var(--accent-red)' : idx === 1 ? 'var(--accent-yellow)' : 'var(--accent-blue)'
              }"
            ></div>
          </div>
          <span class="slow-node-duration" :style="{ color: idx === 0 ? 'var(--accent-red)' : 'var(--text-secondary)' }">
            {{ formatDuration(node.duration_ms) }}
          </span>
          <span class="slow-node-tag" v-if="idx === 0">最慢</span>
        </div>
      </div>
    </div>

    <!-- 节点时间线 -->
    <div class="section-title" v-if="trace">
      链路时间线 · {{ visibleSteps.length }} 个节点
    </div>

    <div class="node-list" v-if="trace">
      <div
        v-for="step in visibleSteps"
        :key="step.step_id"
        class="node"
        :class="[
          nodeStatusClass(step.status),
          { active: step.step_id === selectedStepId, l0: step.visibility_level === 'L0' }
        ]"
        @click="$emit('select-node', step.step_id)"
      >
        <div class="node-top-row">
          <div class="node-left">
            <span class="node-name">{{ step.name }}</span>
            <!-- 耗时条 -->
            <span
              v-if="step.duration_ms != null && step.duration_ms > 0"
              class="duration-bar"
              :style="{
                width: durationBarWidth(step.duration_ms) + 'px',
                background: durationBarColor(step.duration_ms)
              }"
            ></span>
            <span
              v-if="step.duration_ms != null && step.duration_ms > 0"
              class="node-duration"
              :style="{ color: durationTextColor(step.duration_ms) }"
            >{{ formatDuration(step.duration_ms) }}</span>
            <span v-if="isSlowestNode(step)" class="slowest-tag">最慢</span>
          </div>
          <div class="node-right">
            <span v-if="step.visibility_level === 'L0'" class="l0-tag">L0</span>
            <span class="level-tag">{{ step.visibility_level }}</span>
          </div>
        </div>
        <!-- 节点摘要 -->
        <div class="node-summary" v-if="getNodeSummary(step)">
          {{ getNodeSummary(step) }}
        </div>
        <!-- Artifact 引用 -->
        <div class="node-artifacts" v-if="step.artifact_refs && step.artifact_refs.length > 0">
          <span
            v-for="ref in step.artifact_refs"
            :key="ref"
            class="artifact-chip"
            @click.stop="$emit('view-artifact', ref)"
          >{{ ref }}</span>
        </div>
      </div>
    </div>

    <!-- 空状态 -->
    <div class="timeline-empty" v-if="!trace">
      <div class="empty-icon">📋</div>
      <div class="empty-text">请从左侧选择一个样本查看链路详情</div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { formatDuration, getStatusColor, getStatusLabel } from '../lib/formatters.js'

const props = defineProps({
  trace: { type: Object, default: null },
  selectedStepId: { type: String, default: '' },
  viewMode: { type: String, default: 'dev' },
})

defineEmits(['select-node', 'view-artifact'])

// 根据视角过滤节点
const visibleSteps = computed(() => {
  if (!props.trace?.steps) return []
  if (props.viewMode === 'user') {
    return props.trace.steps.filter((s) => s.user_visible || s.visibility_level === 'L0')
  }
  return props.trace.steps
})

// 最大后端节点耗时（用于计算耗时条比例）
const maxBackendDuration = computed(() => {
  if (!props.trace?.steps) return 0
  return props.trace.steps
    .filter((s) => s.step_id !== 'upload_request' && s.duration_ms != null)
    .reduce((max, s) => Math.max(max, s.duration_ms), 0)
})

// 总耗时样式
const totalDurationClass = computed(() => {
  const ms = props.trace?._total_duration_ms
  if (ms == null) return ''
  if (ms > 20000) return 'very-slow'
  if (ms > 10000) return 'slow'
  return 'normal'
})

function statusColor(status) {
  return getStatusColor(status)
}

function statusLabel(status) {
  return getStatusLabel(status)
}

function shortId(id) {
  if (!id) return '—'
  return id.slice(0, 8)
}

function nodeStatusClass(status) {
  const map = {
    success: 's-success',
    done: 's-success',
    skipped: 's-skipped',
    unknown: 's-unknown',
    error: 's-error',
  }
  return map[status] || 's-unknown'
}

// 耗时条宽度（像素，最大 120px）
function durationBarWidth(ms) {
  if (!ms || ms <= 0 || maxBackendDuration.value === 0) return 0
  return Math.max(3, Math.min(120, (ms / maxBackendDuration.value) * 120))
}

function durationBarColor(ms) {
  if (ms > 5000) return 'var(--accent-red)'
  if (ms > 2000) return 'var(--accent-yellow)'
  return 'var(--accent-green)'
}

function durationTextColor(ms) {
  if (ms > 5000) return 'var(--accent-red)'
  if (ms > 2000) return 'var(--accent-yellow)'
  return 'var(--text-secondary)'
}

function isSlowestNode(step) {
  if (!props.trace?._slow_nodes?.length) return false
  return props.trace._slow_nodes[0].step_id === step.step_id
}

function slowNodeBarWidth(ms) {
  if (!ms || ms <= 0 || maxBackendDuration.value === 0) return 0
  return (ms / maxBackendDuration.value) * 100
}

// 提取节点摘要文本
function getNodeSummary(step) {
  const out = step.output_snapshot
  if (!out || typeof out !== 'object') return ''

  // 根据节点类型提取关键信息
  switch (step.step_id) {
    case 'upload_request':
      return `HTTP ${out.http_status || '—'} · ${out.status_text || ''}`
    case 'identity_resolve':
      return out.upload_token_used ? 'upload_token 验证' : '—'
    case 'image_hash':
      return out.perceptual_hash ? `pHash: ${out.perceptual_hash.slice(0, 16)}...` : '—'
    case 'duplicate_check':
      return out.duplicate_kind ? `命中: ${out.duplicate_kind}` : '未命中重复'
    case 'domain_dispatch':
      return out.route_reason || out.skip_reason || (out.selected_domain_key ? `选中: ${out.selected_domain_key}` : '—')
    case 'prompt_build':
      return out.prompt_version ? `${out.prompt_version} · hash: ${shortId(out.prompt_hash)}` : '—'
    case 'model_path':
      return out.vision_mode ? `${out.vision_mode} · ${out.model_provider || ''} ${out.model_name || ''}` : '—'
    case 'model_call':
      return `finish: ${out.finish_reason || '—'} · ${out.attempts || 0}次尝试`
    case 'model_parse':
      return out.record_type ? `record_type: ${out.record_type} · confidence: ${out.confidence ?? '—'}` : '—'
    case 'normalize_validate':
      return out.status ? `status: ${out.status}` + (out.occurred_at ? ` · ${out.occurred_at.slice(0, 10)}` : '') : '—'
    case 'companion_feedback':
      return out.has_ai_feedback ? 'feedback_used · 非兜底' : (out.final === '-' ? '已跳过' : '—')
    case 'archive_or_staging':
      return out.target_table ? `→ ${out.target_table} · ${shortId(out.target_id)}` : '—'
    case 'write_ai_log':
      return out.ai_log_id ? `ai_log_id: ${shortId(out.ai_log_id)}` : '—'
    case 'response_build':
      return `${out.status || '—'} · ${out.record_type || ''} · ${out.has_ai_feedback ? '有反馈' : '无反馈'} · ${out.has_notification ? '有通知' : '无通知'}`
    default:
      return ''
  }
}
</script>

<style scoped>
.timeline-panel {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-md) var(--space-lg);
}

/* 概览信息条 */
.overview-bar {
  display: flex;
  align-items: center;
  gap: var(--space-md);
  padding: var(--space-sm) var(--space-md);
  margin-bottom: var(--space-md);
  border-radius: var(--radius-lg);
  background: var(--bg-panel);
  border: 1px solid var(--border);
  font-size: 12px;
  flex-wrap: wrap;
}

.overview-file {
  font-weight: 500;
  color: var(--text-primary);
}

.overview-status {
  font-weight: 600;
  padding: 2px 8px;
  border-radius: var(--radius-sm);
  background: rgba(255, 255, 255, 0.05);
}

.overview-meta {
  color: var(--text-secondary);
}

.overview-meta code {
  color: var(--accent-blue);
  font-family: var(--font-mono);
  font-size: 11px;
}

/* 总请求耗时 */
.total-duration-section {
  display: flex;
  align-items: center;
  gap: var(--space-md);
  padding: var(--space-md) var(--space-lg);
  margin-bottom: var(--space-md);
  border-radius: var(--radius-lg);
  background: linear-gradient(135deg, rgba(88, 166, 255, 0.05), rgba(88, 166, 255, 0.02));
  border: 1px solid rgba(88, 166, 255, 0.15);
}

.total-label {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-secondary);
  white-space: nowrap;
}

.total-value {
  font-size: 22px;
  font-weight: 700;
  font-family: var(--font-mono);
}

.total-value.normal {
  color: var(--accent-green);
}

.total-value.slow {
  color: var(--accent-yellow);
}

.total-value.very-slow {
  color: var(--accent-red);
}

/* 慢节点排行 */
.slow-nodes-section {
  margin-bottom: var(--space-md);
  padding: var(--space-sm) var(--space-md);
  border-radius: var(--radius-lg);
  background: var(--bg-panel);
  border: 1px solid var(--border);
}

.section-title {
  font-size: 12px;
  font-weight: 700;
  color: var(--text-secondary);
  margin-bottom: var(--space-sm);
}

.slow-nodes-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.slow-node-item {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  font-size: 12px;
}

.rank-num {
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: var(--bg-hover);
  color: var(--text-secondary);
  font-size: 10px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.slow-node-item.rank-1 .rank-num {
  background: var(--accent-red);
  color: #fff;
}

.slow-node-name {
  color: var(--text-primary);
  white-space: nowrap;
  min-width: 80px;
}

.slow-node-bar-wrapper {
  flex: 1;
  height: 4px;
  background: var(--bg-base);
  border-radius: 2px;
  overflow: hidden;
}

.slow-node-bar {
  height: 100%;
  border-radius: 2px;
  transition: width 0.3s;
}

.slow-node-duration {
  font-family: var(--font-mono);
  font-size: 11px;
  white-space: nowrap;
  min-width: 50px;
  text-align: right;
}

.slow-node-tag {
  font-size: 10px;
  color: var(--accent-red);
  white-space: nowrap;
}

/* 节点列表 */
.node-list {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.node {
  position: relative;
  padding: 6px 10px 6px 28px;
  cursor: pointer;
  border-radius: var(--radius-md);
  border-left: 2px solid var(--border);
  margin-left: 10px;
  font-size: 12px;
  transition: background 0.12s;
}

.node::before {
  content: '';
  position: absolute;
  left: -6px;
  top: 10px;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  border: 2px solid var(--border);
  background: var(--bg-base);
}

.node.s-success::before {
  border-color: var(--accent-green);
  background: var(--accent-green);
}

.node.s-skipped::before {
  border-color: var(--status-skipped);
  background: var(--bg-base);
  border-style: dashed;
}

.node.s-unknown::before {
  border-color: var(--status-unknown);
  background: var(--bg-base);
}

.node.s-error::before {
  border-color: var(--accent-red);
  background: var(--accent-red);
}

.node:hover:not(.active) {
  background: rgba(255, 255, 255, 0.03);
}

.node.active {
  background: var(--bg-hover);
  border-left-color: var(--accent-blue);
}

.node.active::before {
  border-color: var(--accent-blue);
  box-shadow: 0 0 6px var(--accent-blue);
}

.node.l0 {
  border-left-color: rgba(88, 166, 255, 0.5);
}

.node-top-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.node-left {
  display: flex;
  align-items: center;
  gap: 6px;
}

.node-name {
  font-weight: 500;
  color: var(--text-primary);
}

.duration-bar {
  display: inline-block;
  height: 2px;
  border-radius: 1px;
  vertical-align: middle;
  opacity: 0.7;
}

.node-duration {
  font-size: 11px;
  font-family: var(--font-mono);
}

.slowest-tag {
  font-size: 10px;
  color: var(--accent-red);
}

.node-right {
  display: flex;
  align-items: center;
  gap: 4px;
}

.l0-tag {
  font-size: 10px;
  color: var(--accent-blue);
  font-weight: 600;
}

.level-tag {
  font-size: 10px;
  color: var(--text-muted);
}

.node-summary {
  color: var(--text-muted);
  font-size: 11px;
  margin-top: 2px;
}

.node-artifacts {
  margin-top: 3px;
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.artifact-chip {
  display: inline-block;
  font-size: 10px;
  padding: 2px 7px;
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

/* 空状态 */
.timeline-empty {
  text-align: center;
  padding: 60px 0;
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
