<template>
  <div class="page active pending-verdict-page">
    <header class="pending-hero">
      <div>
        <div class="page-title">收件箱</div>
        <div class="page-subtitle">
          {{ pendingScope === 'today'
            ? (scopedPendingCount ? `今天还有 ${scopedPendingCount} 条需要你决定` : '今天没有待处理记录')
            : (totalPending ? `全部 ${totalPending} 条按发生时间排列` : '当前没有待处理记录') }}
        </div>
      </div>
      <div class="pending-hero-actions">
        <div class="pending-scope-switch" role="group" aria-label="待处理记录范围">
          <button type="button" :class="{ active: pendingScope === 'all' }" @click="setPendingScope('all')">全部</button>
          <button type="button" :class="{ active: pendingScope === 'today' }" @click="setPendingScope('today')">今天</button>
        </div>
        <button
          v-if="filteredStaging.length"
          type="button"
          class="pending-select-toggle"
          @click="store.toggleBatchMode()"
        >
          {{ store.batchMode.value ? '完成' : '选择' }}
        </button>
      </div>
    </header>

    <div class="pending-filter-row" aria-label="收件箱状态筛选">
      <button type="button" class="pending-filter-chip" :class="{ active: store.pendingFilter.value === 'all' }" @click="setPendingFilter('all')">
        全部 <span>{{ pendingStatusCounts.all }}</span>
      </button>
      <button type="button" class="pending-filter-chip" :class="{ active: store.pendingFilter.value === 'routing_failed' }" @click="setPendingFilter('routing_failed')">
        待分类 <span>{{ pendingStatusCounts.routing_failed }}</span>
      </button>
      <button type="button" class="pending-filter-chip" :class="{ active: store.pendingFilter.value === 'pending_review' }" @click="setPendingFilter('pending_review')">
        待确认 <span>{{ pendingStatusCounts.pending_review }}</span>
      </button>
      <button type="button" class="pending-filter-chip" :class="{ active: store.pendingFilter.value === 'ai_error' }" @click="setPendingFilter('ai_error')">
        需重试 <span>{{ pendingStatusCounts.ai_error }}</span>
      </button>
      <button type="button" class="pending-filter-chip" :class="{ active: store.pendingFilter.value === 'schema_failed' }" @click="setPendingFilter('schema_failed')">
        待修补 <span>{{ pendingStatusCounts.schema_failed }}</span>
      </button>
      <button type="button" class="pending-filter-chip" :class="{ active: store.pendingFilter.value === 'bill_pending' }" @click="setPendingFilter('bill_pending')">
        账单补全 <span>{{ pendingStatusCounts.bill_pending }}</span>
      </button>
    </div>

    <div v-if="!filteredQueue.length" class="pending-empty-state">
      <div class="pending-empty-orbit" aria-hidden="true"><span></span></div>
      <div class="empty-title">{{ totalPending ? '当前范围已经处理完' : '微尘皆已落定' }}</div>
      <div class="empty-desc">{{ totalPending ? '切换范围或状态可以查看其他记录' : '新的截图会在这里稍作停留' }}</div>
    </div>

    <button
      v-if="store.batchMode.value && filteredStaging.length"
      type="button"
      class="batch-select-all"
      @click="store.selectAllStaging(filteredStaging)"
    >
      {{ store.selectedStagingIds.value.size === filteredStaging.length ? '已全选' : `全选 ${filteredStaging.length} 张` }}
    </button>

    <div v-if="filteredQueue.length" class="pending-film-groups">
      <section v-for="section in pendingSections" :key="section.key" class="pending-film-group">
        <div class="pending-date-label">{{ section.label }}</div>
        <div class="pending-film-grid">
          <button
            v-for="item in section.items"
            :key="item.queueId"
            type="button"
            class="pending-film-card"
            :class="{
              selected: item.source === 'staging' && store.selectedStagingIds.value.has(item.sourceId),
              'has-image': Boolean(queueImageUrl(item)),
              'is-fact-card': !queueImageUrl(item),
              'is-bill-card': item.source === 'bill',
              'batch-unavailable': store.batchMode.value && item.source === 'bill',
            }"
            @click="handleQueueTap(item)"
          >
            <span class="pending-film-visual" :class="{ 'has-image': Boolean(queueImageUrl(item)) }">
              <img v-if="queueImageUrl(item)" :src="queueImageUrl(item)" :alt="queueTitle(item)" loading="lazy" decoding="async" fetchpriority="low" @error="markQueueImageUnavailable(item)">
              <span v-else-if="item.source === 'bill'" class="pending-bill-fact-note">
                <span class="pending-film-note-kicker">{{ item.record.image_path || item.record.image_url ? '原图暂不可用 · 账单事实' : '原图未保留 · 账单事实' }}</span>
                <span class="pending-bill-fact-icon">支</span>
                <strong>{{ billReviewTitle(item.record) }}</strong>
                <b>-¥{{ Number(item.record.amount || 0).toFixed(2) }}</b>
                <span class="pending-bill-fact-lines">
                  <span>{{ item.record.platform === '?' ? '平台未知' : item.record.platform }}</span>
                  <span>{{ billCategoryLabel(item.record.cat) }}</span>
                  <span>{{ item.record.payment === '?' ? '支付未知' : item.record.payment }}</span>
                </span>
              </span>
              <span v-else class="pending-film-note">
                <span class="pending-film-note-kicker">{{ item.record.imagePath ? '原图暂不可用 · 文字事实' : '原图未保留 · 文字事实' }}</span>
                <span class="pending-film-note-heading">
                  <span class="pending-film-note-icon">{{ typeGlyph(item.record.recordType) }}</span>
                  <strong>{{ queueTitle(item) }}</strong>
                </span>
                <span class="pending-film-note-summary">{{ queueDescription(item) }}</span>
                <span v-if="queueFactRows(item).length" class="pending-film-facts">
                  <span v-for="fact in queueFactRows(item).slice(0, 3)" :key="`${item.queueId}-${fact.key}`">
                    <small>{{ fact.label }}</small>
                    <b>{{ fact.value }}</b>
                  </span>
                </span>
                <span v-else-if="item.record.lastErrorMessage" class="pending-film-note-error">
                  {{ readableError(item.record.lastErrorMessage) }}
                </span>
              </span>
              <span class="pending-film-state" :class="statusTone(item.status)">
                <i></i>{{ statusLabel(item.status) }}
              </span>
              <span v-if="store.batchMode.value && item.source === 'staging'" class="pending-film-select" :class="{ checked: store.selectedStagingIds.value.has(item.sourceId) }">
                {{ store.selectedStagingIds.value.has(item.sourceId) ? '✓' : '' }}
              </span>
              <span v-if="queueImageUrl(item)" class="pending-film-scrim">
                <strong>{{ queueTitle(item) }}</strong>
                <small>{{ queueDescription(item) }}</small>
              </span>
            </span>
            <span class="pending-film-caption" :class="{ 'pending-bill-film-caption': item.source === 'bill' }">
              <span v-if="item.source === 'bill'" class="pending-bill-film-title">
                <strong>{{ item.record.name || '待补全账单' }}</strong>
                <b>-¥{{ Number(item.record.amount || 0).toFixed(2) }}</b>
              </span>
              <template v-else>
                <strong>{{ queueTitle(item) }}</strong>
                <span class="pending-film-caption-domain">{{ queueContextLabel(item) }}</span>
              </template>
              <span class="pending-time-stack">
                <span><i>记录</i>{{ queueOccurredLabel(item) }}</span>
                <span><i>上传</i>{{ fmtShort(item.createdAt) || '未知' }}</span>
              </span>
              <span v-if="item.source === 'bill'" class="pending-bill-facts">
                <span :class="{ missing: item.record.platform === '?' }">{{ item.record.platform === '?' ? '平台未知' : item.record.platform }}</span>
                <span :class="{ missing: item.record.cat === '?' }">{{ billCategoryLabel(item.record.cat) }}</span>
                <span :class="{ missing: item.record.payment === '?' }">{{ item.record.payment === '?' ? '支付未知' : item.record.payment }}</span>
              </span>
            </span>
          </button>
        </div>
      </section>
    </div>

    <div v-if="store.batchMode.value && store.selectedStagingIds.value.size" class="batch-bar">
      <span class="batch-bar-count">已选 {{ store.selectedStagingIds.value.size }} 条</span>
      <div class="batch-bar-actions">
        <button class="btn btn-secondary btn-sm" @click="store.batchArchive('expense')">收下到支出</button>
        <button class="btn btn-secondary btn-sm" @click="store.batchArchive('income')">收下到收入</button>
        <button class="btn btn-danger btn-sm" @click="store.batchDiscard()">销毁</button>
      </div>
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
            <img v-if="r.imageUrl" :src="r.imageUrl" alt="" loading="lazy" decoding="async">
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
            <button
              v-if="r.status === 'archived' && r.targetRecordId"
              type="button"
              class="pending-processed-edit"
              @click.stop="store.openProcessedStagingRecord(r)"
            >
              查看并编辑
            </button>
          </div>
        </div>
      </div>
    </div>

    <div class="spacer"></div>

    <Teleport to="body">
      <div v-if="activeVerdict" class="verdict-stage" role="dialog" aria-modal="true" aria-label="截图裁决台">
        <div class="verdict-stage-shell">
          <header class="verdict-stage-topbar">
            <button type="button" class="verdict-icon-button" aria-label="关闭裁决台" @click="closeVerdict">×</button>
            <div class="verdict-stage-state" :class="statusTone(activeVerdict.status)">
              <i></i>{{ statusLabel(activeVerdict.status) }} · {{ queueContextLabel(activeVerdict) }}
            </div>
            <div class="verdict-stage-counter">{{ activeVerdictIndex + 1 }} / {{ filteredQueue.length }}</div>
          </header>

          <div class="verdict-photo-stage" @touchstart="onStageTouchStart" @touchend="onStageTouchEnd">
            <button type="button" class="verdict-page-button previous" :disabled="activeVerdictIndex <= 0" aria-label="上一张" @click="moveVerdict(-1)">‹</button>
            <button
              v-if="queueImageUrl(activeVerdict)"
              type="button"
              class="verdict-photo"
              :class="{ 'is-loading': !activeVerdictImageReady }"
              aria-label="查看原图"
              @click="store.openImgFull(queueImageUrl(activeVerdict))"
            >
              <span v-if="!activeVerdictImageReady" class="verdict-image-loading" aria-live="polite">
                <i></i><span>正在准备原图</span>
              </span>
              <img :src="queueImageUrl(activeVerdict)" :alt="queueTitle(activeVerdict)" decoding="async" fetchpriority="high"
                @load="activeVerdictImageReady = true" @error="markActiveQueueImageUnavailable(activeVerdict)">
            </button>
            <div v-else class="verdict-fact-sheet">
              <span class="verdict-fact-kicker">{{ queueHasImageReference(activeVerdict) ? '原图暂不可用 · 文字事实' : '原图未保留 · 文字事实' }}</span>
              <div class="verdict-fact-heading">
                <span>{{ activeVerdict.source === 'bill' ? '支' : typeGlyph(activeVerdict.record.recordType) }}</span>
                <strong>{{ queueTitle(activeVerdict) }}</strong>
              </div>
              <p>{{ queueDescription(activeVerdict) }}</p>
              <dl v-if="queueFactRows(activeVerdict).length">
                <div v-for="fact in queueFactRows(activeVerdict).slice(0, 5)" :key="`verdict-${activeVerdict.queueId}-${fact.key}`">
                  <dt>{{ fact.label }}</dt>
                  <dd>{{ fact.value }}</dd>
                </div>
              </dl>
              <div v-else class="verdict-fact-empty">没有保留原图，当前仅能依据识别摘要进行判断。</div>
            </div>
            <button type="button" class="verdict-page-button next" :disabled="activeVerdictIndex >= filteredQueue.length - 1" aria-label="下一张" @click="moveVerdict(1)">›</button>
          </div>

          <div class="verdict-stage-info">
            <strong>{{ queueTitle(activeVerdict) }}</strong>
            <p class="verdict-stage-guidance">{{ queueDescription(activeVerdict) }}</p>
            <div v-if="activeVerdict.source === 'staging'" class="verdict-stage-meta">
              <span class="verdict-assurance"><i v-for="dot in 3" :key="dot" :class="{ on: dot <= assuranceDots(activeVerdict.record.confidence) }"></i>{{ assuranceLabel(activeVerdict.record.confidence) }}</span>
              <span v-if="activeVerdict.record.retryCount">已重试 {{ activeVerdict.record.retryCount }} 次</span>
            </div>
            <div class="verdict-time-stack verdict-time-stack-detail">
              <span><i>记录时间</i>{{ queueOccurredLabel(activeVerdict) }}</span>
              <span><i>上传时间</i>{{ fmtShort(activeVerdict.createdAt) || '未知' }}</span>
            </div>
            <div v-if="activeVerdict.source === 'staging' && displayError(activeVerdict.record)" class="verdict-stage-error">{{ displayError(activeVerdict.record) }}</div>
            <div v-if="activeVerdict.source === 'staging' && requiresReadingRepair(activeVerdict.record)" class="verdict-value-note">
              <strong>补完有什么用</strong>
              <span>书名用于归到对应书籍，阅读时长会进入你的阅读趋势；原图会继续作为这次记录的依据。</span>
            </div>
          </div>

          <div v-if="activeVerdict.source === 'staging' && activeVerdict.record.repaymentCandidate" class="verdict-repayment">
            <div>
              <strong>可能是还款截图</strong>
              <span>{{ activeVerdict.record.repaymentCandidate.account.name }} {{ activeVerdict.record.repaymentCandidate.cycle.cycleMonth }} 账单</span>
            </div>
            <button type="button" :disabled="verdictBusy" @click="confirmRepaymentFromVerdict(activeVerdict.record)">
              确认 ¥{{ Number(activeVerdict.record.repaymentCandidate.amount || 0).toFixed(2) }}
            </button>
          </div>

          <div v-if="activeVerdict.source === 'bill'" class="verdict-stage-actions verdict-bill-actions">
            <button type="button" class="verdict-accept-button" :disabled="verdictBusy" @click="openBillFromVerdict(activeVerdict)">
              <span>↓</span> 补全这笔账单
            </button>
            <div class="verdict-minor-actions">
              <button type="button" :disabled="activeVerdictIndex >= filteredQueue.length - 1" @click="moveVerdict(1)"><span>›</span>稍后</button>
              <button type="button" @click="queueImageUrl(activeVerdict) && store.openImgFull(queueImageUrl(activeVerdict))"><span>⌕</span>原图</button>
            </div>
          </div>

          <div v-else class="verdict-stage-actions">
            <button
              v-if="suggestedDomain(activeVerdict.record)"
              type="button"
              class="verdict-accept-button"
              :disabled="verdictBusy"
              @click="archiveFromVerdict(activeVerdict.record, suggestedDomain(activeVerdict.record).id)"
            >
              <span>↓</span> {{ verdictPrimaryLabel(activeVerdict.record) }}
            </button>
            <div class="verdict-minor-actions">
              <button v-if="suggestedDomain(activeVerdict.record)" type="button" :disabled="verdictBusy" @click="adjustFromVerdict(activeVerdict.record)"><span>☷</span>调整</button>
              <button v-if="store.canRetryStagingRecord(activeVerdict.record)" type="button" :disabled="verdictBusy" @click="retryFromVerdict(activeVerdict.record)"><span>↻</span>重试</button>
              <button type="button" class="danger" :disabled="verdictBusy" @click="discardFromVerdict(activeVerdict.record)"><span>×</span>销毁</button>
            </div>
          </div>

          <div v-if="activeVerdict.source === 'staging'" class="verdict-domain-strip">
            <span>改判到</span>
            <button
              v-for="domain in archiveDomains"
              :key="`verdict-${domain.id}`"
              type="button"
              :class="{ current: suggestedDomain(activeVerdict.record)?.id === domain.id }"
              :disabled="verdictBusy"
              @click="archiveFromVerdict(activeVerdict.record, domain.id)"
            >
              {{ domain.shortName }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { computed, inject, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { getLocalDateKey } from '../../utils/helpers'
import { getSystemDomainLabel } from '../../domains/registry'
import {
  buildPendingQueue,
  countPendingQueueByStatus,
  filterPendingQueue,
  pendingQueueItemAtPreviousIndex,
} from '../../domains/pendingQueue'

const store = inject('store')
const activeVerdictId = ref(null)
const verdictBusy = ref(false)
const stageTouchStartX = ref(null)
const activeVerdictImageReady = ref(false)
const editingVerdictContext = ref(null)
const pendingScope = ref('today')

const dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

const pendingQueue = computed(() => buildPendingQueue({
  stagingRecords: store.stagingRecords.value,
  pendingBills: store.pendingBills.value,
}))
const todayKey = ref(getLocalDateKey())
let todayRefreshTimer = null
const totalPending = computed(() => pendingQueue.value.length)
const pendingStatusCounts = computed(() => countPendingQueueByStatus(pendingQueue.value, {
  scope: pendingScope.value,
  todayKey: todayKey.value,
}))
const scopedPendingCount = computed(() => pendingStatusCounts.value.all)
const filteredQueue = computed(() => filterPendingQueue(pendingQueue.value, {
  scope: pendingScope.value,
  filter: store.pendingFilter.value,
  todayKey: todayKey.value,
}))
const filteredStaging = computed(() => filteredQueue.value
  .filter(item => item.source === 'staging')
  .map(item => item.record))

const activeVerdictIndex = computed(() => filteredQueue.value.findIndex(item => item.queueId === activeVerdictId.value))
const activeVerdict = computed(() => {
  const index = activeVerdictIndex.value
  return index >= 0 ? filteredQueue.value[index] : null
})

function dateSectionLabel(key, today, yesterday) {
  if (key === today) return '今天'
  if (key === yesterday) return '昨天'
  if (key === 'unknown') return '未知日期'
  const d = new Date(`${key}T00:00:00`)
  if (isNaN(d.getTime())) return key
  const yearPrefix = d.getFullYear() === new Date().getFullYear() ? '' : `${d.getFullYear()}年`
  return `${yearPrefix}${d.getMonth() + 1}月${d.getDate()}日 · ${dayNames[d.getDay()]}`
}

function groupIntoDateSections(items) {
  const today = getLocalDateKey()
  const yesterday = getLocalDateKey(new Date(Date.now() - 86400000))
  const groups = new Map()
  items.forEach(item => {
    const key = item.occurredDateKey || 'unknown'
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(item)
  })
  return [...groups.entries()]
    .sort(([left], [right]) => {
      if (left === 'unknown') return 1
      if (right === 'unknown') return -1
      return right.localeCompare(left)
    })
    .map(([key, sectionItems]) => ({
      key,
      label: dateSectionLabel(key, today, yesterday),
      items: sectionItems,
    }))
}

const pendingSections = computed(() => groupIntoDateSections(filteredQueue.value))

const archiveDomains = computed(() => store.domains.value)

const stagingFactDefinitions = [
  ['amount', '金额'],
  ['merchant_name', '商家名称'],
  ['source_name', '来源名称'],
  ['platform', '消费渠道'],
  ['category', '分类'],
  ['payment_method', '支付方式'],
  ['income_category', '收入类型'],
  ['transaction_date', '消费日期'],
  ['income_date', '到账日期'],
  ['occurred_at', '发生时间'],
  ['sport_type', '运动类型'],
  ['activity_type', '运动类型'],
  ['duration_minutes', '时长'],
  ['distance_km', '距离'],
  ['calories', '消耗热量'],
  ['sleep_minutes', '睡眠时长'],
  ['quality_level', '质量等级'],
  ['quality_score', '质量评分'],
  ['book_name', '书名'],
  ['reading_minutes', '阅读时长'],
  ['pages', '阅读页数'],
  ['meal_type', '餐次'],
  ['total_calorie_kcal', '总热量'],
  ['account_name', '账户名称'],
  ['snapshot_balance', '账户金额'],
  ['account_type', '账户类型'],
  ['due_date', '还款日期'],
  ['note', '备注'],
]

const stagingFactAliases = {
  calories: ['calories_kcal'],
  sleep_minutes: ['sleep_hours'],
  pages: ['pages_read'],
}

const hiddenStagingFactKeys = new Set([
  'ai_feedback', 'ai_summary', 'companion_message', 'confidence', 'failure_reason',
  'image_type', 'payload_jsonb', 'raw_text', 'record_type', 'time_context',
  'title', 'summary',
])

const stagingFieldCopy = {
  amount: '金额',
  platform: '消费渠道',
  category: '分类',
  payment_method: '支付方式',
  income_category: '收入类型',
  merchant_name: '商家名称',
  source_name: '来源名称',
  transaction_date: '消费日期',
  income_date: '到账日期',
  occurred_at: '记录时间',
  book_name: '书名',
  reading_minutes: '阅读时长',
  sleep_minutes: '睡眠时长',
  duration_minutes: '运动时长',
  sport_type: '运动类型',
  meal_type: '餐次',
  account_name: '账户名称',
}

function asPlainObject(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value
  if (typeof value !== 'string') return {}
  try {
    const parsed = JSON.parse(value)
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}
  } catch (_) {
    return {}
  }
}

function recordFacts(record) {
  const root = asPlainObject(record?.extracted)
  const nested = asPlainObject(root.payload_jsonb)
  return { ...root, ...nested }
}

function isPossibleDuplicate(record) {
  const facts = recordFacts(record)
  return record?.lastErrorType === 'POSSIBLE_DUPLICATE'
    || facts.review_reason === 'possible_duplicate'
    || Boolean(facts.duplicate_review)
}

function missingFieldKeys(record) {
  const root = asPlainObject(record?.extracted)
  const nested = asPlainObject(root.payload_jsonb)
  const report = asPlainObject(root.quality_report || nested.quality_report)
  const keys = Array.isArray(report.missing_fields) ? [...report.missing_fields] : []
  const messages = [record?.failureReason, record?.lastErrorMessage, record?.summary]
    .filter(Boolean)
    .map(String)

  messages.forEach(message => {
    const match = message.match(/(?:缺少字段(?:或置信度不足)?|missing_fields?)\s*[:：]\s*([a-z0-9_,，、\s-]+)/i)
    if (!match) return
    match[1].split(/[,，、\s]+/).forEach(key => {
      const normalized = key.trim().replace(/[.:：;；]+$/g, '')
      if (normalized) keys.push(normalized)
    })
  })
  return [...new Set(keys)]
}

function requiresReadingRepair(record) {
  if (record?.domainKey !== 'reading') return false
  const facts = recordFacts(record)
  const bookName = String(facts.book_name || '').trim()
  const minutes = Number(facts.reading_minutes)
  return !bookName || !Number.isFinite(minutes) || minutes <= 0
}

function reviewContextLabel(record) {
  if (requiresReadingRepair(record)) return '阅读内容'
  return record?.domainName || typeLabel(record?.recordType)
}

function reviewPresentation(record) {
  const missing = missingFieldKeys(record)
  const facts = recordFacts(record)
  const context = reviewContextLabel(record)

  if (isPossibleDuplicate(record)) {
    return {
      title: '这笔可能已经记过',
      description: '图片和账单信息都很相似。对照图片或文字事实，确认是新记录再收下。',
    }
  }

  if (requiresReadingRepair(record)) {
    const lacksBook = !String(facts.book_name || '').trim()
    const minutes = Number(facts.reading_minutes)
    const lacksMinutes = !Number.isFinite(minutes) || minutes <= 0
    return {
      title: lacksBook && lacksMinutes
        ? '补上书名和阅读时长'
        : (lacksBook ? '还不知道是哪本书' : '还不知道读了多久'),
      description: '这更像一页阅读内容。补完后会归到对应书籍，并计入阅读趋势。',
    }
  }

  if (['ai_error', 'failed', 'extraction_failed'].includes(record?.status)) {
    return {
      title: '这张图还没识别成功',
      description: '可以重新识别，也可以直接选择它应该归到哪里。',
    }
  }

  if (missing.length) {
    const labels = missing.map(key => stagingFieldCopy[key] || '').filter(Boolean)
    if (labels.length) {
      return {
        title: labels.length === 1 ? `补上${labels[0]}` : `还差 ${labels.length} 项信息`,
        description: `补上${labels.join('、')}后，这条${context}就能继续处理。`,
      }
    }
  }

  if (['routing_failed', 'unrouted', 'unassigned'].includes(record?.status)) {
    return {
      title: '这张图想记到哪里？',
      description: '选一个最合适的分类，之后就能放进对应记录。',
    }
  }

  if (record?.status === 'schema_failed') {
    return {
      title: '还需要补一项信息',
      description: `看着原图补完整，这条${context}就能收下。`,
    }
  }

  const rawSummary = String(record?.summary || '').trim()
  const readableSummary = /缺少字段|置信度不足|schema_failed|missing_fields?/i.test(rawSummary)
    ? ''
    : rawSummary
  return {
    title: `请确认这条${context}`,
    description: readableSummary || '系统已经有初步判断，看一眼原图后收下即可。',
  }
}

function reviewTitle(record) {
  return reviewPresentation(record).title
}

function reviewDescription(record) {
  return reviewPresentation(record).description
}

function displayError(record) {
  if (missingFieldKeys(record).length) return ''
  const message = record?.lastErrorMessage
  if (!message) return ''
  return readableError(message)
}

function verdictPrimaryLabel(record) {
  if (isPossibleDuplicate(record)) return '确认为新记录'
  if (requiresReadingRepair(record)) return '补全阅读信息'
  const domain = suggestedDomain(record)
  return domain ? `收下 · ${domain.shortName}` : '收下这条记录'
}

function displayFactValue(raw, key) {
  if (raw == null || raw === '') return null
  if (typeof raw === 'boolean') return raw ? '是' : '否'
  const numeric = typeof raw === 'number' ? raw : (typeof raw === 'string' && /^-?\d+(\.\d+)?$/.test(raw.trim()) ? Number(raw) : null)
  if (numeric != null && Number.isFinite(numeric)) {
    if (key === 'amount' || key === 'snapshot_balance') return `¥${numeric.toFixed(2)}`
    if (['duration_minutes', 'sleep_minutes', 'reading_minutes'].includes(key)) return `${Math.round(numeric)} 分钟`
    if (key === 'sleep_hours') return `${numeric.toFixed(2)} 小时`
    if (key === 'distance_km') return `${numeric.toFixed(2)} km`
    if (['calories', 'calories_kcal', 'total_calorie_kcal'].includes(key)) return `${Math.round(numeric)} 千卡`
    if (['pages', 'pages_read'].includes(key)) return `${Math.round(numeric)} 页`
    return String(raw)
  }
  if (typeof raw === 'object') return null
  const text = String(raw).trim()
  if (!text) return null
  if (key === 'meal_type') {
    return { breakfast: '早餐', lunch: '午餐', dinner: '晚餐', snack: '加餐' }[text] || text
  }
  return text
}

function factRows(record) {
  const root = asPlainObject(record?.extracted)
  const nested = asPlainObject(root.payload_jsonb)
  const values = { ...nested, ...root }
  return stagingFactDefinitions
    .filter(([key]) => !hiddenStagingFactKeys.has(key))
    .map(([key, label]) => {
      const candidates = [key, ...(stagingFactAliases[key] || [])]
      const resolvedKey = candidates.find(candidate => values[candidate] != null && values[candidate] !== '')
      if (!resolvedKey) return null
      const value = displayFactValue(values[resolvedKey], resolvedKey)
      return value ? { key, label, value } : null
    })
    .filter(Boolean)
}

function readableError(message) {
  const text = String(message || '').trim()
  const lowered = text.toLowerCase()
  if (!text) return ''
  if (lowered.includes('row-level security') || lowered.includes('rls')) return '归档权限校验失败，请刷新后重试。'
  if (lowered.includes('token limit') || lowered.includes('exceeded model token')) return '识别内容超过模型处理上限，请重新识别。'
  if (lowered.includes('timed out') || lowered.includes('timeout')) return '识别服务本次未能及时完成，请稍后重试。'
  if (lowered.includes('unsupported model') || lowered.includes('all vision providers failed')) return '当前识别服务暂时不可用，请稍后重试。'
  return text.length > 120 ? `${text.slice(0, 120)}…` : text
}

function billOccurredLabel(bill) {
  const date = bill?.date || ''
  const time = bill?.time || ''
  return [date, time].filter(Boolean).join(' ') || '未识别'
}

function billMissingFields(bill) {
  const fields = []
  const amount = Number(bill?.amount)
  if (!Number.isFinite(amount) || amount <= 0) fields.push('金额')
  if (!bill?.platform || bill.platform === '?') fields.push('消费渠道')
  if (!bill?.cat || bill.cat === '?') fields.push('分类')
  if (!bill?.payment || bill.payment === '?') fields.push('支付方式')
  return fields
}

function billReviewTitle(bill) {
  const fields = billMissingFields(bill)
  if (!fields.length) return '请确认这笔账单'
  if (fields.length === 1) return `补上${fields[0]}`
  return `还差 ${fields.length} 项账单信息`
}

function billCategoryLabel(value) {
  if (!value || value === '?') return '分类未知'
  return {
    food: '餐饮', shopping: '购物', transport: '出行', entertainment: '娱乐',
    life: '生活', other: '其他',
  }[value] || value
}

function queueImageUrl(item) {
  return item?.record?.imageUrl || ''
}

function queueHasImageReference(item) {
  if (item?.source === 'bill') return Boolean(item.record?.image_path || item.record?.image_url)
  return Boolean(item?.record?.imagePath)
}

function queueTitle(item) {
  if (item?.source === 'bill') return billReviewTitle(item.record)
  return reviewTitle(item?.record)
}

function queueDescription(item) {
  if (item?.source !== 'bill') return reviewDescription(item?.record)
  const bill = item.record
  const merchant = String(bill?.name || '').trim() || '待补全账单'
  const amount = Number(bill?.amount || 0)
  const missing = billMissingFields(bill)
  if (missing.length) return `${merchant} · ¥${amount.toFixed(2)}；还需补充${missing.join('、')}`
  return `${merchant} · ¥${amount.toFixed(2)}；核对后即可进入财务统计`
}

function queueContextLabel(item) {
  if (item?.source === 'bill') return '支出 · 账单补全'
  return reviewContextLabel(item?.record)
}

function queueFactRows(item) {
  if (item?.source !== 'bill') return factRows(item?.record)
  const bill = item.record
  return [
    { key: 'amount', label: '金额', value: `¥${Number(bill?.amount || 0).toFixed(2)}` },
    { key: 'platform', label: '消费渠道', value: bill?.platform === '?' ? '待补充' : bill?.platform },
    { key: 'category', label: '消费分类', value: billCategoryLabel(bill?.cat) },
    { key: 'payment', label: '支付方式', value: bill?.payment === '?' ? '待补充' : bill?.payment },
  ]
}

function queueOccurredLabel(item) {
  if (item?.source === 'bill') return billOccurredLabel(item.record)
  return item?.occurredAt ? fmtShort(item.occurredAt) : '未识别'
}

function markQueueImageUnavailable(item) {
  if (!item?.record) return
  item.record.imageUrl = null
  item.record.imageLoadError = true
}

function markActiveQueueImageUnavailable(item) {
  activeVerdictImageReady.value = true
  markQueueImageUnavailable(item)
}

function setPendingScope(scope) {
  pendingScope.value = scope
  exitBatchMode()
}

function setPendingFilter(filter) {
  store.pendingFilter.value = filter
  exitBatchMode()
}

function exitBatchMode() {
  if (store.batchMode.value) store.toggleBatchMode()
  else store.clearSelection()
}

function scheduleTodayRefresh() {
  if (todayRefreshTimer !== null) window.clearTimeout(todayRefreshTimer)
  const now = new Date()
  const nextMidnight = new Date(now)
  nextMidnight.setHours(24, 0, 0, 0)
  const delay = Math.max(1_000, nextMidnight.getTime() - now.getTime() + 1_000)
  todayRefreshTimer = window.setTimeout(() => {
    todayKey.value = getLocalDateKey()
    scheduleTodayRefresh()
  }, delay)
}

function refreshTodayKey() {
  todayKey.value = getLocalDateKey()
  scheduleTodayRefresh()
}

function handleVisibilityChange() {
  if (document.visibilityState === 'visible') refreshTodayKey()
}

function handleQueueTap(item) {
  if (store.batchMode.value) {
    if (item.source === 'staging') store.toggleSelectStaging(item.sourceId)
    else store.showFlash('账单需要逐条补全')
    return
  }
  activeVerdictId.value = item.queueId
}

function closeVerdict() {
  activeVerdictId.value = null
}

function moveVerdict(offset) {
  const nextIndex = activeVerdictIndex.value + offset
  if (nextIndex < 0 || nextIndex >= filteredQueue.value.length) return
  activeVerdictId.value = filteredQueue.value[nextIndex].queueId
}

function suggestedDomain(record) {
  if (!record?.domainKey) return null
  return archiveDomains.value.find(domain => domain.id === record.domainKey) || null
}

function adjustFromVerdict(record) {
  const domainId = suggestedDomain(record)?.id
  if (!domainId) return
  let opened = false
  if (domainId === 'expense') opened = store.openExpenseStagingModal(record)
  else if (domainId === 'income') opened = store.openIncomeStagingModal(record)
  else opened = store.openUniversalRepairFromStaging(record, domainId)
  if (opened) {
    editingVerdictContext.value = {
      queueId: `staging:${record.id}`,
      previousIndex: activeVerdictIndex.value,
    }
    closeVerdict()
  }
}

function openBillFromVerdict(item) {
  if (item?.source !== 'bill') return
  editingVerdictContext.value = {
    queueId: item.queueId,
    previousIndex: activeVerdictIndex.value,
  }
  void store.openPendingModal(item.record, { returnToQueue: true })
  closeVerdict()
}

async function archiveFromVerdict(record, domainId) {
  if (verdictBusy.value) return
  if (domainId === 'reading' && requiresReadingRepair(record)) {
    const opened = store.openUniversalRepairFromStaging(record, domainId)
    if (opened) {
      editingVerdictContext.value = {
        queueId: `staging:${record.id}`,
        previousIndex: activeVerdictIndex.value,
      }
      closeVerdict()
    }
    return
  }
  const previousIndex = activeVerdictIndex.value
  verdictBusy.value = true
  try {
    await store.archiveStagingRecord(record, domainId)
    settleVerdictAfterAction(`staging:${record.id}`, previousIndex)
  } finally {
    verdictBusy.value = false
  }
}

async function retryFromVerdict(record) {
  if (verdictBusy.value) return
  const previousIndex = activeVerdictIndex.value
  verdictBusy.value = true
  try {
    const result = await store.retryStagingRecord(record)
    if (result?.status === 'accepted') settleVerdictAfterAction(`staging:${record.id}`, previousIndex)
  } finally {
    verdictBusy.value = false
  }
}

async function discardFromVerdict(record) {
  if (verdictBusy.value) return
  const previousIndex = activeVerdictIndex.value
  verdictBusy.value = true
  try {
    const result = await store.discardStagingRecord(record)
    if (result?.status === 'accepted') settleVerdictAfterAction(`staging:${record.id}`, previousIndex)
  } finally {
    verdictBusy.value = false
  }
}

async function confirmRepaymentFromVerdict(record) {
  if (verdictBusy.value) return
  const previousIndex = activeVerdictIndex.value
  verdictBusy.value = true
  try {
    await store.confirmStagingRepayment(record)
    settleVerdictAfterAction(`staging:${record.id}`, previousIndex)
  } finally {
    verdictBusy.value = false
  }
}

function settleVerdictAfterAction(queueId, previousIndex) {
  const sameItem = filteredQueue.value.find(item => item.queueId === queueId)
  if (sameItem) {
    activeVerdictId.value = sameItem.queueId
    return
  }
  const nextItem = pendingQueueItemAtPreviousIndex(filteredQueue.value, previousIndex)
  if (!nextItem) {
    closeVerdict()
    return
  }
  activeVerdictId.value = nextItem.queueId
}

function onStageTouchStart(event) {
  stageTouchStartX.value = event.changedTouches?.[0]?.clientX ?? null
}

function onStageTouchEnd(event) {
  if (stageTouchStartX.value == null) return
  const endX = event.changedTouches?.[0]?.clientX ?? stageTouchStartX.value
  const delta = endX - stageTouchStartX.value
  stageTouchStartX.value = null
  if (Math.abs(delta) < 48) return
  moveVerdict(delta < 0 ? 1 : -1)
}

function handleStageKeydown(event) {
  if (!activeVerdictId.value) return
  if (event.key === 'Escape') closeVerdict()
  else if (event.key === 'ArrowLeft') moveVerdict(-1)
  else if (event.key === 'ArrowRight') moveVerdict(1)
}

function warmImage(url, onReady) {
  if (!url) return
  const image = new Image()
  image.decoding = 'async'
  image.onload = () => onReady?.()
  image.src = url
  if (image.complete && image.naturalWidth > 0) onReady?.()
}

watch(activeVerdict, item => {
  const imageUrl = queueImageUrl(item)
  activeVerdictImageReady.value = !imageUrl
  if (!imageUrl) return
  const activeId = item.queueId
  warmImage(imageUrl, () => {
    if (activeVerdict.value?.queueId === activeId) activeVerdictImageReady.value = true
  })
  const index = activeVerdictIndex.value
  warmImage(queueImageUrl(filteredQueue.value[index - 1]))
  warmImage(queueImageUrl(filteredQueue.value[index + 1]))
}, { immediate: true })

watch(activeVerdictId, value => {
  document.body.classList.toggle('verdict-open', Boolean(value))
})

watch(filteredQueue, items => {
  if (activeVerdictId.value && !items.some(item => item.queueId === activeVerdictId.value)) closeVerdict()
})

watch(
  () => [
    store.expenseModal.open,
    store.incomeModal.open,
    store.universalModal.open,
    store.pendingModal.open,
  ],
  openStates => {
    const context = editingVerdictContext.value
    if (!context || openStates.some(Boolean)) return
    const sameItem = filteredQueue.value.find(item => item.queueId === context.queueId)
    const nextItem = sameItem || pendingQueueItemAtPreviousIndex(filteredQueue.value, context.previousIndex)
    editingVerdictContext.value = null
    activeVerdictId.value = nextItem?.queueId || null
  }
)

onMounted(() => {
  window.addEventListener('keydown', handleStageKeydown)
  document.addEventListener('visibilitychange', handleVisibilityChange)
  refreshTodayKey()
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleStageKeydown)
  document.removeEventListener('visibilitychange', handleVisibilityChange)
  if (todayRefreshTimer !== null) window.clearTimeout(todayRefreshTimer)
  todayRefreshTimer = null
  document.body.classList.remove('verdict-open')
})

function statusLabel(status) {
  const map = {
    bill_pending: '账单补全',
    ai_error: 'AI失败',
    routing_failed: '待分类',
    pending_review: '待确认',
    unrouted: '未路由',
    unassigned: '待分配',
    failed: '失败',
    extraction_failed: '需重试',
    schema_failed: '待补充',
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

function statusTone(status) {
  if (status === 'ai_error' || status === 'failed' || status === 'extraction_failed') return 'retry'
  if (status === 'routing_failed' || status === 'unrouted' || status === 'unassigned') return 'route'
  if (status === 'schema_failed') return 'repair'
  return 'review'
}

function typeLabel(type) {
  const map = { expense: '支出截图', income: '收入截图', uncertain: '未确定截图' }
  return map[type] || '待处理截图'
}

function typeGlyph(type) {
  const map = { expense: '支', income: '收', uncertain: '·' }
  return map[type] || '·'
}

function assuranceDots(confidence) {
  if ((confidence || 0) >= 0.85) return 3
  if ((confidence || 0) >= 0.6) return 2
  return 1
}

function assuranceLabel(confidence) {
  const dots = assuranceDots(confidence)
  return dots === 3 ? '较有把握' : (dots === 2 ? '不太确定' : '需要你看看')
}

function confidenceColor(confidence) {
  if ((confidence || 0) >= 0.7) return 'var(--success)'
  if ((confidence || 0) >= 0.4) return 'var(--warning)'
  return 'var(--danger)'
}

function domainLabel(key) {
  return getSystemDomainLabel(key, key || '未知域')
}

function fmtShort(value) {
  if (!value) return ''
  const s = String(value)
  const normalized = s.includes('T') ? s : (s.includes(' ') ? s.replace(' ', 'T') : `${s}T00:00:00`)
  const d = new Date(normalized)
  if (isNaN(d.getTime())) return s.slice(0, 16)
  return `${d.getMonth() + 1}月${d.getDate()}日 ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}
</script>
