<template>
  <div>
    <!-- Loading overlay -->
    <div v-if="store.loading.value" style="position:fixed;inset:0;background:#F7F6F3;z-index:999;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;">
      <div style="font-size:40px">💰</div>
      <div style="font-size:15px;color:#6B6A65;font-family:'PingFang SC',system-ui,sans-serif">加载中…</div>
    </div>

    <!-- Error overlay -->
    <div v-if="!store.loading.value && store.loadError.value" style="position:fixed;inset:0;background:#F7F6F3;z-index:999;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;padding:32px;text-align:center;overflow-y:auto;">
      <div style="font-size:40px">⚠️</div>
      <div style="font-size:15px;color:#1A1A18;font-family:'PingFang SC',system-ui,sans-serif;font-weight:600">数据加载失败</div>
      <div style="font-size:12px;color:#B91C1C;background:#FEE2E2;border-radius:8px;padding:12px 16px;word-break:break-all;max-width:340px;text-align:left;">{{ store.loadError.value }}</div>
      <div style="font-size:11px;color:#6B6A65;">Supabase URL 是否正确？网络是否正常？</div>
      <button @click="store.loadData()" style="padding:12px 24px;background:#2D6A4F;color:#fff;border:none;border-radius:12px;font-size:15px;cursor:pointer;font-family:'PingFang SC',system-ui,sans-serif">重试</button>
      <a :href="'?debug=1'" style="font-size:12px;color:#2D6A4F;">开启调试控制台</a>
    </div>

    <!-- Pages -->
    <PageHome     v-show="store.currentPage.value === 'home'" />
    <PagePending  v-show="store.currentPage.value === 'pending'" />
    <PageBills    v-show="store.currentPage.value === 'bills'" />
    <PageIncome   v-show="store.currentPage.value === 'income'" />
    <PageReport   v-show="store.currentPage.value === 'report'" />

    <!-- Bottom Nav -->
    <nav class="nav">
      <div class="nav-item" :class="{ active: store.currentPage.value === 'home' }" @click="store.currentPage.value = 'home'">
        <div class="nav-icon">⊙</div><div>首页</div>
      </div>
      <div class="nav-item" :class="{ active: store.currentPage.value === 'pending' }" @click="store.currentPage.value = 'pending'">
        <div class="nav-icon">◎</div><div>待补充</div>
      </div>
      <div class="nav-item" :class="{ active: store.currentPage.value === 'bills' }" @click="store.currentPage.value = 'bills'">
        <div class="nav-icon">☰</div><div>账单</div>
      </div>
      <div class="nav-item" :class="{ active: store.currentPage.value === 'income' }" @click="store.currentPage.value = 'income'">
        <div class="nav-icon">💰</div><div>收入</div>
      </div>
      <div class="nav-item" :class="{ active: store.currentPage.value === 'report' }" @click="store.currentPage.value = 'report'">
        <div class="nav-icon">◈</div><div>报告</div>
      </div>
    </nav>

    <!-- FAB -->
    <div class="fab-overlay" :class="{ open: fabOpen }" @click="fabOpen = false"></div>
    <div class="fab-menu" :class="{ open: fabOpen }">
      <div class="fab-item" @click="store.openIncomeModal(); fabOpen = false">💰 添加收入</div>
      <div class="fab-item" @click="store.openExpenseModal(); fabOpen = false">💸 添加支出</div>
    </div>
    <button class="fab" @click="fabOpen = !fabOpen">+</button>

    <!-- Modals -->
    <ModalPending />
    <ModalIncome />
    <ModalExpense />

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
  </div>
</template>

<script setup>
import { ref, provide, onMounted } from 'vue'
import { useStore } from './composables/useStore'
import PageHome    from './components/pages/PageHome.vue'
import PagePending from './components/pages/PagePending.vue'
import PageBills   from './components/pages/PageBills.vue'
import PageIncome  from './components/pages/PageIncome.vue'
import PageReport  from './components/pages/PageReport.vue'
import ModalPending from './components/ModalPending.vue'
import ModalIncome  from './components/ModalIncome.vue'
import ModalExpense from './components/ModalExpense.vue'

const store = useStore()
provide('store', store)

const fabOpen = ref(false)

onMounted(async () => {
  await store.loadData()
})
</script>
