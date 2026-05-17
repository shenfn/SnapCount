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

    <DomainHero
      :name="domain.name"
      :icon="domain.icon"
      :description="domain.description"
      :color="domain.color"
      :record-count="domain.recordCount"
      kicker="DOMAIN WORKSPACE"
    />

    <button
      v-if="domain.id === 'wallet'"
      class="domain-wallet-add"
      @click="store.openUniversalModal('wallet')"
    >
      👛 添加钱包快照
    </button>

    <DomainMetricStrip
      :metrics="metricsAccented"
      :color="domain.color"
      :cols="4"
    />

    <DomainTrendPanel
      :values="trendValues"
      :labels="trendLabels"
      :today-index="todayIndex"
      :color="domain.color"
      :currency="trendIsCurrency"
      :duration="trendIsDuration"
      :unit="trendUnit"
      title="趋势"
      :scope="trendScope"
    />

    <DomainDistributionPanel
      :items="dimensionItems"
      :color="domain.color"
      title="维度分布"
      :top-label="dimensionItems.length ? `Top ${dimensionItems.length}` : ''"
      :empty-desc="'模板接入后会自动生成分类、来源或状态分布。'"
    />

    <DomainRecentRecordList
      :records="recentRecords"
      :color="domain.color"
      title="最近记录"
      :empty-icon="domain.icon"
      :empty-title="`${domain.name}暂无记录`"
      :empty-desc="'这个数据域已经预留好展示结构，等截图识别链路接入后会自动填充。'"
      @select="openRecord"
    />

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
import { getDomainSchema, getDomainDisplay } from '../../domains/registry'
import { isDurationFact } from '../../utils/format'
import DomainHero from '../domain/DomainHero.vue'
import DomainMetricStrip from '../domain/DomainMetricStrip.vue'
import DomainTrendPanel from '../domain/DomainTrendPanel.vue'
import DomainDistributionPanel from '../domain/DomainDistributionPanel.vue'
import DomainRecentRecordList from '../domain/DomainRecentRecordList.vue'

const store = inject('store')

const today = new Date()
const todayIndex = today.getDay() === 0 ? 6 : today.getDay() - 1

const domain = computed(() => {
  return store.domains.value.find(item => item.id === store.activeDomainId.value) || store.domains.value[0]
})

const metrics = computed(() => getDomainMetricItems(store, domain.value))
// 第一个指标作为强调卡（可一目了然看到主指标）
const metricsAccented = computed(() => metrics.value.map((item, idx) => ({
  ...item,
  accent: idx === 0,
})))

const trendScope = computed(() => getDomainTrendScope(domain.value, store))
const trendItemsRaw = computed(() => getDomainTrendItems(store, domain.value))
const trendValues = computed(() => trendItemsRaw.value.map(item => item.value || 0))
const trendLabels = computed(() => trendItemsRaw.value.map(item => item.label))
const trendIsCurrency = computed(() => ['expense', 'income', 'wallet'].includes(domain.value.id))
const primaryFact = computed(() => {
  const schema = getDomainSchema(domain.value.id)
  const display = getDomainDisplay(domain.value.id)
  const key = display?.primary_fact || schema?.facts?.[0]?.key
  return schema?.facts?.find(f => f.key === key) || null
})
const trendIsDuration = computed(() => isDurationFact(primaryFact.value))
const trendUnit = computed(() => {
  if (trendIsCurrency.value) return ''
  if (trendIsDuration.value) return '' // formatDuration 自带单位
  return primaryFact.value?.unit || '条'
})

const dimensionItems = computed(() => getDomainDimensionItems(store, domain.value))
const recentRecords = computed(() => getDomainRecentRecords(store, domain.value))
const capabilities = computed(() => getDomainCapabilities(domain.value))

function openRecord(item) {
  if (item.kind === 'expense') store.openRecordDetail('expense', item.raw)
  if (item.kind === 'income') store.openRecordDetail('income', item.raw)
  if (item.kind === 'universal') store.openRecordDetail('universal', item.raw)
}
</script>

<style scoped>
.domain-wallet-add {
  width: calc(100% - 32px);
  margin: 0 16px 14px;
  border: none;
  border-radius: 14px;
  padding: 13px 16px;
  background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%);
  color: #fff;
  font-size: 14px;
  font-weight: 700;
  box-shadow: 0 12px 24px rgba(124, 58, 237, 0.22);
}
</style>
