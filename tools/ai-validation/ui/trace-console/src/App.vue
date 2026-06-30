<template>
  <div class="app-root">
    <!-- 顶部概览栏 -->
    <TopBar
      :runs="runs"
      :current-run-id="currentRunId"
      :summary="summary"
      :view-mode="viewMode"
      @update:current-run-id="onRunChange"
      @update:view-mode="viewMode = $event"
      @open-upload="uploadPanelOpen = true"
    />

    <!-- 无批次时 -->
    <EmptyState
      v-if="runs.length === 0 && !loading"
      icon="📂"
      title="未找到测试结果"
      desc="请先运行 npm run test:receipt 生成测试结果，结果会保存在 test-results/ 目录下。"
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
          @select="onCaseSelect"
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
      @close="uploadPanelOpen = false"
      @completed="onUploadCompleted"
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
import { fetchRuns, fetchSummary, fetchTraces, fetchTrace } from './lib/api.js'
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

// 当前选中的 step 对象
const selectedStep = computed(() => {
  if (!currentTrace.value || !selectedStepId.value) return null
  return currentTrace.value.steps.find((s) => s.step_id === selectedStepId.value) || null
})

// ═══════════════════════════════════════════════
// 生命周期
// ═══════════════════════════════════════════════

onMounted(async () => {
  await loadRuns()
})

// ═══════════════════════════════════════════════
// 数据加载
// ═══════════════════════════════════════════════

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

// 批次切换
watch(currentRunId, async (newRunId) => {
  if (!newRunId) return
  selectedCaseKey.value = ''
  currentTrace.value = null
  selectedStepId.value = ''
  await loadRunData(newRunId)
}, { immediate: false })

async function onRunChange(runId) {
  currentRunId.value = runId
}

async function loadRunData(runId) {
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
    // 默认选中第一个样本
    if (traces.value.length > 0) {
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
  traceLoading.value = true
  traceError.value = ''

  const { data, error } = await fetchTrace(currentRunId.value, caseKey)
  traceLoading.value = false

  if (error) {
    console.error('加载 trace 失败:', error)
    traceError.value = error
    return
  }
  currentTrace.value = normalizeTrace(data)
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

// 上传完成 - 切换到新批次并选中结果
async function onUploadCompleted({ runId, caseKey }) {
  uploadPanelOpen.value = false
  // 切换到新批次
  if (runId && runId !== currentRunId.value) {
    currentRunId.value = runId
    // 等待批次数据加载
    await new Promise(resolve => setTimeout(resolve, 500))
  }
  // 选中新 trace
  if (caseKey) {
    onCaseSelect(caseKey)
  }
}
</script>

<style scoped>
.app-root {
  display: flex;
  flex-direction: column;
  height: 100vh;
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
