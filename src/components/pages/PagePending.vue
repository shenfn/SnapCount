<template>
  <div class="page active">
    <div class="topbar">
      <h1>待处理</h1>
      <div class="sub">
        {{ totalPending ? `${totalPending} 条记录需要处理` : '全部处理完毕' }}
      </div>
    </div>
    <div style="height:12px"></div>

    <div v-if="!totalPending" class="empty">
      <div class="e-icon">✓</div><p>全部补充完毕</p>
    </div>

    <div v-if="store.stagingRecords.value.length" class="sec-title">
      <div>中转站</div>
      <span>{{ store.stagingRecords.value.length }} 条</span>
    </div>
    <div v-for="r in store.stagingRecords.value" :key="r.id" class="staging-item">
      <div class="staging-head">
        <div v-if="r.imageUrl" class="staging-thumb" @click="store.openImgFull(r.imageUrl)">
          <img :src="r.imageUrl" alt="">
        </div>
        <div v-else class="staging-thumb placeholder">图</div>
        <div>
          <div class="staging-title">{{ r.domainName || statusLabel(r.status) }}</div>
          <div class="staging-meta">{{ formatCreated(r.createdAt) }} · {{ typeLabel(r.recordType) }}</div>
        </div>
        <span class="staging-status" :class="statusClass(r.status)">{{ statusLabel(r.status) }}</span>
      </div>
      <div class="staging-summary">{{ r.summary }}</div>
      <div v-if="r.lastErrorMessage" class="staging-error">{{ r.lastErrorMessage }}</div>
      <div class="pending-fields">
        <span class="field-chip" :class="r.confidence >= 0.7 ? 'field-ok' : 'field-missing'">
          置信度 {{ Math.round((r.confidence || 0) * 100) }}%
        </span>
        <span v-if="r.imageType" class="field-chip field-ok">{{ r.imageType }}</span>
        <span v-if="r.retryCount" class="field-chip field-missing">已重试 {{ r.retryCount }} 次</span>
      </div>
      <div class="staging-actions">
        <button class="staging-btn" @click="store.retryStagingRecord(r)">重试</button>
        <button class="staging-btn danger" @click="store.discardStagingRecord(r)">销毁</button>
      </div>
    </div>

    <div v-if="store.pendingBills.value.length" class="sec-title">
      <div>账单待补充</div>
      <span>{{ store.pendingBills.value.length }} 条</span>
    </div>
    <div v-for="b in store.pendingBills.value" :key="b.id" class="pending-item" @click="store.openPendingModal(b)">
      <div class="pending-row">
        <div>
          <div class="pending-amount">-¥{{ b.amount.toFixed(2) }}</div>
          <div class="pending-time">{{ b.date }} {{ b.time }} · 截图识别</div>
        </div>
        <div style="font-size:13px; color:var(--accent)">补充 ›</div>
      </div>
      <div class="pending-fields">
        <span class="field-chip" :class="b.platform === '?' ? 'field-missing' : 'field-ok'">
          {{ b.platform === '?' ? '? 平台未知' : '✓ ' + b.platform }}
        </span>
        <span class="field-chip" :class="b.cat === '?' ? 'field-missing' : 'field-ok'">
          {{ b.cat === '?' ? '? 分类未知' : '✓ ' + b.cat }}
        </span>
        <span class="field-chip" :class="b.payment === '?' ? 'field-missing' : 'field-ok'">
          {{ b.payment === '?' ? '? 支付未知' : '✓ ' + b.payment }}
        </span>
      </div>
    </div>
    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
const store = inject('store')

const totalPending = computed(() => store.pendingBills.value.length + store.stagingRecords.value.length)

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

function statusClass(status) {
  if (status === 'ai_error' || status === 'failed') return 'error'
  if (status === 'routing_failed' || status === 'unrouted' || status === 'unassigned') return 'warn'
  return 'ok'
}

function typeLabel(type) {
  const map = { expense: '支出', income: '收入', uncertain: '未确定' }
  return map[type] || '未确定'
}

function formatCreated(value) {
  if (!value) return ''
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return ''
  return `${d.getMonth() + 1}月${d.getDate()}日 ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}
</script>
