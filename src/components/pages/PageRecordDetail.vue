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
          <div class="record-detail-image-label">点击查看原始截图</div>
        </template>
        <div v-else class="record-detail-image-empty">
          <div class="record-detail-image-empty-mark">{{ emptyMark }}</div>
          <div class="record-detail-image-label">{{ record.imageLoadError ? '截图文件不可用' : '暂无截图预览' }}</div>
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
            <span class="badge" :class="isPendingExpense ? 'badge-warning' : 'badge-success'">{{ isPendingExpense ? '待补充' : '已完成' }}</span>
          </span>
        </div>
      </div>

      <div class="record-detail-section">
        <div class="record-detail-section-title">抽取字段</div>
        <div v-for="field in fields" :key="field.label" class="record-detail-field">
          <span class="field-label">{{ field.label }}</span>
          <span class="field-value" :class="{ numeric: field.numeric }">{{ field.value }}</span>
        </div>
      </div>

      <div v-if="foodDishes.length" class="record-detail-section">
        <div class="record-detail-section-title">
          菜品明细
          <span class="badge badge-warning" style="margin-left:8px;font-weight:normal;">估算值</span>
        </div>
        <div v-for="(d, i) in foodDishes" :key="i" class="record-detail-field" style="flex-direction:column;align-items:stretch;gap:4px;">
          <div style="display:flex;justify-content:space-between;align-items:center;">
            <span class="field-label" style="font-weight:600;color:#1f2937;">{{ d.name }}</span>
            <span class="field-value numeric">{{ d.calorie_kcal != null ? `${d.calorie_kcal} 千卡` : '--' }}</span>
          </div>
          <div style="display:flex;gap:12px;font-size:12px;color:#6b7280;">
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
import { formatDateTimeLabel, incomeCatMap } from '../../utils/helpers'

const store = inject('store')

function fmtAbsoluteDate(value) {
  if (!value) return null
  const s = String(value).slice(0, 10)
  const d = new Date(s + 'T00:00:00+08:00')
  if (isNaN(d.getTime())) return null
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`
}

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
  if (record.value?.kind === 'income') return '收入记录'
  if (record.value?.kind === 'expense') return '消费记账'
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
  return domainMeta.value?.shortName?.slice(0, 1) || '域'
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
  if (record.value.kind === 'universal') return raw.source === 'staging' ? '中转站归档' : '手动录入'
  return raw.source === 'ai_scan' ? '截图识别' : '手动录入'
})

const fields = computed(() => {
  if (!record.value?.raw) return []
  const raw = record.value.raw
  if (record.value.kind === 'income') {
    return [
      { label: '金额', value: `+¥${Number(raw.amount || 0).toFixed(2)}`, numeric: true },
      { label: '收入类型', value: incomeCatMap[raw.cat]?.label || '其他' },
      { label: '来源名称', value: raw.source || '未填写' },
      { label: '到账日期', value: fmtAbsoluteDate(raw.dateRaw) || raw.date || '--' },
      { label: '备注', value: raw.note || '无' },
    ]
  }
  if (record.value.kind === 'universal') {
    const payload = raw.payload || {}
    const meta = store.getUniversalDomainMeta(raw.domainKey)
    // food 域专属字段列表：餐次中文化 + 估算依据
    if (raw.domainKey === 'food') {
      const mealLabelMap = { breakfast: '早餐', lunch: '午餐', dinner: '晚餐', snack: '加餐' }
      return [
        { label: '标题', value: raw.title || meta.defaultTitle },
        { label: '餐次', value: mealLabelMap[payload.meal_type] || '未分类' },
        { label: '总热量', value: payload.total_calorie_kcal != null ? `${payload.total_calorie_kcal} 千卡（估算）` : '--', numeric: true },
        { label: '菜品数', value: `${Array.isArray(payload.dishes) ? payload.dishes.length : 0} 道` },
        { label: '记录日期', value: fmtAbsoluteDate(raw.occurredAt) || '--' },
        { label: '来源类型', value: raw.source === 'staging' ? '中转站归档' : '拍照识别' },
        { label: '估算依据', value: payload.confidence_note || '无' },
        { label: '备注', value: payload.note || raw.summary || '无' },
      ]
    }
    return [
      { label: '标题', value: raw.title || meta.defaultTitle },
      { label: meta.dimensionLabel, value: payload[meta.dimensionKey] || '未填写' },
      { label: meta.primaryLabel, value: `${Number(payload[meta.primaryKey] || 0).toFixed(2)}`, numeric: true },
      { label: '发生日期', value: fmtAbsoluteDate(raw.occurredAt) || '--' },
      { label: '模板版本', value: raw.domainVersion || '1.0' },
      { label: '来源类型', value: raw.source === 'staging' ? '中转站归档' : '手动录入' },
      { label: '备注', value: payload.note || raw.summary || '无' },
    ]
  }
  return [
    { label: '金额', value: `-¥${Number(raw.amount || 0).toFixed(2)}`, numeric: true },
    { label: '商家名称', value: raw.name || '未识别商家' },
    { label: '消费渠道', value: raw.platform || '其他' },
    { label: '消费分类', value: raw.cat || '其他' },
    { label: '支付方式', value: raw.payment || '其他' },
    { label: '消费日期', value: fmtAbsoluteDate(raw.dateRaw) || raw.date || '--' },
    { label: '备注', value: raw.note || '无' },
  ]
})

const foodDishes = computed(() => {
  if (!record.value?.raw) return []
  const raw = record.value.raw
  if (record.value.kind !== 'universal' || raw.domainKey !== 'food') return []
  const dishes = raw.payload?.dishes
  return Array.isArray(dishes) ? dishes : []
})

const aiSummary = computed(() => {
  if (!record.value?.raw) return '暂无摘要'
  const raw = record.value.raw
  if (record.value.kind === 'income') {
    const source = raw.source || '未命名来源'
    const cat = incomeCatMap[raw.cat]?.label || '其他收入'
    return `系统记录了一笔 ${cat}，金额 ${Number(raw.amount || 0).toFixed(2)} 元，来源为 ${source}。`
  }
  if (record.value.kind === 'universal') {
    if (raw.domainKey === 'food') {
      // food 域：AI summary 已是可读描述，直接使用
      return raw.summary || `饮食记录了 ${raw.title}。`
    }
    const meta = store.getUniversalDomainMeta(raw.domainKey)
    const payload = raw.payload || {}
    const dimension = payload[meta.dimensionKey] || raw.title || domainLabel.value
    const primary = Number(payload[meta.primaryKey] || 0)
    return `${domainLabel.value}中记录了「${dimension}」，${meta.primaryLabel}为 ${primary.toFixed(2)}。${raw.summary || ''}`
  }
  return `系统记录了一笔支出，商家为 ${raw.name || '未识别商家'}，金额 ${Number(raw.amount || 0).toFixed(2)} 元，渠道 ${raw.platform || '未知'}，分类 ${raw.cat || '未知'}。`
})
</script>
