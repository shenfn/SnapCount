<template>
  <div class="page active">
    <div class="page-title">待处理</div>
    <div class="page-subtitle">
      {{ totalPending ? `${totalPending} 条记录等待分类、确认或补全` : '当前没有待处理记录' }}
    </div>

    <div class="chip-group">
      <div class="chip" :class="{ active: store.pendingFilter.value === 'all' }" @click="store.pendingFilter.value = 'all'">
        全部 <span class="chip-count">{{ totalPending }}</span>
      </div>
      <div class="chip" :class="{ active: store.pendingFilter.value === 'routing_failed' }" @click="store.pendingFilter.value = 'routing_failed'">
        待分类 <span class="chip-count">{{ store.pendingSummary.value.routingFailed }}</span>
      </div>
      <div class="chip" :class="{ active: store.pendingFilter.value === 'pending_review' }" @click="store.pendingFilter.value = 'pending_review'">
        待确认 <span class="chip-count">{{ store.pendingSummary.value.pendingReview }}</span>
      </div>
      <div class="chip" :class="{ active: store.pendingFilter.value === 'ai_error' }" @click="store.pendingFilter.value = 'ai_error'">
        AI失败 <span class="chip-count">{{ store.pendingSummary.value.aiError }}</span>
      </div>
      <div class="chip" :class="{ active: store.pendingFilter.value === 'bill_pending' }" @click="store.pendingFilter.value = 'bill_pending'">
        账单补充 <span class="chip-count">{{ store.pendingSummary.value.billPending }}</span>
      </div>
    </div>

    <div v-if="!totalPending" class="empty-state">
      <div class="empty-title">中转站是空的</div>
      <div class="empty-desc">新的非记账截图、待确认记录和识别失败截图都会先进入这里。</div>
    </div>

    <!-- 中转站待处理 -->
    <div v-if="filteredStaging.length" class="section-header">
      <div class="section-title">中转站</div>
      <div class="section-action">
        <span v-if="!store.batchMode.value" @click="store.toggleBatchMode()" style="margin-right:12px;">批量管理</span>
        <span v-else @click="store.toggleBatchMode()" style="color:var(--danger);">取消</span>
        <span>{{ filteredStaging.length }} 条</span>
      </div>
    </div>
    <div v-if="store.batchMode.value && filteredStaging.length" class="batch-select-all" @click="store.selectAllStaging(filteredStaging)">
      <span v-if="store.selectedStagingIds.value.size === filteredStaging.length">☑ 已全选</span>
      <span v-else>☐ 全选 {{ filteredStaging.length }} 条</span>
    </div>
    <div class="pending-record-list" v-if="filteredStaging.length">
      <template v-for="(dateLabel, idx) in stagingDateKeys" :key="dateLabel">
        <div class="pending-date-label">{{ dateLabel }}</div>
        <div
          v-for="r in stagingByDate[dateLabel]"
          :key="r.id"
          class="pending-record-card"
          :class="{ clickable: r.status !== 'ai_error' && !store.batchMode.value }"
        >
          <div v-if="store.batchMode.value" class="batch-checkbox" @click.stop="store.toggleSelectStaging(r.id)">
            <span v-if="store.selectedStagingIds.value.has(r.id)" style="color:var(--primary);font-size:20px;">☑</span>
            <span v-else style="color:var(--text3);font-size:20px;">☐</span>
          </div>
          <div class="pending-record-top">
            <div class="pending-record-thumb" @click="r.imageUrl && store.openImgFull(r.imageUrl)">
              <img v-if="r.imageUrl" :src="r.imageUrl" alt="">
              <span v-else>图</span>
            </div>
            <div class="pending-record-main">
              <div class="pending-record-title-row">
                <div class="pending-record-title">
                  {{ r.domainName || statusLabel(r.status) }}
                </div>
                <span class="badge" :class="badgeClass(r.status)">{{ statusLabel(r.status) }}</span>
              </div>
              <div class="pending-record-sub">
                {{ typeLabel(r.recordType) }}
                <template v-if="r.occurredAt"> · 记录时间 {{ fmtShort(r.occurredAt) }}</template>
                <template v-if="r.createdAt"> · 截图 {{ fmtShort(r.createdAt) }}</template>
              </div>
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
            <button class="btn btn-secondary btn-sm" @click="store.retryStagingRecord(r)">🔄 重试识别</button>
            <button class="btn btn-danger btn-sm" @click="store.discardStagingRecord(r)">🗑 销毁</button>
          </div>
          <div class="pending-archive-row">
            <span class="pending-archive-label">归档到：</span>
            <button
              v-for="domain in archiveDomains"
              :key="`${r.id}-${domain.id}`"
              class="btn btn-ghost btn-sm"
              @click="store.archiveStagingRecord(r, domain.id)"
            >
              {{ domain.icon }} {{ domain.shortName }}
            </button>
          </div>
        </div>
      </template>
    </div>

    <!-- 批量操作栏 -->
    <div v-if="store.batchMode.value && store.selectedStagingIds.value.size" class="batch-bar">
      <span class="batch-bar-count">已选 {{ store.selectedStagingIds.value.size }} 条</span>
      <div class="batch-bar-actions">
        <button class="btn btn-secondary btn-sm" @click="store.batchArchive('expense')">💰 归档消费</button>
        <button class="btn btn-secondary btn-sm" @click="store.batchArchive('income')">💵 归档收入</button>
        <button class="btn btn-danger btn-sm" @click="store.batchDiscard()">🗑 全部销毁</button>
      </div>
    </div>

    <!-- 账单待补充 -->
    <div v-if="showBillPending && filteredBills.length" class="section-header">
      <div class="section-title">账单待补充</div>
      <div class="section-action">{{ filteredBills.length }} 条</div>
    </div>
    <div class="pending-record-list" v-if="showBillPending && filteredBills.length">
      <template v-for="(dateLabel, idx) in billDateKeys" :key="dateLabel">
        <div class="pending-date-label">{{ dateLabel }}</div>
        <div
          v-for="b in billsByDate[dateLabel]"
          :key="b.id"
          class="pending-record-card clickable"
          @click="store.openPendingModal(b)"
        >
          <div class="pending-record-top">
            <div class="pending-record-thumb placeholder expense">支</div>
            <div class="pending-record-main">
              <div class="pending-record-title-row">
                <div class="pending-record-title">{{ b.name }}</div>
                <div class="pending-record-amount">-¥{{ b.amount.toFixed(2) }}</div>
              </div>
              <div class="pending-record-sub">
                {{ b.date }} {{ b.time }} · 截图识别
                <template v-if="b.createdAt"> · 上传于 {{ fmtShort(b.createdAt) }}</template>
              </div>
              <div class="pending-field-row">
                <span class="badge" :class="b.platform === '?' ? 'badge-warning' : 'badge-success'">{{ b.platform === '?' ? '平台未知' : b.platform }}</span>
                <span class="badge" :class="b.cat === '?' ? 'badge-warning' : 'badge-success'">{{ b.cat === '?' ? '分类未知' : b.cat }}</span>
                <span class="badge" :class="b.payment === '?' ? 'badge-warning' : 'badge-success'">{{ b.payment === '?' ? '支付未知' : b.payment }}</span>
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- 已处理记录 -->
    <div v-if="store.processedStagingRecords.value.length" class="section-header" style="margin-top: 8px;">
      <div class="section-title">已处理</div>
      <div class="section-action" @click="store.processedExpanded.value = !store.processedExpanded.value">
        {{ store.processedExpanded.value ? '收起' : `${store.processedStagingRecords.value.length} 条` }}
      </div>
    </div>
    <div class="pending-record-list" v-if="store.processedStagingRecords.value.length && store.processedExpanded.value">
      <div
        v-for="r in store.processedStagingRecords.value"
        :key="'proc-'+r.id"
        class="pending-record-card processed"
      >
        <div class="pending-record-top">
          <div class="pending-record-thumb" @click="r.imageUrl && store.openImgFull(r.imageUrl)">
            <img v-if="r.imageUrl" :src="r.imageUrl" alt="">
            <span v-else>图</span>
          </div>
          <div class="pending-record-main">
            <div class="pending-record-title-row">
              <div class="pending-record-title">{{ r.domainName || '已处理截图' }}</div>
              <span class="badge" :class="r.status === 'discarded' ? 'badge-danger' : 'badge-success'">
                {{ r.status === 'discarded' ? '已销毁' : '已归档' }}
              </span>
            </div>
            <div class="pending-record-sub">
              <template v-if="r.status === 'archived' && r.domainKey">
                流向「{{ domainLabel(r.domainKey) }}」
              </template>
              <template v-if="r.status === 'discarded' && r.discardReason">
                原因：{{ r.discardReason }}
              </template>
              <template v-if="r.resolvedAt"> · {{ fmtShort(r.resolvedAt) }}</template>
            </div>
            <div class="pending-record-summary" v-if="r.summary && r.status === 'archived'">{{ r.summary }}</div>
          </div>
        </div>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { computed, inject } from 'vue'
import { formatDateTimeLabel, getLocalDateKey } from '../../utils/helpers'

const store = inject('store')

const dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

const totalPending = computed(() => store.pendingBills.value.length + store.stagingRecords.value.length)

const showBillPending = computed(() =>
  store.pendingFilter.value === 'all' || store.pendingFilter.value === 'bill_pending'
)

const filteredStaging = computed(() => {
  const records = store.stagingRecords.value
  if (store.pendingFilter.value === 'bill_pending') return []
  if (store.pendingFilter.value === 'all') return records
  if (store.pendingFilter.value === 'ai_error') return records.filter(r => r.status === 'ai_error' || r.status === 'failed')
  return records.filter(r => r.status === store.pendingFilter.value)
})

const filteredBills = computed(() => {
  if (store.pendingFilter.value !== 'all' && store.pendingFilter.value !== 'bill_pending') return []
  return store.pendingBills.value
})

function groupByDate(items, dateField) {
  const today = getLocalDateKey()
  const yesterday = getLocalDateKey(new Date(Date.now() - 86400000))
  const groups = {}
  items.forEach(item => {
    const raw = item[dateField] || item.createdAt
    const key = String(raw || '').slice(0, 10)
    if (!key || key.length < 10) {
      if (!groups['未知日期']) groups['未知日期'] = []
      groups['未知日期'].push(item)
      return
    }
    let label
    if (key === today) label = '今天'
    else if (key === yesterday) label = '昨天'
    else {
      const d = new Date(key + 'T00:00:00')
      if (!isNaN(d.getTime())) {
        label = `${d.getMonth() + 1}月${d.getDate()}日 · ${dayNames[d.getDay()]}`
      } else {
        label = key
      }
    }
    if (!groups[label]) groups[label] = []
    groups[label].push(item)
  })
  return groups
}

function sortDateKeys(groups) {
  const keys = Object.keys(groups)
  const today = getLocalDateKey()
  const yesterday = getLocalDateKey(new Date(Date.now() - 86400000))
  return keys.sort((a, b) => {
    if (a === '今天') return -1
    if (b === '今天') return 1
    if (a === '昨天') return -1
    if (b === '昨天') return 1
    return b.localeCompare(a)
  })
}

const stagingByDate = computed(() => groupByDate(filteredStaging.value, 'occurredAt'))
const stagingDateKeys = computed(() => sortDateKeys(stagingByDate.value))

const billsByDate = computed(() => groupByDate(filteredBills.value, 'dateRaw'))
const billDateKeys = computed(() => sortDateKeys(billsByDate.value))

const archiveDomains = computed(() => store.domains.value)

function statusLabel(status) {
  const map = {
    ai_error: 'AI失败',
    routing_failed: '待分类',
    pending_review: '待确认',
    unrouted: '未路由',
    unassigned: '待分配',
    failed: '失败',
    routed: '已路由',
    extracted: '已抽取',
    confirmed: '已确认',
  }
  return map[status] || status || '待处理'
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

function domainLabel(key) {
  const map = { expense: '消费记账', income: '收入记录', sport: '运动记录', sleep: '睡眠记录', reading: '阅读记录' }
  return map[key] || key || '未知域'
}

function fmtShort(value) {
  if (!value) return ''
  const s = String(value)
  const d = new Date(s.includes('T') ? s : s + 'T00:00:00')
  if (isNaN(d.getTime())) return s.slice(0, 16)
  return `${d.getMonth() + 1}月${d.getDate()}日 ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}
</script>
