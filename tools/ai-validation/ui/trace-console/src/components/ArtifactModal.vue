<template>
  <div class="modal-overlay" v-if="open" @click.self="$emit('close')">
    <div class="modal-box">
      <!-- 头部 -->
      <div class="modal-header">
        <span class="modal-title">Artifact: {{ artifactKey }}</span>
        <div class="modal-actions">
          <button class="action-btn copy-btn" v-if="artifactData != null" @click="copyContent">
            {{ copied ? '已复制' : '复制' }}
          </button>
          <button class="action-btn" @click="$emit('close')">关闭</button>
        </div>
      </div>

      <!-- 内容 -->
      <div class="modal-body">
        <!-- 有数据 -->
        <template v-if="artifactData != null">
          <JsonViewer :data="artifactData" :max-length="2000" />
        </template>

        <!-- 无数据 -->
        <div v-else class="empty-artifact">
          <div class="empty-icon">📭</div>
          <div class="empty-text">该 Artifact 未采集</div>
          <div class="empty-desc">
            可能原因：partial trace、去重分支未走完整链路、或日志补全未配置。
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import JsonViewer from './JsonViewer.vue'
import { formatJsonString, stripMarkdownCodeBlock } from '../lib/formatters.js'

const props = defineProps({
  open: { type: Boolean, default: false },
  artifactKey: { type: String, default: '' },
  artifacts: { type: Object, default: () => ({}) },
})

defineEmits(['close'])

const copied = ref(false)

// 获取 artifact 数据
const artifactData = computed(() => {
  if (!props.artifactKey || !props.artifacts) return null
  return props.artifacts[props.artifactKey] ?? null
})

// 复制内容
async function copyContent() {
  try {
    let text = artifactData.value
    if (typeof text === 'string') {
      text = stripMarkdownCodeBlock(text)
    }
    const formatted = formatJsonString(text)
    await navigator.clipboard.writeText(formatted)
    copied.value = true
    setTimeout(() => { copied.value = false }, 2000)
  } catch (err) {
    console.error('复制失败:', err)
  }
}
</script>

<style scoped>
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  z-index: 50;
  display: flex;
  align-items: center;
  justify-content: center;
}

.modal-box {
  background: var(--bg-panel);
  border: 1px solid var(--border);
  border-radius: var(--radius-xl);
  width: 90%;
  max-width: 680px;
  max-height: 80vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-md) var(--space-lg);
  border-bottom: 1px solid var(--border);
  flex-shrink: 0;
}

.modal-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  font-family: var(--font-mono);
}

.modal-actions {
  display: flex;
  gap: var(--space-xs);
}

.action-btn {
  font-size: 12px;
  padding: 3px 10px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
}

.action-btn:hover {
  border-color: var(--accent-blue);
  color: var(--text-primary);
}

.copy-btn.copied {
  color: var(--accent-green);
  border-color: var(--accent-green);
}

.modal-body {
  padding: var(--space-md) var(--space-lg);
  overflow-y: auto;
  flex: 1;
}

.empty-artifact {
  text-align: center;
  padding: 40px 0;
  color: var(--text-muted);
}

.empty-icon {
  font-size: 32px;
  margin-bottom: var(--space-sm);
}

.empty-text {
  font-size: 14px;
  font-weight: 600;
  margin-bottom: var(--space-xs);
}

.empty-desc {
  font-size: 12px;
  color: var(--text-muted);
  max-width: 400px;
  margin: 0 auto;
  line-height: 1.6;
}
</style>
