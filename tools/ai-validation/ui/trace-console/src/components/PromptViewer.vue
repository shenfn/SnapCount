<template>
  <div class="prompt-viewer">
    <!-- 加载中 -->
    <div v-if="loading" class="prompt-loading">
      加载 Prompt 文本...
    </div>

    <!-- 加载失败 -->
    <div v-else-if="error" class="prompt-error">
      <span>⚠️ {{ error }}</span>
      <div class="error-hint">请运行 npm run trace:extract-prompt 生成快照</div>
    </div>

    <!-- 已加载 -->
    <div v-else-if="snapshot" class="prompt-content">
      <!-- 标签切换 -->
      <div class="prompt-tabs">
        <button
          :class="{ on: activeTab === 'vision' }"
          @click="activeTab = 'vision'"
        >视觉识别 Prompt ({{ snapshot.vision_prompt.char_count }} 字)</button>
        <button
          :class="{ on: activeTab === 'feedback' }"
          @click="activeTab = 'feedback'"
        >文案生成 Prompt ({{ snapshot.feedback_prompt.char_count }} 字)</button>
      </div>

      <!-- 动态参数提示 -->
      <div class="dynamic-params-hint">
        <span class="hint-icon">ℹ️</span>
        <span class="hint-text">
          以下是静态 prompt 骨架。实际发送时附带动态参数（时间、记忆、人格等），详见 trace 的 model_context 和 user_context。
        </span>
      </div>

      <!-- Prompt 文本（分段高亮） -->
      <div class="prompt-text-area">
        <pre class="prompt-pre" v-html="highlightedPrompt"></pre>
      </div>

      <!-- 搜索 -->
      <div class="search-bar">
        <input
          v-model="searchKeyword"
          class="search-input"
          placeholder="搜索关键词..."
        />
        <span class="search-count" v-if="searchKeyword">
          {{ searchMatches }} 处匹配
        </span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { fetchPrompt } from '../lib/api.js'

const loading = ref(true)
const error = ref('')
const snapshot = ref(null)
const activeTab = ref('vision')
const searchKeyword = ref('')

onMounted(async () => {
  const { data, error: err } = await fetchPrompt()
  loading.value = false
  if (err) {
    error.value = err
    return
  }
  snapshot.value = data
})

// 当前展示的 prompt 文本
const currentPromptText = computed(() => {
  if (!snapshot.value) return ''
  return activeTab.value === 'vision'
    ? snapshot.value.vision_prompt.full_text
    : snapshot.value.feedback_prompt.full_text
})

// 搜索匹配数
const searchMatches = computed(() => {
  if (!searchKeyword.value || !currentPromptText.value) return 0
  const regex = new RegExp(searchKeyword.value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi')
  return (currentPromptText.value.match(regex) || []).length
})

// 高亮后的 prompt 文本
const highlightedPrompt = computed(() => {
  let text = currentPromptText.value
  if (!text) return ''

  // HTML 转义
  let escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

  // 高亮【】标记的段落标题
  escaped = escaped.replace(/【([^】]+)】/g, '<span class="prompt-section-title">【$1】</span>')

  // 高亮 JSON 字段名（"field":）
  escaped = escaped.replace(/"([a-z_]+)":/g, '<span class="prompt-json-key">"$1"</span>:')

  // 高亮枚举值（从 [...] 中选一个）
  escaped = escaped.replace(/\[([^\]]+)\]/g, (match) => {
    return `<span class="prompt-enum">${match}</span>`
  })

  // 高亮禁止项（以 - 开头的禁止规则）
  escaped = escaped.replace(/^- (.*)$/gm, (match, content) => {
    if (content.includes('禁止') || content.includes('不要') || content.includes('不得') || content.includes('必须')) {
      return `<span class="prompt-rule-strict">- ${content}</span>`
    }
    return match
  })

  // 搜索关键词高亮
  if (searchKeyword.value) {
    const kw = searchKeyword.value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    escaped = escaped.replace(new RegExp(`(${kw})`, 'gi'), '<span class="prompt-search-hit">$1</span>')
  }

  return escaped
})
</script>

<style scoped>
.prompt-viewer {
  display: flex;
  flex-direction: column;
  gap: var(--space-sm);
}

.prompt-loading,
.prompt-error {
  padding: var(--space-md);
  font-size: 12px;
  color: var(--text-muted);
  text-align: center;
}

.prompt-error {
  color: var(--accent-red);
}

.error-hint {
  margin-top: var(--space-xs);
  font-size: 11px;
  color: var(--text-muted);
}

.prompt-tabs {
  display: flex;
  gap: var(--space-xs);
}

.prompt-tabs button {
  font-size: 11px;
  padding: 3px 10px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  transition: all 0.12s;
}

.prompt-tabs button.on {
  background: var(--accent-blue);
  color: #fff;
  border-color: var(--accent-blue);
}

.prompt-tabs button:hover:not(.on) {
  border-color: var(--accent-blue);
}

.dynamic-params-hint {
  display: flex;
  align-items: flex-start;
  gap: var(--space-xs);
  padding: var(--space-xs) var(--space-sm);
  border-radius: var(--radius-sm);
  background: rgba(88, 166, 255, 0.07);
  border: 1px solid rgba(88, 166, 255, 0.15);
  font-size: 11px;
  color: var(--text-secondary);
  line-height: 1.5;
}

.hint-icon {
  flex-shrink: 0;
}

.prompt-text-area {
  background: #0a0e14;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: var(--space-sm) var(--space-md);
  max-height: 400px;
  overflow-y: auto;
}

.prompt-pre {
  white-space: pre-wrap;
  word-break: break-all;
  margin: 0;
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.6;
  color: var(--text-secondary);
}

:deep(.prompt-section-title) {
  color: var(--accent-blue);
  font-weight: 700;
}

:deep(.prompt-json-key) {
  color: var(--accent-purple);
}

:deep(.prompt-enum) {
  color: var(--accent-green);
}

:deep(.prompt-rule-strict) {
  color: var(--accent-red);
}

:deep(.prompt-search-hit) {
  background: rgba(210, 153, 34, 0.3);
  color: var(--accent-yellow);
  border-radius: 2px;
  padding: 0 2px;
}

.search-bar {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.search-input {
  flex: 1;
  background: var(--bg-hover);
  color: var(--text-primary);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 3px 8px;
  font-size: 11px;
  font-family: var(--font-sans);
  outline: none;
}

.search-input:focus {
  border-color: var(--accent-blue);
}

.search-input::placeholder {
  color: var(--text-muted);
}

.search-count {
  font-size: 11px;
  color: var(--text-muted);
  white-space: nowrap;
}
</style>
