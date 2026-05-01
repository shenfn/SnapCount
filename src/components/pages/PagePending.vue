<template>
  <div class="page active">
    <div class="page-title">待处理</div>
    <div class="page-subtitle">
      {{ totalPending ? `${totalPending} 条记录等待分类、确认或补全` : '当前没有待处理记录' }}
    </div>

    <div class="chip-group">
      <div class="chip active">全部 <span class="chip-count">{{ totalPending }}</span></div>
      <div class="chip">待分类 <span class="chip-count">{{ store.pendingSummary.value.routingFailed }}</span></div>
      <div class="chip">待确认 <span class="chip-count">{{ store.pendingSummary.value.pendingReview }}</span></div>
      <div class="chip">AI失败 <span class="chip-count">{{ store.pendingSummary.value.aiError }}</span></div>
      <div class="chip">账单补充 <span class="chip-count">{{ store.pendingSummary.value.billPending }}</span></div>
    </div>

    <div v-if="!totalPending" class="empty-state">
      <div class="empty-title">中转站是空的</div>
      <div class="empty-desc">新的非记账截图、待确认记录和识别失败截图都会先进入这里。</div>
    </div>

    <div v-if="store.stagingRecords.value.length" class="section-header">
      <div class="section-title">中转站</div>
      <div class="section-action">{{ store.stagingRecords.value.length }} 条</div>
    </div>
    <div class="pending-record-list" v-if="store.stagingRecords.value.length">
      <div v-for="r in store.stagingRecords.value" :key="r.id" class="pending-record-card">
        <div class="pending-record-top">
          <div class="pending-record-thumb" @click="r.imageUrl && store.openImgFull(r.imageUrl)">
            <img v-if="r.imageUrl" :src="r.imageUrl" alt="">
            <span v-else>图</span>
          </div>
          <div class="pending-record-main">
            <div class="pending-record-title-row">
              <div class="pending-record-title">{{ r.domainName || statusLabel(r.status) }}</div>
              <span class="badge" :class="badgeClass(r.status)">{{ statusLabel(r.status) }}</span>
            </div>
            <div class="pending-record-sub">{{ typeLabel(r.recordType) }} · {{ formatCreated(r.createdAt) }}</div>
            <div class="pending-record-summary">{{ r.summary }}</div>
          </div>
        </div>

        <div class="pending-record-meta">
          <div class="confidence-bar">
            <div class="progress-bar">
              <div class="progress-bar-fill" :style="{ width: `${Math.round((r.confidence || 0) * 100)}%`, background: confidenceColor(r.confidence) }"></div>
            </div>
            <div class="confidence-value">{{ Math.round((r.confidence || 0) * 100) }}%</div>
          </div>
          <div v-if="r.lastErrorMessage" class="pending-record-error">{{ r.lastErrorMessage }}</div>
        </div>

        <div class="pending-record-actions">
          <button class="btn btn-secondary btn-sm" @click="store.retryStagingRecord(r)">重试</button>
          <button
            v-for="domain in archiveDomains"
            :key="`${r.id}-${domain.id}`"
            class="btn btn-ghost btn-sm"
            @click="store.archiveStagingRecord(r, domain.id)"
          >
            {{ domain.shortName }}
          </button>
          <button class="btn btn-danger btn-sm" @click="store.discardStagingRecord(r)">销毁</button>
        </div>
      </div>
    </div>

    <div v-if="store.pendingBills.value.length" class="section-header">
      <div class="section-title">账单待补充</div>
      <div class="section-action">{{ store.pendingBills.value.length }} 条</div>
    </div>
    <div class="pending-record-list" v-if="store.pendingBills.value.length">
      <div v-for="b in store.pendingBills.value" :key="b.id" class="pending-record-card clickable" @click="store.openPendingModal(b)">
        <div class="pending-record-top">
          <div class="pending-record-thumb placeholder expense">支</div>
          <div class="pending-record-main">
            <div class="pending-record-title-row">
              <div class="pending-record-title">{{ b.name }}</div>
              <div class="pending-record-amount">-¥{{ b.amount.toFixed(2) }}</div>
            </div>
            <div class="pending-record-sub">{{ b.date }} {{ b.time }} · 截图识别</div>
            <div class="pending-field-row">
              <span class="badge" :class="b.platform === '?' ? 'badge-warning' : 'badge-success'">{{ b.platform === '?' ? '平台未知' : b.platform }}</span>
              <span class="badge" :class="b.cat === '?' ? 'badge-warning' : 'badge-success'">{{ b.cat === '?' ? '分类未知' : b.cat }}</span>
              <span class="badge" :class="b.payment === '?' ? 'badge-warning' : 'badge-success'">{{ b.payment === '?' ? '支付未知' : b.payment }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
import { formatDateTimeLabel } from '../../utils/helpers'

const store = inject('store')
const totalPending = computed(() => store.pendingBills.value.length + store.stagingRecords.value.length)
const archiveDomains = computed(() => store.domains.value.filter(domain => !['expense', 'income'].includes(domain.id)))

function statusLabel(status) {
  const map = {
    ai_error: 'AI失败',
    routing_failed: '待分类',
    pending_review: '待确认',
    unrouted: '未路由',
    unassigned: '待分配',
    failed: '失败',
  }
  return map[status] || '待处理'
}

function badgeClass(status) {
  if (status === 'ai_error' || status === 'failed') return 'badge-danger'
  if (status === 'routing_failed' || status === 'unrouted' || status === 'unassigned') return 'badge-warning'
  return 'badge-primary'
}

function typeLabel(type) {
  const map = { expense: '支出截图', income: '收入截图', uncertain: '未确定截图' }
  return map[type] || '待处理截图'
}

function confidenceColor(confidence) {
  if ((confidence || 0) >= 0.7) return 'var(--success)'
  if ((confidence || 0) >= 0.4) return 'var(--warning)'
  return 'var(--danger)'
}

function formatCreated(value) {
  return formatDateTimeLabel(value)
}
</script>
