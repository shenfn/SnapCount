<template>
  <div class="duration-input">
    <div class="duration-input-cell">
      <input
        type="number"
        inputmode="numeric"
        min="0"
        :max="99"
        :value="hoursDisplay"
        :placeholder="hoursPlaceholder"
        class="duration-input-field"
        @input="onHoursInput"
        @blur="onHoursBlur"
      />
      <span class="duration-input-unit">小时</span>
    </div>
    <div class="duration-input-cell">
      <input
        type="number"
        inputmode="numeric"
        min="0"
        :max="59"
        :value="minutesDisplay"
        :placeholder="minutesPlaceholder"
        class="duration-input-field"
        @input="onMinutesInput"
        @blur="onMinutesBlur"
      />
      <span class="duration-input-unit">分钟</span>
    </div>
    <div v-if="totalMinutes > 0" class="duration-input-summary">
      总计 {{ summaryText }}
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { formatDuration } from '../utils/format'

const props = defineProps({
  modelValue: { type: [String, Number], default: '' },
  hoursPlaceholder: { type: String, default: '0' },
  minutesPlaceholder: { type: String, default: '0' },
})
const emit = defineEmits(['update:modelValue'])

const totalMinutes = computed(() => {
  if (props.modelValue === '' || props.modelValue == null) return 0
  const n = Number(props.modelValue)
  return Number.isFinite(n) && n > 0 ? Math.round(n) : 0
})

const hoursDisplay = computed(() => {
  const t = totalMinutes.value
  if (t === 0) return ''
  const h = Math.floor(t / 60)
  return h === 0 ? '' : h
})

const minutesDisplay = computed(() => {
  const t = totalMinutes.value
  if (t === 0) return ''
  const m = t % 60
  // 当只有小时数（如 2 小时整），分钟框为空，避免视觉噪声
  return m === 0 ? '' : m
})

const summaryText = computed(() => formatDuration(totalMinutes.value))

function emitFromParts(h, m) {
  const total = Math.max(0, (Number(h) || 0) * 60 + (Number(m) || 0))
  emit('update:modelValue', total === 0 ? '' : total)
}

function onHoursInput(e) {
  const raw = e.target.value
  const h = raw === '' ? 0 : Math.max(0, Math.min(99, Number(raw) || 0))
  const m = totalMinutes.value % 60
  emitFromParts(h, m)
}

function onHoursBlur() {
  // 失焦后规范显示
  emitFromParts(Math.floor(totalMinutes.value / 60), totalMinutes.value % 60)
}

function onMinutesInput(e) {
  const raw = e.target.value
  let m = raw === '' ? 0 : Math.max(0, Number(raw) || 0)
  // 分钟超过 60 自动进位到小时
  let extraH = 0
  if (m >= 60) {
    extraH = Math.floor(m / 60)
    m = m % 60
  }
  const h = Math.floor(totalMinutes.value / 60) + extraH
  emitFromParts(h, m)
}

function onMinutesBlur() {
  // 失焦时若超出，规范化
  emitFromParts(Math.floor(totalMinutes.value / 60), totalMinutes.value % 60)
}
</script>

<style scoped>
.duration-input {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.duration-input-cell {
  flex: 1;
  min-width: 110px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 12px;
  background: rgba(255, 255, 255, 0.88);
  border: 1px solid var(--border);
  border-radius: 12px;
  height: 44px;
  transition: border-color 0.18s ease, box-shadow 0.18s ease;
}
.duration-input-cell:focus-within {
  border-color: var(--primary-light);
  box-shadow: 0 0 0 3px rgba(45, 106, 79, 0.08);
}
.duration-input-field {
  flex: 1;
  border: none;
  outline: none;
  background: transparent;
  font-family: var(--font-num);
  font-size: 17px;
  font-weight: 700;
  color: var(--text);
  letter-spacing: -0.2px;
  width: 100%;
  min-width: 0;
  padding: 0;
  /* 隐藏 number 类型的上下箭头 */
  -moz-appearance: textfield;
}
.duration-input-field::-webkit-outer-spin-button,
.duration-input-field::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}
.duration-input-field::placeholder {
  color: var(--text3);
  font-weight: 500;
}
.duration-input-unit {
  font-size: 13px;
  color: var(--text2);
  font-weight: 600;
  flex-shrink: 0;
  letter-spacing: 0.3px;
}
.duration-input-summary {
  width: 100%;
  font-size: 11px;
  color: var(--text3);
  letter-spacing: 0.4px;
  padding-left: 4px;
}
</style>
