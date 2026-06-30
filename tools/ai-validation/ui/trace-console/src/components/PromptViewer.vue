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
      <!-- 标签切换 + 历史版本 -->
      <div class="prompt-tabs">
        <button
          :class="{ on: activeTab === 'vision' }"
          @click="activeTab = 'vision'"
        >视觉识别 Prompt ({{ currentVisionChars }} 字)</button>
        <button
          :class="{ on: activeTab === 'feedback' }"
          @click="activeTab = 'feedback'"
        >文案生成 Prompt ({{ currentFeedbackChars }} 字)</button>
        <!-- 历史版本下拉 + 刷新按钮 -->
        <div class="prompt-toolbar">
          <select
            v-if="historyVersions.length > 0"
            v-model="selectedHistory"
            class="history-select"
            @change="onHistoryChange"
          >
            <option value="">当前版本</option>
            <option v-for="v in historyVersions" :key="v.file" :value="v.file">
              {{ formatHistoryLabel(v) }}
            </option>
          </select>
          <button
            class="refresh-btn"
            :disabled="refreshing"
            @click="onRefresh"
            :title="'从 prompts.ts 重新提取 prompt'"
          >{{ refreshing ? '刷新中...' : '刷新快照' }}</button>
        </div>
      </div>

      <!-- 视图切换：仅 Prompt / Prompt + 模型输出 -->
      <div class="view-toggle" v-if="hasModelOutput">
        <button
          :class="{ on: viewMode === 'prompt-only' }"
          @click="viewMode = 'prompt-only'"
        >只看 Prompt</button>
        <button
          :class="{ on: viewMode === 'comparison' }"
          @click="viewMode = 'comparison'"
        >Prompt + 模型输出</button>
      </div>

      <!-- 动态参数提示 -->
      <div class="dynamic-params-hint">
        <span class="hint-icon">ℹ️</span>
        <span class="hint-text">
          以下是静态 prompt 骨架。实际发送时附带动态参数（时间、记忆、人格等），详见 trace 的 model_context 和 user_context。
        </span>
      </div>

      <!-- ═══ Prompt 文本（分段高亮） ═══ -->
      <div class="section-label">
        <span class="label-arrow">▶</span> 发送给模型的 Prompt
        <button class="copy-prompt-btn" @click="copyPrompt">
          {{ copied ? '已复制' : '复制' }}
        </button>
      </div>
      <div class="prompt-text-area" :class="{ collapsed: viewMode === 'comparison' && promptCollapsed }">
        <pre class="prompt-pre" v-html="highlightedPrompt"></pre>
      </div>
      <button
        v-if="viewMode === 'comparison'"
        class="collapse-btn"
        @click="promptCollapsed = !promptCollapsed"
      >{{ promptCollapsed ? '展开 Prompt' : '收起 Prompt' }}</button>

      <!-- ═══ 模型实际输出 ═══ -->
      <div v-if="viewMode === 'comparison' && hasModelOutput" class="model-output-section">
        <div class="section-label output-label">
          <span class="label-arrow">▶</span> 模型实际输出
          <span class="output-meta" v-if="modelOutputMeta">{{ modelOutputMeta }}</span>
        </div>

        <!-- 视觉识别输出 -->
        <template v-if="activeTab === 'vision'">
          <div class="output-text-area">
            <pre class="output-pre" v-html="highlightedModelOutput"></pre>
          </div>
        </template>

        <!-- 文案生成输出（部分，完整输出待 V0.4） -->
        <template v-else>
          <div class="partial-output-notice">
            第二次调用的完整 JSON 输出待 V0.4 补全。当前展示最终文案结果：
          </div>
          <div class="feedback-output-cards" v-if="companionFinal || aiFeedbackFinal">
            <div class="feedback-row" v-if="companionFinal">
              <span class="feedback-label">companion_message:</span>
              <span class="feedback-value">{{ companionFinal }}</span>
            </div>
            <div class="feedback-row" v-if="aiFeedbackFinal">
              <span class="feedback-label">ai_feedback:</span>
              <pre class="feedback-json">{{ aiFeedbackFinal }}</pre>
            </div>
          </div>
          <div v-else class="no-feedback-data">无文案输出数据</div>
        </template>
      </div>

      <!-- 无模型输出提示 -->
      <div v-if="!hasModelOutput" class="no-output-hint">
        该 trace 未采集模型输出（可能是 partial trace 或去重分支）
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
import { ref, computed, onMounted } from 'vue'
import { fetchPrompt, fetchPromptHistory, fetchPromptHistoryFile, refreshPrompt } from '../lib/api.js'
import { stripMarkdownCodeBlock, formatJsonString } from '../lib/formatters.js'

const props = defineProps({
  artifacts: { type: Object, default: null },
})

const loading = ref(true)
const error = ref('')
const snapshot = ref(null)
const activeTab = ref('vision')
const searchKeyword = ref('')
const viewMode = ref('comparison')
const promptCollapsed = ref(false)
const copied = ref(false)
const historyVersions = ref([])
const selectedHistory = ref('')
const historySnapshot = ref(null) // 选中历史版本时的数据
const refreshing = ref(false)

async function onRefresh() {
  if (refreshing.value) return
  refreshing.value = true
  try {
    const { data, error } = await refreshPrompt()
    if (error) {
      console.error('刷新失败:', error)
      return
    }
    // 重新加载快照和历史版本
    selectedHistory.value = ''
    historySnapshot.value = null
    const { data: promptData } = await fetchPrompt()
    if (promptData) snapshot.value = promptData
    const { data: histData } = await fetchPromptHistory()
    if (histData?.versions) historyVersions.value = histData.versions
  } finally {
    refreshing.value = false
  }
}

async function copyPrompt() {
  try {
    await navigator.clipboard.writeText(currentPromptText.value)
    copied.value = true
    setTimeout(() => { copied.value = false }, 2000)
  } catch (err) {
    console.error('复制失败:', err)
  }
}

onMounted(async () => {
  const { data, error: err } = await fetchPrompt()
  loading.value = false
  if (err) {
    error.value = err
    return
  }
  snapshot.value = data

  // 加载历史版本列表
  const { data: histData } = await fetchPromptHistory()
  if (histData?.versions) {
    historyVersions.value = histData.versions
  }
})

// 当前展示的数据（当前版本或历史版本）
const activeData = computed(() => {
  return historySnapshot.value || snapshot.value
})

const currentVisionChars = computed(() => activeData.value?.vision_prompt?.char_count || 0)
const currentFeedbackChars = computed(() => activeData.value?.feedback_prompt?.char_count || 0)

async function onHistoryChange() {
  if (!selectedHistory.value) {
    historySnapshot.value = null
    return
  }
  const { data, error } = await fetchPromptHistoryFile(selectedHistory.value)
  if (error) {
    console.error('加载历史版本失败:', error)
    return
  }
  historySnapshot.value = data
}

function formatHistoryLabel(v) {
  const date = v.saved_at ? new Date(v.saved_at).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }) : v.file.slice(0, 8)
  const changes = []
  if (v.changes?.vision_changed) changes.push('视觉')
  if (v.changes?.feedback_changed) changes.push('文案')
  const changeLabel = changes.length > 0 ? ` [${changes.join('+')}]` : ''
  return `${date}${changeLabel}`
}

// ═══════════════════════════════════════════════
// Prompt 文本
// ═══════════════════════════════════════════════

const currentPromptText = computed(() => {
  if (!activeData.value) return ''
  return activeTab.value === 'vision'
    ? activeData.value.vision_prompt.full_text
    : activeData.value.feedback_prompt.full_text
})

const searchMatches = computed(() => {
  if (!searchKeyword.value || !currentPromptText.value) return 0
  const regex = new RegExp(searchKeyword.value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi')
  return (currentPromptText.value.match(regex) || []).length
})

const highlightedPrompt = computed(() => {
  let text = currentPromptText.value
  if (!text) return ''
  let escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
  escaped = escaped.replace(/【([^】]+)】/g, '<span class="prompt-section-title">【$1】</span>')
  escaped = escaped.replace(/"([a-z_]+)":/g, '<span class="prompt-json-key">"$1"</span>:')
  escaped = escaped.replace(/\[([^\]]+)\]/g, (match) => `<span class="prompt-enum">${match}</span>`)
  escaped = escaped.replace(/^- (.*)$/gm, (match, content) => {
    if (content.includes('禁止') || content.includes('不要') || content.includes('不得') || content.includes('必须')) {
      return `<span class="prompt-rule-strict">- ${content}</span>`
    }
    return match
  })
  if (searchKeyword.value) {
    const kw = searchKeyword.value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    escaped = escaped.replace(new RegExp(`(${kw})`, 'gi'), '<span class="prompt-search-hit">$1</span>')
  }
  return escaped
})

// ═══════════════════════════════════════════════
// 模型实际输出
// ═══════════════════════════════════════════════

// 视觉识别的模型输出（model_raw.text 或 extracted_json）
const visionModelOutput = computed(() => {
  if (!props.artifacts?.model_raw) return null
  const raw = props.artifacts.model_raw
  // 优先用 extracted_json（已剥离 markdown 代码块）
  if (raw.extracted_json) {
    return raw.extracted_json
  }
  if (raw.text) {
    return stripMarkdownCodeBlock(raw.text)
  }
  return null
})

// 文案生成的最终输出
const companionFinal = computed(() => {
  return props.artifacts?.companion?.final || null
})

const aiFeedbackFinal = computed(() => {
  const companion = props.artifacts?.companion
  if (!companion) return null
  // 尝试从 trace 的 user_visible_outputs 中找 ai_feedback
  // 这里 artifacts.companion 可能只有 final 文本
  return null
})

// 是否有模型输出可展示
const hasModelOutput = computed(() => {
  if (activeTab.value === 'vision') {
    return visionModelOutput.value != null
  }
  return companionFinal.value != null
})

// 模型输出元信息
const modelOutputMeta = computed(() => {
  if (activeTab.value === 'vision') {
    const raw = props.artifacts?.model_raw
    if (!raw) return ''
    const parts = []
    if (raw.finish_reason) parts.push(`finish: ${raw.finish_reason}`)
    if (raw.response_id) parts.push(`id: ${raw.response_id.slice(0, 16)}...`)
    return parts.join(' · ')
  }
  return ''
})

// 高亮后的模型输出
const highlightedModelOutput = computed(() => {
  const text = visionModelOutput.value
  if (!text) return ''

  // 尝试格式化为 JSON
  let formatted = text
  try {
    const parsed = typeof text === 'string' ? JSON.parse(text) : text
    formatted = JSON.stringify(parsed, null, 2)
  } catch {
    formatted = String(text)
  }

  // HTML 转义
  let escaped = formatted
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

  // JSON 语法高亮
  escaped = escaped.replace(/"([^"]+)":/g, '<span class="out-json-key">"$1"</span>:')
  escaped = escaped.replace(/: "([^"]*)"/g, ': <span class="out-json-str">"$1"</span>')
  escaped = escaped.replace(/: (-?\d+\.?\d*)/g, ': <span class="out-json-num">$1</span>')
  escaped = escaped.replace(/: (true|false|null)/g, ': <span class="out-json-bool">$1</span>')

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

.history-select {
  font-size: 11px;
  padding: 2px 6px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  font-family: var(--font-sans);
  outline: none;
  cursor: pointer;
  max-width: 180px;
}

.history-select:focus {
  border-color: var(--accent-blue);
}

.prompt-toolbar {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.refresh-btn {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: var(--radius-sm);
  background: var(--accent-green);
  color: #fff;
  border: none;
  cursor: pointer;
  font-family: var(--font-sans);
  white-space: nowrap;
  transition: opacity 0.12s;
}

.refresh-btn:hover:not(:disabled) {
  opacity: 0.85;
}

.refresh-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.view-toggle {
  display: inline-flex;
  background: var(--bg-base);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 2px;
  align-self: flex-start;
}

.view-toggle button {
  padding: 2px 8px;
  border: none;
  background: transparent;
  color: var(--text-secondary);
  font-size: 11px;
  border-radius: var(--radius-sm);
  cursor: pointer;
  font-family: var(--font-sans);
}

.view-toggle button.on {
  background: var(--accent-purple);
  color: #fff;
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

.section-label {
  font-size: 11px;
  font-weight: 700;
  color: var(--text-secondary);
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.copy-prompt-btn {
  margin-left: auto;
  font-size: 10px;
  padding: 2px 8px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--accent-blue);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  transition: all 0.12s;
}

.copy-prompt-btn:hover {
  border-color: var(--accent-blue);
}

.section-label.output-label {
  color: var(--accent-green);
}

.label-arrow {
  font-size: 9px;
}

.output-meta {
  font-size: 10px;
  color: var(--text-muted);
  font-weight: 400;
  margin-left: auto;
}

.prompt-text-area {
  background: #0a0e14;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: var(--space-sm) var(--space-md);
  max-height: 400px;
  overflow-y: auto;
  transition: max-height 0.2s;
}

.prompt-text-area.collapsed {
  max-height: 80px;
  overflow: hidden;
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

.collapse-btn {
  font-size: 10px;
  padding: 2px 8px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  align-self: flex-start;
}

.collapse-btn:hover {
  border-color: var(--accent-blue);
}

/* 模型输出区域 */
.model-output-section {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
  margin-top: var(--space-sm);
  padding-top: var(--space-sm);
  border-top: 1px dashed var(--border);
}

.output-text-area {
  background: #0a0e14;
  border: 1px solid var(--accent-green);
  border-radius: var(--radius-sm);
  padding: var(--space-sm) var(--space-md);
  max-height: 400px;
  overflow-y: auto;
}

.output-pre {
  white-space: pre-wrap;
  word-break: break-all;
  margin: 0;
  font-family: var(--font-mono);
  font-size: 11px;
  line-height: 1.6;
  color: var(--text-secondary);
}

.partial-output-notice {
  font-size: 10px;
  color: var(--accent-yellow);
  padding: var(--space-xs) var(--space-sm);
  background: rgba(210, 153, 34, 0.07);
  border-radius: var(--radius-sm);
  border: 1px solid rgba(210, 153, 34, 0.2);
}

.feedback-output-cards {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.feedback-row {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: var(--space-xs) var(--space-sm);
  background: #0a0e14;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
}

.feedback-label {
  font-size: 10px;
  color: var(--text-muted);
  font-family: var(--font-mono);
}

.feedback-value {
  font-size: 12px;
  color: var(--text-primary);
}

.feedback-json {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--text-secondary);
  white-space: pre-wrap;
  margin: 0;
}

.no-feedback-data,
.no-output-hint {
  font-size: 11px;
  color: var(--text-muted);
  font-style: italic;
  padding: var(--space-xs) 0;
}

/* Prompt 高亮 */
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

/* 模型输出高亮 */
:deep(.out-json-key) {
  color: var(--accent-blue);
}

:deep(.out-json-str) {
  color: var(--accent-green);
}

:deep(.out-json-num) {
  color: var(--accent-purple);
}

:deep(.out-json-bool) {
  color: var(--accent-yellow);
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
