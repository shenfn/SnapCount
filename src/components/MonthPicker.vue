<template>
  <div class="month-nav">
    <button class="month-nav-btn" @click="store.changeMonth(-1)">‹</button>
    <span class="month-nav-label" @click="pickerOpen = !pickerOpen" style="cursor:pointer;">
      {{ store.monthLabel.value }} ▾
    </span>
    <button class="month-nav-btn" @click="store.changeMonth(1)">›</button>
  </div>

  <!-- 月份选择面板 -->
  <div v-if="pickerOpen" class="mp-overlay" @click.self="pickerOpen = false">
    <div class="mp-panel">
      <div class="mp-year-row">
        <button class="mp-arrow" @click="pickerYear--">‹</button>
        <span class="mp-year">{{ pickerYear }}年</span>
        <button class="mp-arrow" :disabled="pickerYear >= nowYear" @click="pickerYear++">›</button>
      </div>
      <div class="mp-grid">
        <div v-for="m in 12" :key="m"
          class="mp-cell"
          :class="{
            active: m === store.currentMonth.value && pickerYear === store.currentYear.value,
            disabled: isFuture(pickerYear, m)
          }"
          @click="!isFuture(pickerYear, m) && pickMonth(pickerYear, m)">
          {{ m }}月
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { inject, ref, watch } from 'vue'
const store = inject('store')

const pickerOpen = ref(false)
const pickerYear = ref(store.currentYear.value)
const nowYear = new Date().getFullYear()
const nowMonth = new Date().getMonth() + 1

watch(pickerOpen, open => {
  if (open) pickerYear.value = store.currentYear.value
})

function isFuture(y, m) {
  return y > nowYear || (y === nowYear && m > nowMonth)
}

async function pickMonth(y, m) {
  store.currentYear.value = y
  store.currentMonth.value = m
  pickerOpen.value = false
  await store.loadData()
}
</script>
