<template>
  <div class="page active">
    <div class="auth-hero">
      <div class="auth-logo">芥</div>
      <div class="auth-title">芥子</div>
      <div class="auth-subtitle">芥子纳须弥 · 从聊天AI走向人生AI</div>
    </div>

    <div v-if="mode !== 'reset' && !awaitingVerification" class="auth-tabs">
      <button :class="{ active: mode === 'login' }" @click="mode = 'login'">登录</button>
      <button :class="{ active: mode === 'register' }" @click="mode = 'register'">注册</button>
    </div>

    <div v-if="isWechatBrowser" class="auth-browser-warning">
      当前在微信内置浏览器中，注册/登录可能失败。请点击右上角「...」选择「在浏览器中打开」。
    </div>

    <div v-if="deletionReceipt" class="auth-deletion-receipt" role="status">
      <strong>{{ deletionReceiptTitle }}</strong>
      <span>{{ deletionReceipt.message }}</span>
      <span>支持编号：{{ deletionReceipt.supportReference }}</span>
      <span v-if="deletionReceipt.deletionStatus !== 'completed'">预计完成：{{ deletionEstimateLabel }}</span>
      <small>这是保存在本机的最近回执。退出后如需查询，请向支持人员提供上述编号。</small>
      <button type="button" class="auth-switch-btn" @click="dismissDeletionReceipt">我已保存</button>
    </div>

    <div v-if="authCallbackPending" class="auth-callback-panel">
      <strong>正在验证安全链接</strong>
      <span>验证完成后才能继续，请不要关闭此页面。</span>
    </div>

    <div v-else-if="authCallbackError" class="auth-callback-panel is-error">
      <strong>{{ authCallbackError }}</strong>
      <span>请重新发送链接，或返回登录页。</span>
      <button type="button" class="auth-switch-btn" @click="dismissCallback">返回登录</button>
    </div>

    <div v-else-if="authCallbackNotice" class="auth-callback-panel">
      <strong>{{ authCallbackNotice }}</strong>
      <span>请使用邮箱和密码登录。</span>
      <button type="button" class="auth-switch-btn" @click="dismissCallback">前往登录</button>
    </div>

    <form v-else class="auth-form" @submit.prevent="submit">
      <input v-if="mode !== 'reset'" v-model="email" type="email" class="auth-input" placeholder="邮箱地址" autocomplete="email" required>
      <input v-if="mode !== 'recovery'" v-model="password" type="password" class="auth-input" :placeholder="mode === 'reset' ? '新密码（至少8位）' : mode === 'register' ? '密码（至少6位）' : '密码'" :autocomplete="mode === 'login' ? 'current-password' : 'new-password'" :minlength="mode === 'reset' ? 8 : 6" required>
      <input v-if="mode === 'reset'" v-model="passwordConfirm" type="password" class="auth-input" placeholder="再次输入新密码" autocomplete="new-password" minlength="8" required>

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

      <p v-if="statusMsg" class="auth-message" :class="{ 'is-error': statusIsError }">{{ statusMsg }}</p>

      <div v-if="awaitingVerification" class="auth-verification-panel">
        <strong>请确认邮箱后再登录</strong>
        <span>{{ maskedVerificationEmail }}</span>
        <button type="button" class="auth-switch-btn" :disabled="resendLoading || resendCooldown > 0" @click="resendConfirmation">
          {{ resendCooldown > 0 ? `${resendCooldown} 秒后可重发` : resendLoading ? '发送中...' : '重发确认邮件' }}
        </button>
        <button type="button" class="auth-switch-btn" :disabled="resendLoading" @click="changeVerificationEmail">更换邮箱</button>
        <button type="button" class="auth-switch-btn" @click="returnToLogin">返回登录</button>
      </div>

      <button class="auth-btn" :disabled="loading || (mode === 'register' && (!acceptedTerms || !acceptedSensitiveData)) || (mode === 'recovery' && resendCooldown > 0)">
        {{ loading ? '处理中...' : mode === 'reset' ? '更新密码' : mode === 'recovery' ? resendCooldown > 0 ? `${resendCooldown} 秒后可重发` : '发送重置邮件' : mode === 'login' ? '登录' : '注册' }}
      </button>

      <p class="auth-hint">
        <template v-if="mode === 'login'">
          还没有账号？
          <button type="button" class="auth-switch-btn" @click="mode = 'register'">注册</button>
          <button type="button" class="auth-switch-btn" @click="mode = 'recovery'">忘记密码</button>
        </template>
        <template v-else-if="mode === 'register'">
          已有账号？
          <button type="button" class="auth-switch-btn" @click="mode = 'login'">登录</button>
        </template>
        <template v-else-if="mode === 'recovery'">
          想起密码了？
          <button type="button" class="auth-switch-btn" @click="mode = 'login'">返回登录</button>
        </template>
        <template v-else>设置完成后需要使用新密码重新登录。</template>
      </p>

      <p v-if="mode === 'recovery'" class="auth-hint">
        我们会向邮箱发送一次性重置链接，不会透露该邮箱是否已注册。
      </p>
    </form>

    <p class="auth-footer">
      芥子 · Personal AI Memory。注册即表示你同意数据仅用于提供个人数据管理服务，不会公开或出售给第三方。
    </p>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, ref, inject, watch } from 'vue'
import { sb } from '../../lib/supabase'
import { authRedirectURL, friendlyAuthError } from '../../lib/authFlow.js'
import {
  clearAccountDeletionReceipt,
  loadAccountDeletionReceipt,
} from '../../lib/accountDeletion.js'

const props = defineProps({
  passwordRecovery: Boolean,
  authCallbackPending: Boolean,
  authCallbackError: { type: String, default: '' },
  authCallbackNotice: { type: String, default: '' },
})
const emit = defineEmits(['recovery-complete', 'callback-dismiss'])
const store = inject('store')
const mode = ref('login')
const email = ref('')
const password = ref('')
const passwordConfirm = ref('')
const loading = ref(false)
const statusMsg = ref('')
const statusIsError = ref(false)
const acceptedTerms = ref(false)
const acceptedSensitiveData = ref(false)
const awaitingVerification = ref(false)
const verificationEmail = ref('')
const resendLoading = ref(false)
const resendCooldown = ref(0)
const deletionReceipt = ref(loadAccountDeletionReceipt())
let resendTimer = null
const isWechatBrowser = /MicroMessenger/i.test(typeof navigator === 'undefined' ? '' : navigator.userAgent || '')

const maskedVerificationEmail = computed(() => {
  const [localPart, domain] = verificationEmail.value.split('@')
  if (!localPart || !domain) return verificationEmail.value
  const visible = localPart.length <= 2 ? localPart.slice(0, 1) : localPart.slice(0, 2)
  return `${visible}***@${domain}`
})
const deletionReceiptTitle = computed(() => deletionReceipt.value?.deletionStatus === 'completed'
  ? '账户删除已完成'
  : '账户删除请求已受理')
const deletionEstimateLabel = computed(() => {
  const value = deletionReceipt.value?.estimatedCompletionAt
  if (!value) return '通常在 24 小时内'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? '通常在 24 小时内' : date.toLocaleString('zh-CN')
})

function dismissDeletionReceipt() {
  clearAccountDeletionReceipt()
  deletionReceipt.value = null
}

watch(() => props.passwordRecovery, (active) => {
  if (active) {
    mode.value = 'reset'
    password.value = ''
    passwordConfirm.value = ''
    statusMsg.value = '请输入新的登录密码。'
    statusIsError.value = false
  } else if (mode.value === 'reset') {
    mode.value = 'login'
    password.value = ''
    passwordConfirm.value = ''
  }
}, { immediate: true })

// 登录态/会话恢复统一由 App.vue 的 onAuthStateChange 监听处理，
// 这里不再自行调用 loadData()，避免与 App.vue 产生竞态。

async function submit() {
  if (loading.value) return
  loading.value = true
  statusMsg.value = ''
  statusIsError.value = false

  try {
    if (mode.value === 'reset') {
      if (!props.passwordRecovery) throw new Error('重置链接尚未验证')
      if (password.value.length < 8) throw new Error('新密码至少需要 8 位')
      if (password.value !== passwordConfirm.value) throw new Error('两次输入的新密码不一致')
      const { error } = await sb.auth.updateUser({ password: password.value })
      if (error) throw error
      const { error: globalSignOutError } = await sb.auth.signOut({ scope: 'global' })
      if (globalSignOutError) {
        console.warn('[auth] global sign-out after recovery failed; clearing local session', {
          code: globalSignOutError.code || globalSignOutError.name || 'unknown',
        })
        await sb.auth.signOut({ scope: 'local' }).catch(() => {})
      }
      password.value = ''
      passwordConfirm.value = ''
      emit('recovery-complete')
      store?.showFlash('✓ 密码已更新，请重新登录')
      return
    }

    if (mode.value === 'recovery') {
      const address = email.value.trim()
      if (!address) throw new Error('请输入注册邮箱')
      const { error } = await sb.auth.resetPasswordForEmail(address, {
        redirectTo: authRedirectURL('recovery'),
      })
      if (error) throw error
      statusMsg.value = '如果该邮箱已注册，你会收到密码重置邮件。请检查收件箱和垃圾邮件。'
      startResendCooldown()
      return
    }

    if (mode.value === 'register') {
      if (!acceptedTerms.value || !acceptedSensitiveData.value) {
        statusMsg.value = '请先完成服务协议、隐私政策和敏感数据处理确认'
        statusIsError.value = true
        return
      }
      const acceptedAt = new Date().toISOString()
      const { data, error } = await sb.auth.signUp({
        email: email.value.trim(),
        password: password.value,
        options: {
          emailRedirectTo: authRedirectURL('confirm'),
          data: {
            legal_consent_at: acceptedAt,
            sensitive_data_consent_at: acceptedAt,
            terms_version: '2026-07-19',
            privacy_version: '2026-07-22',
            sensitive_data_version: '2026-07-22',
          },
        },
      })
      if (error) throw error

      if (data?.session) {
        awaitingVerification.value = false
        store?.showFlash('✓ 注册成功，正在加载你的数据')
      } else if (data?.user) {
        awaitingVerification.value = true
        verificationEmail.value = data.user.email || email.value.trim()
        statusMsg.value = '注册成功。请先确认邮箱，再返回这里登录。'
        startResendCooldown()
      } else {
        throw new Error('注册未建立有效会话，请稍后重试')
      }
    } else {
      const { data, error } = await sb.auth.signInWithPassword({
        email: email.value.trim(),
        password: password.value,
      })
      if (error) throw error

      if (data?.session) {
        awaitingVerification.value = false
        store?.showFlash('✓ 登录成功')
      } else {
        throw new Error('登录未建立有效会话，请确认邮箱后重试')
      }
    }
  } catch (e) {
    const context = mode.value === 'recovery'
      ? 'recovery-email'
      : mode.value === 'reset'
        ? 'password-update'
        : 'default'
    statusMsg.value = friendlyAuthError(e, context)
    statusIsError.value = true
  } finally {
    loading.value = false
  }
}

async function resendConfirmation() {
  const address = verificationEmail.value.trim()
  if (!address || resendLoading.value || resendCooldown.value > 0) return
  resendLoading.value = true
  statusMsg.value = ''
  statusIsError.value = false
  try {
    const { error } = await sb.auth.resend({
      type: 'signup',
      email: address,
      options: { emailRedirectTo: authRedirectURL('confirm') },
    })
    if (error) throw error
    statusMsg.value = '确认邮件已重新发送，请检查收件箱和垃圾邮件。'
    startResendCooldown()
  } catch (error) {
    statusMsg.value = friendlyAuthError(error, 'resend')
    statusIsError.value = true
  } finally {
    resendLoading.value = false
  }
}

function startResendCooldown() {
  if (resendTimer) clearInterval(resendTimer)
  resendCooldown.value = 60
  resendTimer = setInterval(() => {
    resendCooldown.value -= 1
    if (resendCooldown.value <= 0) {
      resendCooldown.value = 0
      clearInterval(resendTimer)
      resendTimer = null
    }
  }, 1000)
}

function returnToLogin() {
  mode.value = 'login'
  awaitingVerification.value = false
  statusMsg.value = ''
  statusIsError.value = false
}

function changeVerificationEmail() {
  awaitingVerification.value = false
  verificationEmail.value = ''
  password.value = ''
  statusMsg.value = '请修改邮箱后重新注册。'
  statusIsError.value = false
}

function dismissCallback() {
  emit('callback-dismiss')
}

onBeforeUnmount(() => {
  if (resendTimer) clearInterval(resendTimer)
})
</script>
