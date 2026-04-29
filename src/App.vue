<template>
  <div>
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
      <div class="fab-item" @click="store.showFlash('手动新增支出开发中'); fabOpen = false">💸 添加支出</div>
    </div>
    <button class="fab" @click="fabOpen = !fabOpen">+</button>

    <!-- Modals -->
    <ModalPending />
    <ModalIncome />

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

const store = useStore()
provide('store', store)

const fabOpen = ref(false)

onMounted(async () => {
  await store.loadData()
})
</script>
