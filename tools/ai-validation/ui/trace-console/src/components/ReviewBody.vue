<template>
  <div class="review-body">
    <!-- 图片预览 -->
    <div class="image-section" v-if="imageUrl">
      <div class="section-label">识别图片</div>
      <div class="image-wrapper" @click="$emit('toggle-image')">
        <img
          :src="imageUrl"
          class="preview-image"
          :class="{ expanded: imageExpanded }"
          loading="lazy"
          @error="$emit('toggle-image')"
        />
      </div>
      <div class="image-hint" v-if="!imageExpanded">点击放大</div>
    </div>
    <div class="image-section empty" v-else>
      <div class="section-label">识别图片</div>
      <div class="no-image">无图片</div>
    </div>

    <!-- 评分区 -->
    <div class="rating-section">
      <div class="rating-row">
        <span class="rating-label">识别准确度</span>
        <input
          type="range"
          class="rating-slider"
          min="0"
          max="5"
          step="1"
          :value="ratings.recognition_accuracy"
          @input="$emit('rating', 'recognition_accuracy', $event)"
        />
        <div class="star-display">
          <span
            v-for="n in 5"
            :key="`ra-${n}`"
            class="star"
            :class="{ filled: ratings.recognition_accuracy >= n }"
          >★</span>
        </div>
        <span class="rating-value">{{ ratings.recognition_accuracy || '未评分' }}</span>
      </div>
      <div class="rating-row">
        <span class="rating-label">文案质量</span>
        <input
          type="range"
          class="rating-slider"
          min="0"
          max="5"
          step="1"
          :value="ratings.feedback_quality"
          @input="$emit('rating', 'feedback_quality', $event)"
        />
        <div class="star-display">
          <span
            v-for="n in 5"
            :key="`fq-${n}`"
            class="star"
            :class="{ filled: ratings.feedback_quality >= n }"
          >★</span>
        </div>
        <span class="rating-value">{{ ratings.feedback_quality || '未评分' }}</span>
      </div>
    </div>

    <!-- 问题标签 -->
    <div class="tag-section">
      <span class="section-label">问题标签（可多选）</span>
      <div class="tag-list">
        <label
          v-for="tag in issueTagOptions"
          :key="tag.value"
          class="tag-checkbox"
          :class="{ active: issueTags.includes(tag.value) }"
        >
          <input
            type="checkbox"
            :checked="issueTags.includes(tag.value)"
            @change="$emit('toggle-tag', tag.value)"
          />
          <span class="tag-box"></span>
          <span class="tag-label">{{ tag.label }}</span>
        </label>
      </div>
    </div>

    <!-- 点评备注 -->
    <div class="text-section">
      <div class="section-head">
        <span class="section-label">点评备注</span>
        <span class="char-counter">{{ notes.length }}/2000</span>
      </div>
      <textarea
        :value="notes"
        class="notes-input"
        placeholder="记录你的感受，比如哪里不够好、缺什么"
        maxlength="2000"
        rows="4"
        @input="$emit('update:notes', $event.target.value)"
      ></textarea>
    </div>

    <!-- 改进建议 -->
    <div class="text-section">
      <div class="section-head">
        <span class="section-label">改进建议（可选）</span>
        <span class="char-counter">{{ suggestedAction.length }}/500</span>
      </div>
      <textarea
        :value="suggestedAction"
        class="action-input"
        placeholder="希望 AI 怎么改进"
        maxlength="500"
        rows="2"
        @input="$emit('update:suggested-action', $event.target.value)"
      ></textarea>
    </div>

    <!-- 操作按钮 -->
    <div class="action-row">
      <button
        class="save-btn"
        :disabled="!canSave || reviewState === 'saving'"
        @click="$emit('save')"
      >
        {{ saveBtnText }}
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  imageUrl: { type: String, default: null },
  ratings: { type: Object, required: true },
  issueTags: { type: Array, required: true },
  notes: { type: String, default: '' },
  suggestedAction: { type: String, default: '' },
  reviewState: { type: String, default: 'idle' },
  issueTagOptions: { type: Array, required: true },
  imageExpanded: { type: Boolean, default: false },
})

defineEmits([
  'rating', 'toggle-tag', 'update:notes', 'update:suggested-action',
  'toggle-image', 'save',
])

const canSave = computed(
  () => props.ratings.recognition_accuracy > 0 && props.ratings.feedback_quality > 0
)

const saveBtnText = computed(() => {
  if (props.reviewState === 'saving') return '保存中...'
  if (props.reviewState === 'saved') return '已保存 ✓'
  return '保存点评'
})
</script>

<style scoped>
.review-body { display: flex; flex-direction: column; }

.image-section { margin-bottom: var(--space-md); }
.image-section.empty .no-image {
  font-size: 12px; color: var(--text-muted); text-align: center;
  padding: var(--space-md); background: var(--bg-hover);
  border-radius: var(--radius-md); border: 1px dashed var(--border);
}
.image-wrapper {
  border-radius: var(--radius-md); overflow: hidden;
  border: 1px solid var(--border); cursor: pointer; background: #0a0e14;
}
.preview-image {
  width: 100%; max-height: 200px; object-fit: contain; display: block;
  transition: max-height 0.2s;
}
.preview-image.expanded { max-height: 600px; }
.image-hint { font-size: 10px; color: var(--text-muted); text-align: center; margin-top: 4px; }

.rating-section { display: flex; flex-direction: column; gap: var(--space-sm); margin-bottom: var(--space-md); }
.rating-row { display: flex; align-items: center; gap: var(--space-sm); }
.rating-label { font-size: 11px; color: var(--text-secondary); width: 64px; flex-shrink: 0; }
.rating-slider {
  flex: 1; min-width: 60px; -webkit-appearance: none; appearance: none;
  height: 4px; background: var(--bg-hover); border-radius: var(--radius-sm);
  outline: none; cursor: pointer;
}
.rating-slider::-webkit-slider-thumb {
  -webkit-appearance: none; appearance: none; width: 14px; height: 14px;
  border-radius: 50%; background: var(--accent-blue); border: 2px solid var(--bg-panel);
  cursor: pointer; transition: transform 0.1s;
}
.rating-slider::-webkit-slider-thumb:hover { transform: scale(1.15); }
.rating-slider::-moz-range-thumb {
  width: 14px; height: 14px; border-radius: 50%; background: var(--accent-blue);
  border: 2px solid var(--bg-panel); cursor: pointer;
}
.star-display { display: flex; gap: 1px; flex-shrink: 0; }
.star { font-size: 14px; line-height: 1; color: var(--text-muted); opacity: 0.5; }
.star.filled { color: var(--accent-yellow); opacity: 1; }
.rating-value {
  font-size: 10px; color: var(--text-muted); width: 40px; text-align: right;
  flex-shrink: 0; font-family: var(--font-mono);
}

.tag-section { margin-bottom: var(--space-md); }
.section-label { font-size: 11px; color: var(--text-secondary); display: block; margin-bottom: var(--space-xs); }
.tag-list { display: flex; flex-wrap: wrap; gap: 4px; }
.tag-checkbox {
  display: inline-flex; align-items: center; gap: 4px; font-size: 10px;
  padding: 3px 8px 3px 6px; border-radius: var(--radius-sm);
  background: var(--bg-hover); color: var(--text-muted);
  border: 1px solid var(--border); cursor: pointer; font-family: var(--font-sans);
  transition: all 0.12s; white-space: nowrap; user-select: none;
}
.tag-checkbox input { position: absolute; opacity: 0; width: 0; height: 0; margin: 0; }
.tag-box {
  width: 10px; height: 10px; border-radius: 2px; border: 1px solid var(--text-muted);
  background: transparent; position: relative; flex-shrink: 0; transition: all 0.12s;
}
.tag-checkbox input:checked ~ .tag-box { background: var(--accent-blue); border-color: var(--accent-blue); }
.tag-checkbox input:checked ~ .tag-box::after {
  content: ''; position: absolute; left: 2px; top: 0; width: 4px; height: 7px;
  border: solid #fff; border-width: 0 1.5px 1.5px 0; transform: rotate(45deg);
}
.tag-checkbox.active { color: var(--accent-blue); border-color: var(--accent-blue); }
.tag-checkbox:hover:not(.active) { border-color: var(--accent-blue); color: var(--text-secondary); }

.text-section { margin-bottom: var(--space-md); }
.section-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: var(--space-xs); }
.char-counter { font-size: 10px; color: var(--text-muted); font-family: var(--font-mono); }
.notes-input, .action-input {
  width: 100%; background: var(--bg-hover); color: var(--text-primary);
  border: 1px solid var(--border); border-radius: var(--radius-sm);
  padding: var(--space-xs) var(--space-sm); font-size: 12px;
  font-family: var(--font-sans); resize: vertical; outline: none;
  box-sizing: border-box; line-height: 1.5;
}
.notes-input:focus, .action-input:focus { border-color: var(--accent-blue); }
.notes-input::placeholder, .action-input::placeholder { color: var(--text-muted); }

.action-row { display: flex; gap: var(--space-sm); margin-top: var(--space-sm); }
.save-btn {
  font-size: 12px; padding: 6px 20px; border-radius: var(--radius-sm);
  background: var(--accent-blue); color: #fff; border: none; cursor: pointer;
  font-family: var(--font-sans); font-weight: 600; transition: opacity 0.12s; width: 100%;
}
.save-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.save-btn:hover:not(:disabled) { opacity: 0.9; }
</style>
