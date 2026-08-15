const VISION_PROVIDERS = new Set(['auto', 'qwen'])
const QWEN_MODELS = new Set(['qwen3.6-flash', 'qwen3.7-plus'])
const INSIGHT_PROVIDERS = new Set(['auto', 'qwen'])
const COMPANION_PERSONAS = new Set(['observer', 'warm', 'sharp', 'minimal'])
const MEMORY_STRENGTHS = new Set(['light', 'balanced', 'bold'])
const EXPRESSION_STYLES = new Set(['plain', 'emoji', 'kaomoji'])
const RETENTION_DAYS = new Set([-1, 7, 30])

export const SETTINGS_FIELD_MAP = Object.freeze({
  aiLogsEnabled: 'ai_logs_enabled',
  keepSourceImages: 'keep_source_images',
  promptOptimizationEnabled: 'prompt_optimization_enabled',
  expressionImprovementEnabled: 'expression_improvement_enabled',
  imageRetentionDays: 'image_retention_days',
  companionEnabled: 'companion_enabled',
  companionMemoryEnabled: 'companion_memory_enabled',
  visionPrimary: 'vision_primary',
  screenshotVisionPrimary: 'screenshot_vision_primary',
  photoVisionPrimary: 'photo_vision_primary',
  qwenScreenshotModel: 'qwen_screenshot_model',
  qwenPhotoModel: 'qwen_photo_model',
  qwenScreenshotThinking: 'qwen_screenshot_enable_thinking',
  qwenPhotoThinking: 'qwen_photo_enable_thinking',
  aiInsightProvider: 'ai_insight_provider',
  companionPersona: 'companion_persona',
  companionMemoryStrength: 'companion_memory_strength',
  companionExpressionStyle: 'companion_expression_style',
  companionCustomNote: 'companion_custom_note',
})

export function createDefaultSettingsState() {
  return {
    aiLogsEnabled: false,
    keepSourceImages: true,
    promptOptimizationEnabled: false,
    expressionImprovementEnabled: false,
    imageRetentionDays: -1,
    companionEnabled: true,
    companionMemoryEnabled: true,
    uploadToken: '',
    plan: 'seed',
    visionPrimary: 'auto',
    screenshotVisionPrimary: 'auto',
    photoVisionPrimary: 'qwen',
    qwenScreenshotModel: 'qwen3.6-flash',
    qwenPhotoModel: 'qwen3.6-flash',
    qwenScreenshotThinking: false,
    qwenPhotoThinking: false,
    aiInsightProvider: 'auto',
    companionPersona: 'observer',
    companionMemoryStrength: 'balanced',
    companionExpressionStyle: 'plain',
    companionCustomNote: '',
    settingsLoading: false,
    settingsError: '',
    settingsLegacyMode: false,
  }
}

function allowed(value, values, fallback) {
  return values.has(value) ? value : fallback
}

function stringValue(value, fallback = '') {
  if (value === null || value === undefined) return fallback
  return String(value)
}

export function normalizeSettingsRow(row = {}, { legacy = false } = {}) {
  const defaults = createDefaultSettingsState()
  const visionPrimary = allowed(row.vision_primary, VISION_PROVIDERS, defaults.visionPrimary)
  return {
    ...defaults,
    aiLogsEnabled: row.ai_logs_enabled ?? defaults.aiLogsEnabled,
    keepSourceImages: row.keep_source_images ?? defaults.keepSourceImages,
    promptOptimizationEnabled: row.prompt_optimization_enabled ?? defaults.promptOptimizationEnabled,
    expressionImprovementEnabled: row.expression_improvement_enabled ?? defaults.expressionImprovementEnabled,
    imageRetentionDays: RETENTION_DAYS.has(row.image_retention_days)
      ? row.image_retention_days
      : defaults.imageRetentionDays,
    companionEnabled: row.companion_enabled ?? defaults.companionEnabled,
    companionMemoryEnabled: row.companion_memory_enabled ?? defaults.companionMemoryEnabled,
    uploadToken: stringValue(row.upload_token),
    plan: stringValue(row.plan, defaults.plan),
    visionPrimary,
    screenshotVisionPrimary: allowed(
      row.screenshot_vision_primary ?? visionPrimary,
      VISION_PROVIDERS,
      defaults.screenshotVisionPrimary,
    ),
    photoVisionPrimary: allowed(
      row.photo_vision_primary,
      VISION_PROVIDERS,
      defaults.photoVisionPrimary,
    ),
    qwenScreenshotModel: allowed(
      row.qwen_screenshot_model,
      QWEN_MODELS,
      defaults.qwenScreenshotModel,
    ),
    qwenPhotoModel: allowed(row.qwen_photo_model, QWEN_MODELS, defaults.qwenPhotoModel),
    qwenScreenshotThinking: row.qwen_screenshot_enable_thinking ?? defaults.qwenScreenshotThinking,
    qwenPhotoThinking: row.qwen_photo_enable_thinking ?? defaults.qwenPhotoThinking,
    aiInsightProvider: allowed(
      row.ai_insight_provider,
      INSIGHT_PROVIDERS,
      defaults.aiInsightProvider,
    ),
    companionPersona: allowed(row.companion_persona, COMPANION_PERSONAS, defaults.companionPersona),
    companionMemoryStrength: allowed(
      row.companion_memory_strength,
      MEMORY_STRENGTHS,
      defaults.companionMemoryStrength,
    ),
    companionExpressionStyle: allowed(
      row.companion_expression_style,
      EXPRESSION_STYLES,
      defaults.companionExpressionStyle,
    ),
    companionCustomNote: stringValue(row.companion_custom_note),
    settingsLegacyMode: legacy,
  }
}

function normalizeClientValue(key, value) {
  const defaults = createDefaultSettingsState()
  switch (key) {
    case 'aiLogsEnabled':
    case 'keepSourceImages':
    case 'promptOptimizationEnabled':
    case 'expressionImprovementEnabled':
    case 'companionEnabled':
    case 'companionMemoryEnabled':
    case 'qwenScreenshotThinking':
    case 'qwenPhotoThinking':
      return Boolean(value)
    case 'imageRetentionDays':
      if (!RETENTION_DAYS.has(value)) throw new Error('不允许更新配置字段：imageRetentionDays')
      return value
    case 'visionPrimary':
    case 'screenshotVisionPrimary':
      return allowed(value, VISION_PROVIDERS, defaults.screenshotVisionPrimary)
    case 'photoVisionPrimary':
      return allowed(value, VISION_PROVIDERS, defaults.photoVisionPrimary)
    case 'qwenScreenshotModel':
      return allowed(value, QWEN_MODELS, defaults.qwenScreenshotModel)
    case 'qwenPhotoModel':
      return allowed(value, QWEN_MODELS, defaults.qwenPhotoModel)
    case 'aiInsightProvider':
      return allowed(value, INSIGHT_PROVIDERS, defaults.aiInsightProvider)
    case 'companionPersona':
      return allowed(value, COMPANION_PERSONAS, defaults.companionPersona)
    case 'companionMemoryStrength':
      return allowed(value, MEMORY_STRENGTHS, defaults.companionMemoryStrength)
    case 'companionExpressionStyle':
      return allowed(value, EXPRESSION_STYLES, defaults.companionExpressionStyle)
    case 'companionCustomNote':
      return stringValue(value).trim().slice(0, 80)
    default:
      throw new Error(`不允许更新配置字段：${key}`)
  }
}

export function prepareSettingsPatch(clientPatch) {
  if (!clientPatch || typeof clientPatch !== 'object' || Array.isArray(clientPatch)) {
    throw new Error('设置更新内容无效')
  }
  const statePatch = {}
  const databasePatch = {}
  for (const [key, value] of Object.entries(clientPatch)) {
    const column = SETTINGS_FIELD_MAP[key]
    if (!column) throw new Error(`不允许更新配置字段：${key}`)
    const normalized = normalizeClientValue(key, value)
    statePatch[key] = normalized
    databasePatch[column] = key === 'companionCustomNote' ? normalized || null : normalized
  }
  if (!Object.keys(statePatch).length) throw new Error('设置更新内容为空')
  return { statePatch, databasePatch }
}
