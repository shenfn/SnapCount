<template>
  <div class="sample-list-panel">
    <!-- 标题栏 -->
    <div class="panel-header">
      <span class="header-title">样本列表</span>
      <span class="header-count">{{ traces.length }} 张</span>
    </div>

    <!-- 筛选按钮 -->
    <div class="filter-section">
      <button
        v-for="opt in filterOptions"
        :key="opt.key"
        class="filter-btn"
        :class="{ on: activeFilter === opt.key }"
        @click="activeFilter = opt.key"
      >{{ opt.label }} ({{ opt.count }})</button>
    </div>

    <!-- 样本列表 -->
    <div class="sample-scroll">
      <div
        v-for="t in filteredTraces"
        :key="t.case_key"
        class="sample-item"
        :class="{ active: t.case_key === selectedCaseKey, 'parse-error': t.status === 'parse_error' }"
        @click="$emit('select', t.case_key)"
      >
        <!-- 缩略图（点击放大，阻止冒泡避免触发样本选择） -->
        <div class="thumb-wrapper" @click.stop="t.image_relative_path ? openImage(t) : null">
          <img
            v-if="t.image_relative_path"
            :src="imageUrl(t.image_relative_path)"
            class="thumb"
            loading="lazy"
            @error="onThumbError"
          />
          <div v-else class="thumb-placeholder">—</div>
        </div>

        <!-- 样本信息 -->
        <div class="sample-info">
          <div class="sample-top-row">
            <span class="sample-name">{{ t.file }}</span>
            <span class="sample-status" :style="{ color: statusColor(t.status) }">
              {{ statusLabel(t.status) }}
            </span>
          </div>
          <div class="sample-meta">
            <span>{{ t.domain }}</span>
            <span>·</span>
            <span>{{ formatDuration(t.elapsed_ms) }}</span>
            <span v-if="t.has_ai_feedback" class="feedback-dot" title="有 AI 反馈">AI</span>
            <span v-if="t.parse_error" class="error-dot" :title="t.parse_error">解析失败</span>
          </div>
        </div>
      </div>

      <!-- 空状态 -->
      <div v-if="filteredTraces.length === 0" class="empty-list">
        <span>无匹配样本</span>
      </div>
    </div>

    <!-- 图片放大查看器 -->
    <ImageViewer
      :src="viewerSrc"
      :file-name="viewerFileName"
    />
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { imageUrl } from '../lib/api.js'
import { formatDuration, getStatusColor, getStatusLabel } from '../lib/formatters.js'
import { extractFilterOptions } from '../lib/traceNormalizer.js'
import ImageViewer from './ImageViewer.vue'

const props = defineProps({
  traces: { type: Array, default: () => [] },
  selectedCaseKey: { type: String, default: '' },
})

defineEmits(['select'])

const activeFilter = ref('all')
const viewerSrc = ref(null)
const viewerFileName = ref('')

// 筛选选项
const filterOptions = computed(() => extractFilterOptions(props.traces))

// 筛选后的样本
const filteredTraces = computed(() => {
  if (activeFilter.value === 'all') return props.traces
  return props.traces.filter((t) => t.status === activeFilter.value)
})

function statusColor(status) {
  return getStatusColor(status)
}

function statusLabel(status) {
  return getStatusLabel(status)
}

function onThumbError(e) {
  e.target.style.display = 'none'
}

// 打开图片放大查看
function openImage(trace) {
  viewerSrc.value = imageUrl(trace.image_relative_path)
  viewerFileName.value = trace.file || ''
}
</script>

<style scoped>
.sample-list-panel {
  width: 240px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg-panel);
  border-right: 1px solid var(--border);
}

.panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-sm) var(--space-md);
  border-bottom: 1px solid var(--border);
}

.header-title {
  font-size: 12px;
  font-weight: 700;
  color: var(--text-secondary);
}

.header-count {
  font-size: 12px;
  color: var(--text-muted);
}

.filter-section {
  display: flex;
  gap: var(--space-xs);
  padding: var(--space-sm) var(--space-md);
  border-bottom: 1px solid var(--border);
  flex-wrap: wrap;
}

.filter-btn {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  transition: all 0.12s;
  white-space: nowrap;
}

.filter-btn.on {
  background: var(--accent-blue);
  color: #fff;
  border-color: var(--accent-blue);
}

.filter-btn:hover:not(.on) {
  border-color: var(--accent-blue);
}

.sample-scroll {
  flex: 1;
  overflow-y: auto;
  padding: var(--space-xs) var(--space-sm);
}

.sample-item {
  display: flex;
  gap: var(--space-sm);
  padding: var(--space-sm);
  border-radius: var(--radius-md);
  cursor: pointer;
  transition: background 0.12s;
  border: 1px solid transparent;
  margin-bottom: 2px;
}

.sample-item:hover {
  background: var(--bg-hover);
}

.sample-item.active {
  background: rgba(88, 166, 255, 0.1);
  border-color: rgba(88, 166, 255, 0.3);
}

.thumb-wrapper {
  width: 36px;
  height: 36px;
  flex-shrink: 0;
  border-radius: var(--radius-sm);
  overflow: hidden;
  background: var(--bg-base);
  display: flex;
  align-items: center;
  justify-content: center;
}

.thumb {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.thumb-placeholder {
  color: var(--text-muted);
  font-size: 14px;
}

.sample-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.sample-top-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-xs);
}

.sample-name {
  font-size: 12px;
  font-weight: 500;
  color: var(--text-primary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sample-status {
  font-size: 11px;
  font-weight: 500;
  white-space: nowrap;
}

.sample-meta {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  margin-top: 2px;
  font-size: 11px;
  color: var(--text-muted);
}

.feedback-dot {
  background: rgba(188, 140, 255, 0.15);
  color: var(--accent-purple);
  padding: 0 4px;
  border-radius: 3px;
  font-size: 10px;
  font-weight: 600;
}

.sample-item.parse-error {
  border: 1px dashed var(--accent-red);
}

.error-dot {
  background: rgba(248, 81, 73, 0.15);
  color: var(--accent-red);
  padding: 0 4px;
  border-radius: 3px;
  font-size: 10px;
  font-weight: 600;
}

.empty-list {
  text-align: center;
  padding: 40px 0;
  color: var(--text-muted);
  font-size: 12px;
}
</style>
