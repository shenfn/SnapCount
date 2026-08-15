const MODERN_FIELDS = [
  'ai_logs_enabled',
  'keep_source_images',
  'prompt_optimization_enabled',
  'expression_improvement_enabled',
  'image_retention_days',
  'companion_enabled',
  'companion_memory_enabled',
  'upload_token',
  'plan',
  'vision_primary',
  'screenshot_vision_primary',
  'photo_vision_primary',
  'qwen_screenshot_model',
  'qwen_photo_model',
  'qwen_screenshot_enable_thinking',
  'qwen_photo_enable_thinking',
  'ai_insight_provider',
  'companion_persona',
  'companion_memory_strength',
  'companion_expression_style',
  'companion_custom_note',
]

const LEGACY_FIELDS = MODERN_FIELDS.filter(field => ![
  'screenshot_vision_primary',
  'photo_vision_primary',
  'qwen_screenshot_model',
  'qwen_photo_model',
  'qwen_screenshot_enable_thinking',
  'qwen_photo_enable_thinking',
].includes(field))

const MUTABLE_FIELDS = new Set([
  'ai_logs_enabled',
  'keep_source_images',
  'prompt_optimization_enabled',
  'expression_improvement_enabled',
  'image_retention_days',
  'companion_enabled',
  'companion_memory_enabled',
  'vision_primary',
  'screenshot_vision_primary',
  'photo_vision_primary',
  'qwen_screenshot_model',
  'qwen_photo_model',
  'qwen_screenshot_enable_thinking',
  'qwen_photo_enable_thinking',
  'ai_insight_provider',
  'companion_persona',
  'companion_memory_strength',
  'companion_expression_style',
  'companion_custom_note',
])

function errorMessage(error) {
  return error?.message || String(error || '设置服务请求失败')
}

function isMissingModernColumn(error) {
  const message = `${error?.message || ''} ${error?.details || ''} ${error?.hint || ''}`
  return error?.code === '42703'
    || error?.code === 'PGRST204'
    || /screenshot_vision_primary|photo_vision_primary|qwen_screenshot|qwen_photo|schema cache/i.test(message)
}

export function createSettingsRepository({ client, now = () => new Date() }) {
  if (!client?.from) throw new Error('设置服务缺少数据客户端')

  async function read(userId, fields) {
    const { data, error } = await client.from('user_configs')
      .select(fields.join(', '))
      .eq('user_id', userId)
      .maybeSingle()
    return { data, error }
  }

  async function load(userId) {
    const normalizedUserId = String(userId || '').trim()
    if (!normalizedUserId) throw new Error('缺少用户编号')

    const modern = await read(normalizedUserId, MODERN_FIELDS)
    if (!modern.error) return { data: modern.data || null, legacy: false }
    if (!isMissingModernColumn(modern.error)) throw new Error(errorMessage(modern.error))

    const legacy = await read(normalizedUserId, LEGACY_FIELDS)
    if (legacy.error) throw new Error(errorMessage(legacy.error))
    return { data: legacy.data || null, legacy: true }
  }

  async function save(userId, patch) {
    const normalizedUserId = String(userId || '').trim()
    if (!normalizedUserId) throw new Error('缺少用户编号')
    const entries = Object.entries(patch || {})
    if (!entries.length) throw new Error('设置更新内容为空')
    const invalidField = entries.find(([field]) => !MUTABLE_FIELDS.has(field))?.[0]
    if (invalidField) throw new Error(`不允许更新配置字段：${invalidField}`)

    const body = {
      user_id: normalizedUserId,
      ...Object.fromEntries(entries),
    }
    body.updated_at = now().toISOString()
    const { data, error } = await client.from('user_configs')
      .upsert(body, { onConflict: 'user_id' })
    if (error) throw new Error(errorMessage(error))
    return data || null
  }

  return { load, save }
}
