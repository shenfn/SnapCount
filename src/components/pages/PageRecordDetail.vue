<template>
  <div class="page active detail-page">
    <div class="detail-header">
      <button class="detail-back" @click="store.closeRecordDetail()">‹</button>
      <div class="detail-header-info">
        <div class="detail-header-title">记录详情</div>
      </div>
      <button
        v-if="record"
        class="detail-more"
        @click="store.openDeleteConfirm(deleteType, record.id, record.imagePath)"
      >
        删
      </button>
    </div>

    <div v-if="record" class="record-detail-content">
      <div class="record-detail-image-card">
        <template v-if="record.imageUrl">
          <img :src="record.imageUrl" class="record-detail-image" @click="store.openImgFull(record.imageUrl)">
          <div class="record-detail-image-label">点击查看原始图片</div>
        </template>
        <div v-else class="record-detail-image-empty">
          <div class="record-detail-image-empty-mark">{{ emptyMark }}</div>
          <div class="record-detail-image-label">{{ record.imageLoadError ? '图片文件不可用' : '暂无图片预览' }}</div>
        </div>
      </div>

      <div class="record-detail-section">
        <div class="record-detail-section-title">基本信息</div>
        <div class="record-detail-field">
          <span class="field-label">数据域</span>
          <span class="field-value">
            <span class="badge" :class="domainBadgeClass">{{ domainLabel }}</span>
          </span>
        </div>
        <div class="record-detail-field">
          <span class="field-label">记录时间</span>
          <span class="field-value">{{ recordTime }}</span>
        </div>
        <div class="record-detail-field">
          <span class="field-label">来源</span>
          <span class="field-value">{{ sourceLabel }}</span>
        </div>
        <div v-if="record.kind === 'expense'" class="record-detail-field">
          <span class="field-label">状态</span>
          <span class="field-value">
            <span class="badge" :class="isPendingExpense ? 'badge-warning' : 'badge-success'">
              {{ isPendingExpense ? '待补充' : '已完成' }}
            </span>
          </span>
        </div>
      </div>

      <div class="record-detail-section">
        <div class="record-detail-section-title">抽取字段</div>
        <div v-for="field in fields" :key="field.label" class="record-detail-field" :class="{ stacked: field.multiline }">
          <span class="field-label">{{ field.label }}</span>
          <span class="field-value" :class="{ numeric: field.numeric, wrap: field.multiline }">{{ field.value }}</span>
        </div>
      </div>

      <div v-if="foodDishes.length" class="record-detail-section">
        <div class="record-detail-section-title">
          菜品明细
          <span class="badge badge-warning record-detail-estimate-badge">估算值</span>
        </div>
        <div v-for="(d, i) in foodDishes" :key="i" class="record-detail-field stacked food-dish-field">
          <div class="food-dish-header">
            <span class="field-label food-dish-name">{{ d.name }}</span>
            <span class="field-value numeric">{{ d.calorie_kcal != null ? `${d.calorie_kcal} 千卡` : '--' }}</span>
          </div>
          <div class="food-dish-macros">
            <span v-if="d.estimated_grams != null">约 {{ d.estimated_grams }}g</span>
            <span v-if="d.protein_g != null">蛋白 {{ d.protein_g }}g</span>
            <span v-if="d.carb_g != null">碳水 {{ d.carb_g }}g</span>
            <span v-if="d.fat_g != null">脂肪 {{ d.fat_g }}g</span>
          </div>
        </div>
      </div>

      <div class="record-detail-section">
        <div class="record-detail-section-title">AI 摘要</div>
        <div class="record-detail-ai-summary">{{ aiSummary }}</div>
      </div>

      <div class="record-detail-actions">
        <button class="record-detail-btn secondary" @click="store.openDetailEditor()">{{ isPendingExpense ? '补充信息' : '编辑' }}</button>
        <button class="record-detail-btn danger" @click="store.openDeleteConfirm(deleteType, record.id, record.imagePath)">删除</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
import { getSystemDomainLabel } from '../../domains/registry'
import { formatDateTimeLabel } from '../../utils/helpers'
import { getRecordAiSummary, getRecordDetailFields, getRecordFoodDishes } from '../../domains/recordDetailAdapters'

const store = inject('store')

const record = computed(() => store.detailRecord.value)
const deleteType = computed(() => {
  if (record.value?.kind === 'income') return 'income'
  if (record.value?.kind === 'universal') return 'universal'
  return 'bill'
})
const isPendingExpense = computed(() => record.value?.kind === 'expense' && record.value?.raw?.status === 'pending')
const domainMeta = computed(() => {
  if (!record.value) return null
  return store.domains.value.find(item => item.id === record.value.domainId) || null
})
const domainLabel = computed(() => {
  if (record.value?.kind === 'income') return getSystemDomainLabel('income')
  if (record.value?.kind === 'expense') return getSystemDomainLabel('expense')
  return domainMeta.value?.name || '通用记录'
})
const domainBadgeClass = computed(() => {
  if (record.value?.kind === 'income') return 'badge-income'
  if (record.value?.kind === 'expense') return 'badge-expense'
  return 'badge-primary'
})
const emptyMark = computed(() => {
  if (record.value?.kind === 'income') return '收'
  if (record.value?.kind === 'expense') return '支'
  return domainMeta.value?.shortName?.slice(0, 1) || '记'
})

const recordTime = computed(() => {
  if (!record.value?.raw) return '--'
  const raw = record.value.raw
  if (record.value.kind === 'universal') return formatDateTimeLabel(raw.occurredAt || raw.createdAt) || '--'
  if (raw.createdAt) return formatDateTimeLabel(raw.createdAt)
  if (raw.dateRaw) return raw.time ? `${raw.date} ${raw.time}` : raw.date
  return '--'
})

const sourceLabel = computed(() => {
  if (!record.value?.raw) return '--'
  const raw = record.value.raw
  if (record.value.kind === 'income') return raw.sourceType === 'ai_scan' ? '截图识别' : '手动录入'
  if (record.value.kind === 'universal') return raw.source === 'staging' ? '中转站归档' : '拍照识别'
  return raw.source === 'ai_scan' ? '截图识别' : '手动录入'
})

const fields = computed(() => getRecordDetailFields(store, record.value))
const foodDishes = computed(() => getRecordFoodDishes(record.value))
const aiSummary = computed(() => getRecordAiSummary(store, record.value, domainLabel.value))
</script>
