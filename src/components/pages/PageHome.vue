<template>
  <div class="page active">
    <div class="topbar">
      <h1>随手账</h1>
      <div class="month-nav">
        <button class="month-nav-btn" @click="store.changeMonth(-1)">‹</button>
        <span class="month-nav-label">{{ store.monthLabel.value }}</span>
        <button class="month-nav-btn" @click="store.changeMonth(1)">›</button>
      </div>
    </div>

    <!-- 支出总览 -->
    <div class="hero">
      <div class="label">本月总支出</div>
      <div class="amount">¥{{ store.totalExpense.value.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }}</div>
      <div class="hero-row">
        <div class="hero-col">
          <div class="h-label">笔数</div>
          <div class="h-val">{{ store.doneBills.value.length }} 笔</div>
        </div>
        <div class="hero-col">
          <div class="h-label">日均</div>
          <div class="h-val">¥{{ dailyAvg }}</div>
        </div>
        <div class="hero-col">
          <div class="h-label">日均天数</div>
          <div class="h-val">{{ daysInMonth }} 天</div>
        </div>
      </div>
      <div class="hero-balance-row">
        <div class="hero-bal-col">
          <div class="hb-label">本月收入</div>
          <div class="hb-val">¥{{ store.totalIncome.value.toLocaleString() }}</div>
        </div>
        <div class="hero-bal-col">
          <div class="hb-label">本月结余</div>
          <div class="hb-val" :style="{ color: store.netBalance.value >= 0 ? '#4ADE80' : '#FCA5A5' }">
            ¥{{ store.netBalance.value.toLocaleString() }}
          </div>
        </div>
      </div>
    </div>

    <!-- 待补充提醒 -->
    <div v-if="store.pendingBills.value.length" class="pending-banner" @click="store.currentPage.value = 'pending'">
      <div class="pending-dot">{{ store.pendingBills.value.length }}</div>
      <div class="pending-text">
        <div class="pt">有 {{ store.pendingBills.value.length }} 条记录待补充</div>
        <div class="ps">信息不完整，点击逐一完善</div>
      </div>
      <div class="pending-arrow">›</div>
    </div>

    <!-- 本周支出趋势 -->
    <div class="sec-title">本周支出趋势</div>
    <div class="card">
      <div style="display:flex; align-items:flex-end; gap:6px; height:80px; padding:0 4px;">
        <div v-for="(v, i) in weekData" :key="i"
          style="flex:1; display:flex; flex-direction:column; align-items:center; gap:4px; height:100%">
          <div style="flex:1; display:flex; align-items:flex-end; width:100%">
            <div :style="{
              width: '100%',
              height: Math.max(v / weekMax * 72, v > 0 ? 6 : 0) + 'px',
              borderRadius: '4px 4px 0 0',
              background: i === todayIdx ? 'var(--accent)' : 'var(--surface2)'
            }"></div>
          </div>
        </div>
      </div>
      <div style="display:flex; gap:6px; margin-top:6px;">
        <div v-for="(d, i) in weekLabels" :key="i"
          style="flex:1; text-align:center; font-size:10px;"
          :style="{ color: i === todayIdx ? 'var(--accent)' : 'var(--text3)' }">{{ d }}</div>
      </div>
    </div>

    <!-- 最近记录 -->
    <div class="sec-title">最近记录 <span @click="store.currentPage.value = 'bills'">查看全部 ›</span></div>
    <div class="card">
      <div v-if="!store.bills.value.length" class="empty">
        <div class="e-icon">📋</div><p>本月暂无记录</p>
      </div>
      <BillRow v-for="b in store.bills.value.slice(0, 5)" :key="b.id" :bill="b" />
    </div>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { inject, computed } from 'vue'
import { computeWeekData } from '../../utils/helpers'
import BillRow from '../BillRow.vue'

const store = inject('store')
const weekLabels = ['周一','周二','周三','周四','周五','周六','周日']
const todayIdx = computed(() => { const d = new Date().getDay(); return d === 0 ? 6 : d - 1 })
const weekData = computed(() => computeWeekData(store.bills.value))
const weekMax = computed(() => Math.max(...weekData.value, 1))
const daysInMonth = computed(() => new Date(store.currentYear.value, store.currentMonth.value, 0).getDate())
const dailyAvg = computed(() => (store.totalExpense.value / daysInMonth.value).toFixed(0))
</script>
