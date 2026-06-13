<template>
  <div class="page active">
    <div class="page-title">设置</div>

    <div class="settings-profile">
      <div class="settings-avatar">设</div>
      <div class="settings-profile-info">
        <div class="settings-profile-name">{{ userEmail }}</div>
        <div class="settings-profile-plan">{{ planLabel }} · 已登录</div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">账户</div>
      <div class="settings-item" v-if="uploadToken" @click="copyToken">
        <div class="settings-item-icon success">钥</div>
        <div class="settings-item-content">
          <div class="settings-item-title">上传 Token（点击复制）</div>
          <div class="settings-item-sub" style="word-break:break-all;font-size:11px;">{{ uploadToken }}</div>
        </div>
      </div>
      <div class="settings-item" @click="handleLogout">
        <div class="settings-item-icon warn">退</div>
        <div class="settings-item-content">
          <div class="settings-item-title">退出登录</div>
          <div class="settings-item-sub">切换账号或退出当前会话</div>
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">数据管理</div>
      <div class="settings-item" @click="showExportModal = true">
        <div class="settings-item-icon success">出</div>
        <div class="settings-item-content">
          <div class="settings-item-title">数据导出</div>
          <div class="settings-item-sub">导出账单、收入与通用记录为 CSV 或 JSON</div>
        </div>
        <div class="settings-arrow">›</div>
      </div>
      <div class="settings-item" @click="store.showFlash('导入能力会在后续版本逐步接入')">
        <div class="settings-item-icon info">导</div>
        <div class="settings-item-content">
          <div class="settings-item-title">数据导入</div>
          <div class="settings-item-sub">CSV 与其他来源的历史数据导入</div>
        </div>
        <div class="settings-arrow">›</div>
      </div>
    </div>

    <!-- 数据导出弹窗 -->
    <div class="modal-overlay" :class="{ open: showExportModal }" @click.self="showExportModal = false">
      <div class="modal-sheet">
        <div class="sheet-drag-zone"><div class="sheet-handle"></div></div>
        <div class="sheet-header">
          <div class="sheet-title">数据导出</div>
          <div class="sheet-sub">选择要导出的数据范围和格式</div>
        </div>
        <div class="sheet-body">
          <div class="sel-section">
            <div class="sel-label">导出内容</div>
            <div class="sel-grid">
              <div
                v-for="opt in exportContentOptions"
                :key="opt.value"
                class="chip"
                :class="{ active: exportContent === opt.value }"
                @click="exportContent = opt.value"
              >
                {{ opt.label }}
              </div>
            </div>
          </div>
          <div class="sel-section">
            <div class="sel-label">时间范围</div>
            <div class="sel-grid">
              <div
                v-for="opt in exportRangeOptions"
                :key="opt.value"
                class="chip"
                :class="{ active: exportRange === opt.value }"
                @click="exportRange = opt.value"
              >
                {{ opt.label }}
              </div>
            </div>
          </div>
          <div class="sel-section">
            <div class="sel-label">导出格式</div>
            <div class="sel-grid">
              <div
                v-for="opt in exportFormatOptions"
                :key="opt.value"
                class="chip"
                :class="{ active: exportFormat === opt.value }"
                @click="exportFormat = opt.value"
              >
                {{ opt.label }}
              </div>
            </div>
          </div>
          <div class="sel-section" v-if="exportContent === 'universal'">
            <div class="sel-label">详情程度</div>
            <div class="export-detail-options">
              <div
                v-for="opt in exportDetailOptions"
                :key="opt.value"
                class="export-detail-card"
                :class="{ active: exportDetail === opt.value }"
                @click="exportDetail = opt.value"
              >
                <div class="export-detail-label">{{ opt.label }}</div>
                <div class="export-detail-desc">{{ opt.desc }}</div>
              </div>
            </div>
          </div>
          <div class="export-preview" v-if="exportPreviewCount !== null">
            <div class="export-preview-icon">📊</div>
            <div class="export-preview-text">
              预计导出 <strong>{{ exportPreviewCount }}</strong> 条记录
            </div>
          </div>
        </div>
        <div class="sheet-footer">
          <button class="confirm-btn" :disabled="exporting" @click="handleExport">
            {{ exporting ? '导出中...' : '开始导出' }}
          </button>
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">AI 识别引擎</div>
      <div class="settings-item-sub" style="padding:0 16px 8px;color:#6b7280;font-size:12px;">
        选择截图或拍照识别使用的视觉模型，设置后立即生效。
      </div>
      <div
        v-for="opt in visionOptions"
        :key="opt.value"
        class="settings-item"
        @click="updateVisionPrimary(opt.value)"
      >
        <div class="settings-item-icon" :class="opt.toneClass">{{ opt.iconText }}</div>
        <div class="settings-item-content">
          <div class="settings-item-title">{{ opt.label }}</div>
          <div class="settings-item-sub">{{ opt.desc }}</div>
        </div>
        <div
          class="settings-arrow"
          :style="{ color: visionPrimary === opt.value ? '#10b981' : '#d1d5db', fontSize: '20px', fontWeight: 'bold' }"
        >
          {{ visionPrimary === opt.value ? '✓' : '○' }}
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">AI 陪伴弹窗</div>
      <div class="companion-compact">
        <div class="companion-toggle-grid">
          <div class="companion-toggle-row">
            <div>
              <div class="settings-item-title">陪伴文案</div>
              <div class="settings-item-sub">通知第一句话</div>
            </div>
            <div class="settings-toggle" :class="{ active: store.settingsState.companionEnabled }" @click.stop="store.toggleSetting('companionEnabled')">
              <div class="toggle-knob"></div>
            </div>
          </div>
          <div class="companion-toggle-row">
            <div>
              <div class="settings-item-title">长期记忆</div>
              <div class="settings-item-sub">引用历史模式</div>
            </div>
            <div class="settings-toggle" :class="{ active: store.settingsState.companionMemoryEnabled }" @click.stop="store.toggleSetting('companionMemoryEnabled')">
              <div class="toggle-knob"></div>
            </div>
          </div>
        </div>

        <div class="companion-control">
          <div class="companion-control-head">
            <span>语气</span>
            <span>{{ companionPersonaOptions.find(o => o.value === companionPersona)?.desc }}</span>
          </div>
          <div class="companion-chip-row">
            <button
              v-for="opt in companionPersonaOptions"
              :key="opt.value"
              type="button"
              class="companion-chip"
              :class="{ active: companionPersona === opt.value }"
              @click="updateCompanionPersona(opt.value)"
            >
              {{ opt.label }}
            </button>
          </div>
        </div>

        <div class="companion-control">
          <div class="companion-control-head">
            <span>记忆强度</span>
            <span>{{ companionMemoryStrengthOptions.find(o => o.value === companionMemoryStrength)?.desc }}</span>
          </div>
          <div class="companion-chip-row compact">
            <button
              v-for="opt in companionMemoryStrengthOptions"
              :key="opt.value"
              type="button"
              class="companion-chip"
              :class="{ active: companionMemoryStrength === opt.value }"
              @click="updateCompanionMemoryStrength(opt.value)"
            >
              {{ opt.label.replace('记忆', '') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">AI 联动分析</div>
      <div class="settings-item-sub" style="padding:0 16px 8px;color:#6b7280;font-size:12px;">
        仅影响“联动分析 / AI 解读”模块，不影响截图识别。可以按速度或思考深度切换。
      </div>
      <div
        v-for="opt in insightModelOptions"
        :key="opt.value"
        class="settings-item"
        @click="updateAiInsightProvider(opt.value)"
      >
        <div class="settings-item-icon" :class="opt.toneClass">{{ opt.iconText }}</div>
        <div class="settings-item-content">
          <div class="settings-item-title">{{ opt.label }}</div>
          <div class="settings-item-sub">{{ opt.desc }}</div>
        </div>
        <div
          class="settings-arrow"
          :style="{ color: aiInsightProvider === opt.value ? '#10b981' : '#d1d5db', fontSize: '20px', fontWeight: 'bold' }"
        >
          {{ aiInsightProvider === opt.value ? '✓' : '○' }}
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">隐私与留存</div>
      <div class="settings-item">
        <div class="settings-item-icon warn">志</div>
        <div class="settings-item-content">
          <div class="settings-item-title">AI 日志记录</div>
          <div class="settings-item-sub">保留识别摘要，便于排查问题与优化 Prompt</div>
        </div>
        <div class="settings-toggle" :class="{ active: store.settingsState.aiLogsEnabled }" @click.stop="store.toggleSetting('aiLogsEnabled')">
          <div class="toggle-knob"></div>
        </div>
      </div>
      <div class="settings-item">
        <div class="settings-item-icon info">图</div>
        <div class="settings-item-content">
          <div class="settings-item-title">原图保留</div>
          <div class="settings-item-sub">默认保留截图原图，便于回溯与重新识别</div>
        </div>
        <div class="settings-toggle" :class="{ active: store.settingsState.keepSourceImages }" @click.stop="store.toggleSetting('keepSourceImages')">
          <div class="toggle-knob"></div>
        </div>
      </div>
      <div class="settings-item" @click="store.showFlash('当前使用 Supabase 新加坡节点')">
        <div class="settings-item-icon primary">云</div>
        <div class="settings-item-content">
          <div class="settings-item-title">数据存储</div>
          <div class="settings-item-sub">Supabase 新加坡节点 · 后续可按商业化规划迁移</div>
        </div>
        <div class="settings-arrow">›</div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">关于平台</div>
      <div class="settings-item">
        <div class="settings-item-icon primary">版</div>
        <div class="settings-item-content">
          <div class="settings-item-title">当前版本</div>
          <div class="settings-item-sub">V0.2 平台框架阶段</div>
        </div>
      </div>
      <div class="settings-item" @click="store.showFlash('商业化权益页稍后接入')">
        <div class="settings-item-icon warn">升</div>
        <div class="settings-item-content">
          <div class="settings-item-title">升级到 Pro</div>
          <div class="settings-item-sub">查看平台化后的高级分析与模板能力</div>
        </div>
        <div class="settings-arrow">›</div>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { ref, inject, onMounted, onUnmounted, watch } from 'vue'
import { sb } from '../../lib/supabase'

const store = inject('store')
const uploadToken = ref('')
const visionPrimary = ref('auto')
const aiInsightProvider = ref('auto')
const companionPersona = ref('observer')
const companionMemoryStrength = ref('bold')

// ── 数据导出 ──
const showExportModal = ref(false)
const exporting = ref(false)
const exportContent = ref('expense')
const exportRange = ref('this_month')
const exportFormat = ref('csv')
const exportDetail = ref('summary')
const exportPreviewCount = ref(null)
let exportPreviewTimer = null
let exportPreviewSeq = 0

const exportContentOptions = [
  { value: 'expense', label: '支出记录' },
  { value: 'income', label: '收入记录' },
  { value: 'all_finance', label: '全部财务' },
  { value: 'universal', label: '通用记录' },
]

const exportRangeOptions = [
  { value: 'this_month', label: '本月' },
  { value: 'last_month', label: '上月' },
  { value: 'last_3_months', label: '近 3 月' },
  { value: 'all', label: '全部' },
]

const exportFormatOptions = [
  { value: 'csv', label: 'CSV' },
  { value: 'json', label: 'JSON' },
]

const exportDetailOptions = [
  { value: 'summary', label: '简洁模式', desc: '提取关键字段，方便阅读' },
  { value: 'full', label: '详情模式', desc: '完整 payload，适合 AI 分析' },
]

function getDateRange(range) {
  const now = new Date()
  const y = now.getFullYear()
  const m = now.getMonth()
  let start, end

  switch (range) {
    case 'this_month':
      start = new Date(y, m, 1)
      end = new Date(y, m + 1, 0)
      break
    case 'last_month':
      start = new Date(y, m - 1, 1)
      end = new Date(y, m, 0)
      break
    case 'last_3_months':
      start = new Date(y, m - 2, 1)
      end = new Date(y, m + 1, 0)
      break
    case 'all':
    default:
      start = new Date(2020, 0, 1)
      end = new Date(y, m + 1, 0)
  }

  return {
    start: start.toISOString().split('T')[0],
    end: end.toISOString().split('T')[0],
  }
}

async function fetchExportData() {
  const { start, end } = getDateRange(exportRange.value)
  const content = exportContent.value

  if (content === 'expense' || content === 'all_finance') {
    const { data: expenses } = await sb.from('transactions')
      .select('*')
      .eq('type', 'expense')
      .eq('status', 'done')
      .gte('transaction_date', start)
      .lte('transaction_date', end)
      .order('transaction_date', { ascending: false })

    if (content === 'expense') return expenses || []

    const { data: incomes } = await sb.from('income_records')
      .select('*')
      .gte('income_date', start)
      .lte('income_date', end)
      .order('income_date', { ascending: false })

    return { expenses: expenses || [], incomes: incomes || [] }
  }

  if (content === 'income') {
    const { data } = await sb.from('income_records')
      .select('*')
      .gte('income_date', start)
      .lte('income_date', end)
      .order('income_date', { ascending: false })
    return data || []
  }

  if (content === 'universal') {
    const { data } = await sb.from('data_records')
      .select('*')
      .gte('occurred_at', start + 'T00:00:00')
      .lte('occurred_at', end + 'T23:59:59')
      .order('occurred_at', { ascending: false })
    return data || []
  }

  return []
}

function formatUniversalPayload(row) {
  const p = row.payload_jsonb || {}
  const dk = row.domain_key

  if (dk === 'food') {
    const dishes = (p.dishes || []).map(d => d.name).join('+')
    const cal = p.total_calorie_kcal ? `${p.total_calorie_kcal}千卡` : ''
    const meal = p.meal_type === 'lunch' ? '午餐' : p.meal_type === 'dinner' ? '晚餐' : p.meal_type === 'breakfast' ? '早餐' : p.meal_type || ''
    return [meal, dishes, cal].filter(Boolean).join('·')
  }

  if (dk === 'sleep') {
    const h = p.sleep_hours ? `${p.sleep_hours}h` : ''
    const score = p.quality_score ? `评分${p.quality_score}` : ''
    const level = p.quality_level || ''
    return [h, score, level].filter(Boolean).join('·')
  }

  if (dk === 'sport') {
    const dur = p.duration_minutes ? `${p.duration_minutes}分钟` : ''
    const dist = p.distance_km ? `${p.distance_km}km` : ''
    const cal = p.calories ? `${p.calories}千卡` : ''
    const type = p.sport_type || ''
    return [type, dur, dist, cal].filter(Boolean).join('·')
  }

  if (dk === 'reading') {
    const dur = p.reading_minutes ? `${p.reading_minutes}分钟` : ''
    const pages = p.pages ? `${p.pages}页` : ''
    const book = p.book_name || ''
    return [book, dur, pages].filter(Boolean).join('·')
  }

  // 通用兜底：提取非嵌套的简短字段
  return Object.entries(p)
    .filter(([_, v]) => typeof v !== 'object' && v != null)
    .map(([k, v]) => `${k}:${v}`)
    .join('·')
}

function toCsv(rows, columns) {
  const header = columns.map(c => c.label).join(',')
  const body = rows.map(row =>
    columns.map(c => {
      let val = row[c.key]
      if (val == null) return ''
      if (typeof val === 'object') val = JSON.stringify(val)
      const str = String(val).replace(/"/g, '""')
      return str.includes(',') || str.includes('"') || str.includes('\n')
        ? `"${str}"`
        : str
    }).join(',')
  ).join('\n')
  return '﻿' + header + '\n' + body
}

function download(content, filename, type) {
  const blob = new Blob([content], { type })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

function formatDate(d) {
  return new Date(d).toISOString().split('T')[0]
}

const expenseColumns = [
  { key: 'transaction_date', label: '日期' },
  { key: 'transaction_time', label: '时间' },
  { key: 'amount', label: '金额' },
  { key: 'merchant_name', label: '商家' },
  { key: 'category', label: '分类' },
  { key: 'platform', label: '平台' },
  { key: 'payment_method', label: '支付方式' },
  { key: 'note', label: '备注' },
]

const incomeColumns = [
  { key: 'income_date', label: '日期' },
  { key: 'amount', label: '金额' },
  { key: 'category', label: '分类' },
  { key: 'source_name', label: '来源' },
  { key: 'note', label: '备注' },
]

const universalColumns = [
  { key: 'occurred_at', label: '时间' },
  { key: 'domain_key', label: '数据域' },
  { key: 'title', label: '标题' },
  { key: 'summary', label: '摘要' },
  { key: 'detail', label: '关键数据' },
]

function serializeData(data, format) {
  const ts = formatDate(new Date())

  if (exportContent.value === 'all_finance' && format === 'csv') {
    const expCsv = toCsv(data.expenses, expenseColumns)
    const incCsv = toCsv(data.incomes, incomeColumns)
    return { expenses: expCsv, incomes: incCsv }
  }

  let columns
  let rows = data

  switch (exportContent.value) {
    case 'expense':
      columns = expenseColumns
      break
    case 'income':
      columns = incomeColumns
      break
    case 'universal':
      if (exportDetail.value === 'summary') {
        columns = universalColumns
        rows = data.map(row => ({
          ...row,
          occurred_at: row.occurred_at ? new Date(row.occurred_at).toLocaleString('zh-CN') : '',
          detail: formatUniversalPayload(row),
        }))
      } else {
        // 详情模式：保留完整 payload
        columns = [
          { key: 'occurred_at', label: '时间' },
          { key: 'domain_key', label: '数据域' },
          { key: 'title', label: '标题' },
          { key: 'summary', label: '摘要' },
          { key: 'payload_jsonb', label: '完整数据' },
        ]
        rows = data.map(row => ({
          ...row,
          occurred_at: row.occurred_at ? new Date(row.occurred_at).toLocaleString('zh-CN') : '',
        }))
      }
      break
    default:
      columns = expenseColumns
  }

  if (format === 'csv') {
    return toCsv(rows, columns)
  }

  return JSON.stringify(rows, null, 2)
}

function getFilename(label, format) {
  const ts = formatDate(new Date())
  return `snapcount_${label}_${ts}.${format}`
}

async function handleExport() {
  exporting.value = true
  try {
    const data = await fetchExportData()
    const format = exportFormat.value
    const contentLabel = exportContentOptions.find(o => o.value === exportContent.value)?.label || 'data'

    if (exportContent.value === 'all_finance' && format === 'csv') {
      const serialized = serializeData(data, format)
      download(serialized.expenses, getFilename('支出', 'csv'), 'text/csv;charset=utf-8')
      setTimeout(() => {
        download(serialized.incomes, getFilename('收入', 'csv'), 'text/csv;charset=utf-8')
      }, 500)
    } else {
      const serialized = serializeData(data, format)
      const mime = format === 'csv' ? 'text/csv;charset=utf-8' : 'application/json'
      download(serialized, getFilename(contentLabel, format), mime)
    }

    store.showFlash('✓ 导出成功')
    showExportModal.value = false
  } catch (e) {
    store.showFlash('⚠️ 导出失败：' + e.message)
  } finally {
    exporting.value = false
  }
}

function scheduleExportPreview() {
  exportPreviewCount.value = null
  exportPreviewSeq += 1
  const seq = exportPreviewSeq
  if (exportPreviewTimer) clearTimeout(exportPreviewTimer)
  exportPreviewTimer = setTimeout(async () => {
    try {
      const data = await fetchExportData()
      if (seq !== exportPreviewSeq) return
      if (Array.isArray(data)) {
        exportPreviewCount.value = data.length
      } else {
        exportPreviewCount.value = (data.expenses?.length || 0) + (data.incomes?.length || 0)
      }
    } catch {
      if (seq === exportPreviewSeq) exportPreviewCount.value = null
    }
  }, 180)
}

watch([exportContent, exportRange], scheduleExportPreview)

const visionOptions = [
  {
    value: 'auto',
    label: '自动（推荐）',
    desc: '平台自动调度，速度与稳定性更均衡，异常时会自动降级。',
    iconText: 'A',
    toneClass: 'primary',
  },
  {
    value: 'qwen',
    label: '阿里云通义千问 Vision',
    desc: '当前偏快的视觉方案，适合大多数截图识别。',
    iconText: 'Q',
    toneClass: 'success',
  },
  {
    value: 'moonshot',
    label: 'Moonshot Kimi',
    desc: '财务场景验证较充分，速度中等。',
    iconText: 'K',
    toneClass: 'info',
  },
  {
    value: 'mimo',
    label: '小米 MiMo（实验）',
    desc: '多模态试验中，速度较慢，准确率待继续验证。',
    iconText: 'M',
    toneClass: 'warn',
  },
  {
    value: 'relay',
    label: '自建中转站 Vision',
    desc: '走自建 OpenAI 兼容网关，适合对比速度与识图效果。',
    iconText: 'R',
    toneClass: 'info',
  },
]

const insightModelOptions = [
  {
    value: 'auto',
    label: '自动（推荐）',
    desc: '跟随后端默认分析模型，速度通常更稳。',
    iconText: 'A',
    toneClass: 'primary',
  },
  {
    value: 'moonshot',
    label: 'Moonshot 分析',
    desc: '当前稳定方案，整体响应通常更快。',
    iconText: 'K',
    toneClass: 'success',
  },
  {
    value: 'relay',
    label: '自建中转站分析',
    desc: '使用自建 OpenAI 兼容模型，适合追求更深一层的分析。',
    iconText: 'R',
    toneClass: 'warn',
  },
]

const companionPersonaOptions = [
  {
    value: 'observer',
    label: '旁观者',
    desc: '冷静看见细节，事实为主，偶尔轻调侃。',
    iconText: '观',
    toneClass: 'primary',
  },
  {
    value: 'warm',
    label: '老朋友',
    desc: '更会接住辛苦信号，关心但不说教。',
    iconText: '暖',
    toneClass: 'success',
  },
  {
    value: 'sharp',
    label: '损友',
    desc: '基于数据轻轻扎心，只损行为不攻击人。',
    iconText: '损',
    toneClass: 'warn',
  },
  {
    value: 'minimal',
    label: '极简',
    desc: '有强信号才说一句，没话时保持沉默。',
    iconText: '简',
    toneClass: 'info',
  },
]

const companionMemoryStrengthOptions = [
  {
    value: 'light',
    label: '轻量',
    desc: '偶尔引用历史，更多围绕当前截图。',
    iconText: '轻',
    toneClass: 'info',
  },
  {
    value: 'balanced',
    label: '自然',
    desc: '在当前记录和历史模式之间保持平衡。',
    iconText: '衡',
    toneClass: 'primary',
  },
  {
    value: 'bold',
    label: '大胆',
    desc: '有证据时优先写出连续性和个人感。',
    iconText: '敢',
    toneClass: 'warn',
  },
]

onMounted(async () => {
  if (store.currentUserId.value) {
    await store.loadUserSettings()
    const { data: cfg } = await sb.from('user_configs')
      .select('upload_token, plan, vision_primary, ai_insight_provider, companion_persona, companion_memory_strength')
      .eq('user_id', store.currentUserId.value)
      .maybeSingle()
    if (cfg) {
      uploadToken.value = cfg.upload_token || ''
      visionPrimary.value = cfg.vision_primary || 'auto'
      aiInsightProvider.value = cfg.ai_insight_provider || 'auto'
      companionPersona.value = cfg.companion_persona || 'observer'
      companionMemoryStrength.value = cfg.companion_memory_strength || 'bold'
    }
  }
})

onUnmounted(() => {
  if (exportPreviewTimer) clearTimeout(exportPreviewTimer)
})

async function updateVisionPrimary(value) {
  if (visionPrimary.value === value) return
  if (!store.currentUserId.value) {
    store.showFlash('请先登录')
    return
  }
  const prev = visionPrimary.value
  visionPrimary.value = value
  const { error } = await sb.from('user_configs')
    .update({ vision_primary: value, updated_at: new Date().toISOString() })
    .eq('user_id', store.currentUserId.value)
  if (error) {
    visionPrimary.value = prev
    store.showFlash('⚠️ 切换失败：' + error.message)
    return
  }
  const opt = visionOptions.find(o => o.value === value)
  store.showFlash(`✓ 已切换到「${opt?.label || value}」`)
}

async function updateAiInsightProvider(value) {
  if (aiInsightProvider.value === value) return
  if (!store.currentUserId.value) {
    store.showFlash('请先登录')
    return
  }
  const prev = aiInsightProvider.value
  aiInsightProvider.value = value
  const { error } = await sb.from('user_configs')
    .update({ ai_insight_provider: value, updated_at: new Date().toISOString() })
    .eq('user_id', store.currentUserId.value)
  if (error) {
    aiInsightProvider.value = prev
    store.showFlash('⚠️ 切换失败：' + error.message)
    return
  }
  const opt = insightModelOptions.find(o => o.value === value)
  store.showFlash(`✓ AI 分析已切换到「${opt?.label || value}」`)
}

async function updateCompanionPersona(value) {
  if (companionPersona.value === value) return
  if (!store.currentUserId.value) {
    store.showFlash('请先登录')
    return
  }
  const prev = companionPersona.value
  companionPersona.value = value
  const { error } = await sb.from('user_configs')
    .update({ companion_persona: value, updated_at: new Date().toISOString() })
    .eq('user_id', store.currentUserId.value)
  if (error) {
    companionPersona.value = prev
    store.showFlash('⚠️ 切换失败：' + error.message)
    return
  }
  const opt = companionPersonaOptions.find(o => o.value === value)
  store.showFlash(`✓ 陪伴语气已切换到「${opt?.label || value}」`)
}

async function updateCompanionMemoryStrength(value) {
  if (companionMemoryStrength.value === value) return
  if (!store.currentUserId.value) {
    store.showFlash('请先登录')
    return
  }
  const prev = companionMemoryStrength.value
  companionMemoryStrength.value = value
  const { error } = await sb.from('user_configs')
    .update({ companion_memory_strength: value, updated_at: new Date().toISOString() })
    .eq('user_id', store.currentUserId.value)
  if (error) {
    companionMemoryStrength.value = prev
    store.showFlash('⚠️ 切换失败：' + error.message)
    return
  }
  const opt = companionMemoryStrengthOptions.find(o => o.value === value)
  store.showFlash(`✓ 记忆强度已切换到「${opt?.label || value}」`)
}

const userEmail = ref(store.currentUserEmail.value || '内测用户')
const planLabel = ref('种子用户')

function copyToken() {
  if (!uploadToken.value) return
  navigator.clipboard?.writeText(uploadToken.value)
    .then(() => store.showFlash('✓ Token 已复制到剪贴板'))
    .catch(() => store.showFlash('⚠️ 复制失败，请手动选择'))
}

async function handleLogout() {
  await sb.auth.signOut()
  store.showFlash('✓ 已退出登录')
}
</script>
