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

        <!-- run_id 输入（仅线上模式） -->
        <div class="run-id-section" v-if="!simulateMode">
          <label class="run-id-label">批次 ID:</label>
          <input
            v-model="runId"
            class="run-id-input"
            placeholder="manual-check-YYYYMMDD"
          />
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

      <!-- ═══ 本地模拟完成 ═══ -->
      <template v-else-if="status === 'done' && simulateMode">
        <div class="sim-result-area">
          <div class="result-icon">✅</div>
          <div class="result-title">模拟完成（{{ Math.round(elapsed / 1000) }}s）</div>

          <!-- 视觉识别输出 -->
          <div class="sim-section">
            <div class="sim-section-title">视觉识别输出 <span class="sim-model">{{ simResult?.vision_output?.model || '' }}</span></div>
            <pre class="sim-json">{{ formatJson(simResult?.vision_output?.parsed) }}</pre>
          </div>

          <!-- 文案生成输出 -->
          <div class="sim-section">
            <div class="sim-section-title">文案生成输出 <span class="sim-model">{{ simResult?.feedback_output?.model || '' }}</span></div>
            <pre class="sim-json">{{ formatJson(simResult?.feedback_output?.parsed) }}</pre>
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

          <button class="result-btn" @click="reset">再次模拟</button>
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
import { ref, computed, onUnmounted } from 'vue'
import { uploadTest, fetchUploadStatus, localSimulate, fetchSimulateStatus } from '../lib/api.js'

const props = defineProps({
  open: { type: Boolean, default: false },
})

const emit = defineEmits(['close', 'completed'])

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

// 默认 runId
const today = new Date().toISOString().slice(0, 10).replace(/-/g, '')
runId.value = `manual-check-${today}`

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
  const payload = { ...selectedFileData.value }
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
        simResult.value = data.result
      } else {
        resultCaseKey.value = data.traceCaseKey
        emit('completed', { runId: data.runId, caseKey: data.traceCaseKey })
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
.sim-section-title { font-size: 12px; font-weight: 700; color: var(--accent-blue); margin-bottom: var(--space-xs); }
.sim-model { font-size: 10px; font-weight: 400; color: var(--text-muted); font-family: var(--font-mono); }
.sim-json {
  background: #0a0e14; border: 1px solid var(--border); border-radius: var(--radius-sm);
  padding: var(--space-sm) var(--space-md); font-family: var(--font-mono); font-size: 11px;
  color: var(--text-secondary); white-space: pre-wrap; word-break: break-all; max-height: 250px; overflow-y: auto; margin: 0;
}
.token-info { display: flex; gap: var(--space-md); font-size: 11px; color: var(--text-muted); }
</style>
