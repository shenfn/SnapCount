<template>
  <div class="inferred-summary" v-if="hasData">
    <div class="card-title">
      记录摘要
      <span class="inferred-tag">推断</span>
    </div>
    <div class="inferred-source">从 db_targets / response 推断</div>

    <div class="summary-content">
      <!-- 记录类型 -->
      <div class="summary-row" v-if="recordType">
        <span class="summary-label">类型:</span>
        <span class="summary-value">{{ recordType }}</span>
      </div>

      <!-- 目标表 -->
      <div class="summary-row" v-if="targetTable">
        <span class="summary-label">目标表:</span>
        <span class="summary-value">{{ targetTable }}</span>
      </div>

      <!-- 关键字段（从 extracted_json 推断） -->
      <template v-if="payloadFields.length > 0">
        <div
          v-for="field in payloadFields"
          :key="field.key"
          class="summary-row"
        >
          <span class="summary-label">{{ field.label }}:</span>
          <span class="summary-value">{{ field.value }}</span>
        </div>
      </template>

      <!-- 无可推断数据 -->
      <div v-else-if="!recordType && !targetTable" class="no-data">
        无可推断的摘要信息
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  trace: { type: Object, default: null },
})

// 是否有可展示的数据
const hasData = computed(() => {
  if (!props.trace) return false
  return true
})

// 记录类型
const recordType = computed(() => {
  const dbTarget = props.trace?.db_targets?.[0]
  return dbTarget?.record_type || null
})

// 目标表
const targetTable = computed(() => {
  const dbTarget = props.trace?.db_targets?.[0]
  return dbTarget?.table || null
})

// 从 artifacts.model_raw.extracted_json 推断关键字段
const payloadFields = computed(() => {
  const modelRaw = props.trace?.artifacts?.model_raw
  if (!modelRaw) return []

  let extracted = null
  // extracted_json 可能是字符串或对象
  if (typeof modelRaw.extracted_json === 'string') {
    try {
      extracted = JSON.parse(modelRaw.extracted_json)
    } catch {
      return []
    }
  } else if (typeof modelRaw.extracted_json === 'object') {
    extracted = modelRaw.extracted_json
  }

  if (!extracted) return []

  const fields = []
  const payload = extracted.payload_jsonb || {}

  // 常见字段映射
  const fieldMap = [
    { key: 'amount', label: '金额' },
    { key: 'merchant_name', label: '商家' },
    { key: 'source_name', label: '来源' },
    { key: 'category', label: '分类' },
    { key: 'occurred_at', label: '时间' },
    { key: 'sport_type', label: '运动类型' },
    { key: 'duration_minutes', label: '时长(分)' },
    { key: 'distance_km', label: '距离(km)' },
    { key: 'calories', label: '热量(千卡)' },
    { key: 'avg_heart_rate', label: '心率' },
    { key: 'avg_speed_kmh', label: '速度(km/h)' },
    { key: 'sleep_duration_minutes', label: '睡眠(分)' },
    { key: 'book_title', label: '书名' },
    { key: 'food_name', label: '食物' },
  ]

  for (const { key, label } of fieldMap) {
    if (extracted[key] != null && extracted[key] !== '') {
      fields.push({ key, label, value: formatValue(extracted[key]) })
    }
    if (payload[key] != null && payload[key] !== '') {
      // 避免重复
      if (!fields.find((f) => f.key === key)) {
        fields.push({ key, label, value: formatValue(payload[key]) })
      }
    }
  }

  return fields.slice(0, 5) // 最多显示 5 个字段
})

function formatValue(val) {
  if (typeof val === 'number') {
    return Number.isInteger(val) ? String(val) : val.toFixed(2)
  }
  return String(val)
}
</script>

<style scoped>
.inferred-summary {
  flex: 1;
  min-width: 0;
  padding: var(--space-sm) var(--space-md);
  border-radius: var(--radius-lg);
  background: var(--bg-panel);
  border: 1px dashed var(--border);
  overflow: hidden;
}

.card-title {
  font-size: 11px;
  font-weight: 700;
  color: var(--text-secondary);
  margin-bottom: 2px;
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.inferred-tag {
  font-size: 9px;
  padding: 1px 5px;
  border-radius: 6px;
  background: rgba(210, 153, 34, 0.15);
  color: var(--accent-yellow);
  font-weight: 600;
  text-transform: uppercase;
}

.inferred-source {
  font-size: 10px;
  color: var(--text-muted);
  font-style: italic;
  margin-bottom: var(--space-xs);
}

.summary-content {
  max-height: 70px;
  overflow-y: auto;
}

.summary-row {
  display: flex;
  gap: var(--space-xs);
  font-size: 11px;
  line-height: 1.5;
}

.summary-label {
  color: var(--text-muted);
  flex-shrink: 0;
}

.summary-value {
  color: var(--text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.no-data {
  font-size: 11px;
  color: var(--text-muted);
  font-style: italic;
}
</style>
