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
      <div class="platform-loader-mark">数</div>
      <div class="platform-loader-text">个人数据平台加载中…</div>
    </div>

    <!-- Error overlay -->
    <div v-if="!store.loading.value && store.loadError.value" class="platform-overlay error">
      <div class="platform-loader-mark danger">!</div>
      <div class="platform-loader-text">数据加载失败</div>
      <div class="platform-error-box">{{ store.loadError.value }}</div>
      <div class="platform-error-sub">请确认网络、Supabase 配置和数据库迁移状态。</div>
      <button class="platform-retry-btn" @click="store.loadData()">重新加载</button>
    </div>

    <!-- Pages -->
    <PageHome     v-show="store.currentPage.value === 'home'" />
    <PagePending  v-show="store.currentPage.value === 'pending'" />
    <PageDomains  v-show="store.currentPage.value === 'domains'" />
    <PageReport   v-show="store.currentPage.value === 'report'" />
    <PageSettings v-show="store.currentPage.value === 'settings'" />
    <PageDomainDetail v-show="store.currentPage.value === 'domain-detail'" />
    <PageAccountDetail v-show="store.currentPage.value === 'account-detail'" />
    <PageDayDetail v-show="store.currentPage.value === 'day-detail'" />
    <PageRecordDetail v-show="store.currentPage.value === 'record-detail'" />
    <PageInsights v-if="store.currentPage.value === 'insights'" />

    <!-- Bottom Nav -->
    <nav class="nav platform-nav">
      <div class="nav-item" :class="{ active: store.currentPage.value === 'home' }" @click="store.navigateTo('home')">
        <div class="nav-icon">◉</div><div>首页</div>
      </div>
      <div class="nav-item" :class="{ active: store.currentPage.value === 'pending' }" @click="store.navigateTo('pending')">
        <div class="nav-icon">◌</div><div>待处理</div>
      </div>
      <div class="nav-item" :class="{ active: store.currentPage.value === 'domains' }" @click="store.navigateTo('domains')">
        <div class="nav-icon">▣</div><div>数据域</div>
      </div>
      <div class="nav-item" :class="{ active: store.currentPage.value === 'report' }" @click="store.navigateTo('report')">
        <div class="nav-icon">◫</div><div>报告</div>
      </div>
      <div class="nav-item" :class="{ active: store.currentPage.value === 'settings' }" @click="store.navigateTo('settings')">
        <div class="nav-icon">⚙</div><div>设置</div>
      </div>
    </nav>

    <!-- FAB -->
    <div class="fab-overlay" :class="{ open: fabOpen }" @click="fabOpen = false"></div>
    <div class="fab-menu" :class="{ open: fabOpen }">
      <div class="fab-item" @click="store.navigateTo('domains'); store.showFlash('数据域创建入口将在阶段 3 接入'); fabOpen = false">🧩 新建数据域</div>
      <div class="fab-item" @click="store.openIncomeModal(); fabOpen = false">💰 添加收入</div>
      <div class="fab-item" @click="store.openExpenseModal(); fabOpen = false">💸 添加支出</div>
      <div class="fab-item" @click="store.openUniversalModal('sport'); fabOpen = false">🏃 添加运动</div>
      <div class="fab-item" @click="store.openUniversalModal('sleep'); fabOpen = false">🌙 添加睡眠</div>
      <div class="fab-item" @click="store.openUniversalModal('reading'); fabOpen = false">📚 添加阅读</div>
      <div class="fab-item" @click="store.openUniversalModal('wallet'); fabOpen = false">👛 添加钱包</div>
    </div>
    <button class="fab" @click="fabOpen = !fabOpen">+</button>

    <!-- Modals -->
    <ModalWelcome />
    <ModalPending />
    <ModalIncome />
    <ModalExpense />
    <ModalUniversal />
    <ModalAccount />

    <!-- Delete confirmation -->
    <div v-if="store.deleteConfirm.open"
      style="position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:9000;display:flex;align-items:center;justify-content:center;padding:24px;">
      <div style="background:#fff;border-radius:16px;width:100%;max-width:320px;padding:24px;text-align:center;">
        <div style="font-size:28px;margin-bottom:12px;">🗑</div>
        <div style="font-size:16px;font-weight:600;color:#1A1A18;margin-bottom:8px;">确认删除？</div>
        <div style="font-size:13px;color:#6B6A65;margin-bottom:24px;">此操作不可撤销，记录将永久删除</div>
        <div style="display:flex;gap:12px;">
          <button @click="store.closeDeleteConfirm()"
            style="flex:1;padding:12px;border-radius:10px;border:1.5px solid #E0E0E0;background:#fff;font-size:15px;cursor:pointer;font-family:'PingFang SC',system-ui,sans-serif;">
            取消
          </button>
          <button @click="store.confirmDelete()"
            style="flex:1;padding:12px;border-radius:10px;border:none;background:#B91C1C;color:#fff;font-size:15px;font-weight:600;cursor:pointer;font-family:'PingFang SC',system-ui,sans-serif;">
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
import PageDomainDetail from './components/pages/PageDomainDetail.vue'
import PageAccountDetail from './components/pages/PageAccountDetail.vue'
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
