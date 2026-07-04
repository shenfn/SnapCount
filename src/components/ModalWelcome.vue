<template>
  <div v-if="visible" class="welcome-overlay" @click.self="trySkip">
    <div class="welcome-card">

      <!-- 步骤指示器 -->
      <div class="welcome-steps">
        <span v-for="i in TOTAL_STEPS" :key="i"
          class="welcome-dot" :class="{ active: step === i }" @click="step = i"></span>
      </div>

      <!-- Step 1: 是什么 -->
      <div v-if="step === 1" class="welcome-body">
        <div class="welcome-icon">🌱</div>
        <h2 class="welcome-title">欢迎来到芥子</h2>
        <p class="welcome-desc">
          芥子是一个 <strong>AI 驱动的个人数据平台</strong>，从记账出发，帮你把生活中的截图自动变成结构化数据。
        </p>
        <ul class="welcome-list">
          <li>📸 截图发给快捷指令 → AI 自动识别金额、分类</li>
          <li>📥 进入「待处理」确认后归档</li>
          <li>📈 首页查看本月消费汇总与趋势</li>
          <li>🗂 已支持运动、睡眠、饮食、钱包等更多数据域</li>
        </ul>
        <p class="welcome-vision">
          芥子纳须弥——成为你的<strong>全品类个人生活记录仪</strong>，从聊天 AI 走向人生 AI。
        </p>
      </div>

      <!-- Step 2: 快捷指令配置 -->
      <div v-if="step === 2" class="welcome-body">
        <div class="welcome-icon">⚡</div>
        <h2 class="welcome-title">一键截图记账</h2>
        <p class="welcome-desc">
          配置快捷指令后，截图即可自动记账。不配置也能在 App 内手动记账。
        </p>
        <p class="welcome-vision" style="margin-bottom:16px">
          💡 AppStore 原生版即将上线，届时免配置直接使用。
        </p>

        <ol class="welcome-steps-list">
          <li>复制下方 Token</li>
        </ol>
        <div class="welcome-token-box">
          <div v-if="uploadToken" class="welcome-token-value" @click="copyToken">
            {{ uploadToken }}
            <span class="welcome-token-copy">📋 复制</span>
          </div>
          <div v-else class="welcome-token-loading">登录后在「设置」页面查看</div>
          <div v-if="copyTip" class="welcome-copy-tip">{{ copyTip }}</div>
        </div>

        <ol class="welcome-steps-list" start="2" style="margin-top:12px">
          <li>导入快捷指令 → 填入 Token</li>
        </ol>
        <div class="welcome-shortcut-link">
          <a href="https://www.icloud.com/shortcuts/60be42007bee43ff850d53106813b351" target="_blank" rel="noopener">
            📲 导入快捷指令 →
          </a>
        </div>

        <ol class="welcome-steps-list" start="3" style="margin-top:12px">
          <li>绑定触发方式：<strong>辅助触控</strong>或<strong>操作按钮</strong></li>
        </ol>
      </div>

      <!-- Step 3: 开始使用 -->
      <div v-if="step === 3" class="welcome-body">
        <div class="welcome-icon">🚀</div>
        <h2 class="welcome-title">开始使用</h2>
        <ul class="welcome-list">
          <li>📲 在订单页面触发快捷指令，上传第一张截图</li>
          <li>◌ 去「待处理」确认 AI 识别结果</li>
          <li>✚ 点右下角 <strong>＋</strong> 手动添加收入/支出</li>
          <li>⚙ 「设置」页面可查看 Token 和账户信息</li>
        </ul>

        <div class="welcome-tip" style="margin-bottom:12px">
          <strong>添加到桌面</strong>：用 Safari 打开 snapflow.me → 点底部分享按钮 → 添加到主屏幕，即可像 App 一样使用。
        </div>

        <p class="welcome-vision">
          💡 上传数据后如果首页没刷新，把 App 从后台划掉重新进入即可。
        </p>
        <p class="welcome-vision" style="margin-top:8px">
          📌 <strong>体验分层</strong>：登录即可查看数据 · 配置快捷指令享一键记账+AI记忆 · AppStore 原生版即将上线
        </p>
      </div>

      <!-- 操作按钮 -->
      <div class="welcome-footer">
        <button v-if="step > 1" class="welcome-btn-secondary" @click="step--">上一步</button>
        <button v-if="step < TOTAL_STEPS" class="welcome-btn-primary" @click="step++">下一步</button>
        <button v-if="step === TOTAL_STEPS" class="welcome-btn-primary" @click="finish">开始使用</button>
      </div>

      <!-- 跳过 -->
      <button class="welcome-skip" @click="finish">跳过</button>
    </div>
  </div>
</template>

<script setup>
import { ref, inject, onMounted } from 'vue'
import { sb } from '../lib/supabase'

const STORAGE_KEY = 'snapcount_onboarded'
const TOTAL_STEPS = 3

const store = inject('store')
const visible = ref(false)
const step = ref(1)
const uploadToken = ref('')
const copyTip = ref('')

onMounted(async () => {
  if (localStorage.getItem(STORAGE_KEY)) return
  visible.value = true

  if (store.currentUserId.value) {
    const { data: cfg } = await sb.from('user_configs')
      .select('upload_token')
      .eq('user_id', store.currentUserId.value)
      .maybeSingle()
    if (cfg) uploadToken.value = cfg.upload_token || ''
  }
})

function finish() {
  localStorage.setItem(STORAGE_KEY, '1')
  visible.value = false
}

function trySkip() {
  finish()
}

function copyToken() {
  if (!uploadToken.value) return
  const text = uploadToken.value
  // 优先用 Clipboard API，降级用 execCommand（兼容 iOS Safari）
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text)
      .then(() => showCopyTip('✓ 已复制'))
      .catch(() => fallbackCopy(text))
  } else {
    fallbackCopy(text)
  }
}

function fallbackCopy(text) {
  const ta = document.createElement('textarea')
  ta.value = text
  ta.style.position = 'fixed'
  ta.style.opacity = '0'
  document.body.appendChild(ta)
  ta.select()
  try {
    document.execCommand('copy')
    showCopyTip('✓ 已复制')
  } catch {
    showCopyTip('⚠ 复制失败，请手动选择')
  }
  document.body.removeChild(ta)
}

function showCopyTip(msg) {
  copyTip.value = msg
  setTimeout(() => { copyTip.value = '' }, 2000)
}
</script>

<style scoped>
.welcome-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  z-index: 8000;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}

.welcome-card {
  background: #fff;
  border-radius: 20px;
  width: 100%;
  max-width: 380px;
  max-height: 88vh;
  overflow-y: auto;
  padding: 28px 24px 20px;
  position: relative;
  box-shadow: 0 20px 60px rgba(0,0,0,0.2);
}

.welcome-steps {
  display: flex;
  justify-content: center;
  gap: 8px;
  margin-bottom: 24px;
}

.welcome-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #E0E0E0;
  cursor: pointer;
  transition: background 0.2s;
}
.welcome-dot.active {
  background: var(--accent, #2D6A4F);
  width: 24px;
  border-radius: 4px;
}

.welcome-body {
  text-align: center;
}

.welcome-icon {
  font-size: 48px;
  margin-bottom: 12px;
}

.welcome-title {
  font-size: 20px;
  font-weight: 700;
  color: #1A1A18;
  margin: 0 0 12px;
}

.welcome-desc {
  font-size: 14px;
  color: #4A4A45;
  line-height: 1.6;
  margin-bottom: 16px;
  text-align: left;
}

.welcome-list {
  list-style: none;
  padding: 0;
  margin: 0 0 16px;
  text-align: left;
}

.welcome-list li {
  font-size: 13px;
  color: #4A4A45;
  padding: 6px 0;
  border-bottom: 1px solid #F0F0EE;
  line-height: 1.5;
}

.welcome-list li:last-child {
  border-bottom: none;
}

.welcome-vision {
  font-size: 13px;
  color: #6B6A65;
  background: #F8F6F2;
  border-radius: 10px;
  padding: 10px 14px;
  text-align: left;
  line-height: 1.6;
  margin-top: 4px;
}

.welcome-shortcut-link {
  background: #F4FBF7;
  border: 1.5px solid #2D6A4F;
  border-radius: 12px;
  padding: 14px;
  margin: 12px 0;
  text-align: center;
}

.welcome-shortcut-link a {
  font-size: 14px;
  font-weight: 600;
  color: #2D6A4F;
  text-decoration: none;
  display: block;
}

.welcome-shortcut-link a:active {
  opacity: 0.7;
}

.welcome-token-box {
  background: #F4FBF7;
  border: 1.5px solid #B7DFC8;
  border-radius: 12px;
  padding: 14px;
  position: relative;
  margin: 12px 0 16px;
  text-align: left;
}

.welcome-token-label {
  font-size: 11px;
  color: #2D6A4F;
  font-weight: 600;
  margin-bottom: 6px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.welcome-token-value {
  font-size: 12px;
  font-family: 'SF Mono', 'Menlo', monospace;
  color: #1A1A18;
  word-break: break-all;
  cursor: pointer;
  line-height: 1.5;
}

.welcome-token-copy {
  display: inline-block;
  margin-left: 6px;
  font-size: 11px;
  color: #2D6A4F;
  font-family: 'PingFang SC', system-ui, sans-serif;
}

.welcome-copy-tip {
  position: absolute;
  top: -36px;
  left: 50%;
  transform: translateX(-50%);
  background: #2D6A4F;
  color: #fff;
  font-size: 13px;
  font-weight: 500;
  padding: 6px 16px;
  border-radius: 8px;
  white-space: nowrap;
  z-index: 9000;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
  animation: tipPop 0.25s ease;
}
@keyframes tipPop {
  from { opacity: 0; transform: translateX(-50%) translateY(4px); }
  to   { opacity: 1; transform: translateX(-50%) translateY(0); }
}

.welcome-token-loading {
  font-size: 13px;
  color: #9E9E9E;
}

.welcome-steps-list {
  text-align: left;
  padding-left: 20px;
  margin: 0 0 14px;
}

.welcome-steps-list li {
  font-size: 13px;
  color: #4A4A45;
  line-height: 1.6;
  margin-bottom: 6px;
}

.welcome-steps-list code {
  font-family: 'SF Mono', 'Menlo', monospace;
  font-size: 11px;
  background: #F0F0EE;
  padding: 1px 4px;
  border-radius: 4px;
  word-break: break-all;
}

.welcome-tip {
  font-size: 13px;
  color: #2D6A4F;
  background: #F4FBF7;
  border-radius: 10px;
  padding: 10px 14px;
  text-align: left;
  line-height: 1.5;
}

.welcome-sub-options {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin: 8px 0 12px;
}

.welcome-sub-option {
  background: #F8F6F2;
  border-radius: 10px;
  padding: 10px 14px;
  text-align: left;
}

.welcome-sub-option strong {
  display: block;
  font-size: 13px;
  color: #1A1A18;
  margin-bottom: 2px;
}

.welcome-sub-option span {
  font-size: 12px;
  color: #6B6A65;
  line-height: 1.5;
}

.welcome-footer {
  display: flex;
  gap: 10px;
  margin-top: 24px;
}

.welcome-btn-primary {
  flex: 1;
  padding: 13px;
  border-radius: 12px;
  border: none;
  background: var(--accent, #2D6A4F);
  color: #fff;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  font-family: 'PingFang SC', system-ui, sans-serif;
  transition: opacity 0.15s;
}
.welcome-btn-primary:active { opacity: 0.8; }

.welcome-btn-secondary {
  flex: 0 0 auto;
  padding: 13px 18px;
  border-radius: 12px;
  border: 1.5px solid #E0E0E0;
  background: #fff;
  color: #4A4A45;
  font-size: 15px;
  cursor: pointer;
  font-family: 'PingFang SC', system-ui, sans-serif;
}

.welcome-skip {
  display: block;
  width: 100%;
  margin-top: 10px;
  padding: 8px;
  background: none;
  border: none;
  color: #9E9E9E;
  font-size: 13px;
  cursor: pointer;
  font-family: 'PingFang SC', system-ui, sans-serif;
}
</style>
