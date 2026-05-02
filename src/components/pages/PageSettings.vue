<template>
  <div class="page active">
    <div class="page-title">设置</div>

    <div class="settings-profile">
      <div class="settings-avatar">数</div>
      <div class="settings-profile-info">
        <div class="settings-profile-name">{{ userEmail }}</div>
        <div class="settings-profile-plan">{{ planLabel }} · 已登录</div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">账户</div>
      <div class="settings-item" v-if="uploadToken" @click="copyToken">
        <div class="settings-item-icon success">钥</div>
        <div class="settings-item-content">
          <div class="settings-item-title">上传 Token（点击复制）</div>
          <div class="settings-item-sub" style="word-break:break-all;font-size:11px;">{{ uploadToken }}</div>
        </div>
      </div>
      <div class="settings-item" @click="handleLogout">
        <div class="settings-item-icon warn">出</div>
        <div class="settings-item-content">
          <div class="settings-item-title">退出登录</div>
          <div class="settings-item-sub">切换账号或退出</div>
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">数据管理</div>
      <div class="settings-item" @click="store.showFlash('导入能力将在平台阶段逐步接入')">
        <div class="settings-item-icon info">入</div>
        <div class="settings-item-content">
          <div class="settings-item-title">数据导入</div>
          <div class="settings-item-sub">CSV 与其他来源的历史数据导入</div>
        </div>
        <div class="settings-arrow">›</div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">隐私与留存</div>
      <div class="settings-item">
        <div class="settings-item-icon warn">志</div>
        <div class="settings-item-content">
          <div class="settings-item-title">AI 日志记录</div>
          <div class="settings-item-sub">保留识别摘要，便于排查与迭代 Prompt</div>
        </div>
        <div class="settings-toggle" :class="{ active: store.settingsState.aiLogsEnabled }" @click.stop="store.toggleSetting('aiLogsEnabled')">
          <div class="toggle-knob"></div>
        </div>
      </div>
      <div class="settings-item">
        <div class="settings-item-icon info">图</div>
        <div class="settings-item-content">
          <div class="settings-item-title">原图保留</div>
          <div class="settings-item-sub">默认保留截图原图，便于回溯与重新识别</div>
        </div>
        <div class="settings-toggle" :class="{ active: store.settingsState.keepSourceImages }" @click.stop="store.toggleSetting('keepSourceImages')">
          <div class="toggle-knob"></div>
        </div>
      </div>
      <div class="settings-item" @click="store.showFlash('当前为 Supabase 新加坡节点')">
        <div class="settings-item-icon primary">云</div>
        <div class="settings-item-content">
          <div class="settings-item-title">数据存储</div>
          <div class="settings-item-sub">Supabase 新加坡节点 · 后续可按商业化规划迁移</div>
        </div>
        <div class="settings-arrow">›</div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">关于平台</div>
      <div class="settings-item">
        <div class="settings-item-icon primary">版</div>
        <div class="settings-item-content">
          <div class="settings-item-title">当前版本</div>
          <div class="settings-item-sub">V0.2 平台骨架阶段</div>
        </div>
      </div>
      <div class="settings-item" @click="store.showFlash('商业化权益页稍后接入')">
        <div class="settings-item-icon warn">升</div>
        <div class="settings-item-content">
          <div class="settings-item-title">升级到 Pro</div>
          <div class="settings-item-sub">查看平台化后的高级分析与模板能力</div>
        </div>
        <div class="settings-arrow">›</div>
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { ref, inject, onMounted } from 'vue'
import { sb } from '../../lib/supabase'

const store = inject('store')
const uploadToken = ref('')
const userEmail = ref('')

onMounted(async () => {
  const { data: authData } = await sb.auth.getUser()
  if (authData?.user) {
    userEmail.value = authData.user.email || '内测用户'
  }
  if (store.currentUserId.value) {
    const { data: cfg } = await sb.from('user_configs')
      .select('upload_token, plan')
      .eq('user_id', store.currentUserId.value)
      .maybeSingle()
    if (cfg) {
      uploadToken.value = cfg.upload_token || ''
    }
  }
})

const planLabel = ref('种子用户')

function copyToken() {
  if (!uploadToken.value) return
  navigator.clipboard?.writeText(uploadToken.value)
    .then(() => store.showFlash('✓ Token 已复制到剪贴板'))
    .catch(() => store.showFlash('⚠ 复制失败，请手动选择'))
}

async function handleLogout() {
  await sb.auth.signOut()
  store.currentUserId.value = null
  store.isLoggedIn.value = false
  store.showFlash('✓ 已退出登录')
}
</script>
