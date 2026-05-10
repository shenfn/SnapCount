<template>
  <div class="page active">
    <div class="page-title">数据域</div>
    <div class="page-subtitle">用统一入口管理现在的记账数据，以及后续会接入的运动、睡眠、阅读等记录域。</div>

    <div class="search-bar">
      <input class="form-input" type="text" placeholder="搜索数据域..." v-model.trim="searchTerm">
    </div>

    <div class="home-domains-scroll" style="margin-bottom: 18px;">
      <div
        v-for="domain in featuredDomains"
        :key="domain.id"
        class="domain-quick-card"
        @click="store.openDomainPage(domain.id)"
      >
        <div class="domain-quick-icon" :style="{ background: `${domain.color}18`, color: domain.color }">
          {{ domain.icon }}
        </div>
        <div class="domain-quick-name">{{ domain.name }}</div>
        <div class="domain-quick-count">{{ domain.recordCount }} 条</div>
      </div>
    </div>

    <div class="section-header">
      <div class="section-title">全部数据域</div>
      <div class="section-action" @click="store.showFlash('AI 建模板入口将在阶段 3 开放')">新建</div>
    </div>

    <div class="domain-list">
      <div v-if="!filteredDomains.length" class="empty-state">
        <div class="empty-title">没有匹配的数据域</div>
        <div class="empty-desc">试试搜索“收入”“运动”或其他关键字。</div>
      </div>

      <div
        v-for="domain in filteredDomains"
        :key="domain.id"
        class="domain-card"
        @click="store.openDomainPage(domain.id)"
      >
        <div class="domain-card-icon" :style="{ background: `${domain.color}16`, color: domain.color }">
          {{ domain.icon }}
        </div>
        <div class="domain-card-info">
          <div class="domain-card-name">{{ domain.name }}</div>
          <div class="domain-card-meta">{{ domain.meta }}</div>
          <div class="domain-card-desc">{{ domain.description }}</div>
        </div>
        <span v-if="domain.isSystem" class="domain-card-badge">内置</span>
        <div class="domain-card-arrow">›</div>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject, ref } from 'vue'

const store = inject('store')
const searchTerm = ref('')

const filteredDomains = computed(() => {
  const term = searchTerm.value.toLowerCase()
  if (!term) return store.domains.value
  return store.domains.value.filter(domain =>
    domain.name.toLowerCase().includes(term)
    || domain.description.toLowerCase().includes(term)
  )
})

const featuredDomains = computed(() => store.domains.value)
</script>
