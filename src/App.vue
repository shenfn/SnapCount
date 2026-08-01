<template>
  <div>
    <!-- Auth gate -->
    <AccountConsentGate
      v-if="store.isLoggedIn.value && authGate.startsWith('consent')"
      :key="store.currentUserId.value || 'account-consent'"
      :loading="authGate === 'consent-checking'"
      :submitting="consentSubmitting"
      :deleting="consentDeleting"
      :blocked="consentBlocked"
      :error="consentError"
      @accept="acceptAccountConsent"
      @retry="retryAccountConsent"
      @delete-account="deleteAccountFromConsentGate"
      @sign-out="signOutFromConsentGate"
    />
    <AuthPage
      v-else-if="!store.isLoggedIn.value || authGate !== 'none'"
      :password-recovery="passwordRecoveryActive"
      :auth-callback-pending="authCallbackPending"
      :auth-callback-error="authCallbackError"
      :auth-callback-notice="authCallbackNotice"
      @recovery-complete="completePasswordRecovery"
      @callback-dismiss="dismissAuthCallback"
    />

    <template v-else>
    <!-- 下拉刷新指示器 -->
    <div class="ptr-indicator" :class="{ active: ptrActive, refreshing }" :style="ptrStyle">
      <div class="ptr-spinner" :class="{ ready: ptrReady, spin: refreshing }">
        <span v-if="refreshing">⟳</span>
        <span v-else-if="ptrReady">↻ 松开刷新</span>
        <span v-else>↓ 下拉刷新</span>
      </div>
    </div>

    <!-- Loading overlay -->
    <div v-if="store.loading.value" class="platform-overlay">
      <div class="platform-loader-mark platform-loader-brand" aria-hidden="true">
        <svg class="platform-loader-icon" viewBox="0 0 64 64" role="img">
          <rect class="loader-book" x="14" y="12" width="36" height="44" rx="10" />
          <path class="loader-spine" d="M24 14v42" />
          <path class="loader-line" d="M31 25h12" />
          <path class="loader-line" d="M31 33h9" />
          <path class="loader-coin" d="M31 43h14" />
          <circle class="loader-dot" cx="44" cy="43" r="3" />
        </svg>
      </div>
      <div class="platform-loader-text">正在整理你的账本…</div>
      <div class="platform-loader-track" aria-hidden="true"><span></span></div>
    </div>

    <!-- Error overlay -->
    <div v-if="!store.loading.value && store.loadError.value" class="platform-overlay error">
      <div class="platform-loader-mark danger">!</div>
      <div class="platform-loader-text">
        {{ store.loadErrorDetail.value ? store.loadErrorDetail.value.title : '数据加载失败' }}
      </div>
      <div class="platform-error-box">{{ store.loadError.value }}</div>

      <!-- 友好提示：当 supabase.js 识别出网络/TLS/上游错误时，逐条展示用户可操作的步骤 -->
      <div
        v-if="store.loadErrorDetail.value && store.loadErrorDetail.value.userAction && store.loadErrorDetail.value.userAction.length"
        class="platform-error-actions"
      >
        <div class="platform-error-actions-title">你可以尝试：</div>
        <ol class="platform-error-actions-list">
          <li
            v-for="(tip, idx) in store.loadErrorDetail.value.userAction"
            :key="idx"
          >{{ tip }}</li>
        </ol>
        <div v-if="store.loadErrorDetail.value.code" class="platform-error-code">
          错误码：{{ store.loadErrorDetail.value.code }}
        </div>
      </div>

      <!-- 原始兜底说明：仅在没有结构化提示时显示 -->
      <div
        v-else
        class="platform-error-sub"
      >请确认网络、Supabase 配置和数据库迁移状态。</div>

      <button class="platform-retry-btn" @click="store.loadData()">重新加载</button>
    </div>

    <!-- Pages -->
    <main id="main-content">
      <PageHome     v-show="store.currentPage.value === 'home'" />
      <PagePending  v-show="store.currentPage.value === 'pending'" />
      <PageDomains  v-show="store.currentPage.value === 'domains'" />
      <PageReport   v-show="store.currentPage.value === 'report'" />
      <PageSettings v-show="store.currentPage.value === 'settings'" />
      <PageAiVisionSettings v-show="store.currentPage.value === 'ai-vision-settings'" />
      <PageDomainDetail v-show="store.currentPage.value === 'domain-detail'" />
      <PageAccountDetail v-show="store.currentPage.value === 'account-detail'" />
      <PageUnboundRecords v-show="store.currentPage.value === 'unbound-records'" />
      <PageDayDetail v-show="store.currentPage.value === 'day-detail'" />
      <PageRecordDetail v-show="store.currentPage.value === 'record-detail'" />
      <PageInsights v-if="store.currentPage.value === 'insights'" />
    </main>

    <!-- Bottom Nav -->
    <nav class="nav platform-nav">
      <button type="button" class="nav-item" :class="{ active: store.currentPage.value === 'home' }" @click="store.navigateTo('home')">
        <span class="nav-icon nav-icon-home">账</span><div>首页</div>
      </button>
      <button type="button" class="nav-item" :class="{ active: store.currentPage.value === 'pending' }" @click="store.navigateTo('pending')">
        <span class="nav-icon nav-icon-pending">待</span><div>待处理</div>
      </button>
      <button type="button" class="nav-item" :class="{ active: store.currentPage.value === 'domains' }" @click="store.navigateTo('domains')">
        <span class="nav-icon nav-icon-domains">域</span><div>数据域</div>
      </button>
      <button type="button" class="nav-item" :class="{ active: store.currentPage.value === 'report' }" @click="store.navigateTo('report')">
        <span class="nav-icon nav-icon-report">析</span><div>报告</div>
      </button>
      <button type="button" class="nav-item" :class="{ active: store.currentPage.value === 'settings' }" @click="store.navigateTo('settings')">
        <span class="nav-icon nav-icon-settings">设</span><div>设置</div>
      </button>
    </nav>

    <!-- FAB -->
    <div class="fab-overlay" :class="{ open: fabOpen }" @click="fabOpen = false"></div>
    <div class="fab-menu" :class="{ open: fabOpen }">
      <button type="button" class="fab-item" @click="openFabAction(() => { store.navigateTo('domains'); store.showFlash('数据域创建入口将在阶段 3 接入') })">
        <span class="fab-item-icon fab-item-icon-domain">域</span>
        <span class="fab-item-copy"><strong>新建数据域</strong><small>从模板扩展新的记录面板</small></span>
      </button>
      <button type="button" class="fab-item" @click="openFabAction(() => store.openIncomeModal())">
        <span class="fab-item-icon fab-item-icon-income">收</span>
        <span class="fab-item-copy"><strong>添加收入</strong><small>工资、报销与转账收款</small></span>
      </button>
      <button type="button" class="fab-item" @click="openFabAction(() => store.openExpenseModal())">
        <span class="fab-item-icon fab-item-icon-expense">支</span>
        <span class="fab-item-copy"><strong>添加支出</strong><small>消费、账单与生活流水</small></span>
      </button>
      <button type="button" class="fab-item" @click="openFabAction(() => store.openUniversalModal('sport'))">
        <span class="fab-item-icon fab-item-icon-sport">动</span>
        <span class="fab-item-copy"><strong>添加运动</strong><small>先记一笔，后续接健康数据</small></span>
      </button>
      <button type="button" class="fab-item" @click="openFabAction(() => store.openUniversalModal('sleep'))">
        <span class="fab-item-icon fab-item-icon-sleep">眠</span>
        <span class="fab-item-copy"><strong>添加睡眠</strong><small>补充作息与恢复状态</small></span>
      </button>
      <button type="button" class="fab-item" @click="openFabAction(() => store.openUniversalModal('reading'))">
        <span class="fab-item-icon fab-item-icon-reading">读</span>
        <span class="fab-item-copy"><strong>添加阅读</strong><small>把时长和进度放进账本</small></span>
      </button>
      <button type="button" class="fab-item" @click="openFabAction(() => store.openUniversalModal('wallet'))">
        <span class="fab-item-icon fab-item-icon-wallet">钱</span>
        <span class="fab-item-copy"><strong>添加钱包</strong><small>记录余额与短期待还</small></span>
      </button>
    </div>
    <button type="button" class="fab" @click="fabOpen = !fabOpen">+</button>

    <!-- Modals -->
    <ModalWelcome />
    <ModalPending />
    <ModalIncome />
    <ModalExpense />
    <ModalUniversal />
    <ModalAccount />

    <!-- Delete confirmation -->
    <div v-if="store.deleteConfirm.open" class="delete-confirm-overlay">
      <div class="delete-confirm-dialog" role="dialog" aria-modal="true" aria-labelledby="delete-confirm-title">
        <div class="delete-confirm-icon">🗑</div>
        <div id="delete-confirm-title" class="delete-confirm-title">确认删除？</div>
        <div class="delete-confirm-body">此操作不可撤销，记录将永久删除</div>
        <div class="delete-confirm-actions">
          <button type="button" class="delete-confirm-btn delete-confirm-btn-secondary" @click="store.closeDeleteConfirm()">
            取消
          </button>
          <button type="button" class="delete-confirm-btn delete-confirm-btn-danger" @click="store.confirmDelete()">
            确认删除
          </button>
        </div>
      </div>
    </div>

    <!-- Flash -->
    <div class="flash" :class="{ show: store.flashVisible.value }">{{ store.flashMsg.value }}</div>

    <!-- Fullscreen image overlay -->
    <div class="img-overlay" :class="{ open: store.imgOverlay.open }" @click="store.closeImgFull()">
      <button class="img-overlay-close" @click.stop="store.closeImgFull()">✕</button>
      <img :src="store.imgOverlay.src" @click.stop>
    </div>
    </template>
  </div>
</template>

<script setup>
import { ref, provide, onMounted, onBeforeUnmount, computed } from 'vue'
import { sb, SUPABASE_URL, SUPABASE_ANON_KEY } from './lib/supabase'
import {
  authCallbackError as readAuthCallbackError,
  friendlyAuthError,
  hasAuthCallbackPayload,
  readAuthCallbackIntent,
  sanitizedAuthCallbackPath,
} from './lib/authFlow.js'
import {
  acceptCurrentAccountConsent,
  fetchMyAccountConsent,
  isAccountConsentCurrent,
} from './lib/accountConsent.js'
import { canLoadBusinessData, isSameSessionUser } from './lib/userSessionGuard.js'
import {
  requestAccountDeletion,
  saveAccountDeletionReceipt,
} from './lib/accountDeletion.js'
import { useStore } from './composables/useStore'
import { usePullToRefresh } from './composables/usePullToRefresh'
import AuthPage   from './components/pages/AuthPage.vue'
import AccountConsentGate from './components/pages/AccountConsentGate.vue'
import PageHome    from './components/pages/PageHome.vue'
import PagePending from './components/pages/PagePending.vue'
import PageDomains from './components/pages/PageDomains.vue'
import PageReport  from './components/pages/PageReport.vue'
import PageSettings from './components/pages/PageSettings.vue'
import PageAiVisionSettings from './components/pages/PageAiVisionSettings.vue'
import PageDomainDetail from './components/pages/PageDomainDetail.vue'
import PageAccountDetail from './components/pages/PageAccountDetail.vue'
import PageUnboundRecords from './components/pages/PageUnboundRecords.vue'
import PageDayDetail from './components/pages/PageDayDetail.vue'
import PageRecordDetail from './components/pages/PageRecordDetail.vue'
import PageInsights from './components/pages/PageInsights.vue'
import ModalPending from './components/ModalPending.vue'
import ModalIncome  from './components/ModalIncome.vue'
import ModalExpense from './components/ModalExpense.vue'
import ModalUniversal from './components/ModalUniversal.vue'
import ModalAccount from './components/ModalAccount.vue'
import ModalWelcome from './components/ModalWelcome.vue'

const store = useStore()
provide('store', store)
provide('authActions', { signOut: signOutLocally })

const fabOpen = ref(false)
const initialAuthURL = typeof window === 'undefined' ? '' : window.location.href
const initialCallbackIntent = readAuthCallbackIntent(initialAuthURL)
const initialCallbackPayload = hasAuthCallbackPayload(initialAuthURL)
const initialCallbackFlow = initialCallbackIntent || (initialCallbackPayload ? 'unknown' : null)
const initialCallbackFailure = initialCallbackFlow
  ? readAuthCallbackError(initialAuthURL)
  : null
const authGate = ref(initialCallbackFailure
  ? `${initialCallbackFlow}-error`
  : initialCallbackFlow
    ? `${initialCallbackFlow}-pending`
    : 'none')
const authCallbackError = ref(initialCallbackFailure
  ? friendlyAuthError(
    initialCallbackFailure,
    initialCallbackFlow === 'recovery'
      ? 'recovery'
      : initialCallbackFlow === 'confirmation'
        ? 'confirmation'
        : 'default',
  )
  : '')
const authCallbackNotice = ref('')
const consentError = ref('')
const consentSubmitting = ref(false)
const consentDeleting = ref(false)
const consentBlocked = ref(false)
const passwordRecoveryActive = computed(() => authGate.value === 'recovery')
const authCallbackPending = computed(() => authGate.value.endsWith('-pending'))
const callbackIntent = ref(initialCallbackFlow)
let callbackTimeout = null
let confirmationCompleting = false
let authSubscription = null
let sessionApplyGeneration = 0
let pendingConsentSession = null

// 登录态：以 supabase 的 auth 事件为唯一真相源，避免冷启动时
// getSession() 还未完成本地恢复就进入未登录态，或 AuthPage / App
// 同时各调一次 loadData() 产生竞态。
async function applySession(session) {
  if (!session?.user) return
  const sameUser = store.isLoggedIn.value
    && isSameSessionUser(session, store.currentUserId.value)
  if (authGate.value !== 'none') {
    if (!authGate.value.startsWith('consent')) return
    if (sameUser) {
      pendingConsentSession = session
      return
    }
  }
  const switchingUser = Boolean(
    store.currentUserId.value && store.currentUserId.value !== session.user.id,
  )
  if (switchingUser) {
    sessionApplyGeneration += 1
    pendingConsentSession = null
    consentSubmitting.value = false
    consentDeleting.value = false
    store.resetUserData()
  }
  store.currentUserId.value = session.user.id
  store.currentUserEmail.value = session.user.email || ''
  store.isLoggedIn.value = true
  if (sameUser) return
  store.navigateTo('home')
  await verifyAccountConsent(session, { loadData: !sameUser })
}

function isCurrentConsentAttempt(generation, userId) {
  return generation === sessionApplyGeneration
    && pendingConsentSession?.user?.id === userId
    && store.currentUserId.value === userId
    && store.isLoggedIn.value
}

async function reconcileConsentSession(expectedUserId) {
  const { data, error } = await sb.auth.getSession()
  if (error) throw error
  const liveSession = data?.session || null
  if (isSameSessionUser(liveSession, expectedUserId)) return liveSession
  if (liveSession?.user) await applySession(liveSession)
  else handleSignedOut()
  return null
}

async function verifyAccountConsent(session, { loadData = true } = {}) {
  if (!session?.user) return
  const userId = session.user.id
  const generation = ++sessionApplyGeneration
  pendingConsentSession = session
  consentError.value = ''
  consentBlocked.value = false
  authGate.value = 'consent-checking'
  try {
    if (!await reconcileConsentSession(userId)) return
    const status = await fetchMyAccountConsent(sb)
    if (!await reconcileConsentSession(userId)) return
    if (!isCurrentConsentAttempt(generation, userId)) return
    if (!status.isActive) {
      consentBlocked.value = true
      consentError.value = '账户已停用或正在删除，不能继续加载数据'
      authGate.value = 'consent-error'
      return
    }
    if (!isAccountConsentCurrent(status)) {
      authGate.value = 'consent'
      return
    }
    pendingConsentSession = null
    authGate.value = 'none'
    if (loadData) await store.loadData()
  } catch (error) {
    if (!isCurrentConsentAttempt(generation, userId)) return
    authGate.value = 'consent-error'
    consentError.value = accountConsentError(error)
  }
}

async function acceptAccountConsent() {
  if (!pendingConsentSession || consentSubmitting.value || consentBlocked.value) return
  const session = pendingConsentSession
  const userId = session.user.id
  const generation = sessionApplyGeneration
  consentSubmitting.value = true
  consentError.value = ''
  try {
    if (!await reconcileConsentSession(userId)) return
    await acceptCurrentAccountConsent(sb)
    if (!await reconcileConsentSession(userId)) return
    if (!isCurrentConsentAttempt(generation, userId)) return
    pendingConsentSession = null
    authGate.value = 'none'
    store.navigateTo('home')
    await store.loadData()
  } catch (error) {
    if (!isCurrentConsentAttempt(generation, userId)) return
    authGate.value = 'consent-error'
    consentError.value = accountConsentError(error)
  } finally {
    consentSubmitting.value = false
  }
}

async function retryAccountConsent() {
  if (consentSubmitting.value) return
  const { data, error } = await sb.auth.getSession()
  if (error) {
    consentError.value = accountConsentError(error)
    return
  }
  const session = data?.session || null
  if (!session) {
    handleSignedOut()
    return
  }
  if (!isSameSessionUser(session, store.currentUserId.value)) {
    await applySession(session)
    return
  }
  await verifyAccountConsent(session)
}

async function signOutLocally() {
  try {
    const { error } = await sb.auth.signOut({ scope: 'local' })
    if (error) {
      console.warn('[auth] local sign-out failed; clearing application state', {
        code: error.code || error.name || 'unknown',
      })
    }
  } catch (error) {
    console.warn('[auth] local sign-out failed; clearing application state', {
      code: error?.code || error?.name || 'unknown',
    })
  } finally {
    handleSignedOut()
  }
}

async function signOutFromConsentGate() {
  if (consentDeleting.value) return
  sessionApplyGeneration += 1
  pendingConsentSession = null
  await signOutLocally()
}

async function deleteAccountFromConsentGate() {
  if (consentDeleting.value || consentSubmitting.value) return
  consentDeleting.value = true
  consentError.value = ''
  try {
    const result = await requestAccountDeletion({
      client: sb,
      functionUrl: `${SUPABASE_URL}/functions/v1/ingest-receipt`,
      anonKey: SUPABASE_ANON_KEY,
    })
    saveAccountDeletionReceipt(result)
    sessionApplyGeneration += 1
    pendingConsentSession = null
    await signOutLocally()
  } catch (error) {
    consentError.value = error?.message || '账户删除请求失败，请稍后重试'
    authGate.value = 'consent-error'
  } finally {
    consentDeleting.value = false
  }
}

function accountConsentError(error) {
  const value = String(error?.message || error || '').toLowerCase()
  if (
    value.includes('failed to fetch')
      || value.includes('network')
      || value.includes('timeout')
  ) return '网络连接不稳定，尚未加载你的记录。请检查网络后重试'
  if (value.includes('outdated') || value.includes('check_violation')) {
    return '协议版本已更新，请重新核对后确认'
  }
  return '暂时无法核对账号同意状态。你的记录尚未加载，请稍后重试'
}

function handleSignedOut() {
  sessionApplyGeneration += 1
  pendingConsentSession = null
  consentSubmitting.value = false
  consentDeleting.value = false
  consentBlocked.value = false
  consentError.value = ''
  if (authGate.value.startsWith('consent')) authGate.value = 'none'
  store.resetUserData()
  store.currentUserId.value = null
  store.currentUserEmail.value = ''
  store.isLoggedIn.value = false
  store.navigateTo('home')
}

function completePasswordRecovery() {
  authGate.value = 'none'
  callbackIntent.value = null
  authCallbackError.value = ''
  handleSignedOut()
  clearAuthCallbackURL()
  if (callbackTimeout) {
    window.clearTimeout(callbackTimeout)
    callbackTimeout = null
  }
}

async function dismissAuthCallback() {
  await sb.auth.signOut({ scope: 'local' }).catch(() => {})
  authGate.value = 'none'
  callbackIntent.value = null
  authCallbackError.value = ''
  authCallbackNotice.value = ''
  handleSignedOut()
  clearAuthCallbackURL()
  if (callbackTimeout) {
    window.clearTimeout(callbackTimeout)
    callbackTimeout = null
  }
}

function clearAuthCallbackURL() {
  const path = sanitizedAuthCallbackPath(window.location.href)
  window.history.replaceState({}, document.title, path)
}

async function completeConfirmation() {
  if (confirmationCompleting) return
  confirmationCompleting = true
  try {
    const { error } = await sb.auth.signOut({ scope: 'local' })
    if (error) throw error
  } catch (error) {
    console.warn('[auth] confirmation callback local sign-out failed', {
      code: error?.code || error?.name || 'unknown',
    })
  }
  handleSignedOut()
  authGate.value = 'confirmation-notice'
  authCallbackNotice.value = '邮箱已确认'
  callbackIntent.value = null
  clearAuthCallbackURL()
  if (callbackTimeout) {
    window.clearTimeout(callbackTimeout)
    callbackTimeout = null
  }
  confirmationCompleting = false
}

// 下拉刷新（全局生效，仅在页面滚到顶才会触发）
const { pullDistance, refreshing, ptrActive } = usePullToRefresh({
  onRefresh: async () => {
    if (!canLoadBusinessData(store.isLoggedIn.value, authGate.value)) return
    // 静默刷新不显示全屏 loading，配合下拉指示器即可
    await store.loadData(0, true)
  },
  threshold: 60,
  maxPull: 100,
})

const ptrStyle = computed(() => ({
  transform: `translateY(${pullDistance.value}px)`,
  opacity: Math.min(pullDistance.value / 60, 1),
}))

const ptrReady = computed(() => pullDistance.value >= 60)

function openFabAction(action) {
  action()
  fabOpen.value = false
}

// 后台切回前台时静默刷新：命中快捷指令上传 → 切回 PWA 的核心动线
function handleVisibilityChange() {
  if (document.visibilityState === 'visible' && authGate.value === 'none') {
    store.refreshIfStale()
  }
}
function handleWindowFocus() {
  // 兜底：部分浏览器在 tab 切换时 visibilitychange 不可靠
  if (authGate.value === 'none') store.refreshIfStale()
}

onMounted(async () => {
  if (authCallbackPending.value) {
    callbackTimeout = window.setTimeout(() => {
      if (!authCallbackPending.value) return
      authGate.value = `${callbackIntent.value}-error`
      authCallbackError.value = callbackIntent.value === 'recovery'
        ? '重置链接验证超时，请重新发送'
        : callbackIntent.value === 'confirmation'
          ? '邮箱确认验证超时，请重新发送确认邮件'
          : '安全链接验证超时，请重新发送'
    }, 15000)
  }

  // 先订阅，再读取 session，避免恢复/确认回跳事件在冷启动时丢失。
  const { data: authData } = sb.auth.onAuthStateChange((event, session) => {
    if (event === 'PASSWORD_RECOVERY') {
      callbackIntent.value = 'recovery'
      authGate.value = 'recovery'
      authCallbackError.value = ''
      store.resetUserData()
      store.isLoggedIn.value = false
      return
    }
    if (
      ['confirmation', 'unknown'].includes(callbackIntent.value)
      && authGate.value.endsWith('-pending')
      && event === 'SIGNED_IN'
      && session
    ) {
      window.setTimeout(() => void completeConfirmation(), 0)
      return
    }
    if (event === 'SIGNED_OUT') {
      handleSignedOut()
    } else if (session) {
      window.setTimeout(() => void applySession(session), 0)
    }
  })
  authSubscription = authData?.subscription || null

  try {
    const { data, error } = await sb.auth.getSession()
    if (error) throw error
    if (authGate.value === 'none') {
      await applySession(data?.session)
    }
  } catch (error) {
    if (authGate.value.endsWith('-pending')) {
      authGate.value = `${callbackIntent.value}-error`
      const context = callbackIntent.value === 'recovery'
        ? 'recovery'
        : callbackIntent.value === 'confirmation'
          ? 'confirmation'
          : 'default'
      authCallbackError.value = friendlyAuthError(error, context)
    }
  }

  document.addEventListener('visibilitychange', handleVisibilityChange)
  window.addEventListener('focus', handleWindowFocus)
})

onBeforeUnmount(() => {
  if (callbackTimeout) window.clearTimeout(callbackTimeout)
  authSubscription?.unsubscribe()
  document.removeEventListener('visibilitychange', handleVisibilityChange)
  window.removeEventListener('focus', handleWindowFocus)
})
</script>
