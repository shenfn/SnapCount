<template>
  <!-- 浮动模式：遮罩 -->
  <div v-if="!embedded" class="review-mask" :class="{ on: open }" @click="$emit('close')"></div>

  <!-- 浮动模式：抽屉 -->
  <div v-if="!embedded" class="review-drawer" :class="{ open: open }">
    <div class="drawer-header">
      <span class="drawer-title">点评</span>
      <span class="review-status" v-if="reviewState === 'loading'">加载中...</span>
      <span class="review-status saved" v-else-if="reviewState === 'saved'">已保存</span>
      <span class="review-status dirty" v-else-if="reviewState === 'dirty'">未保存</span>
      <button class="close-btn" @click="$emit('close')">收起</button>
    </div>
    <div class="drawer-body" v-if="open">
      <ReviewBody
        :image-url="imageUrl"
        :ratings="ratings"
        :issue-tags="issueTags"
        :notes="notes"
        :suggested-action="suggestedAction"
        :review-state="reviewState"
        :issue-tag-options="ISSUE_TAG_OPTIONS"
        :image-expanded="imageExpanded"
        @rating="onRatingInput"
        @toggle-tag="toggleTag"
        @update:notes="notes = $event; markDirty()"
        @update:suggested-action="suggestedAction = $event; markDirty()"
        @toggle-image="imageExpanded = !imageExpanded"
        @save="onSave"
      />
    </div>
  </div>

  <!-- 内嵌模式：可折叠块 -->
  <div v-else class="review-embedded" :class="{ collapsed: !embeddedOpen }">
    <div class="embedded-header" @click="embeddedOpen = !embeddedOpen">
      <span class="embedded-title">点评</span>
      <span class="review-status" v-if="reviewState === 'loading'">加载中...</span>
      <span class="review-status saved" v-else-if="reviewState === 'saved'">已保存 ✓</span>
      <span class="review-status dirty" v-else-if="reviewState === 'dirty'">未保存</span>
      <span class="embedded-toggle">{{ embeddedOpen ? '收起 ▲' : '展开 ▼' }}</span>
    </div>
    <div class="embedded-body" v-show="embeddedOpen">
      <ReviewBody
        :image-url="imageUrl"
        :ratings="ratings"
        :issue-tags="issueTags"
        :notes="notes"
        :suggested-action="suggestedAction"
        :review-state="reviewState"
        :issue-tag-options="ISSUE_TAG_OPTIONS"
        :image-expanded="imageExpanded"
        @rating="onRatingInput"
        @toggle-tag="toggleTag"
        @update:notes="notes = $event; markDirty()"
        @update:suggested-action="suggestedAction = $event; markDirty()"
        @toggle-image="imageExpanded = !imageExpanded"
        @save="onSave"
      />
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { saveReview, fetchReview, imageUrl as buildImageUrl, remoteImageUrl } from '../lib/api.js'
import ReviewBody from './ReviewBody.vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  runId: { type: String, required: true },
  caseKey: { type: String, required: true },
  mode: { type: String, default: 'trace' },
  simSnapshot: { type: Object, default: null },
  traceSnapshot: { type: Object, default: null },
  accountKey: { type: String, default: '' },
  embedded: { type: Boolean, default: false },
})

const emit = defineEmits(['close', 'saved'])

// issue_tags 枚举 -> 中文标签映射
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

// 状态机：idle -> loading -> dirty -> saving -> saved
const reviewState = ref('idle')
const imageExpanded = ref(false)
const imageError = ref(false)
const embeddedOpen = ref(true)

// 表单数据
const ratings = ref({ recognition_accuracy: 0, feedback_quality: 0 })
const issueTags = ref([])
const notes = ref('')
const suggestedAction = ref('')

const canSave = computed(
  () => ratings.value.recognition_accuracy > 0 && ratings.value.feedback_quality > 0
)

const saveBtnText = computed(() => {
  if (reviewState.value === 'saving') return '保存中...'
  if (reviewState.value === 'saved') return '已保存 ✓'
  return '保存点评'
})

// 计算图片 URL（支持本地和远程）
const imageUrl = computed(() => {
  if (!props.traceSnapshot || imageError.value) return null
  const t = props.traceSnapshot
  // 远程模式
  if (t.is_remote || (t.case && t.case.image_status)) {
    if (t.case?.image_status === 'available' && t.trace_id) {
      return remoteImageUrl(t.trace_id, props.accountKey)
    }
    return null
  }
  // 本地模式
  if (t.case?.image_relative_path) {
    return buildImageUrl(t.case.image_relative_path)
  }
  return null
})

// 记录上次加载的 caseKey，避免收起/展开时重复加载丢草稿
const lastLoadedKey = ref('')

// 抽屉打开时：仅在 caseKey 变化时才重新加载（收起再展开不丢草稿）
watch(() => props.open, async (isOpen) => {
  if (!isOpen) return
  imageError.value = false
  imageExpanded.value = false
  if (props.caseKey && props.caseKey !== lastLoadedKey.value) {
    await loadReview()
  }
})

// caseKey 变化时（切换 trace）重新加载
watch(() => props.caseKey, async (newKey) => {
  if (props.open && newKey && newKey !== lastLoadedKey.value) {
    imageError.value = false
    await loadReview()
  }
})

// embedded 模式：caseKey 变化时重新加载
watch(() => props.embedded ? props.caseKey : null, async (newKey) => {
  if (newKey && newKey !== lastLoadedKey.value) {
    imageError.value = false
    await loadReview()
  }
})

async function loadReview() {
  reviewState.value = 'loading'
  lastLoadedKey.value = props.caseKey
  const { data, error } = await fetchReview(props.runId, props.caseKey)
  if (error || !data) {
    // 404 或失败：重置表单，回到 idle
    ratings.value = { recognition_accuracy: 0, feedback_quality: 0 }
    issueTags.value = []
    notes.value = ''
    suggestedAction.value = ''
    reviewState.value = 'idle'
    return
  }
  // 回填已有点评
  ratings.value = {
    recognition_accuracy: data.ratings?.recognition_accuracy || 0,
    feedback_quality: data.ratings?.feedback_quality || 0,
  }
  issueTags.value = Array.isArray(data.issue_tags) ? [...data.issue_tags] : []
  notes.value = data.notes || ''
  suggestedAction.value = data.suggested_action || ''
  reviewState.value = 'saved'
}

function onImageError() {
  imageError.value = true
}

function onRatingInput(field, event) {
  ratings.value[field] = Number(event.target.value)
  markDirty()
}

function markDirty() {
  if (reviewState.value !== 'saving' && reviewState.value !== 'loading') {
    reviewState.value = 'dirty'
  }
}

function toggleTag(tag) {
  const idx = issueTags.value.indexOf(tag)
  if (idx >= 0) {
    issueTags.value.splice(idx, 1)
  } else {
    issueTags.value.push(tag)
  }
  markDirty()
}

async function onSave() {
  if (!canSave.value) return
  reviewState.value = 'saving'

  const payload = {
    ratings: {
      recognition_accuracy: ratings.value.recognition_accuracy,
      feedback_quality: ratings.value.feedback_quality,
    },
    issue_tags: [...issueTags.value],
    notes: notes.value,
    suggested_action: suggestedAction.value,
    mode: props.mode,
    sim_snapshot: props.mode === 'local-simulate' && props.simSnapshot ? props.simSnapshot : null,
    trace_snapshot: props.traceSnapshot || null,
  }

  const { data, error } = await saveReview(props.runId, props.caseKey, payload)
  if (error) {
    reviewState.value = 'dirty'
    alert('保存失败: ' + error)
    return
  }

  reviewState.value = 'saved'
  emit('saved', data)
}
</script>

<style scoped>
/* 遮罩 — 半透明，不完全挡住链路 */
.review-mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.25);
  z-index: 39;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.2s;
}
.review-mask.on {
  opacity: 1;
  pointer-events: auto;
}

/* 抽屉 — 右侧浮动 */
.review-drawer {
  position: fixed;
  top: 0;
  right: 0;
  bottom: 0;
  width: 380px;
  background: var(--bg-panel);
  border-left: 1px solid var(--border);
  transform: translateX(100%);
  transition: transform 0.2s ease;
  z-index: 40;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.review-drawer.open {
  transform: translateX(0);
}

/* 头部 */
.drawer-header {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-md) var(--space-lg);
  border-bottom: 1px solid var(--border);
  flex-shrink: 0;
}

.drawer-title {
  font-size: 13px;
  font-weight: 700;
  color: var(--accent-blue);
}

.review-status {
  font-size: 10px;
  color: var(--text-muted);
}
.review-status.saved { color: var(--accent-green); font-weight: 600; }
.review-status.dirty { color: var(--accent-yellow); }

.close-btn {
  margin-left: auto;
  font-size: 12px;
  padding: 3px 10px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
}
.close-btn:hover { background: var(--bg-active); }

/* 内容区 */
.drawer-body {
  padding: var(--space-md) var(--space-lg);
  overflow-y: auto;
  flex: 1;
}

/* 图片预览 */
.image-section {
  margin-bottom: var(--space-md);
}
.image-section.empty .no-image {
  font-size: 12px;
  color: var(--text-muted);
  text-align: center;
  padding: var(--space-md);
  background: var(--bg-hover);
  border-radius: var(--radius-md);
  border: 1px dashed var(--border);
}
.image-wrapper {
  border-radius: var(--radius-md);
  overflow: hidden;
  border: 1px solid var(--border);
  cursor: pointer;
  background: #0a0e14;
}
.preview-image {
  width: 100%;
  max-height: 200px;
  object-fit: contain;
  display: block;
  transition: max-height 0.2s;
}
.preview-image.expanded {
  max-height: 600px;
}
.image-hint {
  font-size: 10px;
  color: var(--text-muted);
  text-align: center;
  margin-top: 4px;
}

/* 评分 */
.rating-section {
  display: flex;
  flex-direction: column;
  gap: var(--space-sm);
  margin-bottom: var(--space-md);
}
.rating-row {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}
.rating-label {
  font-size: 11px;
  color: var(--text-secondary);
  width: 64px;
  flex-shrink: 0;
}

.rating-slider {
  flex: 1;
  min-width: 60px;
  -webkit-appearance: none;
  appearance: none;
  height: 4px;
  background: var(--bg-hover);
  border-radius: var(--radius-sm);
  outline: none;
  cursor: pointer;
}
.rating-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: var(--accent-blue);
  border: 2px solid var(--bg-panel);
  cursor: pointer;
  transition: transform 0.1s;
}
.rating-slider::-webkit-slider-thumb:hover { transform: scale(1.15); }
.rating-slider::-moz-range-thumb {
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: var(--accent-blue);
  border: 2px solid var(--bg-panel);
  cursor: pointer;
}

.star-display { display: flex; gap: 1px; flex-shrink: 0; }
.star { font-size: 14px; line-height: 1; color: var(--text-muted); opacity: 0.5; }
.star.filled { color: var(--accent-yellow); opacity: 1; }
.rating-value {
  font-size: 10px;
  color: var(--text-muted);
  width: 40px;
  text-align: right;
  flex-shrink: 0;
  font-family: var(--font-mono);
}

/* 标签 */
.tag-section { margin-bottom: var(--space-md); }
.section-label {
  font-size: 11px;
  color: var(--text-secondary);
  display: block;
  margin-bottom: var(--space-xs);
}
.tag-list { display: flex; flex-wrap: wrap; gap: 4px; }
.tag-checkbox {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
  padding: 3px 8px 3px 6px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-muted);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  transition: all 0.12s;
  white-space: nowrap;
  user-select: none;
}
.tag-checkbox input { position: absolute; opacity: 0; width: 0; height: 0; margin: 0; }
.tag-box {
  width: 10px; height: 10px;
  border-radius: 2px;
  border: 1px solid var(--text-muted);
  background: transparent;
  position: relative;
  flex-shrink: 0;
  transition: all 0.12s;
}
.tag-checkbox input:checked ~ .tag-box {
  background: var(--accent-blue);
  border-color: var(--accent-blue);
}
.tag-checkbox input:checked ~ .tag-box::after {
  content: '';
  position: absolute;
  left: 2px; top: 0;
  width: 4px; height: 7px;
  border: solid #fff;
  border-width: 0 1.5px 1.5px 0;
  transform: rotate(45deg);
}
.tag-checkbox.active { color: var(--accent-blue); border-color: var(--accent-blue); }
.tag-checkbox:hover:not(.active) { border-color: var(--accent-blue); color: var(--text-secondary); }

/* 文本输入 */
.text-section { margin-bottom: var(--space-md); }
.section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--space-xs);
}
.char-counter { font-size: 10px; color: var(--text-muted); font-family: var(--font-mono); }
.notes-input, .action-input {
  width: 100%;
  background: var(--bg-hover);
  color: var(--text-primary);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: var(--space-xs) var(--space-sm);
  font-size: 12px;
  font-family: var(--font-sans);
  resize: vertical;
  outline: none;
  box-sizing: border-box;
  line-height: 1.5;
}
.notes-input:focus, .action-input:focus { border-color: var(--accent-blue); }
.notes-input::placeholder, .action-input::placeholder { color: var(--text-muted); }

/* 按钮 */
.action-row { display: flex; gap: var(--space-sm); margin-top: var(--space-sm); }
.save-btn {
  font-size: 12px;
  padding: 6px 20px;
  border-radius: var(--radius-sm);
  background: var(--accent-blue);
  color: #fff;
  border: none;
  cursor: pointer;
  font-family: var(--font-sans);
  font-weight: 600;
  transition: opacity 0.12s;
  width: 100%;
}
.save-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.save-btn:hover:not(:disabled) { opacity: 0.9; }

/* ═══ 内嵌模式（UploadPanel 用） ═══ */
.review-embedded {
  margin-top: var(--space-md);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--bg-panel);
  overflow: hidden;
}
.embedded-header {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-sm) var(--space-md);
  background: var(--bg-hover);
  cursor: pointer;
  user-select: none;
  transition: background 0.12s;
}
.embedded-header:hover { background: var(--bg-active); }
.embedded-title {
  font-size: 13px;
  font-weight: 700;
  color: var(--accent-blue);
}
.embedded-toggle {
  margin-left: auto;
  font-size: 11px;
  color: var(--text-muted);
  white-space: nowrap;
}
.embedded-body {
  padding: var(--space-md);
}
</style>
