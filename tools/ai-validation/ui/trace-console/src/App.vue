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
          <Timeline
            v-if="currentTrace"
            :trace="currentTrace"
            :selected-step-id="selectedStepId"
            :view-mode="viewMode"
            @select-node="onNodeSelect"
            @view-artifact="onViewArtifact"
          />
          <EmptyState
            v-else
            icon="📋"
            title="请选择样本"
            desc="从左侧选择一个测试样本，查看完整识别链路。"
          />

          <!-- 底部用户可见输出 -->
          <UserOutputPanel
            v-if="currentTrace"
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

  const { data, error } = await fetchTrace(currentRunId.value, caseKey)
  if (error) {
    console.error('加载 trace 失败:', error)
    // 设置一个错误 trace
    currentTrace.value = normalizeTrace(null)
    currentTrace.value.errors = [error]
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
</style>
