<template>
  <div class="json-viewer">
    <!-- 展开模式 -->
    <div class="json-content" v-if="!truncated || expanded">
      <pre class="json-pre" v-html="highlightedJson"></pre>
    </div>
    <!-- 截断模式 -->
    <div v-else>
      <pre class="json-pre" v-html="highlightedJson"></pre>
      <div class="truncate-notice">
        ... 已截断，共 {{ fullLength }} 字符
        <button class="expand-btn" @click="expanded = true">展开全文</button>
      </div>
    </div>
    <!-- 收起按钮 -->
    <div v-if="truncated && expanded" class="truncate-notice">
      <button class="expand-btn" @click="expanded = false">收起</button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { formatJsonString, truncateText, stripMarkdownCodeBlock } from '../lib/formatters.js'

const props = defineProps({
  data: { type: [Object, String, null], default: null },
  maxLength: { type: Number, default: 2000 },
})

const expanded = ref(false)

// 当 data 变化时重置展开状态
watch(() => props.data, () => { expanded.value = false })

// 处理数据：剥离 markdown 代码块，格式化 JSON
const processedText = computed(() => {
  if (props.data == null) return 'null'

  let text = props.data

  // 如果是字符串，先剥离 markdown 代码块
  if (typeof text === 'string') {
    text = stripMarkdownCodeBlock(text)
  }

  // 格式化为 JSON
  return formatJsonString(text)
})

// 截断处理
const truncationResult = computed(() => {
  return truncateText(processedText.value, props.maxLength)
})

const truncated = computed(() => truncationResult.value.truncated)
const fullLength = computed(() => truncationResult.value.fullLength)

// 语法高亮
const highlightedJson = computed(() => {
  const text = truncated.value && !expanded.value
    ? truncationResult.value.text
    : processedText.value

  if (!text) return '<span style="color:var(--text-muted)">null</span>'

  // HTML 转义
  let escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

  // 语法高亮
  return escaped
    .replace(/"([^"]+)":/g, '<span class="jk">"$1"</span>:')
    .replace(/: "([^"]*)"/g, ': <span class="js">"$1"</span>')
    .replace(/: (-?\d+\.?\d*)/g, ': <span class="jn">$1</span>')
    .replace(/: (true|false|null)/g, ': <span class="jb">$1</span>')
})
</script>

<style scoped>
.json-viewer {
  background: #0a0e14;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: var(--space-sm) var(--space-md);
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.5;
  color: var(--text-secondary);
  max-height: 300px;
  overflow-y: auto;
}

.json-pre {
  white-space: pre-wrap;
  word-break: break-all;
  margin: 0;
}

:deep(.jk) {
  color: var(--accent-blue);
}

:deep(.js) {
  color: var(--accent-green);
}

:deep(.jn) {
  color: var(--accent-purple);
}

:deep(.jb) {
  color: var(--accent-yellow);
}

.truncate-notice {
  margin-top: var(--space-sm);
  padding-top: var(--space-sm);
  border-top: 1px dashed var(--border);
  font-size: 11px;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.expand-btn {
  background: var(--bg-hover);
  color: var(--accent-blue);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 2px 8px;
  font-size: 11px;
  cursor: pointer;
  font-family: var(--font-sans);
}

.expand-btn:hover {
  border-color: var(--accent-blue);
}
</style>
