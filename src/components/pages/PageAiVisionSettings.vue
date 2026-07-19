<template>
  <div class="page active ai-vision-page">
    <div class="settings-detail-header">
      <button type="button" class="settings-back-btn" @click="store.goBack()">‹</button>
      <div>
        <div class="page-title compact">识别模型配置</div>
        <div class="settings-detail-sub">截图保持快速，拍照优先质量</div>
      </div>
    </div>

    <div class="vision-overview">
      <div class="vision-overview-item">
        <span>截图</span>
        <strong>{{ routeSummary('screenshot') }}</strong>
      </div>
      <div class="vision-overview-divider"></div>
      <div class="vision-overview-item">
        <span>拍照</span>
        <strong>{{ routeSummary('photo') }}</strong>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">链路调度</div>
      <div
        v-for="route in routeSections"
        :key="route.key"
        class="vision-route-block"
      >
        <div class="vision-route-head">
          <div>
            <div class="vision-route-title">{{ route.title }}</div>
            <div class="vision-route-desc">{{ route.desc }}</div>
          </div>
          <div class="vision-route-badge">{{ route.badge }}</div>
        </div>
        <div class="vision-provider-grid">
          <button
            v-for="opt in providerOptions"
            :key="`${route.key}-${opt.value}`"
            type="button"
            class="vision-provider-btn"
            :class="{ active: routeProvider(route.key) === opt.value }"
            @click="updateRouteProvider(route.key, opt.value)"
          >
            <span>{{ opt.iconText }}</span>
            <strong>{{ opt.label }}</strong>
          </button>
        </div>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">Qwen 参数</div>
      <div class="vision-model-row">
        <div class="vision-model-copy">
          <div class="settings-item-title">截图模型</div>
          <div class="settings-item-sub">默认 3.6 Flash，也可以切到 3.7 Plus 追求质量。</div>
        </div>
      </div>
      <div class="vision-preset-row">
        <button
          v-for="preset in qwenModelPresets"
          :key="`screenshot-${preset.value}`"
          type="button"
          class="vision-preset-btn"
          :class="{ active: qwenScreenshotModel === preset.value }"
          @click="setQwenModel('screenshot', preset.value)"
        >
          <strong>{{ preset.label }}</strong>
          <span>{{ preset.desc }}</span>
        </button>
      </div>
      <div class="vision-toggle-row">
        <div>
          <div class="settings-item-title">截图思考模式</div>
          <div class="settings-item-sub">关闭可减少识别耗时。</div>
        </div>
        <button
          type="button"
          class="settings-toggle"
          :class="{ active: qwenScreenshotThinking }"
          @click="updateQwenThinking('screenshot', !qwenScreenshotThinking)"
        >
          <div class="toggle-knob"></div>
        </button>
      </div>

      <div class="vision-model-row">
        <div class="vision-model-copy">
          <div class="settings-item-title">拍照模型</div>
          <div class="settings-item-sub">默认 3.6 Flash；需要更细识别时可切换 3.7 Plus。</div>
        </div>
      </div>
      <div class="vision-preset-row">
        <button
          v-for="preset in qwenModelPresets"
          :key="`photo-${preset.value}`"
          type="button"
          class="vision-preset-btn"
          :class="{ active: qwenPhotoModel === preset.value }"
          @click="setQwenModel('photo', preset.value)"
        >
          <strong>{{ preset.label }}</strong>
          <span>{{ preset.desc }}</span>
        </button>
      </div>
      <div class="vision-toggle-row">
        <div>
          <div class="settings-item-title">拍照思考模式</div>
          <div class="settings-item-sub">开启后更重质量，速度可能变慢。</div>
        </div>
        <button
          type="button"
          class="settings-toggle"
          :class="{ active: qwenPhotoThinking }"
          @click="updateQwenThinking('photo', !qwenPhotoThinking)"
        >
          <div class="toggle-knob"></div>
        </button>
      </div>
    </div>

    <div class="settings-section">
      <div class="settings-section-title">识别规则</div>
      <div class="vision-note">
        有 OCR 文本、账户、余额、支付、账单等特征时按截图链路走；明确传入拍照来源，或低成本路由判断为饮食照片时，按拍照链路走。
      </div>
    </div>

    <div class="spacer"></div>
  </div>
</template>

<script setup>
import { inject, onMounted, ref } from 'vue'
import { sb } from '../../lib/supabase'

const store = inject('store')

const screenshotVisionPrimary = ref('auto')
const photoVisionPrimary = ref('qwen')
const qwenScreenshotModel = ref('qwen3.6-flash')
const qwenPhotoModel = ref('qwen3.6-flash')
const qwenScreenshotThinking = ref(false)
const qwenPhotoThinking = ref(false)

const routeSections = [
  {
    key: 'screenshot',
    title: '截图识别',
    desc: '支付、收入、余额、账单和账户快照。',
    badge: '快速优先',
  },
  {
    key: 'photo',
    title: '拍照识别',
    desc: '餐盘、食物、真实世界照片。',
    badge: '质量优先',
  },
]

const providerOptions = [
  { value: 'auto', label: '自动', iconText: 'A' },
  { value: 'qwen', label: 'Qwen', iconText: 'Q' },
]

const qwenModelPresets = [
  { value: 'qwen3.6-flash', label: '3.6 Flash', desc: '速度优先' },
  { value: 'qwen3.7-plus', label: '3.7 Plus', desc: '质量优先' },
]

function isMissingConfigColumn(error) {
  const msg = `${error?.message || ''} ${error?.details || ''} ${error?.hint || ''}`
  return /screenshot_vision_primary|photo_vision_primary|qwen_screenshot|qwen_photo|schema cache|column/i.test(msg)
}

function configErrorMessage(error) {
  if (isMissingConfigColumn(error)) {
    return '数据库还没执行 060_split_vision_capture_settings.sql，暂时不能保存分链路模型配置'
  }
  return error?.message || '未知错误'
}

function providerLabel(value) {
  return providerOptions.find(item => item.value === value)?.label || value || '自动'
}

function normalizeProvider(value, fallback = 'auto') {
  return providerOptions.some(item => item.value === value) ? value : fallback
}

function normalizeQwenModel(value) {
  return qwenModelPresets.some(item => item.value === value) ? value : 'qwen3.6-flash'
}

function routeProvider(route) {
  return route === 'photo' ? photoVisionPrimary.value : screenshotVisionPrimary.value
}

function setRouteProvider(route, value) {
  if (route === 'photo') photoVisionPrimary.value = value
  else screenshotVisionPrimary.value = value
}

function routeSummary(route) {
  const provider = routeProvider(route)
  if (provider === 'qwen') {
    return `${providerLabel(provider)} · ${route === 'photo' ? qwenPhotoModel.value : qwenScreenshotModel.value}`
  }
  return providerLabel(provider)
}

async function updateUserConfig(patch, successMessage) {
  if (!store.currentUserId.value) {
    store.showFlash('请先登录')
    return false
  }
  const { error } = await sb.from('user_configs')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('user_id', store.currentUserId.value)
  if (error) {
    store.showFlash('⚠ 切换失败：' + configErrorMessage(error))
    return false
  }
  if (successMessage) store.showFlash(successMessage)
  return true
}

async function updateRouteProvider(route, value) {
  if (routeProvider(route) === value) return
  const prev = routeProvider(route)
  setRouteProvider(route, value)
  const patch = route === 'photo'
    ? { photo_vision_primary: value }
    : { screenshot_vision_primary: value, vision_primary: value }
  const ok = await updateUserConfig(patch, `✓ ${route === 'photo' ? '拍照' : '截图'}链路已切换到「${providerLabel(value)}」`)
  if (!ok) setRouteProvider(route, prev)
}

async function setQwenModel(route, model) {
  const isPhoto = route === 'photo'
  const prev = isPhoto ? qwenPhotoModel.value : qwenScreenshotModel.value
  if (prev === model) return
  if (isPhoto) qwenPhotoModel.value = model
  else qwenScreenshotModel.value = model
  const patch = isPhoto
    ? { qwen_photo_model: model }
    : { qwen_screenshot_model: model }
  const ok = await updateUserConfig(patch, `✓ ${isPhoto ? '拍照' : '截图'}模型已切换到「${model}」`)
  if (!ok) {
    if (isPhoto) qwenPhotoModel.value = prev
    else qwenScreenshotModel.value = prev
  }
}

async function updateQwenThinking(route, value) {
  const isPhoto = route === 'photo'
  const prev = isPhoto ? qwenPhotoThinking.value : qwenScreenshotThinking.value
  if (isPhoto) qwenPhotoThinking.value = value
  else qwenScreenshotThinking.value = value

  const patch = isPhoto
    ? { qwen_photo_enable_thinking: value }
    : { qwen_screenshot_enable_thinking: value }
  const ok = await updateUserConfig(patch, `✓ ${isPhoto ? '拍照' : '截图'}思考模式已${value ? '开启' : '关闭'}`)
  if (!ok) {
    if (isPhoto) qwenPhotoThinking.value = prev
    else qwenScreenshotThinking.value = prev
  }
}

onMounted(async () => {
  if (!store.currentUserId.value) return
  const { data, error } = await sb.from('user_configs')
    .select('vision_primary, screenshot_vision_primary, photo_vision_primary, qwen_screenshot_model, qwen_photo_model, qwen_screenshot_enable_thinking, qwen_photo_enable_thinking')
    .eq('user_id', store.currentUserId.value)
    .maybeSingle()
  if (error) {
    if (isMissingConfigColumn(error)) {
      const { data: legacy } = await sb.from('user_configs')
        .select('vision_primary')
        .eq('user_id', store.currentUserId.value)
        .maybeSingle()
      screenshotVisionPrimary.value = normalizeProvider(legacy?.vision_primary)
      photoVisionPrimary.value = 'qwen'
      store.showFlash('⚠ 需要先执行数据库迁移 060，才能保存分链路配置')
      return
    }
    store.showFlash('⚠ 配置加载失败：' + configErrorMessage(error))
    return
  }
  screenshotVisionPrimary.value = normalizeProvider(data?.screenshot_vision_primary || data?.vision_primary)
  photoVisionPrimary.value = normalizeProvider(data?.photo_vision_primary, 'qwen')
  qwenScreenshotModel.value = normalizeQwenModel(data?.qwen_screenshot_model)
  qwenPhotoModel.value = normalizeQwenModel(data?.qwen_photo_model)
  qwenScreenshotThinking.value = data?.qwen_screenshot_enable_thinking ?? false
  qwenPhotoThinking.value = data?.qwen_photo_enable_thinking ?? false
})
</script>
