<template>
  <div class="app-root">
    <!-- 顶部概览栏 -->
    <TopBar
      :runs="runs"
      :current-run-id="currentRunId"
      :summary="summary"
      :view-mode="viewMode"
      :mode="mode"
      :accounts="accounts"
      :account-key="accountKey"
      @update:current-run-id="onRunChange"
      @update:view-mode="viewMode = $event"
      @open-upload="uploadPanelOpen = true"
      @update:mode="mode = $event"
      @update:account-key="accountKey = $event"
      @open-memory="memoryPanelOpen = true"
      @refresh="onRefresh"
    />

    <!-- 无批次时 -->
    <EmptyState
      v-if="runs.length === 0 && !loading"
      :icon="mode === 'remote' ? '🔌' : '📂'"
      :title="mode === 'remote' ? '未找到远程记录' : '未找到测试结果'"
      :desc="mode === 'remote'
        ? (accountKey ? '该账号暂无 AI 识别记录，可通过上传测试生成。' : '请先选择一个账号。')
        : '请先运行 npm run test:receipt 生成测试结果，结果会保存在 test-results/ 目录下。'"
    />

    <!-- 加载中 -->
    <EmptyState
      v-else-if="loading && runs.length === 0"
      icon="⏳"
      title="加载中..."
    />

    <!-- 主体 -->
    <template v-else>
      <div class="main-body">
        <!-- 左栏：样本列表 -->
        <SampleList
          :traces="traces"
          :selected-case-key="selectedCaseKey"
          :account-key="accountKey"
          @select="onCaseSelect"
          @open-reviews="reviewHistoryOpen = true"
        />

        <!-- 中栏：时间线 + 用户可见输出 -->
        <div class="center-area">
          <!-- 加载中 -->
          <div v-if="traceLoading" class="trace-loading">
            <span>加载 trace 数据...</span>
          </div>

          <!-- 错误状态 -->
          <div v-else-if="traceError" class="trace-error-state">
            <div class="error-icon">⚠️</div>
            <div class="error-title">Trace 加载失败</div>
            <div class="error-detail">{{ traceError }}</div>
            <div class="error-hint">该样本的 trace.json 可能已损坏或格式不正确</div>
          </div>

          <!-- 正常时间线 -->
          <Timeline
            v-else-if="currentTrace"
            :trace="currentTrace"
            :selected-step-id="selectedStepId"
            :view-mode="viewMode"
            @select-node="onNodeSelect"
            @view-artifact="onViewArtifact"
          />

          <!-- 空状态 -->
          <EmptyState
            v-else
            icon="📋"
            title="请选择样本"
            desc="从左侧选择一个测试样本，查看完整识别链路。"
          />

          <!-- 底部用户可见输出 -->
          <UserOutputPanel
            v-if="currentTrace && !traceError"
            :outputs="currentTrace.user_visible_outputs"
            :trace="currentTrace"
          />

          <!-- 点评入口按钮 -->
          <div class="review-entry" v-if="currentTrace && !traceError && currentRunId && selectedCaseKey">
            <button class="review-toggle-btn" @click="reviewDrawerOpen = !reviewDrawerOpen">
              {{ reviewDrawerOpen ? '收起点评' : '点评此记录' }}
              <span class="review-badge" v-if="reviewStateSaved">✓</span>
            </button>
          </div>
        </div>
      </div>
    </template>

    <!-- 节点详情抽屉 -->
    <NodeDrawer
      :open="drawerOpen"
      :step="selectedStep"
      :artifacts="currentTrace?.artifacts"
      @close="drawerOpen = false"
      @view-artifact="onViewArtifact"
    />

    <!-- Artifact 弹窗 -->
    <ArtifactModal
      :open="artifactModalOpen"
      :artifact-key="activeArtifactKey"
      :artifacts="currentTrace?.artifacts || {}"
      @close="artifactModalOpen = false"
    />

    <!-- 上传面板 -->
    <UploadPanel
      :open="uploadPanelOpen"
      :account-key="accountKey"
      :accounts="accounts"
      :mode="mode"
      @close="uploadPanelOpen = false"
      @completed="onViewCompleted"
      @simulated="onSimulated"
    />

    <!-- 记忆面板 -->
    <MemoryPanel
      :open="memoryPanelOpen"
      :account-key="accountKey"
      :account-label="accountLabel"
      @close="memoryPanelOpen = false"
    />

    <!-- 点评浮动抽屉 -->
    <ReviewPanel
      :open="reviewDrawerOpen"
      :run-id="reviewRunId"
      :case-key="selectedCaseKey"
      mode="trace"
      :trace-snapshot="currentTrace"
      :account-key="accountKey"
      @close="reviewDrawerOpen = false"
      @saved="onReviewSaved"
    />

    <!-- 点评记录弹窗 -->
    <ReviewHistoryModal
      :open="reviewHistoryOpen"
      :run-id="currentRunId"
      @close="reviewHistoryOpen = false"
    />
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import TopBar from './components/TopBar.vue'
import SampleList from './components/SampleList.vue'
import Timeline from './components/Timeline.vue'
import EmptyState from './components/EmptyState.vue'
import NodeDrawer from './components/NodeDrawer.vue'
import ArtifactModal from './components/ArtifactModal.vue'
import UserOutputPanel from './components/UserOutputPanel.vue'
import UploadPanel from './components/UploadPanel.vue'
import ReviewHistoryModal from './components/ReviewHistoryModal.vue'
import MemoryPanel from './components/MemoryPanel.vue'
import ReviewPanel from './components/ReviewPanel.vue'
import {
  fetchRuns, fetchSummary, fetchTraces, fetchTrace,
  fetchAccounts, fetchRemoteDays, fetchRemoteTraces, fetchRemoteTraceDetail,
} from './lib/api.js'
import { normalizeTrace } from './lib/traceNormalizer.js'

// ═══════════════════════════════════════════════
// 状态
// ═══════════════════════════════════════════════

const loading = ref(false)
const runs = ref([])
const currentRunId = ref('')
const summary = ref(null)
const traces = ref([])
const selectedCaseKey = ref('')
const currentTrace = ref(null)
const selectedStepId = ref('')
const viewMode = ref('dev')
const drawerOpen = ref(false)
const artifactModalOpen = ref(false)
const activeArtifactKey = ref('')
const traceLoading = ref(false)
const traceError = ref('')
const uploadPanelOpen = ref(false)
const reviewHistoryOpen = ref(false)
const pendingRunId = ref(null)   // 模拟/上传完成后的 runId，供"查看结果"使用
const pendingCaseKey = ref(null) // 模拟/上传完成后的 caseKey，供"查看结果"使用

// 远程模式状态
const mode = ref('local')         // 'local' | 'remote'
const accounts = ref([])          // [{ key, label }]
const accountKey = ref('')        // 选中的账号 key
const memoryPanelOpen = ref(false)
const reviewDrawerOpen = ref(false)
const reviewStateSaved = ref(false)

// 当前选中的 step 对象
const selectedStep = computed(() => {
  if (!currentTrace.value || !selectedStepId.value) return null
  return currentTrace.value.steps.find((s) => s.step_id === selectedStepId.value) || null
})

// ═══════════════════════════════════════════════
// 生命周期
// ═══════════════════════════════════════════════

onMounted(async () => {
  // 并行加载本地批次和远程账号列表
  await Promise.all([loadRuns(), loadAccounts()])
})

// 账号标签（给 MemoryPanel 用）
const accountLabel = computed(() => {
  const acc = accounts.value.find(a => a.key === accountKey.value)
  return acc?.label || ''
})

// 点评用的 runId：远程模式下加 remote- 前缀，与 server 存储路径一致
const reviewRunId = computed(() => {
  if (mode.value === 'remote' && currentRunId.value) {
    return `remote-${currentRunId.value}`
  }
  return currentRunId.value
})

// 点评保存后刷新 traces 列表（更新 has_review 标记）
async function onReviewSaved() {
  reviewStateSaved.value = true
  if (mode.value === 'remote' && currentRunId.value) {
    await loadRemoteTraces(currentRunId.value, false)
  }
}

// ═══════════════════════════════════════════════
// 数据加载
// ═══════════════════════════════════════════════

// 加载账号列表
async function loadAccounts() {
  const { data, error } = await fetchAccounts()
  if (error) {
    console.error('加载账号列表失败:', error)
    return
  }
  accounts.value = data?.accounts || []
}

// 模式切换：local ↔ remote
watch(mode, async (newMode) => {
  selectedCaseKey.value = ''
  currentTrace.value = null
  selectedStepId.value = ''
  traces.value = []
  summary.value = null
  runs.value = []
  currentRunId.value = ''

  if (newMode === 'remote') {
    // 远程模式：默认选第一个账号
    if (!accountKey.value && accounts.value.length > 0) {
      accountKey.value = accounts.value[0].key
    }
    if (accountKey.value) {
      await loadRemoteDays()
    }
  } else {
    // 本地模式：重新加载批次
    await loadRuns()
  }
})

// 账号切换：重新加载日期列表
watch(accountKey, async (newKey) => {
  if (mode.value !== 'remote' || !newKey) return
  selectedCaseKey.value = ''
  currentTrace.value = null
  traces.value = []
  summary.value = null
  await loadRemoteDays()
})

// 加载远程日期列表
async function loadRemoteDays() {
  if (!accountKey.value) return
  loading.value = true
  const { data, error } = await fetchRemoteDays(accountKey.value)
  loading.value = false
  if (error) {
    console.error('加载远程日期失败:', error)
    runs.value = []
    return
  }
  // 转换为 runs 兼容格式
  const days = data?.days || []
  runs.value = days.map(d => ({
    run_id: d.date,
    has_summary: true,
    label: d.date,
    total_cases: d.count,
    success_cases: d.success,
    failed_cases: d.error,
  }))
  // 默认选最新的一天
  if (runs.value.length > 0) {
    currentRunId.value = runs.value[0].run_id
  } else {
    currentRunId.value = ''
  }
}

async function loadRuns() {
  loading.value = true
  const { data, error } = await fetchRuns()
  loading.value = false
  if (error) {
    console.error('加载批次失败:', error)
    return
  }
  runs.value = data.runs || []
  // 默认选中第一个有 summary 的批次
  const firstRun = runs.value.find((r) => r.has_summary) || runs.value[0]
  if (firstRun) {
    currentRunId.value = firstRun.run_id
  }
}

// 批次/日期切换
watch(currentRunId, async (newRunId) => {
  if (!newRunId) return
  selectedCaseKey.value = ''
  currentTrace.value = null
  selectedStepId.value = ''
  if (mode.value === 'remote') {
    await loadRemoteTraces(newRunId)
  } else {
    await loadRunData(newRunId)
  }
}, { immediate: false })

async function onRunChange(runId) {
  currentRunId.value = runId
}

// 刷新当前列表
async function onRefresh() {
  if (mode.value === 'remote') {
    // 远程模式：刷新当前日期的 traces
    if (currentRunId.value) {
      await loadRemoteTraces(currentRunId.value, false)
    } else {
      await loadRemoteDays()
    }
  } else {
    // 本地模式：刷新批次列表
    await loadRuns()
  }
}

// 加载远程某天的 traces
async function loadRemoteTraces(dateStr, autoSelect = true) {
  const { data, error } = await fetchRemoteTraces(accountKey.value, dateStr)
  if (error) {
    console.error('加载远程 traces 失败:', error)
    traces.value = []
    summary.value = null
    return
  }
  const remoteTraces = (data?.traces || []).map(t => ({ ...t, is_remote: true }))
  traces.value = remoteTraces
  // 构造 summary 供 TopBar 统计
  summary.value = {
    total_cases: remoteTraces.length,
    success_cases: remoteTraces.filter(t => t.status === 'success' || t.status === 'done').length,
    failed_cases: remoteTraces.filter(t => t.status === 'error' || t.status === 'failed').length,
    cases: remoteTraces,
  }
  if (autoSelect && remoteTraces.length > 0) {
    onCaseSelect(remoteTraces[0].case_key)
  }
}

async function loadRunData(runId, autoSelect = true) {
  // 并行加载 summary 和 traces
  const [summaryResult, tracesResult] = await Promise.all([
    fetchSummary(runId),
    fetchTraces(runId),
  ])

  if (summaryResult.error) {
    console.error('加载 summary 失败:', summaryResult.error)
  } else {
    summary.value = summaryResult.data
  }

  if (tracesResult.error) {
    console.error('加载 traces 失败:', tracesResult.error)
    traces.value = []
  } else {
    traces.value = tracesResult.data.traces || []
    // 默认选中第一个样本（可关闭，用于"查看结果"时由调用方指定）
    if (autoSelect && traces.value.length > 0) {
      onCaseSelect(traces.value[0].case_key)
    }
  }
}

// 样本选择
async function onCaseSelect(caseKey) {
  selectedCaseKey.value = caseKey
  selectedStepId.value = ''
  currentTrace.value = null
  drawerOpen.value = false
  artifactModalOpen.value = false
  reviewStateSaved.value = false
  traceLoading.value = true
  traceError.value = ''

  if (mode.value === 'remote') {
    // 远程模式：从 traces 列表找到 trace_id（logId），调远程详情接口
    const traceItem = traces.value.find(t => t.case_key === caseKey)
    if (!traceItem) {
      traceLoading.value = false
      traceError.value = '未找到样本'
      return
    }
    const { data, error } = await fetchRemoteTraceDetail(
      accountKey.value,
      currentRunId.value,
      traceItem.trace_id,
    )
    traceLoading.value = false
    if (error) {
      console.error('加载远程 trace 失败:', error)
      traceError.value = error
      return
    }
    currentTrace.value = normalizeTrace(data)
  } else {
    // 本地模式：按原逻辑
    const { data, error } = await fetchTrace(currentRunId.value, caseKey)
    traceLoading.value = false
    if (error) {
      console.error('加载 trace 失败:', error)
      traceError.value = error
      return
    }
    currentTrace.value = normalizeTrace(data)
  }
}

// 节点选择 - 打开抽屉
function onNodeSelect(stepId) {
  selectedStepId.value = stepId
  drawerOpen.value = true
}

// Artifact 查看 - 打开弹窗
function onViewArtifact(artifactRef) {
  activeArtifactKey.value = artifactRef
  artifactModalOpen.value = true
}

// 模拟/上传完成 - 静默刷新批次列表，不跳转，让用户留在面板内看结果和点评
async function onSimulated({ runId, caseKey }) {
  // 记录新的 runId 和 caseKey，供"查看结果"使用
  pendingRunId.value = runId
  pendingCaseKey.value = caseKey

  // 远程模式下模拟是本地操作，切回本地模式
  if (mode.value === 'remote') {
    mode.value = 'local'
    // 等待模式切换完成
    await new Promise(resolve => setTimeout(resolve, 500))
  }

  // 如果是新批次，静默切换（不选中 trace，不影响面板）
  if (runId && runId !== currentRunId.value) {
    currentRunId.value = runId
    await new Promise(resolve => setTimeout(resolve, 500))
  }
}

// 用户点击"查看结果" - 关闭面板，跳转到主追踪台
async function onViewCompleted({ runId, caseKey }) {
  uploadPanelOpen.value = false

  if (mode.value === 'remote') {
    // 远程模式：刷新当前日期的 traces 列表（EF 已写入数据库）
    // 等待 1 秒让数据库写入完成
    await new Promise(resolve => setTimeout(resolve, 1000))
    await loadRemoteTraces(currentRunId.value, false)
    return
  }

  const targetRunId = runId || pendingRunId.value
  const targetCaseKey = caseKey || pendingCaseKey.value
  if (targetRunId && targetRunId !== currentRunId.value) {
    currentRunId.value = targetRunId
    await new Promise(resolve => setTimeout(resolve, 500))
  }
  // 重新加载 traces 列表，确保新 trace 出现在侧边栏（不自动选中，由下方手动选中）
  await loadRunData(currentRunId.value, false)
  if (targetCaseKey) {
    onCaseSelect(targetCaseKey)
  }
  pendingRunId.value = null
  pendingCaseKey.value = null
}
</script>

<style scoped>
.app-root {
  display: flex;
  flex-direction: column;
  height: 100vh;
}

/* 点评入口 */
.review-entry {
  display: flex;
  justify-content: center;
  padding: var(--space-sm) 0;
}
.review-toggle-btn {
  font-size: 12px;
  padding: 5px 20px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  transition: all 0.12s;
}
.review-toggle-btn:hover {
  background: var(--bg-active);
  color: var(--text-primary);
  border-color: var(--accent-blue);
}
.review-badge {
  color: var(--accent-green);
  font-weight: 700;
  margin-left: 4px;
}

.main-body {
  display: flex;
  flex: 1;
  min-height: 0;
}

.center-area {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.trace-loading {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  font-size: 13px;
}

.trace-error-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: var(--space-xl);
}

.trace-error-state .error-icon {
  font-size: 32px;
  margin-bottom: var(--space-md);
}

.trace-error-state .error-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--accent-red);
  margin-bottom: var(--space-sm);
}

.trace-error-state .error-detail {
  font-size: 12px;
  color: var(--text-secondary);
  font-family: var(--font-mono);
  background: var(--bg-panel);
  padding: var(--space-sm) var(--space-md);
  border-radius: var(--radius-md);
  border: 1px solid var(--border);
  max-width: 500px;
  margin-bottom: var(--space-sm);
  word-break: break-all;
}

.trace-error-state .error-hint {
  font-size: 12px;
  color: var(--text-muted);
}
</style>
