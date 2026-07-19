<template>
  <!-- 遮罩 -->
  <div class="upload-mask" v-if="open" @click="$emit('close')"></div>

  <!-- 面板 -->
  <div class="upload-panel" :class="{ open: open }">
    <div class="panel-header">
      <span class="panel-title">上传测试</span>
      <button class="close-btn" @click="$emit('close')">关闭</button>
    </div>

    <div class="panel-body">
      <!-- 远程模式账号提示 -->
      <div class="remote-account-banner" v-if="mode === 'remote' && accountLabel">
        当前使用账号：<strong>{{ accountLabel }}</strong>
        <span class="banner-hint">上传将走真实 EF，使用该账号的 upload_token</span>
      </div>

      <!-- ═══ 空闲状态：选择图片 ═══ -->
      <template v-if="status === 'idle'">
        <!-- 模式切换 -->
        <div class="mode-toggle">
          <label class="mode-option">
            <input type="radio" v-model="simulateMode" :value="false" />
            <span>线上验证（走 Edge Function）</span>
          </label>
          <label class="mode-option">
            <input type="radio" v-model="simulateMode" :value="true" />
            <span>本地模拟（直接调 qwen，不部署）</span>
          </label>
        </div>

        <!-- 本地模拟说明 -->
        <div class="mode-hint" v-if="simulateMode">
          本地模拟使用当前 prompts.ts 的 prompt 直接调用 qwen API，不经过 Edge Function。
          改完 prompt 后运行 <code>npm run trace:extract-prompt</code> 即可验证，无需部署。
        </div>

        <!-- 粘贴区 -->
        <div
          class="paste-zone"
          :class="{ active: pasteZoneActive }"
          @paste="onPaste"
          @dragover.prevent="pasteZoneActive = true"
          @dragleave="pasteZoneActive = false"
          @drop.prevent="onDrop"
          tabindex="0"
        >
          <div class="paste-icon">📋</div>
          <div class="paste-text">点击此处后 Ctrl+V 粘贴图片</div>
          <div class="paste-hint">或拖拽图片到此区域</div>
        </div>

        <!-- 分隔线 -->
        <div class="divider">或</div>

        <!-- 文件选择 -->
        <div class="file-section">
          <button class="file-btn" @click="pickFile">选择图片文件</button>
          <span class="file-name" v-if="selectedFileName">{{ selectedFileName }}</span>
        </div>

        <!-- 预览 -->
        <div class="preview-area" v-if="previewUrl">
          <img :src="previewUrl" class="preview-img" />
        </div>

        <!-- run_id 输入（始终显示） -->
        <div class="run-id-section">
          <label class="run-id-label">{{ simulateMode ? '模拟批次 ID:' : '批次 ID:' }}</label>
          <input
            v-model="runId"
            class="run-id-input"
            :placeholder="simulateMode ? 'manual-sim-YYYYMMDD' : 'manual-check-YYYYMMDD'"
          />
        </div>

        <!-- 关 thinking 开关（仅本地模拟模式） -->
        <div class="thinking-toggle" v-if="simulateMode">
          <label class="thinking-option">
            <input type="checkbox" v-model="noVisionThinking" />
            <span>极速模式（关闭深度思考，更快但可能不准）</span>
          </label>
        </div>

        <!-- 模型选择（仅本地模拟模式） -->
        <div class="model-select-row" v-if="simulateMode">
          <div class="model-select-item">
            <label class="model-label">视觉模型</label>
            <select v-model="visionModel" class="model-select">
              <option v-for="opt in VISION_MODEL_OPTIONS" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
            </select>
          </div>
          <div class="model-select-item">
            <label class="model-label">文案模型</label>
            <select v-model="feedbackModel" class="model-select">
              <option v-for="opt in FEEDBACK_MODEL_OPTIONS" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
            </select>
          </div>
        </div>

        <!-- 上传按钮 -->
        <button
          class="start-btn"
          :disabled="!canStart"
          @click="startUpload"
        >{{ simulateMode ? '开始模拟' : '开始上传' }}</button>
      </template>

      <!-- ═══ 进行中状态 ═══ -->
      <template v-else-if="status === 'running'">
        <div class="progress-area">
          <div class="progress-icon">⏳</div>
          <div class="progress-step">{{ stepLabel }}</div>
          <div class="progress-elapsed">已用 {{ Math.round(elapsed / 1000) }}s</div>
          <div class="progress-log">
            <div
              v-for="(line, idx) in progressOutput"
              :key="idx"
              class="log-line"
              :class="{ stderr: line.startsWith('[stderr]') }"
            >{{ line }}</div>
          </div>
        </div>
      </template>

      <!-- ═══ 线上验证完成 ═══ -->
      <template v-else-if="status === 'done' && !simulateMode">
        <div class="result-area">
          <div class="result-icon">✅</div>
          <div class="result-title">识别完成</div>
          <div class="result-meta" v-if="resultCaseKey">
            case: <code>{{ resultCaseKey }}</code>
          </div>
          <button class="result-btn" @click="onViewResult">查看结果</button>
        </div>
      </template>

      <!-- ═══ 本地模拟完成 - 结构化展示 ═══ -->
      <template v-else-if="status === 'done' && simulateMode">
        <div class="sim-result-area">
          <div class="result-icon">✅</div>
          <div class="result-title">模拟完成（{{ Math.round(elapsed / 1000) }}s）</div>

          <!-- 原图预览 - 方便对比模型输出和图片细节 -->
          <div class="sim-section" v-if="previewUrl">
            <div class="sim-section-title">原图 <span class="sim-section-hint">点击图片放大/缩小</span></div>
            <img
              :src="previewUrl"
              class="sim-preview-img"
              :class="{ enlarged: previewEnlarged }"
              @click="previewEnlarged = !previewEnlarged"
            />
          </div>

          <!-- 解析状态 -->
          <div class="sim-section">
            <div class="sim-section-title">
              解析状态
              <span class="parse-badge" :class="simResult?.vision_output?.parsed ? 'ok' : 'fail'">
                {{ simResult?.vision_output?.parsed ? '视觉OK' : (simResult?.vision_output?.truncated ? '思考截断' : '视觉解析失败') }}
              </span>
              <span v-if="simResult?.vision_output?.truncated" class="parse-badge warn">
                {{ simResult?.vision_output?.usage?.completion_tokens || '?' }} tokens 已用完
              </span>
              <span v-if="simResult?.feedback_output?.parsed" class="parse-badge ok">文案OK</span>
            </div>
          </div>

          <!-- 视觉识别输出 -->
          <div class="sim-section">
            <div class="sim-section-title">视觉识别输出 <span class="sim-model">{{ simResult?.vision_output?.model || '' }}</span></div>
            <template v-if="simResult?.vision_output?.parsed">
              <div class="field-grid">
                <div class="field-item" v-if="simResult.vision_output.parsed.record_type">
                  <span class="field-label">record_type</span>
                  <span class="field-value">{{ simResult.vision_output.parsed.record_type }}</span>
                </div>
                <div class="field-item" v-if="simResult.vision_output.parsed.domain_key">
                  <span class="field-label">domain_key</span>
                  <span class="field-value">{{ simResult.vision_output.parsed.domain_key }}</span>
                </div>
                <div class="field-item" v-if="simResult.vision_output.parsed.amount != null">
                  <span class="field-label">amount</span>
                  <span class="field-value">{{ simResult.vision_output.parsed.amount }}</span>
                </div>
                <div class="field-item" v-if="simResult.vision_output.parsed.title">
                  <span class="field-label">title</span>
                  <span class="field-value">{{ simResult.vision_output.parsed.title }}</span>
                </div>
                <div class="field-item" v-if="simResult.vision_output.parsed.confidence != null">
                  <span class="field-label">confidence</span>
                  <span class="field-value">{{ simResult.vision_output.parsed.confidence }}</span>
                </div>
              </div>
              <details class="raw-json-details">
                <summary>完整 JSON</summary>
                <pre class="sim-json">{{ formatJson(simResult?.vision_output?.parsed) }}</pre>
              </details>
            </template>
            <template v-else>
              <div class="parse-error-box">
                <!-- 截断提示 -->
                <div class="parse-error-label" v-if="simResult?.vision_output?.truncated">
                  ⚠️ 模型思考过程过长（{{ simResult?.vision_output?.finish_reason }}），用完了 {{ simResult?.vision_output?.usage?.completion_tokens || '?' }} token 配额，JSON 答案未输出。
                  <br />建议：关闭深度思考（极速模式），或换用更简单的图片测试。
                </div>
                <div class="parse-error-label" v-else>JSON 解析失败，原始输出：</div>

                <!-- 思考过程（如果单独存在） -->
                <details class="raw-json-details" v-if="simResult?.vision_output?.reasoning_text">
                  <summary>模型思考过程（{{ simResult.vision_output.reasoning_text.length }} 字）</summary>
                  <pre class="sim-json">{{ simResult.vision_output.reasoning_text.slice(0, 3000) }}</pre>
                </details>

                <!-- 原始输出 -->
                <details class="raw-json-details" v-if="simResult?.vision_output?.raw_text">
                  <summary>message.content 原始输出</summary>
                  <pre class="sim-json error">{{ simResult.vision_output.raw_text.slice(0, 2000) }}</pre>
                </details>
                <pre class="sim-json error" v-if="!simResult?.vision_output?.reasoning_text && !simResult?.vision_output?.raw_text">无输出</pre>
              </div>
            </template>
          </div>

          <!-- 文案生成输出 -->
          <div class="sim-section" v-if="simResult?.feedback_output">
            <div class="sim-section-title">文案生成输出 <span class="sim-model">{{ simResult?.feedback_output?.model || '' }}</span></div>
            <template v-if="simResult?.feedback_output?.parsed">
              <div class="field-grid">
                <div class="field-item" v-if="simResult.feedback_output.parsed.companion_message">
                  <span class="field-label">companion_message</span>
                  <span class="field-value">{{ simResult.feedback_output.parsed.companion_message }}</span>
                </div>
                <div class="field-item" v-if="simResult.feedback_output.parsed.ai_feedback?.badge">
                  <span class="field-label">badge</span>
                  <span class="field-value">{{ simResult.feedback_output.parsed.ai_feedback.badge }}</span>
                </div>
                <div class="field-item" v-if="simResult.feedback_output.parsed.ai_feedback?.band">
                  <span class="field-label">band</span>
                  <span class="field-value">{{ simResult.feedback_output.parsed.ai_feedback.band }}</span>
                </div>
                <div class="field-item" v-if="simResult.feedback_output.parsed.ai_feedback?.emotion_line">
                  <span class="field-label">emotion_line</span>
                  <span class="field-value">{{ simResult.feedback_output.parsed.ai_feedback.emotion_line }}</span>
                </div>
                <div class="field-item" v-if="simResult.feedback_output.parsed.ai_feedback?.utility_line">
                  <span class="field-label">utility_line</span>
                  <span class="field-value">{{ simResult.feedback_output.parsed.ai_feedback.utility_line }}</span>
                </div>
              </div>
              <details class="raw-json-details">
                <summary>完整 JSON</summary>
                <pre class="sim-json">{{ formatJson(simResult?.feedback_output?.parsed) }}</pre>
              </details>
            </template>
            <template v-else>
              <div class="parse-error-box">
                <div class="parse-error-label">JSON 解析失败，原始输出：</div>
                <pre class="sim-json error">{{ simResult?.feedback_output?.raw_text?.slice(0, 2000) || '无输出' }}</pre>
              </div>
            </template>
          </div>

          <!-- Token 使用 -->
          <div class="sim-section" v-if="simResult?.vision_output?.usage || simResult?.feedback_output?.usage">
            <div class="sim-section-title">Token 使用</div>
            <div class="token-info">
              <span v-if="simResult?.vision_output?.usage">
                视觉: {{ simResult.vision_output.usage.total_tokens || '?' }} tokens
              </span>
              <span v-if="simResult?.feedback_output?.usage">
                文案: {{ simResult.feedback_output.usage.total_tokens || '?' }} tokens
              </span>
            </div>
          </div>

          <!-- 点评面板 - 内嵌模式，可折叠 -->
          <ReviewPanel
            v-if="resultCaseKey"
            embedded
            :open="true"
            :run-id="runId"
            :case-key="resultCaseKey"
            mode="local-simulate"
            :sim-snapshot="simSnapshot"
            @saved="onReviewSaved"
          />

          <div class="sim-actions">
            <button class="result-btn" @click="onViewResult">查看结果</button>
            <button class="reset-btn" @click="reset">再次模拟</button>
          </div>
        </div>
      </template>

      <!-- ═══ 错误状态 ═══ -->
      <template v-else-if="status === 'error'">
        <div class="result-area">
          <div class="result-icon">❌</div>
          <div class="result-title">执行失败</div>
          <div class="error-detail">{{ errorMsg }}</div>
          <div class="progress-log" v-if="progressOutput.length > 0">
            <div
              v-for="(line, idx) in progressOutput"
              :key="idx"
              class="log-line"
              :class="{ stderr: line.startsWith('[stderr]') }"
            >{{ line }}</div>
          </div>
          <button class="result-btn" @click="reset">重新上传</button>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onUnmounted } from 'vue'
import { uploadTest, fetchUploadStatus, localSimulate, fetchSimulateStatus } from '../lib/api.js'
import ReviewPanel from './ReviewPanel.vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  accountKey: { type: String, default: '' },
  accounts: { type: Array, default: () => [] },
  mode: { type: String, default: 'local' }, // 'local' | 'remote'
})

const emit = defineEmits(['close', 'completed', 'simulated'])

// 远程模式：当前账号标签
const accountLabel = computed(() => {
  const acc = props.accounts.find(a => a.key === props.accountKey)
  return acc?.label || ''
})

// 状态
const status = ref('idle') // idle | running | done | error
const simulateMode = ref(false) // false=线上, true=本地模拟
const pasteZoneActive = ref(false)
const previewUrl = ref(null)
const selectedFileName = ref('')
const selectedFileData = ref(null)
const runId = ref('')
const elapsed = ref(0)
const progressOutput = ref([])
const progressStep = ref('starting')
const errorMsg = ref('')
const resultCaseKey = ref('')
const simResult = ref(null)
const previewEnlarged = ref(false)
const noVisionThinking = ref(false)
const visionModel = ref('')
const feedbackModel = ref('')

// 模型选项
const VISION_MODEL_OPTIONS = [
  { value: '', label: '默认（qwen3.6-flash）' },
  { value: 'qwen3.6-flash', label: 'qwen3.6-flash（快速）' },
  { value: 'qwen3.7-plus', label: 'qwen3.7-plus（质量）' },
  { value: 'qwen-vl-plus', label: 'qwen-vl-plus（经典）' },
  { value: 'qwen-vl-max', label: 'qwen-vl-max（最强）' },
]
const FEEDBACK_MODEL_OPTIONS = [
  { value: '', label: '默认（qwen-plus）' },
  { value: 'qwen-plus', label: 'qwen-plus（推荐）' },
  { value: 'qwen3.6-flash', label: 'qwen3.6-flash（快速）' },
  { value: 'qwen-max', label: 'qwen-max（最强）' },
]

// 默认 runId
const today = new Date().toISOString().slice(0, 10).replace(/-/g, '')
runId.value = `manual-check-${today}`

// 模拟模式切换时更新默认 runId
watch(simulateMode, (newVal) => {
  if (newVal && (!runId.value || runId.value.startsWith('manual-check-'))) {
    runId.value = `manual-sim-${today}`
  } else if (!newVal && (!runId.value || runId.value.startsWith('manual-sim-'))) {
    runId.value = `manual-check-${today}`
  }
})

const canStart = computed(() => selectedFileData.value != null)

const stepLabel = computed(() => {
  const labels = {
    starting: '启动中...',
    uploading: '上传图片中...',
    recognizing: 'AI 识别中...',
    generating: '文案生成中...',
    saving: '保存结果中...',
    moving: '归档图片中...',
  }
  return labels[progressStep.value] || '处理中...'
})

let pollTimer = null
let elapsedTimer = null

// ═══════════════════════════════════════════════
// 粘贴 / 拖拽 / 文件选择
// ═══════════════════════════════════════════════

function onPaste(e) {
  const items = e.clipboardData?.items
  if (!items) return
  for (const item of items) {
    if (item.type.startsWith('image/')) {
      const file = item.getAsFile()
      if (file) loadFile(file)
    }
  }
}

function onDrop(e) {
  pasteZoneActive.value = false
  const files = e.dataTransfer?.files
  if (files && files.length > 0) {
    const file = files[0]
    if (file.type.startsWith('image/')) loadFile(file)
  }
}

function pickFile() {
  const input = document.createElement('input')
  input.type = 'file'
  input.accept = 'image/*'
  input.onchange = (e) => {
    const file = e.target.files[0]
    if (file) loadFile(file)
  }
  input.click()
}

function loadFile(file) {
  const reader = new FileReader()
  reader.onload = (e) => {
    previewUrl.value = e.target.result
    const base64 = e.target.result.split(',')[1]
    selectedFileData.value = { mode: 'paste', imageBase64: base64 }
    selectedFileName.value = file.name || 'pasted-image.png'
  }
  reader.readAsDataURL(file)
}

// ═══════════════════════════════════════════════
// 开始上传 / 模拟
// ═══════════════════════════════════════════════

async function startUpload() {
  if (!canStart.value) return
  status.value = 'running'
  progressStep.value = 'starting'
  elapsed.value = 0
  progressOutput.value = []
  simResult.value = null

  if (simulateMode.value) {
    await startSimulate()
  } else {
    await startOnlineUpload()
  }
}

// 线上上传
async function startOnlineUpload() {
  const payload = { ...selectedFileData.value, runId: runId.value }
  // 远程模式：传入 accountKey，使用该账号的 upload_token
  if (props.mode === 'remote' && props.accountKey) {
    payload.accountKey = props.accountKey
  }
  const { data, error } = await uploadTest(payload)
  if (error) {
    status.value = 'error'
    errorMsg.value = error
    return
  }
  startPolling(data.jobId, false)
  startElapsedTimer()
}

// 本地模拟
async function startSimulate() {
  const payload = {
    ...selectedFileData.value,
    noVisionThinking: noVisionThinking.value,
    visionModel: visionModel.value || null,
    feedbackModel: feedbackModel.value || null,
  }
  const { data, error } = await localSimulate(payload)
  if (error) {
    status.value = 'error'
    errorMsg.value = error
    return
  }
  startPolling(data.jobId, true)
  startElapsedTimer()
}

// ═══════════════════════════════════════════════
// 轮询
// ═══════════════════════════════════════════════

function startPolling(jobId, isSimulate) {
  pollTimer = setInterval(async () => {
    const { data, error } = isSimulate
      ? await fetchSimulateStatus(jobId)
      : await fetchUploadStatus(jobId)

    if (error) {
      stopPolling()
      status.value = 'error'
      errorMsg.value = error
      return
    }

    progressStep.value = data.step
    progressOutput.value = data.output || []

    if (data.status === 'done') {
      stopPolling()
      stopElapsedTimer()
      status.value = 'done'
      if (isSimulate) {
        // 本地模拟完成：保留面板展示结果和点评
        // simResult 用于即时展示，runId/caseKey 用于静默落盘
        // 不 emit completed，不关闭面板，让用户在面板内点评
        simResult.value = data.result
        resultCaseKey.value = data.traceCaseKey
        if (data.runId) runId.value = data.runId
        // 通知 App.vue 已有新 trace（静默刷新批次列表，但不跳转）
        emit('simulated', { runId: data.runId, caseKey: data.traceCaseKey })
      } else {
        // 线上验证完成：也保留面板，用户点"查看结果"才跳转
        resultCaseKey.value = data.traceCaseKey
        emit('simulated', { runId: data.runId, caseKey: data.traceCaseKey })
      }
    } else if (data.status === 'error') {
      stopPolling()
      stopElapsedTimer()
      status.value = 'error'
      errorMsg.value = data.error || '未知错误'
    }
  }, 2000)
}

function stopPolling() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
}

function startElapsedTimer() {
  const startTime = Date.now()
  elapsedTimer = setInterval(() => { elapsed.value = Date.now() - startTime }, 1000)
}

function stopElapsedTimer() {
  if (elapsedTimer) { clearInterval(elapsedTimer); elapsedTimer = null }
}

// ═══════════════════════════════════════════════
// 操作
// ═══════════════════════════════════════════════

// 本地模拟的 caseKey（用于点评）— 追加时间戳防覆盖，支持同一张图多次对比
const simCaseKey = computed(() => {
  if (!simResult.value?.vision_output?.parsed) return ''
  const parsed = simResult.value.vision_output.parsed
  const domain = parsed.domain_key || parsed.record_type || 'uncertain'
  const fileName = selectedFileName.value.replace(/\.[^.]+$/, '') || 'unknown'
  const dateStr = new Date().toISOString().slice(0, 10)
  const timeStr = new Date().toTimeString().slice(0, 8).replace(/:/g, '')
  return `single/${domain}/${dateStr}/${fileName}-${timeStr}`
})

// 点评快照（精简版，只存关键字段摘要）
const simSnapshot = computed(() => {
  if (!simResult.value) return null
  const vp = simResult.value.vision_output?.parsed
  const fp = simResult.value.feedback_output?.parsed
  return {
    elapsed_ms: simResult.value.elapsed_ms || 0,
    vision_model: simResult.value.vision_output?.model || '',
    vision_parse_ok: simResult.value.vision_output?.parse_ok ?? false,
    vision_thinking_enabled: simResult.value.vision_thinking_enabled !== false,
    feedback_model: simResult.value.feedback_output?.model || '',
    image_file_name: selectedFileName.value || '',
    vision_parsed_summary: vp ? {
      record_type: vp.record_type || null,
      domain_key: vp.domain_key || null,
      amount: vp.amount ?? null,
      title: vp.title || null,
    } : null,
    feedback_parsed: fp || null,
  }
})

function onReviewSaved() {
  // 点评保存成功后的回调（可扩展通知逻辑）
}

function formatJson(obj) {
  if (!obj) return 'null'
  try { return JSON.stringify(obj, null, 2) } catch { return String(obj) }
}

function onViewResult() {
  emit('completed', { runId: runId.value, caseKey: resultCaseKey.value })
  reset()
  emit('close')
}

function reset() {
  status.value = 'idle'
  previewUrl.value = null
  selectedFileName.value = ''
  selectedFileData.value = null
  progressOutput.value = []
  errorMsg.value = ''
  resultCaseKey.value = ''
  simResult.value = null
  previewEnlarged.value = false
  elapsed.value = 0
}

onUnmounted(() => { stopPolling(); stopElapsedTimer() })
</script>

<style scoped>
.upload-mask {
  position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 39;
}
.upload-panel {
  position: fixed; top: 50%; left: 50%;
  transform: translate(-50%, -50%) scale(0.95); opacity: 0; pointer-events: none;
  z-index: 40; width: 500px; max-height: 85vh;
  background: var(--bg-panel); border: 1px solid var(--border);
  border-radius: var(--radius-xl); display: flex; flex-direction: column; overflow: hidden;
  transition: all 0.2s;
}
.upload-panel.open { transform: translate(-50%, -50%) scale(1); opacity: 1; pointer-events: auto; }

.panel-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: var(--space-md) var(--space-lg); border-bottom: 1px solid var(--border); flex-shrink: 0;
}
.panel-title { font-size: 14px; font-weight: 700; }
.close-btn {
  font-size: 12px; padding: 3px 10px; border-radius: var(--radius-sm);
  background: var(--bg-hover); color: var(--text-secondary);
  border: 1px solid var(--border); cursor: pointer; font-family: var(--font-sans);
}
.panel-body { padding: var(--space-lg); overflow-y: auto; flex: 1; }

/* 远程模式账号提示 */
.remote-account-banner {
  font-size: 12px; color: var(--text-secondary);
  background: rgba(139, 92, 246, 0.08); border: 1px solid rgba(139, 92, 246, 0.2);
  border-radius: var(--radius-md); padding: var(--space-sm) var(--space-md);
  margin-bottom: var(--space-md); display: flex; align-items: center; gap: var(--space-sm);
  flex-wrap: wrap;
}
.remote-account-banner strong { color: #a78bfa; }
.remote-account-banner .banner-hint { font-size: 10px; color: var(--text-muted); }

/* 模式切换 */
.mode-toggle { display: flex; flex-direction: column; gap: var(--space-xs); margin-bottom: var(--space-md); }
.mode-option { display: flex; align-items: center; gap: var(--space-xs); font-size: 12px; color: var(--text-secondary); cursor: pointer; }
.mode-option input { accent-color: var(--accent-blue); }
.mode-hint {
  font-size: 11px; color: var(--accent-yellow); padding: var(--space-xs) var(--space-sm);
  background: rgba(210,153,34,0.07); border-radius: var(--radius-sm); border: 1px solid rgba(210,153,34,0.2);
  margin-bottom: var(--space-md); line-height: 1.5;
}
.mode-hint code { font-family: var(--font-mono); color: var(--accent-blue); }

/* 粘贴区 */
.paste-zone {
  border: 2px dashed var(--border); border-radius: var(--radius-lg);
  padding: 28px; text-align: center; cursor: pointer; transition: all 0.15s; outline: none;
}
.paste-zone:focus, .paste-zone.active { border-color: var(--accent-blue); background: rgba(88,166,255,0.05); }
.paste-icon { font-size: 28px; margin-bottom: var(--space-sm); }
.paste-text { font-size: 13px; color: var(--text-primary); margin-bottom: 4px; }
.paste-hint { font-size: 11px; color: var(--text-muted); }

.divider { text-align: center; font-size: 11px; color: var(--text-muted); margin: var(--space-md) 0; position: relative; }
.divider::before, .divider::after { content: ''; position: absolute; top: 50%; width: 40%; height: 1px; background: var(--border); }
.divider::before { left: 0; } .divider::after { right: 0; }

.file-section { display: flex; align-items: center; gap: var(--space-sm); }
.file-btn {
  font-size: 12px; padding: 5px 14px; border-radius: var(--radius-sm);
  background: var(--bg-hover); color: var(--text-primary);
  border: 1px solid var(--border); cursor: pointer; font-family: var(--font-sans); white-space: nowrap;
}
.file-btn:hover { border-color: var(--accent-blue); }
.file-name { font-size: 12px; color: var(--text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.preview-area { margin-top: var(--space-md); text-align: center; }
.preview-img { max-width: 100%; max-height: 200px; border-radius: var(--radius-md); border: 1px solid var(--border); }

.run-id-section { display: flex; align-items: center; gap: var(--space-sm); margin-top: var(--space-md); }
.run-id-label { font-size: 12px; color: var(--text-secondary); white-space: nowrap; }
.run-id-input {
  flex: 1; background: var(--bg-hover); color: var(--text-primary);
  border: 1px solid var(--border); border-radius: var(--radius-sm);
  padding: 4px 8px; font-size: 12px; font-family: var(--font-mono); outline: none;
}
.run-id-input:focus { border-color: var(--accent-blue); }

.start-btn {
  width: 100%; margin-top: var(--space-lg); padding: 8px; font-size: 13px; font-weight: 600;
  border-radius: var(--radius-md); background: var(--accent-blue); color: #fff;
  border: none; cursor: pointer; font-family: var(--font-sans); transition: opacity 0.12s;
}
.start-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.start-btn:hover:not(:disabled) { opacity: 0.9; }

/* 进度 */
.progress-area { text-align: center; padding: var(--space-md) 0; }
.progress-icon { font-size: 32px; margin-bottom: var(--space-sm); }
.progress-step { font-size: 14px; font-weight: 600; color: var(--text-primary); margin-bottom: var(--space-xs); }
.progress-elapsed { font-size: 12px; color: var(--text-muted); margin-bottom: var(--space-md); }
.progress-log {
  background: #0a0e14; border: 1px solid var(--border); border-radius: var(--radius-sm);
  padding: var(--space-sm) var(--space-md); max-height: 200px; overflow-y: auto; text-align: left;
}
.log-line { font-family: var(--font-mono); font-size: 10px; color: var(--text-muted); line-height: 1.5; white-space: pre-wrap; word-break: break-all; }
.log-line.stderr { color: var(--accent-red); }

/* 结果 */
.result-area { text-align: center; padding: var(--space-md) 0; }
.result-icon { font-size: 32px; margin-bottom: var(--space-sm); }
.result-title { font-size: 14px; font-weight: 700; margin-bottom: var(--space-sm); }
.result-meta { font-size: 12px; color: var(--text-muted); margin-bottom: var(--space-md); }
.result-meta code { color: var(--accent-blue); font-family: var(--font-mono); }
.error-detail {
  font-size: 12px; color: var(--accent-red); margin-bottom: var(--space-md);
  font-family: var(--font-mono); background: var(--bg-hover); padding: var(--space-sm);
  border-radius: var(--radius-sm); border: 1px solid var(--border); word-break: break-all;
}
.result-btn {
  font-size: 13px; padding: 6px 18px; border-radius: var(--radius-md);
  background: var(--accent-blue); color: #fff; border: none; cursor: pointer;
  font-family: var(--font-sans); font-weight: 600;
}
.result-btn:hover { opacity: 0.9; }

/* 本地模拟结果 */
.sim-result-area { padding: var(--space-md) 0; }
.sim-section { margin-top: var(--space-md); }
.sim-section-title { font-size: 12px; font-weight: 700; color: var(--accent-blue); margin-bottom: var(--space-xs); display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.sim-model { font-size: 10px; font-weight: 400; color: var(--text-muted); font-family: var(--font-mono); }
.sim-json {
  background: #0a0e14; border: 1px solid var(--border); border-radius: var(--radius-sm);
  padding: var(--space-sm) var(--space-md); font-family: var(--font-mono); font-size: 11px;
  color: var(--text-secondary); white-space: pre-wrap; word-break: break-all; max-height: 250px; overflow-y: auto; margin: 0;
}
.sim-json.error { border-color: var(--accent-red); color: var(--accent-red); }
.token-info { display: flex; gap: var(--space-md); font-size: 11px; color: var(--text-muted); }

/* 原图预览 */
.sim-preview-img {
  width: 100%; max-height: 200px; object-fit: contain;
  border: 1px solid var(--border); border-radius: var(--radius-md);
  cursor: zoom-in; transition: max-height 0.2s;
}
.sim-preview-img.enlarged { max-height: none; cursor: zoom-out; }
.sim-section-hint { font-size: 10px; font-weight: 400; color: var(--text-muted); }

/* 字段网格 */
.field-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-xs); margin-bottom: var(--space-sm); }
.field-item { display: flex; flex-direction: column; gap: 2px; background: var(--bg-hover); padding: var(--space-xs) var(--space-sm); border-radius: var(--radius-sm); border: 1px solid var(--border); }
.field-label { font-size: 10px; color: var(--text-muted); font-family: var(--font-mono); }
.field-value { font-size: 12px; color: var(--text-primary); word-break: break-all; }

/* 解析状态徽章 */
.parse-badge { font-size: 10px; padding: 1px 6px; border-radius: var(--radius-sm); font-family: var(--font-sans); font-weight: 600; }
.parse-badge.ok { background: rgba(63,185,80,0.15); color: var(--accent-green); border: 1px solid rgba(63,185,80,0.3); }
.parse-badge.fail { background: rgba(248,81,73,0.15); color: var(--accent-red); border: 1px solid rgba(248,81,73,0.3); }
.parse-badge.warn { background: rgba(210,153,34,0.15); color: var(--accent-yellow); border: 1px solid rgba(210,153,34,0.3); }

/* 原始 JSON 折叠 */
.raw-json-details { margin-top: var(--space-xs); }
.raw-json-details summary { font-size: 11px; color: var(--text-muted); cursor: pointer; padding: var(--space-xs) 0; }
.raw-json-details summary:hover { color: var(--accent-blue); }

/* 解析错误框 */
.parse-error-box { }
.parse-error-label { font-size: 11px; color: var(--accent-red); margin-bottom: var(--space-xs); }

/* 操作按钮组 */
.sim-actions { display: flex; gap: var(--space-sm); justify-content: center; margin-top: var(--space-lg); }
.reset-btn {
  font-size: 13px; padding: 6px 18px; border-radius: var(--radius-md);
  background: var(--bg-hover); color: var(--text-primary);
  border: 1px solid var(--border); cursor: pointer; font-family: var(--font-sans); font-weight: 600;
}
.reset-btn:hover { border-color: var(--accent-blue); }

/* thinking 开关 */
.thinking-toggle { margin-top: var(--space-sm); }
.thinking-option {
  display: flex; align-items: center; gap: 6px;
  font-size: 11px; color: var(--text-secondary); cursor: pointer;
}
.thinking-option input { cursor: pointer; }

/* 模型选择 */
.model-select-row {
  display: flex; gap: var(--space-md); margin-top: var(--space-sm);
}
.model-select-item {
  display: flex; flex-direction: column; gap: 2px; flex: 1;
}
.model-label {
  font-size: 10px; color: var(--text-muted);
}
.model-select {
  background: var(--bg-hover); color: var(--text-primary);
  border: 1px solid var(--border); border-radius: var(--radius-sm);
  padding: 4px 8px; font-size: 11px; font-family: var(--font-sans);
  outline: none; cursor: pointer;
}
.model-select:focus { border-color: var(--accent-blue); }

/* 解析状态徽标 */
.parse-badge {
  font-size: 10px; padding: 1px 6px; border-radius: 3px; font-weight: 600;
}
.parse-badge.ok { background: rgba(63, 185, 80, 0.15); color: var(--accent-green); }
.parse-badge.fail { background: rgba(248, 81, 73, 0.15); color: var(--accent-red); }
.parse-badge.warn { background: rgba(255, 193, 7, 0.15); color: var(--accent-yellow); }

/* 字段网格 */
.field-grid {
  display: grid; grid-template-columns: 1fr 1fr; gap: 6px 12px;
  margin-bottom: var(--space-xs);
}
.field-item { display: flex; flex-direction: column; gap: 2px; }
.field-label {
  font-size: 10px; color: var(--text-muted); font-family: var(--font-mono);
}
.field-value {
  font-size: 12px; color: var(--text-primary); word-break: break-all;
}

/* record_type 颜色 */
.field-value.expense { color: var(--accent-red); font-weight: 600; }
.field-value.income { color: var(--accent-green); font-weight: 600; }
.field-value.sport { color: var(--accent-blue); font-weight: 600; }
.field-value.sleep { color: var(--accent-purple, #b39ddb); font-weight: 600; }
.field-value.food { color: var(--accent-yellow); font-weight: 600; }
.field-value.wallet { color: var(--accent-cyan, #26c6da); font-weight: 600; }
.field-value.reading { color: var(--accent-orange, #ffa726); font-weight: 600; }
.field-value.uncertain { color: var(--text-muted); font-weight: 600; }

/* 完整 JSON 折叠 */
.raw-json-details { margin-top: var(--space-xs); }
.raw-json-details summary {
  font-size: 10px; color: var(--text-muted); cursor: pointer;
  font-family: var(--font-sans);
}
.raw-json-details summary:hover { color: var(--accent-blue); }

/* 解析失败提示 */
.parse-error-box { margin-top: var(--space-xs); }
.parse-error-label {
  font-size: 11px; color: var(--accent-red); margin-bottom: 4px; font-weight: 600;
}
</style>
