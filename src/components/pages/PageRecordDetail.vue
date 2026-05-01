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
          <div class="record-detail-image-empty-mark">{{ record.kind === 'income' ? '收' : '支' }}</div>
          <div class="record-detail-image-label">{{ record.imageLoadError ? '截图文件不可用' : '暂无截图预览' }}</div>
        </div>
      </div>

      <div class="record-detail-section">
        <div class="record-detail-section-title">基本信息</div>
        <div class="record-detail-field">
          <span class="field-label">数据域</span>
          <span class="field-value">
            <span class="badge" :class="record.kind === 'income' ? 'badge-income' : 'badge-expense'">{{ record.kind === 'income' ? '收入记录' : '消费记账' }}</span>
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

const record = computed(() => store.detailRecord.value)
const deleteType = computed(() => (record.value?.kind === 'income' ? 'income' : 'bill'))
const isPendingExpense = computed(() => record.value?.kind === 'expense' && record.value?.raw?.status === 'pending')

const recordTime = computed(() => {
  if (!record.value?.raw) return '--'
  const raw = record.value.raw
  if (raw.createdAt) return formatDateTimeLabel(raw.createdAt)
  if (raw.dateRaw) return raw.time ? `${raw.date} ${raw.time}` : raw.date
  return '--'
})

const sourceLabel = computed(() => {
  if (!record.value?.raw) return '--'
  const raw = record.value.raw
  if (record.value.kind === 'income') return raw.sourceType === 'ai_scan' ? '截图识别' : '手动录入'
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
      { label: '到账日期', value: raw.date || '--' },
      { label: '备注', value: raw.note || '无' },
    ]
  }
  return [
    { label: '金额', value: `-¥${Number(raw.amount || 0).toFixed(2)}`, numeric: true },
    { label: '商家名称', value: raw.name || '未识别商家' },
    { label: '消费渠道', value: raw.platform || '其他' },
    { label: '消费分类', value: raw.cat || '其他' },
    { label: '支付方式', value: raw.payment || '其他' },
    { label: '消费日期', value: raw.date || '--' },
    { label: '备注', value: raw.note || '无' },
  ]
})

const aiSummary = computed(() => {
  if (!record.value?.raw) return '暂无摘要'
  const raw = record.value.raw
  if (record.value.kind === 'income') {
    const source = raw.source || '未命名来源'
    const cat = incomeCatMap[raw.cat]?.label || '其他收入'
    return `系统记录了一笔 ${cat}，金额 ${Number(raw.amount || 0).toFixed(2)} 元，来源为 ${source}。`
  }
  return `系统记录了一笔支出，商家为 ${raw.name || '未识别商家'}，金额 ${Number(raw.amount || 0).toFixed(2)} 元，渠道 ${raw.platform || '未知'}，分类 ${raw.cat || '未知'}。`
})
</script>
