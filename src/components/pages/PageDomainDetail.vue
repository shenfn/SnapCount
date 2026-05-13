<template>
  <div class="page active domain-detail-page">
    <div class="detail-header domain-detail-header">
      <button class="detail-back" @click="store.goBack()">‹</button>
      <div class="detail-header-info">
        <div class="detail-header-title">{{ domain.name }}</div>
        <div class="domain-detail-header-sub">{{ domain.isSystem ? '系统内置数据域' : '自定义数据域' }}</div>
      </div>
      <button class="detail-more" @click="store.showFlash('数据域配置将在模板阶段开放')">设</button>
    </div>

    <div class="domain-detail-hero" :style="{ '--domain-color': domain.color }">
      <div class="domain-detail-hero-top">
        <div class="domain-detail-mark" :style="{ background: `${domain.color}18`, color: domain.color }">{{ domain.icon }}</div>
        <div class="domain-detail-status">
          <span class="badge" :class="domain.recordCount ? 'badge-success' : 'badge-warning'">{{ domain.recordCount ? '运行中' : '待接入' }}</span>
        </div>
      </div>
      <div class="domain-detail-title-row">
        <div>
          <div class="domain-detail-kicker">Domain Workspace</div>
          <div class="domain-detail-title">{{ domain.name }}</div>
        </div>
        <div class="domain-detail-count">{{ domain.recordCount }}</div>
      </div>
      <div class="domain-detail-desc">{{ domain.description }}</div>
    </div>

    <div class="domain-metric-grid">
      <div v-for="item in metrics" :key="item.label" class="domain-metric">
        <div class="domain-metric-label">{{ item.label }}</div>
        <div class="domain-metric-value">{{ item.value }}</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">趋势</div>
      <div class="section-action">{{ trendScope }}</div>
    </div>
    <div class="domain-panel">
      <div class="domain-trend-bars">
        <div v-for="(item, index) in trendItems" :key="index" class="domain-trend-col">
          <div class="domain-trend-bar-wrap">
            <div
              class="domain-trend-bar"
              :style="{ height: `${Math.max(item.pct, item.value ? 12 : 4)}%`, background: domainBarColor }"
            ></div>
          </div>
          <div class="domain-trend-label">{{ item.label }}</div>
        </div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">维度分布</div>
      <div class="section-action">Top {{ dimensionItems.length || 0 }}</div>
    </div>
    <div class="domain-panel">
      <div v-if="!dimensionItems.length" class="empty-state compact">
        <div class="empty-title">还没有可分析的数据</div>
        <div class="empty-desc">模板接入后会自动生成分类、来源或状态分布。</div>
      </div>
      <div v-for="item in dimensionItems" :key="item.name" class="domain-dimension-row">
        <div class="domain-dimension-main">
          <div class="domain-dimension-name">{{ item.name }}</div>
          <div class="domain-dimension-track">
            <div class="domain-dimension-fill" :style="{ width: `${item.pct}%`, background: domainBarColor }"></div>
          </div>
        </div>
        <div class="domain-dimension-value">{{ item.display }}</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">最近记录</div>
      <div class="section-action">{{ recentRecords.length }} 条</div>
    </div>
    <div class="domain-record-list">
      <div v-if="!recentRecords.length" class="empty-state">
        <div class="empty-title">{{ domain.name }}暂无记录</div>
        <div class="empty-desc">这个数据域已经预留好展示结构，等截图识别链路接入后会自动填充。</div>
      </div>
      <div
        v-for="item in recentRecords"
        :key="item.id"
        class="domain-record-row"
        @click="openRecord(item)"
      >
        <div class="domain-record-icon" :style="{ background: `${domain.color}16`, color: domain.color }">{{ item.icon }}</div>
        <div class="domain-record-main">
          <div class="domain-record-title-row">
            <div class="domain-record-title">{{ item.title }}</div>
            <div class="domain-record-value" :class="item.kind">{{ item.value }}</div>
          </div>
          <div class="domain-record-sub">{{ item.subtitle }}</div>
          <div class="domain-record-date">{{ item.date }}</div>
        </div>
      </div>
    </div>

    <div class="domain-next-panel">
      <div class="domain-next-title">默认展示能力</div>
      <div class="domain-next-grid">
        <span v-for="capability in capabilities" :key="capability" class="domain-next-chip">{{ capability }}</span>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
import {
  getDomainCapabilities,
  getDomainDimensionItems,
  getDomainMetricItems,
  getDomainRecentRecords,
  getDomainTrendItems,
  getDomainTrendScope,
} from '../../domains/detailAdapters'

const store = inject('store')

const domain = computed(() => {
  return store.domains.value.find(item => item.id === store.activeDomainId.value) || store.domains.value[0]
})

const domainBarColor = computed(() => `linear-gradient(180deg, ${domain.value.color} 0%, ${softenColor(domain.value.color)} 100%)`)

const metrics = computed(() => getDomainMetricItems(store, domain.value))
const trendScope = computed(() => getDomainTrendScope(domain.value))
const trendItems = computed(() => getDomainTrendItems(store, domain.value))
const dimensionItems = computed(() => getDomainDimensionItems(store, domain.value))
const recentRecords = computed(() => getDomainRecentRecords(store, domain.value))
const capabilities = computed(() => getDomainCapabilities(domain.value))

function openRecord(item) {
  if (item.kind === 'expense') store.openRecordDetail('expense', item.raw)
  if (item.kind === 'income') store.openRecordDetail('income', item.raw)
  if (item.kind === 'universal') store.openRecordDetail('universal', item.raw)
}

function softenColor(color) {
  const map = {
    '#C2410C': '#F97316',
    '#1565C0': '#38BDF8',
    '#B45309': '#FBBF24',
    '#4338CA': '#818CF8',
    '#0369A1': '#38BDF8',
  }
  return map[color] || color
}
</script>
