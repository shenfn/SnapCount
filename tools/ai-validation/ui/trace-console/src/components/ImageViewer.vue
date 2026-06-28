<template>
  <!-- 缩略图模式 -->
  <div class="thumb-wrapper" @click="open = true" v-if="!open">
    <img
      v-if="src"
      :src="src"
      class="thumb-img"
      loading="lazy"
      @error="onError"
    />
    <div v-else class="thumb-placeholder">无图</div>
  </div>

  <!-- 放大查看模态框 -->
  <teleport to="body">
    <div class="viewer-overlay" v-if="open" @click="open = false">
      <div class="viewer-content" @click.stop>
        <div class="viewer-header">
          <span class="viewer-title">{{ fileName }}</span>
          <button class="viewer-close" @click="open = false">关闭</button>
        </div>
        <div class="viewer-body">
          <img
            v-if="src && !error"
            :src="src"
            class="full-image"
            @click="open = false"
          />
          <div v-else class="viewer-error">
            <div class="error-icon">🖼️</div>
            <div class="error-text">图片加载失败</div>
          </div>
        </div>
      </div>
    </div>
  </teleport>
</template>

<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  src: { type: String, default: null },
  fileName: { type: String, default: '' },
})

const open = ref(false)
const error = ref(false)

const fileName = computed(() => props.fileName || '测试图片')

function onError() {
  error.value = true
}
</script>

<style scoped>
.thumb-wrapper {
  width: 36px;
  height: 36px;
  flex-shrink: 0;
  border-radius: var(--radius-sm);
  overflow: hidden;
  background: var(--bg-base);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.thumb-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  transition: transform 0.15s;
}

.thumb-wrapper:hover .thumb-img {
  transform: scale(1.1);
}

.thumb-placeholder {
  color: var(--text-muted);
  font-size: 11px;
}

.viewer-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.8);
  z-index: 60;
  display: flex;
  align-items: center;
  justify-content: center;
}

.viewer-content {
  background: var(--bg-panel);
  border: 1px solid var(--border);
  border-radius: var(--radius-xl);
  max-width: 90vw;
  max-height: 90vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.viewer-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--space-md) var(--space-lg);
  border-bottom: 1px solid var(--border);
}

.viewer-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary);
}

.viewer-close {
  font-size: 12px;
  padding: 3px 10px;
  border-radius: var(--radius-sm);
  background: var(--bg-hover);
  color: var(--text-secondary);
  border: 1px solid var(--border);
  cursor: pointer;
  font-family: var(--font-sans);
}

.viewer-body {
  padding: var(--space-lg);
  overflow: auto;
  display: flex;
  align-items: center;
  justify-content: center;
}

.full-image {
  max-width: 100%;
  max-height: 70vh;
  object-fit: contain;
  border-radius: var(--radius-md);
  cursor: pointer;
}

.viewer-error {
  text-align: center;
  padding: 60px;
  color: var(--text-muted);
}

.error-icon {
  font-size: 32px;
  margin-bottom: var(--space-sm);
}

.error-text {
  font-size: 13px;
}
</style>
