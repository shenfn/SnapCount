<template>
  <div class="modal-overlay" :class="{ open: store.universalModal.open }" @click.self="sheet.tryClose">
    <div class="modal-sheet" ref="sheetEl"
      :class="{ swiping: sheet.isSwiping.value, closing: sheet.isClosing.value }"
      @touchstart="sheet.onTouchStart"
      @touchmove="sheet.onTouchMove"
      @touchend="sheet.onTouchEnd">
      <div class="sheet-drag-zone">
        <div class="sheet-handle"></div>
      </div>

      <div class="sheet-header">
        <div class="sheet-title">{{ metaTitle }}</div>
        <div class="sheet-sub">{{ store.universalModal.mode === 'edit' ? '调整这条通用记录' : '手动验证一个内置数据域' }}</div>
      </div>

      <div class="sheet-body" ref="bodyEl">
        <div v-if="store.universalModal.mode === 'edit'" class="thumb-wrap">
          <div v-if="store.universalModal.imageUrl" style="width:100%" @click="store.openImgFull(store.universalModal.imageUrl)">
            <img :src="store.universalModal.imageUrl"
              @error="store.markUniversalImageUnavailable()"
              style="width:100%; max-height:160px; object-fit:contain; background:#f0f0f0; display:block;">
            <div style="text-align:center; padding:6px 0; font-size:11px; color:var(--text3);">点击放大原图</div>
          </div>
          <template v-else-if="store.universalModal.imageLoadError">
            <span>!</span><span>截图文件不可用或已删除</span>
          </template>
          <template v-else>
            <span>□</span><span>无截图预览</span>
          </template>
        </div>

        <div class="sel-section" style="margin-top:16px">
          <div class="sel-label">数据域</div>
          <div class="sel-grid">
            <div
              v-for="domain in editableDomains"
              :key="domain.id"
              class="sel-chip"
              :class="{ selected: store.universalModal.domainKey === domain.id }"
              @click="store.universalModal.mode === 'create' && store.openUniversalModal(domain.id)"
            >
              {{ domain.icon }} {{ domain.shortName }}
            </div>
          </div>
        </div>

        <div
          v-for="field in formFields"
          :key="field.model"
          class="sel-section"
          style="margin-top:16px"
        >
          <div class="sel-label">{{ field.label }}</div>
          <DurationInput
            v-if="field.input === 'duration'"
            v-model="store.universalModal[field.model]"
          />
          <input
            v-else
            :type="field.type"
            class="sheet-input"
            v-model="store.universalModal[field.model]"
            :placeholder="field.placeholder || ''"
            :maxlength="field.maxlength || null"
            :min="field.min || null"
            :step="field.step || null"
            :max="field.type === 'date' ? today : null"
          >
        </div>
      </div>

      <div class="sheet-footer">
        <button class="confirm-btn"
          :disabled="isSubmitDisabled"
          @click="store.confirmUniversalRecord()">
          确认保存
        </button>
        <button v-if="store.universalModal.mode === 'edit'" class="delete-bill-btn"
          @click="store.openDeleteConfirm('universal', store.universalModal.id, store.universalModal.imagePath)">
          删除此记录
        </button>
      </div>

      <div v-if="sheet.showUnsaved.value" class="unsaved-bar">
        <span class="unsaved-text">内容未保存，确认退出？</span>
        <button class="unsaved-cancel" @click="sheet.showUnsaved.value = false">继续编辑</button>
        <button class="unsaved-confirm" @click="sheet.doForceClose">退出</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
import { useBottomSheet } from '../composables/useBottomSheet'
import DurationInput from './DurationInput.vue'

const store = inject('store')
const today = new Date().toISOString().slice(0, 10)

const sheet = useBottomSheet(
  computed(() => store.universalModal.open),
  store.closeUniversalModal,
  {
    hasChanges: store.hasUniversalChanges,
    resetChanges: store.resetUniversalChanges,
  }
)
const sheetEl = sheet.sheetEl
const bodyEl = sheet.bodyEl

const editableDomains = computed(() => store.domains.value.filter(domain => !['expense', 'income'].includes(domain.id)))
const meta = computed(() => store.getUniversalDomainMeta(store.universalModal.domainKey))
const metaTitle = computed(() => store.universalModal.mode === 'edit' ? meta.value.editTitle : meta.value.title)
const formFields = computed(() => meta.value.formFields || [])

const isSubmitDisabled = computed(() => formFields.value.some(field => {
  if (!field.required) return false
  const value = store.universalModal[field.model]
  if (value == null) return true
  return String(value).trim() === ''
}))
</script>
