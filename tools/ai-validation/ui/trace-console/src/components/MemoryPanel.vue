<template>
  <!-- 遮罩 -->
  <div class="memory-mask" v-if="open" @click="$emit('close')"></div>

  <!-- 面板 -->
  <div class="memory-panel" :class="{ open: open }">
    <div class="panel-header">
      <span class="panel-title">🧠 AI 记忆上下文</span>
      <span class="panel-subtitle" v-if="accountLabel">{{ accountLabel }}</span>
      <button class="refresh-btn" @click="loadMemory" :disabled="loading" title="刷新记忆数据">
        {{ loading ? '...' : '🔄' }}
      </button>
      <button class="close-btn" @click="$emit('close')">关闭</button>
    </div>

    <div class="panel-body">
      <!-- 加载中 -->
      <div v-if="loading" class="loading-state">
        <span>加载记忆数据...</span>
      </div>

      <!-- 错误 -->
      <div v-else-if="error" class="error-state">
        <div class="error-icon">⚠️</div>
        <div>{{ error }}</div>
      </div>

      <!-- 空数据 -->
      <div v-else-if="!memoryData" class="empty-state">
        <span>暂无记忆数据</span>
      </div>

      <!-- 正常展示 -->
      <template v-else>
        <!-- ═══ 伴随设置 ═══ -->
        <section class="mem-section" v-if="memoryData.settings">
          <div class="section-title">伴随设置</div>
          <div class="settings-grid">
            <div class="setting-item">
              <span class="setting-label">状态</span>
              <span class="setting-value" :class="{ on: memoryData.settings.enabled }">
                {{ memoryData.settings.enabled ? '已启用' : '已关闭' }}
              </span>
            </div>
            <div class="setting-item">
              <span class="setting-label">人格</span>
              <span class="setting-value">{{ personaLabel }}</span>
            </div>
            <div class="setting-item">
              <span class="setting-label">记忆强度</span>
              <span class="setting-value">{{ memoryData.settings.memory_strength || '-' }}</span>
            </div>
            <div class="setting-item">
              <span class="setting-label">表达风格</span>
              <span class="setting-value">{{ memoryData.settings.expression_style || '-' }}</span>
            </div>
            <div class="setting-item" v-if="memoryData.settings.memory_enabled != null">
              <span class="setting-label">记忆功能</span>
              <span class="setting-value" :class="{ on: memoryData.settings.memory_enabled }">
                {{ memoryData.settings.memory_enabled ? '开启' : '关闭' }}
              </span>
            </div>
            <div class="setting-item" v-if="memoryData.settings.custom_note">
              <span class="setting-label">自定义备注</span>
              <span class="setting-value">{{ memoryData.settings.custom_note }}</span>
            </div>
          </div>
        </section>

        <!-- ═══ 短期统计 ═══ -->
        <section class="mem-section" v-if="memoryData.short_term">
          <div class="section-title">短期统计（近 7 天）</div>

          <!-- 消费概况 -->
          <div class="stat-row" v-if="memoryData.short_term.week_spend">
            <div class="stat-card">
              <div class="stat-card-label">本周支出</div>
              <div class="stat-card-value">{{ formatMoney(memoryData.short_term.week_spend.total) }}</div>
              <div class="stat-card-sub">{{ memoryData.short_term.week_spend.count }} 笔 · 外卖 {{ memoryData.short_term.week_spend.food_count }} 次</div>
            </div>
            <div class="stat-card" v-if="memoryData.short_term.today_spend">
              <div class="stat-card-label">今日支出</div>
              <div class="stat-card-value">{{ formatMoney(memoryData.short_term.today_spend.total) }}</div>
              <div class="stat-card-sub">{{ memoryData.short_term.today_spend.count }} 笔</div>
            </div>
            <div class="stat-card" v-if="memoryData.short_term.last_sleep">
              <div class="stat-card-label">上次睡眠</div>
              <div class="stat-card-value">{{ memoryData.short_term.last_sleep.hours }}h</div>
              <div class="stat-card-sub">{{ memoryData.short_term.last_sleep.date }} · 评分 {{ memoryData.short_term.last_sleep.score }}</div>
            </div>
          </div>

          <!-- 健康概况 -->
          <div class="stat-row" v-if="memoryData.short_term.food_this_week || memoryData.short_term.sport_this_week">
            <div class="stat-card" v-if="memoryData.short_term.food_this_week">
              <div class="stat-card-label">本周饮食记录</div>
              <div class="stat-card-value">{{ memoryData.short_term.food_this_week.count }} 次</div>
              <div class="stat-card-sub" v-if="memoryData.short_term.food_this_week.calories">
                约 {{ memoryData.short_term.food_this_week.calories }} 卡
              </div>
            </div>
            <div class="stat-card" v-if="memoryData.short_term.sport_this_week">
              <div class="stat-card-label">本周运动</div>
              <div class="stat-card-value">{{ memoryData.short_term.sport_this_week.count }} 次</div>
              <div class="stat-card-sub">
                {{ memoryData.short_term.sport_this_week.minutes }} 分钟
                <span v-if="memoryData.short_term.sport_this_week.last_date">
                  · 最近 {{ memoryData.short_term.sport_this_week.last_date.slice(5) }}
                </span>
              </div>
            </div>
          </div>

          <!-- 高频商户 -->
          <div class="sub-section" v-if="memoryData.short_term.frequent_merchants_30d?.length">
            <div class="sub-title">近 30 天高频商户</div>
            <div class="merchant-list">
              <div
                v-for="(m, idx) in memoryData.short_term.frequent_merchants_30d"
                :key="idx"
                class="merchant-item"
              >
                <span class="merchant-rank">{{ idx + 1 }}</span>
                <span class="merchant-name">{{ m.name }}</span>
                <span class="merchant-times">{{ m.times }} 次</span>
                <span class="merchant-total">{{ formatMoney(m.total) }}</span>
              </div>
            </div>
          </div>
        </section>

        <!-- ═══ 最近伴随文案 ═══ -->
        <section class="mem-section" v-if="memoryData.short_term?.recent_companions?.length">
          <div class="section-title">最近伴随文案</div>
          <div class="companion-list">
            <div
              v-for="(c, idx) in memoryData.short_term.recent_companions"
              :key="idx"
              class="companion-item"
            >
              <span class="companion-date">{{ c.d?.slice(5) || '-' }}</span>
              <span class="companion-text">{{ c.t }}</span>
            </div>
          </div>
        </section>

        <!-- ═══ 长期记忆 ═══ -->
        <section class="mem-section" v-if="memoryData.long_term?.length">
          <div class="section-title">长期记忆（{{ memoryData.long_term.length }} 条）</div>
          <div class="memory-list">
            <div
              v-for="(m, idx) in memoryData.long_term"
              :key="idx"
              class="memory-item"
            >
              <div class="memory-header">
                <span class="memory-type">{{ typeLabel(m.type) }}</span>
                <span class="memory-weight">权重 {{ m.weight }}</span>
                <span class="memory-confidence" v-if="m.confidence != null">
                  置信度 {{ Math.round(m.confidence * 100) }}%
                </span>
                <span class="memory-last-seen" v-if="m.last_seen_at">
                  {{ formatDate(m.last_seen_at) }}
                </span>
              </div>
              <div class="memory-content">{{ m.content }}</div>
              <details class="memory-evidence" v-if="m.evidence">
                <summary>证据</summary>
                <pre class="evidence-json">{{ formatJson(m.evidence) }}</pre>
              </details>
            </div>
          </div>
        </section>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, computed } from 'vue'
import { fetchRemoteMemory } from '../lib/api.js'

const props = defineProps({
  open: { type: Boolean, default: false },
  accountKey: { type: String, default: '' },
  accountLabel: { type: String, default: '' },
})

const loading = ref(false)
const error = ref('')
const memoryData = ref(null)

const personaMap = {
  observer: '观察者',
  sharp: '犀利',
  warm: '温暖',
  humorous: '幽默',
}

const personaLabel = computed(() => {
  const p = memoryData.value?.settings?.persona
  return personaMap[p] || p || '-'
})

// 每次打开都强制重新加载（不依赖 accountKey 变化）
watch(() => props.open, async (isOpen) => {
  if (isOpen && props.accountKey) {
    await loadMemory()
  }
})

// 面板已打开时切账号也重新加载
watch(() => props.accountKey, async (key) => {
  if (props.open && key) {
    await loadMemory()
  }
})

async function loadMemory() {
  loading.value = true
  error.value = ''
  memoryData.value = null
  const { data, error: err } = await fetchRemoteMemory(props.accountKey)
  loading.value = false
  if (err) {
    error.value = err
    return
  }
  memoryData.value = data
}

function formatMoney(val) {
  if (val == null) return '-'
  return `¥${Number(val).toFixed(2)}`
}

function formatDate(dt) {
  if (!dt) return '-'
  return dt.slice(0, 10)
}

function typeLabel(type) {
  const map = {
    merchant_pattern: '商户偏好',
    category_pattern: '分类偏好',
    behavior_pattern: '行为模式',
    lifestyle_pattern: '生活习惯',
  }
  return map[type] || type || '未知'
}

function formatJson(obj) {
  if (!obj) return 'null'
  try { return JSON.stringify(obj, null, 2) } catch { return String(obj) }
}
</script>

<style scoped>
.memory-mask {
  position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 39;
}
.memory-panel {
  position: fixed; top: 50%; left: 50%;
  transform: translate(-50%, -50%) scale(0.95); opacity: 0; pointer-events: none;
  z-index: 40; width: 600px; max-height: 85vh;
  background: var(--bg-panel); border: 1px solid var(--border);
  border-radius: var(--radius-xl); display: flex; flex-direction: column; overflow: hidden;
  transition: all 0.2s;
}
.memory-panel.open { transform: translate(-50%, -50%) scale(1); opacity: 1; pointer-events: auto; }

.panel-header {
  display: flex; align-items: center; gap: var(--space-sm);
  padding: var(--space-md) var(--space-lg); border-bottom: 1px solid var(--border); flex-shrink: 0;
}
.panel-title { font-size: 14px; font-weight: 700; }
.panel-subtitle {
  font-size: 11px; color: var(--text-muted);
  background: var(--bg-hover); padding: 2px 8px; border-radius: var(--radius-sm);
}
.close-btn {
  margin-left: auto;
  font-size: 12px; padding: 3px 10px; border-radius: var(--radius-sm);
  background: var(--bg-hover); color: var(--text-secondary);
  border: 1px solid var(--border); cursor: pointer; font-family: var(--font-sans);
}
.refresh-btn {
  font-size: 14px; padding: 3px 8px; border-radius: var(--radius-sm);
  background: var(--bg-hover); border: 1px solid var(--border);
  cursor: pointer; line-height: 1; transition: all 0.12s;
}
.refresh-btn:hover:not(:disabled) { background: var(--bg-active); }
.refresh-btn:disabled { opacity: 0.5; cursor: not-allowed; }

.panel-body { padding: var(--space-lg); overflow-y: auto; flex: 1; }

.loading-state, .error-state, .empty-state {
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  padding: var(--space-xl); color: var(--text-muted); font-size: 13px; gap: var(--space-sm);
}
.error-state .error-icon { font-size: 28px; }

/* Section */
.mem-section { margin-bottom: var(--space-lg); }
.mem-section:last-child { margin-bottom: 0; }
.section-title {
  font-size: 12px; font-weight: 700; color: #a78bfa;
  margin-bottom: var(--space-sm); padding-bottom: 4px;
  border-bottom: 1px solid rgba(139, 92, 246, 0.15);
}

/* Settings */
.settings-grid {
  display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-xs);
}
.setting-item {
  display: flex; flex-direction: column; gap: 2px;
  background: var(--bg-hover); padding: var(--space-xs) var(--space-sm);
  border-radius: var(--radius-sm); border: 1px solid var(--border);
}
.setting-label { font-size: 10px; color: var(--text-muted); font-family: var(--font-mono); }
.setting-value { font-size: 12px; color: var(--text-primary); }
.setting-value.on { color: var(--accent-green); font-weight: 600; }

/* Stat cards */
.stat-row { display: flex; gap: var(--space-sm); margin-bottom: var(--space-sm); }
.stat-card {
  flex: 1; background: var(--bg-hover); border: 1px solid var(--border);
  border-radius: var(--radius-md); padding: var(--space-sm) var(--space-md);
}
.stat-card-label { font-size: 10px; color: var(--text-muted); }
.stat-card-value { font-size: 18px; font-weight: 700; color: var(--text-primary); margin: 2px 0; }
.stat-card-sub { font-size: 10px; color: var(--text-secondary); }

/* Sub-section */
.sub-section { margin-top: var(--space-sm); }
.sub-title { font-size: 11px; color: var(--text-secondary); margin-bottom: var(--space-xs); }

/* Merchant list */
.merchant-list { display: flex; flex-direction: column; gap: 4px; }
.merchant-item {
  display: flex; align-items: center; gap: var(--space-sm);
  padding: 4px var(--space-sm); background: var(--bg-hover);
  border-radius: var(--radius-sm); font-size: 12px;
}
.merchant-rank {
  width: 18px; height: 18px; display: flex; align-items: center; justify-content: center;
  background: rgba(139, 92, 246, 0.15); color: #a78bfa;
  border-radius: 50%; font-size: 10px; font-weight: 700; flex-shrink: 0;
}
.merchant-name { flex: 1; color: var(--text-primary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.merchant-times { color: var(--text-muted); font-size: 11px; white-space: nowrap; }
.merchant-total { color: var(--accent-yellow); font-size: 11px; font-family: var(--font-mono); white-space: nowrap; }

/* Companion list */
.companion-list { display: flex; flex-direction: column; gap: 4px; }
.companion-item {
  display: flex; gap: var(--space-sm); align-items: flex-start;
  padding: 4px var(--space-sm); background: var(--bg-hover);
  border-radius: var(--radius-sm); font-size: 12px;
}
.companion-date {
  color: var(--text-muted); font-size: 10px; font-family: var(--font-mono);
  white-space: nowrap; padding-top: 1px;
}
.companion-text { color: var(--text-primary); line-height: 1.4; }

/* Memory list */
.memory-list { display: flex; flex-direction: column; gap: var(--space-sm); }
.memory-item {
  background: var(--bg-hover); border: 1px solid var(--border);
  border-radius: var(--radius-md); padding: var(--space-sm) var(--space-md);
}
.memory-header {
  display: flex; align-items: center; gap: var(--space-sm); margin-bottom: 4px; flex-wrap: wrap;
}
.memory-type {
  font-size: 10px; padding: 1px 6px; border-radius: var(--radius-sm);
  background: rgba(139, 92, 246, 0.12); color: #a78bfa; font-weight: 600;
}
.memory-weight, .memory-confidence {
  font-size: 10px; color: var(--text-muted); font-family: var(--font-mono);
}
.memory-last-seen { font-size: 10px; color: var(--text-muted); margin-left: auto; }
.memory-content { font-size: 12px; color: var(--text-primary); line-height: 1.4; }
.memory-evidence { margin-top: 4px; }
.memory-evidence summary { font-size: 10px; color: var(--text-muted); cursor: pointer; }
.evidence-json {
  font-family: var(--font-mono); font-size: 10px; color: var(--text-secondary);
  background: #0a0e14; border: 1px solid var(--border); border-radius: var(--radius-sm);
  padding: var(--space-xs) var(--space-sm); margin: 4px 0 0; white-space: pre-wrap; word-break: break-all;
  max-height: 150px; overflow-y: auto;
}
</style>
