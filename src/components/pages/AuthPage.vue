<template>
  <div class="page active">
    <div class="auth-hero">
      <div class="auth-logo">芥</div>
      <div class="auth-title">芥子</div>
      <div class="auth-subtitle">芥子纳须弥 · 从聊天AI走向人生AI</div>
    </div>

    <div class="auth-tabs">
      <button :class="{ active: mode === 'login' }" @click="mode = 'login'">登录</button>
      <button :class="{ active: mode === 'register' }" @click="mode = 'register'">注册</button>
    </div>

    <div v-if="isWechatBrowser" class="auth-browser-warning">
      当前在微信内置浏览器中，注册/登录可能失败。请点击右上角「...」选择「在浏览器中打开」。
    </div>

    <form class="auth-form" @submit.prevent="submit">
      <input v-model="email" type="email" class="auth-input" placeholder="邮箱地址" autocomplete="email" required>
      <input v-model="password" type="password" class="auth-input" placeholder="密码（至少6位）" autocomplete="current-password" minlength="6" required>

      <div v-if="mode === 'register'" class="auth-consent-list">
        <label class="auth-consent-row">
          <input v-model="acceptedTerms" type="checkbox">
          <span>我已阅读并同意 <a href="/terms.html" target="_blank" rel="noopener">服务协议</a> 和 <a href="/privacy.html" target="_blank" rel="noopener">隐私政策</a></span>
        </label>
        <label class="auth-consent-row">
          <input v-model="acceptedSensitiveData" type="checkbox">
          <span>我同意处理主动提交的财务、睡眠等敏感数据，并知悉主要数据存储于新加坡、图片会传输至阿里云百炼中国内地接口完成 Qwen 识别。</span>
        </label>
      </div>

      <p v-if="errorMsg" class="auth-error">{{ errorMsg }}</p>

      <button class="auth-btn" :disabled="loading || (mode === 'register' && (!acceptedTerms || !acceptedSensitiveData))">
        {{ loading ? '处理中...' : mode === 'login' ? '登录' : '注册' }}
      </button>

      <p class="auth-hint">
        {{ mode === 'login' ? '还没有账号？' : '已有账号？' }}
        <button type="button" class="auth-switch-btn" @click="mode = mode === 'login' ? 'register' : 'login'">
          {{ mode === 'login' ? '注册' : '登录' }}
        </button>
      </p>
    </form>

    <p class="auth-footer">
      芥子 · Personal AI Memory。注册即表示你同意数据仅用于提供个人数据管理服务，不会公开或出售给第三方。
    </p>
  </div>
</template>

<script setup>
import { ref, inject } from 'vue'
import { sb } from '../../lib/supabase'

const store = inject('store')
const mode = ref('login')
const email = ref('')
const password = ref('')
const loading = ref(false)
const errorMsg = ref('')
const acceptedTerms = ref(false)
const acceptedSensitiveData = ref(false)
const isWechatBrowser = /MicroMessenger/i.test(typeof navigator === 'undefined' ? '' : navigator.userAgent || '')

// 登录态/会话恢复统一由 App.vue 的 onAuthStateChange 监听处理，
// 这里不再自行调用 loadData()，避免与 App.vue 产生竞态。

async function submit(attempt = 0) {
  loading.value = true
  errorMsg.value = ''

  try {
    if (mode.value === 'register') {
      if (!acceptedTerms.value || !acceptedSensitiveData.value) {
        errorMsg.value = '请先完成服务协议、隐私政策和敏感数据处理确认'
        return
      }
      const acceptedAt = new Date().toISOString()
      const { data, error } = await sb.auth.signUp({
        email: email.value.trim(),
        password: password.value,
        options: {
          data: {
            legal_consent_at: acceptedAt,
            sensitive_data_consent_at: acceptedAt,
            terms_version: '2026-07-19',
            privacy_version: '2026-07-22',
          },
        },
      })
      if (error) throw error

      if (data?.user) {
        await sb.from('user_configs').upsert({
          user_id: data.user.id,
          plan: 'seed',
          created_at: new Date().toISOString(),
        }, { onConflict: 'user_id' })
        store.currentUserId.value = data.user.id
        store.currentUserEmail.value = data.user.email || ''
        store.isLoggedIn.value = true
        store.showFlash('✓ 注册成功，已自动登录')
        await store.loadData()
      }
    } else {
      const { data, error } = await sb.auth.signInWithPassword({
        email: email.value.trim(),
        password: password.value,
      })
      if (error) throw error

      if (data?.user) {
        store.currentUserId.value = data.user.id
        store.currentUserEmail.value = data.user.email || ''
        store.isLoggedIn.value = true
        store.showFlash('✓ 登录成功')
        await store.loadData()
      }
    }
  } catch (e) {
    if (e.message === 'Load failed' && attempt < 1) {
      errorMsg.value = '网络波动，正在重试...'
      await new Promise(r => setTimeout(r, 1500))
      return submit(attempt + 1)
    }
    errorMsg.value = e.message || '操作失败，请重试'
  } finally {
    if (!errorMsg.value || !errorMsg.value.startsWith('网络波动')) loading.value = false
  }
}
</script>
