<template>
  <div class="page active">
    <div class="topbar">
      <h1>账单记录</h1>
      <div class="sub">本月 {{ store.doneBills.value.length }} 笔</div>
    </div>

    <div class="filter-row">
      <button v-for="f in filters" :key="f.val"
        class="filter-chip" :class="{ active: store.currentFilter.value === f.val }"
        @click="store.currentFilter.value = f.val">{{ f.label }}</button>
    </div>

    <div style="padding-top:12px">
      <div v-if="!grouped.length" class="empty">
        <div class="e-icon">📋</div><p>暂无记录</p>
      </div>
      <div v-for="group in grouped" :key="group.date" class="bill-group">
        <div class="bill-date">{{ group.date }}</div>
        <div class="card" style="padding:0 16px">
          <BillRow v-for="b in group.items" :key="b.id" :bill="b" />
        </div>
      </div>
    </div>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { inject, computed } from 'vue'
import BillRow from '../BillRow.vue'

const store = inject('store')

const filters = [
  { val: 'all', label: '全部' },
  { val: '餐饮', label: '餐饮' },
  { val: '购物', label: '购物' },
  { val: '出行', label: '出行' },
  { val: '娱乐', label: '娱乐' },
  { val: '生活', label: '生活' },
]

const grouped = computed(() => {
  const map = {}
  store.filteredBills.value.forEach(b => {
    if (!map[b.date]) map[b.date] = []
    map[b.date].push(b)
  })
  return Object.entries(map).map(([date, items]) => ({ date, items }))
})
</script>
