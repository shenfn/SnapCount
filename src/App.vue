<template>
  <div>
    <!-- Auth gate -->
    <AuthPage v-if="!store.isLoggedIn.value" />

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
import { sb } from './lib/supabase'
import { useStore } from './composables/useStore'
import { usePullToRefresh } from './composables/usePullToRefresh'
import AuthPage   from './components/pages/AuthPage.vue'
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

const fabOpen = ref(false)

// 登录态：以 supabase 的 auth 事件为唯一真相源，避免冷启动时
// getSession() 还未完成本地恢复就进入未登录态，或 AuthPage / App
// 同时各调一次 loadData() 产生竞态。
async function applySession(session) {
  if (!session?.user) return
  const sameUser = store.isLoggedIn.value && store.currentUserId.value === session.user.id
  store.currentUserId.value = session.user.id
  store.currentUserEmail.value = session.user.email || ''
  store.isLoggedIn.value = true
  if (!sameUser) {
    store.navigateTo('home')
    await store.loadData()
  }
}

function handleSignedOut() {
  store.resetUserData()
  store.currentUserId.value = null
  store.currentUserEmail.value = ''
  store.isLoggedIn.value = false
  store.navigateTo('home')
}

// 下拉刷新（全局生效，仅在页面滚到顶才会触发）
const { pullDistance, refreshing, ptrActive } = usePullToRefresh({
  onRefresh: async () => {
    if (!store.isLoggedIn.value) return
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
  if (document.visibilityState === 'visible') {
    store.refreshIfStale()
  }
}
function handleWindowFocus() {
  // 兜底：部分浏览器在 tab 切换时 visibilitychange 不可靠
  store.refreshIfStale()
}

onMounted(async () => {
  // 先同步读一次作为快速路径（热启动 / session 已恢复的场景）
  const { data } = await sb.auth.getSession()
  await applySession(data?.session)

  // 订阅后续变化：INITIAL_SESSION（冷启动恢复）/ SIGNED_IN /
  // TOKEN_REFRESHED / SIGNED_OUT 都会走这里
  sb.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT') {
      handleSignedOut()
    } else if (session) {
      applySession(session)
    }
  })

  document.addEventListener('visibilitychange', handleVisibilityChange)
  window.addEventListener('focus', handleWindowFocus)
})

onBeforeUnmount(() => {
  document.removeEventListener('visibilitychange', handleVisibilityChange)
  window.removeEventListener('focus', handleWindowFocus)
})
</script>
