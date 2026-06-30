<template>
  <div class="review-panel">
    <div class="review-header">
      <span class="review-title">点评</span>
      <span class="review-status" v-if="reviewState === 'loading'">加载中...</span>
      <span class="review-status" v-if="reviewState === 'saved'">已保存</span>
    </div>

    <!-- 评分区 -->
    <div class="rating-section">
      <div class="rating-row">
        <span class="rating-label">识别准度</span>
        <div class="star-group">
          <button
            v-for="n in 5"
            :key="`ra-${n}`"
            class="star-btn"
            :class="{ active: ratings.recognition_accuracy >= n }"
            @click="ratings.recognition_accuracy = n; markDirty()"
            @mouseenter="hoverRa = n"
            @mouseleave="hoverRa = 0"
          >{{ ratings.recognition_accuracy >= n || hoverRa >= n ? '★' : '☆' }}</button>
        </div>
      </div>
      <div class="rating-row">
        <span class="rating-label">文案质量</span>
        <div class="star-group">
          <button
            v-for="n in 5"
            :key="`fq-${n}`"
            class="star-btn"
            :class="{ active: ratings.feedback_quality >= n }"
            @click="ratings.feedback_quality = n; markDirty()"
            @mouseenter="hoverFq = n"
            @mouseleave="hoverFq = 0"
          >{{ ratings.feedback_quality >= n || hoverFq >= n ? '★' : '☆' }}</button>
        </div>
      </div>
    </div>

    <!-- 问题标签 -->
    <div class="tag-section">
      <span class="section-label">问题标签（可多选）</span>
      <div class="tag-list">
        <button
          v-for="tag in ISSUE_TAG_OPTIONS"
          :key="tag.value"
          class="tag-chip"
          :class="{ active: issueTags.includes(tag.value) }"
          @click="toggleTag(tag.value)"
        >{{ tag.label }}</button>
      </div>
    </div>

    <!-- 文字点评 -->
    <div class="text-section">
      <span class="section-label">点评内容</span>
      <textarea
        v-model="notes"
        class="notes-input"
        placeholder="记录你的感受，比如哪里不够好、缺什么"
        rows="3"
        @input="markDirty()"
      ></textarea>
    </div>

    <!-- 改进建议 -->
    <div class="text-section">
      <span class="section-label">改进建议（可选）</span>
      <input
        v-model="suggestedAction"
        class="action-input"
        placeholder="希望 AI 怎么改进"
        @input="markDirty()"
      />
    </div>

    <!-- 操作按钮 -->
    <div class="action-row">
      <button class="save-btn" :disabled="!canSave || reviewState === 'saving'" @click="onSave">
        {{ reviewState === 'saving' ? '保存中...' : '保存点评' }}
      </button>
      <button class="cancel-btn" @click="$emit('cancel')">取消</button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { saveReview, fetchReview } from '../lib/api.js'

const props = defineProps({
  runId: { type: String, required: true },
  caseKey: { type: String, required: true },
  mode: { type: String, default: 'trace' },
  simSnapshot: { type: Object, default: null },
})

const emit = defineEmits(['saved', 'cancel'])

// issue_tags 枚举映射
const ISSUE_TAG_OPTIONS = [
  { value: 'wrong_domain', label: '域识别错' },
  { value: 'wrong_amount', label: '金额错' },
  { value: 'wrong_date', label: '日期错' },
  { value: 'wrong_category', label: '分类错' },
  { value: 'missing_key_field', label: '漏关键字段' },
  { value: 'ai_feedback_too_generic', label: '文案套话' },
  { value: 'ai_feedback_too_exaggerated', label: '文案夸张' },
  { value: 'ai_feedback_wrong_tone', label: '语气不对' },
  { value: 'hallucination', label: '幻觉' },
  { value: 'model_timeout', label: '超时' },
  { value: 'parse_failure', label: '解析失败' },
  { value: 'other', label: '其他' },
]

// 状态机：idle → loading → dirty → saving → saved
const reviewState = ref('idle')
const hoverRa = ref(0)
const hoverFq = ref(0)

// 表单数据
const ratings = ref({ recognition_accuracy: 0, feedback_quality: 0 })
const issueTags = ref([])
const notes = ref('')
const suggestedAction = ref('')

const canSave = computed(() => ratings.value.recognition_accuracy > 0 && ratings.value.feedback_quality > 0)

// 挂载时尝试拉取已有点评
onMounted(async () => {
  reviewState.value = 'loading'
  const { data, error } = await fetchReview(props.runId, props.caseKey)
  if (error || !data) {
    // 404 或失败，静默回到 idle，不阻塞新建
    reviewState.value = 'idle'
    return
  }
  // 回填已有点评
  ratings.value = {
    recognition_accuracy: data.ratings?.recognition_accuracy || 0,
    feedback_quality: data.ratings?.feedback_quality || 0,
  }
  issueTags.value = data.issue_tags || []
  notes.value = data.notes || ''
  suggestedAction.value = data.suggested_action || ''
  reviewState.value = 'idle'
})

function markDirty() {
  reviewState.value = 'dirty'
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
  if (!ratings.value.recognition_accuracy || !ratings.value.feedback_quality) return
  reviewState.value = 'saving'

  const payload = {
    ratings: {
      recognition_accuracy: ratings.value.recognition_accuracy,
      feedback_quality: ratings.value.feedback_quality,
    },
    issue_tags: issueTags.value,
    notes: notes.value,
    suggested_action: suggestedAction.value,
    mode: props.mode,
  }

  // 本地模拟模式附带 sim_snapshot
  if (props.mode === 'local-simulate' && props.simSnapshot) {
    payload.sim_snapshot = props.simSnapshot
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
.review-panel {
  background: var(--bg-base);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: var(--space-md);
  margin-top: var(--space-md);
}

.review-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--space-sm);
}

.review-title {
  font-size: 12px;
  font-weight: 700;
  color: var(--accent-blue);
}

.review-status {
  font-size: 10px;
  color: var(--text-muted);
}

.review-status:empty { display: none; }

/* 评分 */
.rating-section {
  display: flex;
  flex-direction: column;
  gap: var(--space-xs);
  margin-bottom: var(--space-sm);
}

.rating-row {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
}

.rating-label {
  font-size: 11px;
  color: var(--text-secondary);
  width: 60px;
  flex-shrink: 0;
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

/* 标签 */
.tag-section {
  margin-bottom: var(--space-sm);
}

.section-label {
  font-size: 11px;
  color: var(--text-secondary);
  display: block;
  margin-bottom: var(--space-xs);
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
  background: var(--bg-hover);
  color: var(--text-muted);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
  transition: all 0.12s;
  white-space: nowrap;
}

.tag-chip.active {
  background: rgba(88, 166, 255, 0.15);
  color: var(--accent-blue);
  border-color: var(--accent-blue);
}

.tag-chip:hover:not(.active) {
  border-color: var(--accent-blue);
}

/* 文本输入 */
.text-section {
  margin-bottom: var(--space-sm);
}

.notes-input {
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
}

.notes-input:focus { border-color: var(--accent-blue); }

.action-input {
  width: 100%;
  background: var(--bg-hover);
  color: var(--text-primary);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: var(--space-xs) var(--space-sm);
  font-size: 12px;
  font-family: var(--font-sans);
  outline: none;
  box-sizing: border-box;
}

.action-input:focus { border-color: var(--accent-blue); }

/* 按钮 */
.action-row {
  display: flex;
  gap: var(--space-sm);
  margin-top: var(--space-sm);
}

.save-btn {
  font-size: 12px;
  padding: 5px 16px;
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

.save-btn:hover:not(:disabled) { opacity: 0.9; }

.cancel-btn {
  font-size: 12px;
  padding: 5px 16px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
}

.cancel-btn:hover { border-color: var(--accent-blue); }
</style>
