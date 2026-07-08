<template>
  <div class="modal-overlay" v-if="open" @click.self="$emit('close')">
    <div class="modal-box">
      <!-- 头部 -->
      <div class="modal-header">
        <span class="modal-title">点评记录 - {{ runId }}</span>
        <div class="modal-actions">
          <button class="action-btn refresh-btn" :disabled="loading" @click="loadData(runId)">
            {{ loading ? '加载中...' : '刷新' }}
          </button>
          <button class="action-btn" @click="$emit('close')">关闭</button>
        </div>
      </div>

      <!-- 工具栏：筛选 tab + 域下拉 -->
      <div class="toolbar">
        <div class="filter-tabs">
          <button
            v-for="opt in filterOptions"
            :key="opt.key"
            class="filter-btn"
            :class="{ on: reviewFilter === opt.key }"
            @click="reviewFilter = opt.key"
          >{{ opt.label }} ({{ opt.count }})</button>
        </div>

        <div class="domain-filter">
          <span class="filter-label">域:</span>
          <select v-model="domainFilter" class="domain-select">
            <option value="">全部</option>
            <option v-for="d in domainOptions" :key="d" :value="d">{{ d }}</option>
          </select>
        </div>
      </div>

      <!-- 内容 -->
      <div class="modal-body">
        <!-- 加载中 -->
        <div v-if="loading" class="state-box">
          <span>加载点评数据...</span>
        </div>

        <!-- 错误状态 -->
        <div v-else-if="loadError" class="state-box error">
          <div class="state-icon">⚠️</div>
          <div class="state-text">加载失败</div>
          <div class="state-desc">{{ loadError }}</div>
        </div>

        <!-- 空状态 -->
        <div v-else-if="filteredList.length === 0" class="state-box empty">
          <div class="state-icon">📝</div>
          <div class="state-text">{{ emptyHint }}</div>
        </div>

        <!-- 卡片网格 -->
        <div v-else class="cards-grid">
          <div
            v-for="item in filteredList"
            :key="item.case_key"
            class="review-card"
          >
            <!-- 顶部：缩略图 + 概要 -->
            <div class="card-top">
              <div class="card-thumb">
                <img
                  v-if="item.image_url"
                  :src="item.image_url"
                  class="thumb-img"
                  loading="lazy"
                  @error="onThumbError"
                />
                <div v-else class="thumb-placeholder">无图</div>
              </div>

              <div class="card-meta">
                <div class="meta-row">
                  <span class="domain-tag" v-if="item.domain">{{ item.domain }}</span>
                  <span class="mode-badge" :class="modeClass(item.review?.mode)">{{ modeLabel(item.review?.mode) }}</span>
                </div>
                <div class="case-key" :title="item.case_key">{{ item.case_key }}</div>
                <div class="review-time">
                  点评时间: {{ formatDateTime(item.review?.reviewed_at) }}
                </div>
              </div>
            </div>

            <!-- 点评详情（已点评时展示） -->
            <template v-if="item.reviewed && editingCaseKey !== item.case_key">
              <!-- 评分 -->
              <div class="rating-block">
                <div class="rating-line">
                  <span class="rating-label">识别准确度</span>
                  <span class="stars">{{ starStr(item.review?.ratings?.recognition_accuracy) }}</span>
                  <span class="rating-num">{{ item.review?.ratings?.recognition_accuracy ?? 0 }}/5</span>
                </div>
                <div class="rating-line">
                  <span class="rating-label">文案质量</span>
                  <span class="stars">{{ starStr(item.review?.ratings?.feedback_quality) }}</span>
                  <span class="rating-num">{{ item.review?.ratings?.feedback_quality ?? 0 }}/5</span>
                </div>
              </div>

              <!-- 问题标签 -->
              <div class="card-section" v-if="issueTagsOf(item.review).length > 0">
                <span class="section-label">问题标签</span>
                <div class="tag-list">
                  <span
                    v-for="tag in issueTagsOf(item.review)"
                    :key="tag"
                    class="tag-chip"
                  >{{ issueTagLabel(tag) }}</span>
                </div>
              </div>

              <!-- 备注 -->
              <div class="card-section" v-if="item.review?.notes">
                <span class="section-label">点评备注</span>
                <div class="text-block">{{ item.review.notes }}</div>
              </div>

              <!-- 改进建议 -->
              <div class="card-section" v-if="item.review?.suggested_action">
                <span class="section-label">改进建议</span>
                <div class="text-block accent">{{ item.review.suggested_action }}</div>
              </div>

              <!-- 复评按钮 -->
              <div class="card-footer">
                <button class="re-review-btn" @click="startEdit(item)">复评</button>
              </div>
            </template>

            <!-- 未点评：提示 + 开始点评 -->
            <template v-else-if="!item.reviewed && editingCaseKey !== item.case_key">
              <div class="not-reviewed-hint">该样本尚未点评</div>
              <div class="card-footer">
                <button class="re-review-btn" @click="startEdit(item)">开始点评</button>
              </div>
            </template>

            <!-- 内联编辑表单 -->
            <div v-if="editingCaseKey === item.case_key" class="edit-form">
              <div class="edit-title">复评编辑</div>

              <!-- 评分 -->
              <div class="rating-block">
                <div class="rating-line">
                  <span class="rating-label">识别准确度</span>
                  <div class="star-group">
                    <button
                      v-for="n in 5"
                      :key="`ra-${n}`"
                      class="star-btn"
                      :class="{ active: editForm.ratings.recognition_accuracy >= n }"
                      @click="editForm.ratings.recognition_accuracy = n"
                      @mouseenter="hoverRa = n"
                      @mouseleave="hoverRa = 0"
                    >{{ editForm.ratings.recognition_accuracy >= n || hoverRa >= n ? '★' : '☆' }}</button>
                  </div>
                </div>
                <div class="rating-line">
                  <span class="rating-label">文案质量</span>
                  <div class="star-group">
                    <button
                      v-for="n in 5"
                      :key="`fq-${n}`"
                      class="star-btn"
                      :class="{ active: editForm.ratings.feedback_quality >= n }"
                      @click="editForm.ratings.feedback_quality = n"
                      @mouseenter="hoverFq = n"
                      @mouseleave="hoverFq = 0"
                    >{{ editForm.ratings.feedback_quality >= n || hoverFq >= n ? '★' : '☆' }}</button>
                  </div>
                </div>
              </div>

              <!-- 问题标签 -->
              <div class="card-section">
                <span class="section-label">问题标签（可多选）</span>
                <div class="tag-list">
                  <button
                    v-for="tag in ISSUE_TAG_OPTIONS"
                    :key="tag.value"
                    class="tag-chip"
                    :class="{ active: editForm.issue_tags.includes(tag.value) }"
                    @click="toggleEditTag(tag.value)"
                  >{{ tag.label }}</button>
                </div>
              </div>

              <!-- 备注 -->
              <div class="card-section">
                <span class="section-label">点评内容</span>
                <textarea
                  v-model="editForm.notes"
                  class="notes-input"
                  placeholder="记录你的感受，比如哪里不够好、缺什么"
                  rows="3"
                ></textarea>
              </div>

              <!-- 改进建议 -->
              <div class="card-section">
                <span class="section-label">改进建议（可选）</span>
                <input
                  v-model="editForm.suggested_action"
                  class="action-input"
                  placeholder="希望 AI 怎么改进"
                />
              </div>

              <!-- 操作按钮 -->
              <div class="action-row">
                <button
                  class="save-btn"
                  :disabled="!canSaveEdit || saving"
                  @click="saveEdit(item)"
                >{{ saving ? '保存中...' : '保存' }}</button>
                <button class="cancel-btn" :disabled="saving" @click="cancelEdit">取消</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { fetchReviews, fetchTraces, saveReview, imageUrl } from '../lib/api.js'
import { formatDateTime } from '../lib/formatters.js'

const props = defineProps({
  open: { type: Boolean, default: false },
  runId: { type: String, default: '' },
})

defineEmits(['close'])

// ═══════════════════════════════════════════════
// issue_tags 中文标签映射（完整版）
// ═══════════════════════════════════════════════
const ISSUE_TAG_OPTIONS = [
  { value: 'wrong_domain', label: '域识别错误' },
  { value: 'wrong_amount', label: '金额错误' },
  { value: 'wrong_date', label: '日期错误' },
  { value: 'wrong_category', label: '分类错误' },
  { value: 'missing_key_field', label: '关键字段缺失' },
  { value: 'ai_feedback_too_generic', label: '文案太泛' },
  { value: 'ai_feedback_too_exaggerated', label: '文案夸张' },
  { value: 'ai_feedback_wrong_tone', label: '语气不当' },
  { value: 'hallucination', label: '幻觉编造' },
  { value: 'model_timeout', label: '模型超时' },
  { value: 'parse_failure', label: '解析失败' },
  { value: 'other', label: '其他' },
]

const ISSUE_TAG_LABEL_MAP = ISSUE_TAG_OPTIONS.reduce((acc, item) => {
  acc[item.value] = item.label
  return acc
}, {})

// ═══════════════════════════════════════════════
// 状态
// ═══════════════════════════════════════════════
const loading = ref(false)
const loadError = ref('')
const reviews = ref([]) // 原始 reviews 列表
const traces = ref([]) // 原始 traces 列表

const reviewFilter = ref('all') // all | reviewed | unreviewed
const domainFilter = ref('')

// 内联编辑状态
const editingCaseKey = ref('')
const editForm = ref({
  ratings: { recognition_accuracy: 0, feedback_quality: 0 },
  issue_tags: [],
  notes: '',
  suggested_action: '',
  mode: 'trace',
})
const saving = ref(false)
const hoverRa = ref(0)
const hoverFq = ref(0)

// ═══════════════════════════════════════════════
// 数据加载
// ═══════════════════════════════════════════════
watch(
  () => [props.open, props.runId],
  async ([open, runId]) => {
    if (open && runId) {
      await loadData(runId)
    } else if (!open) {
      // 关闭时清理编辑态
      editingCaseKey.value = ''
      hoverRa.value = 0
      hoverFq.value = 0
    }
  },
  { immediate: true }
)

async function loadData(runId) {
  loading.value = true
  loadError.value = ''
  // 并行拉取 reviews 与 traces
  const [reviewsResult, tracesResult] = await Promise.all([
    fetchReviews(runId),
    fetchTraces(runId),
  ])
  loading.value = false

  if (reviewsResult.error) {
    loadError.value = reviewsResult.error
    reviews.value = []
  } else {
    reviews.value = reviewsResult.data?.reviews || []
  }

  if (tracesResult.error) {
    // traces 失败不致命，仅影响缩略图与域信息
    console.warn('加载 traces 失败:', tracesResult.error)
    traces.value = []
  } else {
    traces.value = tracesResult.data?.traces || []
  }
}

// ═══════════════════════════════════════════════
// 数据合并：traces 为基底，叠加 reviews 详情
// ═══════════════════════════════════════════════
const mergedList = computed(() => {
  const traceMap = new Map()
  for (const t of traces.value) {
    if (t.case_key) traceMap.set(t.case_key, t)
  }
  const reviewMap = new Map()
  for (const r of reviews.value) {
    if (r.case_key) reviewMap.set(r.case_key, r)
  }

  const list = []

  // 基底：所有 traces
  for (const t of traces.value) {
    const r = reviewMap.get(t.case_key) || null
    list.push(buildRecord(t.case_key, t, r))
  }

  // 孤儿 review：reviews 中存在但 traces 没有的（防御性处理）
  for (const r of reviews.value) {
    if (r.case_key && !traceMap.has(r.case_key)) {
      list.push(buildRecord(r.case_key, null, r))
    }
  }

  return list
})

/**
 * 构造单条合并记录
 * @param {string} caseKey
 * @param {object|null} trace
 * @param {object|null} review
 */
function buildRecord(caseKey, trace, review) {
  // 优先用完整 review 对象；若 trace 标记 has_review 但 reviews API 未返回（异常情况），则用 trace.review_ratings 兜底
  let effectiveReview = review
  let reviewed = false
  if (review) {
    reviewed = true
  } else if (trace?.has_review) {
    reviewed = true
    effectiveReview = {
      case_key: caseKey,
      reviewed_at: null,
      ratings: trace.review_ratings || { recognition_accuracy: 0, feedback_quality: 0 },
      issue_tags: [],
      notes: '',
      suggested_action: '',
      mode: '',
    }
  }

  const relativePath = trace?.image_relative_path || null
  return {
    case_key: caseKey,
    reviewed,
    review: effectiveReview,
    trace,
    domain: trace?.test_case_domain || trace?.domain || '',
    image_url: relativePath ? imageUrl(relativePath) : null,
  }
}

// ═══════════════════════════════════════════════
// 域下拉选项
// ═══════════════════════════════════════════════
const domainOptions = computed(() => {
  const set = new Set()
  for (const item of mergedList.value) {
    if (item.domain) set.add(item.domain)
  }
  return Array.from(set).sort()
})

// ═══════════════════════════════════════════════
// 筛选
// ═══════════════════════════════════════════════
const filterOptions = computed(() => {
  const all = mergedList.value
  const reviewedCount = all.filter((i) => i.reviewed).length
  const unreviewedCount = all.length - reviewedCount
  return [
    { key: 'all', label: '全部', count: all.length },
    { key: 'reviewed', label: '已点评', count: reviewedCount },
    { key: 'unreviewed', label: '未点评', count: unreviewedCount },
  ]
})

const filteredList = computed(() => {
  let list = mergedList.value
  if (reviewFilter.value === 'reviewed') {
    list = list.filter((i) => i.reviewed)
  } else if (reviewFilter.value === 'unreviewed') {
    list = list.filter((i) => !i.reviewed)
  }
  if (domainFilter.value) {
    list = list.filter((i) => i.domain === domainFilter.value)
  }
  return list
})

const emptyHint = computed(() => {
  if (reviewFilter.value === 'reviewed') return '暂无点评记录'
  if (reviewFilter.value === 'unreviewed') return '全部样本已点评'
  if (domainFilter.value) return '该筛选条件下无样本'
  return '暂无点评记录'
})

// ═══════════════════════════════════════════════
// 展示辅助
// ═══════════════════════════════════════════════
function starStr(n) {
  const num = Number(n) || 0
  return '★'.repeat(num) + '☆'.repeat(Math.max(0, 5 - num))
}

function issueTagLabel(tag) {
  return ISSUE_TAG_LABEL_MAP[tag] || tag
}

function issueTagsOf(review) {
  return review?.issue_tags || []
}

function modeLabel(mode) {
  if (mode === 'local-simulate') return '模拟'
  if (mode === 'trace') return '线上'
  if (!mode) return '—'
  return mode
}

function modeClass(mode) {
  if (mode === 'local-simulate') return 'sim'
  if (mode === 'trace') return 'online'
  return ''
}

function onThumbError(e) {
  // 图片加载失败，隐藏 img 露出占位符（这里直接替换为占位）
  const img = e.target
  img.style.display = 'none'
  const wrapper = img.parentElement
  if (wrapper && !wrapper.querySelector('.thumb-placeholder')) {
    const ph = document.createElement('div')
    ph.className = 'thumb-placeholder'
    ph.textContent = '加载失败'
    wrapper.appendChild(ph)
  }
}

// ═══════════════════════════════════════════════
// 复评编辑
// ═══════════════════════════════════════════════
const canSaveEdit = computed(
  () => editForm.value.ratings.recognition_accuracy > 0 && editForm.value.ratings.feedback_quality > 0
)

function startEdit(item) {
  editingCaseKey.value = item.case_key
  const r = item.review
  editForm.value = {
    ratings: {
      recognition_accuracy: r?.ratings?.recognition_accuracy || 0,
      feedback_quality: r?.ratings?.feedback_quality || 0,
    },
    issue_tags: r?.issue_tags ? [...r.issue_tags] : [],
    notes: r?.notes || '',
    suggested_action: r?.suggested_action || '',
    // 保留原 mode，未点评的新建默认 trace
    mode: r?.mode || item.trace?.mode || 'trace',
  }
  hoverRa.value = 0
  hoverFq.value = 0
}

function cancelEdit() {
  editingCaseKey.value = ''
  hoverRa.value = 0
  hoverFq.value = 0
}

function toggleEditTag(tag) {
  const idx = editForm.value.issue_tags.indexOf(tag)
  if (idx >= 0) {
    editForm.value.issue_tags.splice(idx, 1)
  } else {
    editForm.value.issue_tags.push(tag)
  }
}

async function saveEdit(item) {
  if (!canSaveEdit.value) return
  saving.value = true

  const payload = {
    ratings: {
      recognition_accuracy: editForm.value.ratings.recognition_accuracy,
      feedback_quality: editForm.value.ratings.feedback_quality,
    },
    issue_tags: editForm.value.issue_tags,
    notes: editForm.value.notes,
    suggested_action: editForm.value.suggested_action,
    mode: editForm.value.mode,
  }

  const { data, error } = await saveReview(props.runId, item.case_key, payload)
  saving.value = false

  if (error) {
    alert('保存失败: ' + error)
    return
  }

  // 用返回数据更新本地 reviews，使 mergedList 自动刷新
  const normalized = normalizeSavedReview(data, item.case_key, payload)
  upsertReview(normalized)
  // 同步 trace 摘要的 has_review / review_ratings
  syncTraceReviewState(item.case_key, normalized)

  editingCaseKey.value = ''
  hoverRa.value = 0
  hoverFq.value = 0
}

/**
 * 将保存返回结果标准化为 review 对象
 * 兼容后端返回完整对象或仅返回 ok 的情形
 */
function normalizeSavedReview(data, caseKey, payload) {
  if (data && typeof data === 'object') {
    return {
      case_key: data.case_key || caseKey,
      reviewed_at: data.reviewed_at || new Date().toISOString(),
      ratings: data.ratings || payload.ratings,
      issue_tags: data.issue_tags || payload.issue_tags,
      notes: data.notes ?? payload.notes,
      suggested_action: data.suggested_action ?? payload.suggested_action,
      mode: data.mode || payload.mode,
    }
  }
  // 后端未返回详情时，基于 payload + 当前时间构造
  return {
    case_key: caseKey,
    reviewed_at: new Date().toISOString(),
    ratings: payload.ratings,
    issue_tags: payload.issue_tags,
    notes: payload.notes,
    suggested_action: payload.suggested_action,
    mode: payload.mode,
  }
}

function upsertReview(review) {
  const idx = reviews.value.findIndex((r) => r.case_key === review.case_key)
  if (idx >= 0) {
    reviews.value[idx] = review
  } else {
    reviews.value.push(review)
  }
}

function syncTraceReviewState(caseKey, review) {
  const t = traces.value.find((x) => x.case_key === caseKey)
  if (!t) return
  t.has_review = true
  t.review_ratings = review.ratings
}
</script>

<style scoped>
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  z-index: 60;
  display: flex;
  align-items: center;
  justify-content: center;
}

.modal-box {
  background: var(--bg-panel);
  border: 1px solid var(--border);
  border-radius: var(--radius-xl);
  width: 96%;
  max-width: 1280px;
  height: 92vh;
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
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  font-family: var(--font-mono);
  word-break: break-all;
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

.action-btn:hover:not(:disabled) {
  border-color: var(--accent-blue);
  color: var(--text-primary);
}

.action-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

/* 工具栏 */
.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-md);
  padding: var(--space-sm) var(--space-lg);
  border-bottom: 1px solid var(--border);
  flex-shrink: 0;
  flex-wrap: wrap;
}

.filter-tabs {
  display: flex;
  gap: var(--space-xs);
  flex-wrap: wrap;
}

.filter-btn {
  font-size: 11px;
  padding: 3px 10px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  white-space: nowrap;
  transition: all 0.12s;
}

.filter-btn.on {
  background: var(--accent-blue);
  color: #fff;
  border-color: var(--accent-blue);
}

.filter-btn:hover:not(.on) {
  border-color: var(--accent-blue);
}

.domain-filter {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.filter-label {
  font-size: 11px;
  color: var(--text-secondary);
}

.domain-select {
  font-size: 11px;
  padding: 3px 8px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-primary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  outline: none;
}

.domain-select:focus {
  border-color: var(--accent-blue);
}

/* 主体 */
.modal-body {
  padding: var(--space-md) var(--space-lg);
  overflow-y: auto;
  flex: 1;
}

/* 状态盒子 */
.state-box {
  text-align: center;
  padding: 60px 0;
  color: var(--text-muted);
  font-size: 13px;
}

.state-box.error {
  color: var(--accent-red);
}

.state-icon {
  font-size: 32px;
  margin-bottom: var(--space-sm);
}

.state-text {
  font-size: 14px;
  font-weight: 600;
  margin-bottom: var(--space-xs);
}

.state-desc {
  font-size: 12px;
  color: var(--text-muted);
  max-width: 500px;
  margin: 0 auto;
  word-break: break-all;
}

/* 卡片网格 */
.cards-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
  gap: var(--space-md);
}

.review-card {
  background: var(--bg-base);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: var(--space-md);
  display: flex;
  flex-direction: column;
  gap: var(--space-sm);
}

/* 卡片顶部：缩略图 + 概要 */
.card-top {
  display: flex;
  gap: var(--space-sm);
}

.card-thumb {
  width: 64px;
  height: 64px;
  flex-shrink: 0;
  border-radius: var(--radius-md);
  overflow: hidden;
  background: var(--bg-hover);
  display: flex;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--border);
}

.thumb-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.thumb-placeholder {
  color: var(--text-muted);
  font-size: 11px;
}

.card-meta {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.meta-row {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  flex-wrap: wrap;
}

.domain-tag {
  font-size: 10px;
  font-weight: 600;
  padding: 1px 8px;
  border-radius: 10px;
  background: rgba(188, 140, 255, 0.12);
  color: var(--accent-purple);
  border: 1px solid rgba(188, 140, 255, 0.25);
}

.mode-badge {
  font-size: 10px;
  font-weight: 600;
  padding: 1px 8px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--bg-hover);
  color: var(--text-secondary);
}

.mode-badge.online {
  background: rgba(63, 185, 80, 0.12);
  color: var(--accent-green);
  border-color: rgba(63, 185, 80, 0.3);
}

.mode-badge.sim {
  background: rgba(210, 153, 34, 0.12);
  color: var(--accent-yellow);
  border-color: rgba(210, 153, 34, 0.3);
}

.case-key {
  font-size: 12px;
  color: var(--text-primary);
  font-family: var(--font-mono);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.review-time {
  font-size: 11px;
  color: var(--text-muted);
}

/* 评分 */
.rating-block {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
  padding: var(--space-sm) 0;
  border-top: 1px dashed var(--border);
  border-bottom: 1px dashed var(--border);
}

.rating-line {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.rating-label {
  font-size: 11px;
  color: var(--text-secondary);
  width: 72px;
  flex-shrink: 0;
}

.stars {
  color: var(--accent-yellow);
  font-size: 14px;
  letter-spacing: 1px;
}

.rating-num {
  font-size: 11px;
  color: var(--text-muted);
  font-family: var(--font-mono);
}

/* 卡片分区 */
.card-section {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
}

.section-label {
  font-size: 11px;
  color: var(--text-secondary);
  font-weight: 600;
}

.tag-list {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.tag-chip {
  font-size: 10px;
  padding: 2px 8px;
  border-radius: var(--radius-sm);
  background: rgba(248, 81, 73, 0.1);
  color: var(--accent-red);
  border: 1px solid rgba(248, 81, 73, 0.25);
  white-space: nowrap;
}

/* 编辑表单中的可点击 tag */
.edit-form .tag-chip {
  cursor: pointer;
  background: var(--bg-hover);
  color: var(--text-muted);
  border: 1px solid var(--border);
  transition: all 0.12s;
}

.edit-form .tag-chip.active {
  background: rgba(88, 166, 255, 0.15);
  color: var(--accent-blue);
  border-color: var(--accent-blue);
}

.edit-form .tag-chip:hover:not(.active) {
  border-color: var(--accent-blue);
}

.text-block {
  font-size: 12px;
  color: var(--text-primary);
  line-height: 1.6;
  padding: var(--space-xs) var(--space-sm);
  background: var(--bg-hover);
  border-radius: var(--radius-sm);
  word-break: break-word;
  white-space: pre-wrap;
}

.text-block.accent {
  color: var(--accent-blue);
  border-left: 2px solid var(--accent-blue);
}

/* 未点评提示 */
.not-reviewed-hint {
  font-size: 12px;
  color: var(--text-muted);
  padding: var(--space-sm) 0;
  font-style: italic;
}

/* 卡片底部 */
.card-footer {
  display: flex;
  justify-content: flex-end;
  margin-top: auto;
}

.re-review-btn {
  font-size: 12px;
  padding: 4px 14px;
  border-radius: var(--radius-sm);
  background: var(--accent-blue);
  color: #fff;
  border: none;
  cursor: pointer;
  font-family: var(--font-sans);
  font-weight: 600;
}

.re-review-btn:hover {
  opacity: 0.9;
}

/* 内联编辑表单 */
.edit-form {
  display: flex;
  flex-direction: column;
  gap: var(--space-sm);
  padding: var(--space-sm);
  background: var(--bg-hover);
  border-radius: var(--radius-md);
  border: 1px solid var(--accent-blue);
}

.edit-title {
  font-size: 12px;
  font-weight: 700;
  color: var(--accent-blue);
}

.star-group {
  display: flex;
  gap: 2px;
}

.star-btn {
  font-size: 16px;
  line-height: 1;
  background: none;
  border: none;
  cursor: pointer;
  color: var(--text-muted);
  padding: 0 2px;
  transition: color 0.1s;
  font-family: var(--font-sans);
}

.star-btn.active {
  color: var(--accent-yellow);
}

.star-btn:hover {
  color: var(--accent-yellow);
}

.notes-input {
  width: 100%;
  background: var(--bg-base);
  color: var(--text-primary);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: var(--space-xs) var(--space-sm);
  font-size: 12px;
  font-family: var(--font-sans);
  resize: vertical;
  outline: none;
  box-sizing: border-box;
}

.notes-input:focus {
  border-color: var(--accent-blue);
}

.action-input {
  width: 100%;
  background: var(--bg-base);
  color: var(--text-primary);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: var(--space-xs) var(--space-sm);
  font-size: 12px;
  font-family: var(--font-sans);
  outline: none;
  box-sizing: border-box;
}

.action-input:focus {
  border-color: var(--accent-blue);
}

.action-row {
  display: flex;
  gap: var(--space-sm);
}

.save-btn {
  font-size: 12px;
  padding: 5px 18px;
  border-radius: var(--radius-sm);
  background: var(--accent-blue);
  color: #fff;
  border: none;
  cursor: pointer;
  font-family: var(--font-sans);
  font-weight: 600;
}

.save-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.save-btn:hover:not(:disabled) {
  opacity: 0.9;
}

.cancel-btn {
  font-size: 12px;
  padding: 5px 18px;
  border-radius: var(--radius-sm);
  background: var(--bg-base);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
}

.cancel-btn:hover:not(:disabled) {
  border-color: var(--accent-blue);
}

.cancel-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

/* 响应式：窄屏单列 */
@media (max-width: 640px) {
  .modal-box {
    width: 100%;
    height: 100vh;
    border-radius: 0;
  }

  .cards-grid {
    grid-template-columns: 1fr;
  }

  .toolbar {
    flex-direction: column;
    align-items: stretch;
  }
}
</style>
