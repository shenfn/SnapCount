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
        <div class="welcome-icon">📊</div>
        <h2 class="welcome-title">欢迎来到随手账</h2>
        <p class="welcome-desc">
          随手账是一个 <strong>AI 驱动的个人数据平台</strong>，从记账出发，帮你把生活中的截图自动变成结构化数据。
        </p>
        <ul class="welcome-list">
          <li>📸 截图发给快捷指令 → AI 自动识别金额、分类</li>
          <li>📥 进入「待处理」确认后归档</li>
          <li>📈 首页查看本月消费汇总与趋势</li>
          <li>🗂 未来支持运动、睡眠、阅读等更多数据域</li>
        </ul>
        <p class="welcome-vision">
          目标：成为你的<strong>全品类个人生活记录仪</strong>，而不只是一个记账 App。
        </p>
      </div>

      <!-- Step 2: 快捷指令配置 -->
      <div v-if="step === 2" class="welcome-body">
        <div class="welcome-icon">⚡</div>
        <h2 class="welcome-title">配置快捷指令</h2>
        <p class="welcome-desc">
          随手账通过 <strong>iOS 快捷指令</strong> 接收截图。配置一次，之后一键记账。
        </p>

        <div class="welcome-token-box">
          <div class="welcome-token-label">你的专属上传 Token（稍后在设置中复制）</div>
          <div v-if="uploadToken" class="welcome-token-value" @click="copyToken">
            {{ uploadToken }}
            <span class="welcome-token-copy">点击复制</span>
          </div>
          <div v-else class="welcome-token-loading">登录后在「设置」页面查看</div>
        </div>

        <ol class="welcome-steps-list">
          <li>点击下方链接导入快捷指令</li>
          <li>打开快捷指令 App → 找到 <code>upload_token</code> 字段 → 粘贴上方 Token</li>
          <li><strong>绑定触发方式</strong>（二选一）：</li>
        </ol>
        <div class="welcome-sub-options">
          <div class="welcome-sub-option">
            <strong>辅助触控</strong>
            <span>设置 → 辅助触控 → 开启 → 自定义操作 → 绑定快捷指令</span>
          </div>
          <div class="welcome-sub-option">
            <strong>操作按钮</strong>
            <span>设置 → 操作按钮 → 选择快捷指令</span>
          </div>
        </div>

        <p class="welcome-tip">
          ⚠️ 首次执行可能因网络波动超时，重新执行即可。绑定后在订单页面触发就能自动识别截图。
        </p>
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
  navigator.clipboard?.writeText(uploadToken.value)
    .then(() => store.showFlash('✓ Token 已复制到剪贴板'))
    .catch(() => store.showFlash('⚠ 复制失败，请手动选择'))
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

.welcome-token-box {
  background: #F4FBF7;
  border: 1.5px solid #B7DFC8;
  border-radius: 12px;
  padding: 14px;
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
