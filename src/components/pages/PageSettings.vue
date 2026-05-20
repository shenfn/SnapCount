<template>
  <div class="page active">
    <div class="page-title">设置</div>

    <div class="settings-profile">
      <div class="settings-avatar">设</div>
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
        <div class="settings-item-icon warn">退</div>
        <div class="settings-item-content">
          <div class="settings-item-title">退出登录</div>
          <div class="settings-item-sub">切换账号或退出当前会话</div>
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">数据管理</div>
      <div class="settings-item" @click="store.showFlash('导入能力会在后续版本逐步接入')">
        <div class="settings-item-icon info">导</div>
        <div class="settings-item-content">
          <div class="settings-item-title">数据导入</div>
          <div class="settings-item-sub">CSV 与其他来源的历史数据导入</div>
        </div>
        <div class="settings-arrow">›</div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">AI 识别引擎</div>
      <div class="settings-item-sub" style="padding:0 16px 8px;color:#6b7280;font-size:12px;">
        选择截图或拍照识别使用的视觉模型，设置后立即生效。
      </div>
      <div
        v-for="opt in visionOptions"
        :key="opt.value"
        class="settings-item"
        @click="updateVisionPrimary(opt.value)"
      >
        <div class="settings-item-icon" :class="opt.toneClass">{{ opt.iconText }}</div>
        <div class="settings-item-content">
          <div class="settings-item-title">{{ opt.label }}</div>
          <div class="settings-item-sub">{{ opt.desc }}</div>
        </div>
        <div
          class="settings-arrow"
          :style="{ color: visionPrimary === opt.value ? '#10b981' : '#d1d5db', fontSize: '20px', fontWeight: 'bold' }"
        >
          {{ visionPrimary === opt.value ? '✓' : '○' }}
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">AI 联动分析</div>
      <div class="settings-item-sub" style="padding:0 16px 8px;color:#6b7280;font-size:12px;">
        仅影响“联动分析 / AI 解读”模块，不影响截图识别。可以按速度或思考深度切换。
      </div>
      <div
        v-for="opt in insightModelOptions"
        :key="opt.value"
        class="settings-item"
        @click="updateAiInsightProvider(opt.value)"
      >
        <div class="settings-item-icon" :class="opt.toneClass">{{ opt.iconText }}</div>
        <div class="settings-item-content">
          <div class="settings-item-title">{{ opt.label }}</div>
          <div class="settings-item-sub">{{ opt.desc }}</div>
        </div>
        <div
          class="settings-arrow"
          :style="{ color: aiInsightProvider === opt.value ? '#10b981' : '#d1d5db', fontSize: '20px', fontWeight: 'bold' }"
        >
          {{ aiInsightProvider === opt.value ? '✓' : '○' }}
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">隐私与留存</div>
      <div class="settings-item">
        <div class="settings-item-icon warn">志</div>
        <div class="settings-item-content">
          <div class="settings-item-title">AI 日志记录</div>
          <div class="settings-item-sub">保留识别摘要，便于排查问题与优化 Prompt</div>
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
      <div class="settings-item" @click="store.showFlash('当前使用 Supabase 新加坡节点')">
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
          <div class="settings-item-sub">V0.2 平台框架阶段</div>
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
const visionPrimary = ref('auto')
const aiInsightProvider = ref('auto')

const visionOptions = [
  {
    value: 'auto',
    label: '自动（推荐）',
    desc: '平台自动调度，速度与稳定性更均衡，异常时会自动降级。',
    iconText: 'A',
    toneClass: 'primary',
  },
  {
    value: 'qwen',
    label: '阿里云通义千问 Vision',
    desc: '当前偏快的视觉方案，适合大多数截图识别。',
    iconText: 'Q',
    toneClass: 'success',
  },
  {
    value: 'moonshot',
    label: 'Moonshot Kimi',
    desc: '财务场景验证较充分，速度中等。',
    iconText: 'K',
    toneClass: 'info',
  },
  {
    value: 'mimo',
    label: '小米 MiMo（实验）',
    desc: '多模态试验中，速度较慢，准确率待继续验证。',
    iconText: 'M',
    toneClass: 'warn',
  },
  {
    value: 'relay',
    label: '自建中转站 Vision',
    desc: '走自建 OpenAI 兼容网关，适合对比速度与识图效果。',
    iconText: 'R',
    toneClass: 'info',
  },
]

const insightModelOptions = [
  {
    value: 'auto',
    label: '自动（推荐）',
    desc: '跟随后端默认分析模型，速度通常更稳。',
    iconText: 'A',
    toneClass: 'primary',
  },
  {
    value: 'moonshot',
    label: 'Moonshot 分析',
    desc: '当前稳定方案，整体响应通常更快。',
    iconText: 'K',
    toneClass: 'success',
  },
  {
    value: 'relay',
    label: '自建中转站分析',
    desc: '使用自建 OpenAI 兼容模型，适合追求更深一层的分析。',
    iconText: 'R',
    toneClass: 'warn',
  },
]

onMounted(async () => {
  if (store.currentUserId.value) {
    const { data: cfg } = await sb.from('user_configs')
      .select('upload_token, plan, vision_primary, ai_insight_provider')
      .eq('user_id', store.currentUserId.value)
      .maybeSingle()
    if (cfg) {
      uploadToken.value = cfg.upload_token || ''
      visionPrimary.value = cfg.vision_primary || 'auto'
      aiInsightProvider.value = cfg.ai_insight_provider || 'auto'
    }
  }
})

async function updateVisionPrimary(value) {
  if (visionPrimary.value === value) return
  if (!store.currentUserId.value) {
    store.showFlash('请先登录')
    return
  }
  const prev = visionPrimary.value
  visionPrimary.value = value
  const { error } = await sb.from('user_configs')
    .update({ vision_primary: value, updated_at: new Date().toISOString() })
    .eq('user_id', store.currentUserId.value)
  if (error) {
    visionPrimary.value = prev
    store.showFlash('⚠️ 切换失败：' + error.message)
    return
  }
  const opt = visionOptions.find(o => o.value === value)
  store.showFlash(`✓ 已切换到「${opt?.label || value}」`)
}

async function updateAiInsightProvider(value) {
  if (aiInsightProvider.value === value) return
  if (!store.currentUserId.value) {
    store.showFlash('请先登录')
    return
  }
  const prev = aiInsightProvider.value
  aiInsightProvider.value = value
  const { error } = await sb.from('user_configs')
    .update({ ai_insight_provider: value, updated_at: new Date().toISOString() })
    .eq('user_id', store.currentUserId.value)
  if (error) {
    aiInsightProvider.value = prev
    store.showFlash('⚠️ 切换失败：' + error.message)
    return
  }
  const opt = insightModelOptions.find(o => o.value === value)
  store.showFlash(`✓ AI 分析已切换到「${opt?.label || value}」`)
}

const userEmail = ref(store.currentUserEmail.value || '内测用户')
const planLabel = ref('种子用户')

function copyToken() {
  if (!uploadToken.value) return
  navigator.clipboard?.writeText(uploadToken.value)
    .then(() => store.showFlash('✓ Token 已复制到剪贴板'))
    .catch(() => store.showFlash('⚠️ 复制失败，请手动选择'))
}

async function handleLogout() {
  await sb.auth.signOut()
  store.showFlash('✓ 已退出登录')
}
</script>
