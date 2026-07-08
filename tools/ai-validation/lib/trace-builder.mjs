/**
 * ═══════════════════════════════════════════════
 * 共享 Trace 构建模块
 * ═══════════════════════════════════════════════
 *
 * 纯函数模块，不包含文件 IO、HTTP 请求或 CLI 上下文。
 * 被 test-ingest-receipt.mjs（上传测试）和 server/index.mjs（远程查看）共用。
 *
 * 核心函数：
 *   - buildTraceFromUploadResult(payload)   从上传结果构建 trace
 *   - buildTraceFromAiLog(logRow, options)  从 ai_recognition_logs 记录构建 trace（远程模式）
 *   - parseRawDebug(value)                 解析 raw_response
 *   - summarizeResult(result)               提取识别结果摘要
 */

import path from 'node:path'

// ═══════════════════════════════════════════════
// 基础工具函数
// ═══════════════════════════════════════════════

/**
 * JSON 格式化（2 空格缩进）
 * @param {any} value
 * @returns {string}
 */
export function compactJson(value) {
  return JSON.stringify(value, null, 2)
}

/**
 * 将路径中的操作系统分隔符统一为正斜杠
 * @param {string} targetPath
 * @returns {string}
 */
export function normalizePathForReport(targetPath) {
  return targetPath.split(path.sep).join('/')
}

/**
 * 将 UTC 时间戳转为 Asia/Shanghai 日期字符串 (YYYY-MM-DD)
 * Shanghai 固定 UTC+8，无夏令时
 * @param {string|Date} timestamp
 * @returns {string}
 */
export function toShanghaiDate(timestamp) {
  const date = new Date(timestamp)
  const shanghaiMs = date.getTime() + 8 * 60 * 60 * 1000
  return new Date(shanghaiMs).toISOString().slice(0, 10)
}

// ═══════════════════════════════════════════════
// 结果摘要
// ═══════════════════════════════════════════════

/**
 * 从识别响应中提取摘要字段
 * @param {Object} result - EF 返回的 parsed response
 * @returns {Object}
 */
export function summarizeResult(result) {
  return {
    status: result.status ?? '-',
    record_type: result.record_type ?? result.data?.type ?? '-',
    id: result.id ?? result.data?.id ?? '-',
    trace_id: result.trace_id ?? null,
    ai_log_id: result.ai_log_id ?? null,
    vision_mode: result.vision_mode ?? null,
    photo_quality_mode: result.photo_quality_mode ?? null,
    model_provider: result.model_provider ?? null,
    model_name: result.model_name ?? null,
    capture_kind: result.capture_kind ?? null,
    source_app: result.source_app ?? null,
    message: result.message ?? '-',
    notification: result.notification ?? result.notification_text ?? '-',
    companion_message: result.companion_message ?? '-',
    ai_feedback: result.ai_feedback ?? null,
    time_context: result.time_context ?? null,
    error: result.error ?? null,
  }
}

// ═══════════════════════════════════════════════
// raw_response 解析
// ═══════════════════════════════════════════════

/**
 * 解析 ai_recognition_logs.raw_response 字段
 * @param {string|Object|null} value
 * @returns {Object|null}
 */
export function parseRawDebug(value) {
  if (!value) return null
  if (typeof value === 'object') return value
  if (typeof value !== 'string') return null
  try {
    return JSON.parse(value)
  } catch {
    return null
  }
}

// ═══════════════════════════════════════════════
// 数据库目标推断
// ═══════════════════════════════════════════════

/**
 * 根据 record_type 和 status 推断目标表
 * @param {string} recordType
 * @param {string} status
 * @returns {string|null}
 */
export function inferTargetTable(recordType, status) {
  if (recordType === 'expense') return 'transactions'
  if (recordType === 'income') return 'income_records'
  if (status === 'staging') return 'staging_records'
  if (recordType && recordType !== '-') return 'data_records'
  return null
}

/**
 * 合并本地和远程的 DB 目标信息
 * @param {Array} localTargets
 * @param {Object} aiLog
 * @returns {Array}
 */
function mergeDbTargets(localTargets, aiLog) {
  if (!aiLog?.target_table && !aiLog?.target_id && !aiLog?.staging_record_id && !aiLog?.data_record_id) {
    return localTargets
  }
  const fromLog = {
    table: aiLog.target_table || null,
    id: aiLog.target_id || aiLog.staging_record_id || aiLog.data_record_id || null,
    record_type: aiLog.record_type || null,
    status: aiLog.status || null,
    domain_id: aiLog.domain_id || null,
    staging_record_id: aiLog.staging_record_id || null,
    data_record_id: aiLog.data_record_id || null,
  }
  return [fromLog, ...localTargets.filter((item) => item.id !== fromLog.id)]
}

// ═══════════════════════════════════════════════
// Trace 步骤构建（完整模式，依赖 rawDebug）
// ═══════════════════════════════════════════════

/**
 * 构建带计时信息的步骤
 */
function buildTimingStep({ stepId, name, timingKey, rawDebug, input = {}, output = {}, artifactRefs = [] }) {
  const duration = rawDebug?.timings?.[timingKey]
  const hasOutput = Object.values(output).some((value) => value !== null && value !== undefined)
  return {
    step_id: stepId,
    name,
    status: duration !== undefined || hasOutput ? 'success' : 'unknown',
    duration_ms: duration ?? null,
    input_snapshot: input,
    output_snapshot: output,
    user_visible: false,
    visibility_level: 'L2',
    ...(artifactRefs.length ? { artifact_refs: artifactRefs } : {}),
  }
}

/**
 * 构建完整的 trace 步骤列表（需要 rawDebug）
 * @param {Object} params - { payload, parsed, summary, aiLog, rawDebug }
 * @returns {Array}
 */
function buildTraceSteps({ payload, parsed, summary, aiLog, rawDebug }) {
  const steps = [
    {
      step_id: 'upload_request',
      name: '上传请求',
      status: payload.httpStatus >= 200 && payload.httpStatus < 500 ? 'success' : 'error',
      duration_ms: payload.elapsedMs,
      input_snapshot: {
        image: payload.relativeImage,
        mime: payload.mime,
        capture_kind: payload.context.captureKind,
        source_app: payload.context.sourceApp,
      },
      output_snapshot: {
        http_status: payload.httpStatus,
        status_text: payload.statusText,
      },
      user_visible: false,
      visibility_level: 'L1',
    },
    {
      step_id: 'identity_resolve',
      name: '身份解析',
      status: parsed.error && payload.httpStatus === 401 ? 'error' : 'success',
      input_snapshot: {
        identity_source: payload.context.userId ? 'user_id' : (payload.context.uploadToken ? 'upload_token' : 'none'),
      },
      output_snapshot: {
        user_id: payload.context.userId || null,
        upload_token_used: Boolean(payload.context.uploadToken),
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    buildTimingStep({
      stepId: 'image_hash',
      name: '图片哈希与去重准备',
      timingKey: 'hash',
      rawDebug,
      input: {
        mime: payload.mime,
      },
      output: {
        image_hash: aiLog?.image_hash || null,
        perceptual_hash: aiLog?.perceptual_hash || null,
        perceptual_distance: aiLog?.perceptual_distance ?? null,
      },
    }),
    buildTimingStep({
      stepId: 'duplicate_check',
      name: '去重检查',
      timingKey: 'dup_check',
      rawDebug,
      output: {
        duplicate_kind: aiLog?.duplicate_kind || null,
        duplicate_ref_table: aiLog?.duplicate_ref_table || null,
        duplicate_ref_id: aiLog?.duplicate_ref_id || null,
      },
    }),
    buildTimingStep({
      stepId: 'domain_dispatch',
      name: '低成本预路由 / Dispatcher',
      timingKey: 'dispatcher',
      rawDebug,
      input: {
        source_app: rawDebug?.dispatcher?.source_app || parsed.source_app || payload.context.sourceApp,
      },
      output: {
        selected_domain_key: rawDebug?.dispatcher?.selected_domain_key || null,
        route_confidence: rawDebug?.dispatcher?.route_confidence ?? null,
        route_reason: rawDebug?.dispatcher?.route_reason || null,
        should_call_vision: rawDebug?.dispatcher?.should_call_vision ?? null,
        skip_reason: rawDebug?.dispatcher?.skip_reason || null,
      },
      artifactRefs: ['dispatcher'],
    }),
    {
      step_id: 'prompt_build',
      name: 'Prompt 构造',
      status: rawDebug?.prompt?.version || aiLog?.prompt_version ? 'success' : 'unknown',
      duration_ms: null,
      input_snapshot: {
        response_mode: payload.context.responseMode,
      },
      output_snapshot: {
        prompt_version: aiLog?.prompt_version || rawDebug?.prompt?.version || null,
        prompt_hash: rawDebug?.prompt?.hash || null,
        prompt_snapshot_available: Boolean(rawDebug?.prompt?.messages || rawDebug?.prompt?.text || rawDebug?.prompt?.snapshot),
      },
      user_visible: false,
      visibility_level: 'L2',
      artifact_refs: ['prompt'],
    },
    {
      step_id: 'model_path',
      name: '模型路径',
      status: parsed.model_name || parsed.vision_mode || aiLog?.model_name ? 'success' : 'unknown',
      input_snapshot: {
        capture_kind: parsed.capture_kind || rawDebug?.request_context?.capture_kind || payload.context.captureKind,
        source_app: parsed.source_app || rawDebug?.request_context?.source_app || payload.context.sourceApp,
      },
      output_snapshot: {
        vision_mode: parsed.vision_mode || rawDebug?.request_context?.vision_mode || null,
        photo_quality_mode: parsed.photo_quality_mode ?? rawDebug?.request_context?.photo_quality_mode ?? null,
        model_provider: parsed.model_provider || aiLog?.model_provider || null,
        model_name: parsed.model_name || aiLog?.model_name || null,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    buildTimingStep({
      stepId: 'model_call',
      name: '模型调用',
      timingKey: 'vision_total',
      rawDebug,
      output: {
        response_id: rawDebug?.model_raw?.response_id || null,
        finish_reason: rawDebug?.model_raw?.finish_reason || null,
        attempts: rawDebug?.vision_attempts?.length ?? null,
        has_raw_text: Boolean(rawDebug?.model_raw?.text),
        has_extracted_json: Boolean(rawDebug?.model_raw?.extracted_json),
      },
      artifactRefs: ['model_raw', 'vision_attempts'],
    }),
    {
      step_id: 'model_parse',
      name: '模型解析',
      status: rawDebug?.model_raw?.extracted_json || aiLog?.ai_response ? 'success' : 'unknown',
      duration_ms: null,
      input_snapshot: {
        raw_text_available: Boolean(rawDebug?.model_raw?.text),
      },
      output_snapshot: {
        extracted_json_available: Boolean(rawDebug?.model_raw?.extracted_json),
        record_type: aiLog?.record_type || summary.record_type,
        confidence: aiLog?.confidence ?? null,
      },
      user_visible: false,
      visibility_level: 'L2',
      artifact_refs: ['model_raw.extracted_json', 'ai_response'],
    },
    {
      step_id: 'normalize_validate',
      name: '标准化与校验',
      status: aiLog?.status ? 'success' : 'unknown',
      duration_ms: null,
      input_snapshot: {
        record_type: aiLog?.record_type || summary.record_type,
      },
      output_snapshot: {
        status: aiLog?.status || summary.status,
        confidence: aiLog?.confidence ?? null,
        occurred_at: aiLog?.occurred_at || null,
        order_finished_at: aiLog?.order_finished_at || null,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    {
      step_id: 'companion_feedback',
      name: '伴随文案 / AI 反馈',
      status: rawDebug?.companion || summary.ai_feedback || summary.companion_message !== '-' ? 'success' : 'skipped',
      duration_ms: null,
      input_snapshot: {
        disabled: rawDebug?.companion?.disabled ?? null,
        fallback_used: rawDebug?.companion?.fallback_used ?? null,
        feedback_used: rawDebug?.companion?.feedback_used ?? null,
      },
      output_snapshot: {
        final: rawDebug?.companion?.final || summary.companion_message || null,
        has_ai_feedback: Boolean(rawDebug?.companion?.ai_feedback || summary.ai_feedback),
      },
      user_visible: true,
      visibility_level: 'L0',
      artifact_refs: ['companion'],
    },
    buildTimingStep({
      stepId: 'archive_or_staging',
      name: '归档或中转',
      timingKey: 'db_insert',
      rawDebug,
      output: {
        target_table: aiLog?.target_table || inferTargetTable(summary.record_type, parsed.status),
        target_id: aiLog?.target_id || parsed.id || null,
        staging_record_id: aiLog?.staging_record_id || null,
        data_record_id: aiLog?.data_record_id || null,
      },
    }),
    {
      step_id: 'write_ai_log',
      name: '写入 AI 日志',
      status: aiLog ? 'success' : (parsed.ai_log_id ? 'error' : 'skipped'),
      duration_ms: null,
      input_snapshot: {
        ai_log_id: parsed.ai_log_id || null,
      },
      output_snapshot: {
        ai_log_id: aiLog?.id || parsed.ai_log_id || null,
        raw_debug_available: Boolean(rawDebug),
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    {
      step_id: 'response_build',
      name: '响应构造',
      status: summary.error ? 'error' : 'success',
      input_snapshot: {
        ai_log_id: parsed.ai_log_id || null,
      },
      output_snapshot: {
        status: summary.status,
        record_type: summary.record_type,
        id: summary.id,
        has_ai_feedback: Boolean(summary.ai_feedback),
        has_notification: Boolean(parsed.notification_text || parsed.notification),
      },
      user_visible: true,
      visibility_level: 'L0',
    },
  ]
  return steps.filter(Boolean)
}

// ═══════════════════════════════════════════════
// 从上传结果构建 Trace（原 buildTraceArtifact）
// ═══════════════════════════════════════════════

/**
 * 从上传测试结果构建 trace.json 兼容格式
 * @param {Object} payload - 包含 httpStatus, elapsedMs, testCase, caseMeta, parsed, summary, aiLog, raw 等字段
 * @returns {Object} trace 对象
 */
export function buildTraceFromUploadResult(payload) {
  const parsed = payload.parsed || {}
  const summary = payload.summary || summarizeResult(parsed)
  const aiLog = payload.aiLog || null
  const rawDebug = parseRawDebug(aiLog?.raw_response)
  const traceId = parsed.trace_id || `local-${payload.context.runId}-${payload.caseMeta.test_case_domain}-${payload.caseMeta.test_case_file}`
  const generatedAt = new Date().toISOString()
  const status = summary.error ? 'error' : (summary.status || parsed.status || (payload.httpStatus >= 200 && payload.httpStatus < 300 ? 'success' : 'error'))

  const userVisibleOutputs = [
    parsed.notification_text || parsed.notification ? {
      output_type: 'ios_shortcut_notification',
      label: 'iOS 快捷指令通知',
      value: parsed.notification_text || parsed.notification,
      source_step: 'response_build',
      user_visible: true,
    } : null,
    summary.companion_message && summary.companion_message !== '-' ? {
      output_type: 'app_companion_message',
      label: 'App 伴随文案',
      value: summary.companion_message,
      source_step: 'companion_feedback',
      user_visible: true,
    } : null,
    summary.ai_feedback ? {
      output_type: 'app_ai_feedback',
      label: 'App AI 弹窗反馈',
      value: summary.ai_feedback,
      source_step: 'companion_feedback',
      user_visible: true,
    } : null,
  ].filter(Boolean)

  const dbTargets = parsed.id ? [{
    table: inferTargetTable(summary.record_type, parsed.status),
    id: parsed.id,
    record_type: summary.record_type,
    status: parsed.status || summary.status,
  }] : []

  return {
    trace_id: traceId,
    ai_log_id: parsed.ai_log_id || null,
    run_id: payload.context.runId,
    status,
    created_at: generatedAt,
    case: {
      ...payload.caseMeta,
      image_path: normalizePathForReport(payload.testCase.imagePath),
      image_relative_path: payload.relativeImage,
      mime: payload.mime,
    },
    user_context: {
      user_id: payload.context.userId || null,
      identity_source: payload.context.userId ? 'user_id' : (payload.context.uploadToken ? 'upload_token' : 'none'),
      upload_token_used: Boolean(payload.context.uploadToken),
      is_test_account: Boolean(payload.context.uploadToken),
    },
    request_context: {
      endpoint: payload.context.endpoint,
      response_mode: payload.context.responseMode,
      capture_kind: parsed.capture_kind || rawDebug?.request_context?.capture_kind || payload.context.captureKind,
      source_app: parsed.source_app || rawDebug?.request_context?.source_app || payload.context.sourceApp,
    },
    model_context: {
      vision_mode: parsed.vision_mode || rawDebug?.request_context?.vision_mode || null,
      photo_quality_mode: parsed.photo_quality_mode ?? rawDebug?.request_context?.photo_quality_mode ?? null,
      model_provider: parsed.model_provider || aiLog?.model_provider || null,
      model_name: parsed.model_name || aiLog?.model_name || null,
      prompt_version: aiLog?.prompt_version || rawDebug?.prompt?.version || null,
      prompt_hash: rawDebug?.prompt?.hash || null,
    },
    steps: buildTraceSteps({ payload, parsed, summary, aiLog, rawDebug }),
    user_visible_outputs: userVisibleOutputs,
    artifacts: {
      response_file: normalizePathForReport(payload.responseFile),
      raw_response_available: Boolean(payload.raw),
      parsed_response_available: Boolean(payload.parsed),
      ai_log_available: Boolean(aiLog),
      ai_log_fetch_error: payload.aiLogFetchError || null,
      raw_debug_available: Boolean(rawDebug),
      prompt: rawDebug?.prompt || null,
      dispatcher: rawDebug?.dispatcher || null,
      model_raw: rawDebug?.model_raw || null,
      companion: rawDebug?.companion || null,
      notification: rawDebug?.notification || null,
    },
    db_targets: mergeDbTargets(dbTargets, aiLog),
    errors: summary.error ? [{
      code: parsed.error_code || 'REQUEST_ERROR',
      message: summary.error,
      source_step: payload.httpStatus ? 'response_build' : 'upload_request',
    }] : payload.aiLogFetchError ? [{
      code: 'AI_LOG_FETCH_FAILED',
      message: payload.aiLogFetchError,
      source_step: 'write_ai_log',
    }] : [],
  }
}

// ═══════════════════════════════════════════════
// 从 ai_recognition_logs 记录构建 Trace（远程模式）
// ═══════════════════════════════════════════════

/**
 * 判断图片可用性状态
 * @param {string|null} imageUrl - ai_recognition_logs.image_url
 * @returns {'available'|'no_image_url'|'expired'}
 */
function determineImageStatus(imageUrl) {
  if (!imageUrl) return 'no_image_url'
  if (imageUrl.startsWith('tmp/')) return 'expired'
  return 'available'
}

/**
 * 构建基础模式步骤（raw_response 为空但有 ai_response）
 * @param {Object} logRow
 * @param {Object} summary
 * @returns {Array}
 */
function buildBasicSteps(logRow, summary) {
  return [
    {
      step_id: 'upload_request',
      name: '上传请求',
      status: 'success',
      duration_ms: logRow.duration_ms ?? null,
      input_snapshot: {
        image: logRow.image_url || null,
        image_type: logRow.image_type || null,
      },
      output_snapshot: {
        http_status: 200,
      },
      user_visible: false,
      visibility_level: 'L1',
    },
    {
      step_id: 'identity_resolve',
      name: '身份解析',
      status: 'success',
      input_snapshot: { identity_source: 'upload_token' },
      output_snapshot: {
        user_id: logRow.user_id || null,
        upload_token_used: true,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    {
      step_id: 'model_call',
      name: '模型调用',
      status: logRow.model_name ? 'success' : 'unknown',
      duration_ms: logRow.duration_ms ?? null,
      input_snapshot: {},
      output_snapshot: {
        model_provider: logRow.model_provider || null,
        model_name: logRow.model_name || null,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    {
      step_id: 'model_parse',
      name: '模型解析',
      status: logRow.record_type ? 'success' : 'unknown',
      duration_ms: null,
      input_snapshot: {},
      output_snapshot: {
        record_type: logRow.record_type || null,
        confidence: logRow.confidence ?? null,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    {
      step_id: 'companion_feedback',
      name: '伴随文案 / AI 反馈',
      status: (summary.companion_message && summary.companion_message !== '-') || summary.ai_feedback ? 'success' : 'skipped',
      duration_ms: null,
      input_snapshot: {},
      output_snapshot: {
        final: summary.companion_message !== '-' ? summary.companion_message : null,
        has_ai_feedback: Boolean(summary.ai_feedback),
      },
      user_visible: true,
      visibility_level: 'L0',
    },
    {
      step_id: 'write_ai_log',
      name: '写入 AI 日志',
      status: 'success',
      duration_ms: null,
      input_snapshot: { ai_log_id: logRow.id },
      output_snapshot: {
        ai_log_id: logRow.id,
        raw_debug_available: false,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
    {
      step_id: 'response_build',
      name: '响应构造',
      status: summary.error ? 'error' : 'success',
      input_snapshot: {},
      output_snapshot: {
        status: summary.status,
        record_type: summary.record_type,
        has_ai_feedback: Boolean(summary.ai_feedback),
      },
      user_visible: true,
      visibility_level: 'L0',
    },
  ].filter(Boolean)
}

/**
 * 构建最小模式步骤（raw_response 和 ai_response 都为空）
 * @param {Object} logRow
 * @returns {Array}
 */
function buildMinimalSteps(logRow) {
  return [
    {
      step_id: 'upload_request',
      name: '上传请求',
      status: logRow.status === 'error' ? 'error' : 'success',
      duration_ms: logRow.duration_ms ?? null,
      input_snapshot: {
        image: logRow.image_url || null,
      },
      output_snapshot: {},
      user_visible: false,
      visibility_level: 'L1',
    },
    {
      step_id: 'write_ai_log',
      name: '写入 AI 日志',
      status: logRow.status || 'unknown',
      duration_ms: null,
      input_snapshot: { ai_log_id: logRow.id },
      output_snapshot: {
        ai_log_id: logRow.id,
        raw_debug_available: false,
      },
      user_visible: false,
      visibility_level: 'L2',
    },
  ]
}

/**
 * 从 ai_recognition_logs 记录构建 trace（远程模式）
 *
 * 支持三级降级：
 *   - full:   raw_response 存在 → 解析 rawDebug，生成完整 steps + artifacts
 *   - basic:  raw_response 为空但有 ai_response → 精简 steps，artifacts 只含 ai_response
 *   - minimal: 两者都空 → 只展示 status / duration_ms / created_at
 *
 * @param {Object} logRow - ai_recognition_logs 表行
 * @param {Object} [options={}]
 * @param {string} [options.runId] - 批次 ID（如 'remote-2026-07-06'）
 * @param {string} [options.dateStr] - 日期字符串（YYYY-MM-DD），不传则从 created_at 推导
 * @param {string} [options.accountKey] - 账号 key（用于标识来源）
 * @returns {Object} trace 兼容格式
 */
export function buildTraceFromAiLog(logRow, options = {}) {
  const dateStr = options.dateStr || toShanghaiDate(logRow.created_at)
  const runId = options.runId || `remote-${dateStr}`

  // 判断图片状态
  const imageStatus = determineImageStatus(logRow.image_url)

  // 判断 debug 级别
  const rawDebug = parseRawDebug(logRow.raw_response)
  const aiResponse = logRow.ai_response
  const debugLevel = rawDebug ? 'full' : (aiResponse ? 'basic' : 'minimal')

  // 构建 summary
  const parsed = aiResponse || {}
  const summary = summarizeResult(parsed)

  // 构建 user_visible_outputs
  const userVisibleOutputs = [
    summary.companion_message && summary.companion_message !== '-' ? {
      output_type: 'app_companion_message',
      label: 'App 伴随文案',
      value: summary.companion_message,
      source_step: 'companion_feedback',
      user_visible: true,
    } : null,
    summary.ai_feedback ? {
      output_type: 'app_ai_feedback',
      label: 'App AI 弹窗反馈',
      value: summary.ai_feedback,
      source_step: 'companion_feedback',
      user_visible: true,
    } : null,
  ].filter(Boolean)

  // 构建 steps
  let steps
  if (debugLevel === 'full') {
    // 完整模式：构造 payload 并复用 buildTraceSteps
    const payload = {
      httpStatus: 200,
      statusText: 'OK',
      elapsedMs: logRow.duration_ms ?? null,
      relativeImage: logRow.image_url || null,
      mime: logRow.image_type || 'image/jpeg',
      context: {
        captureKind: rawDebug?.request_context?.capture_kind || 'screenshot',
        sourceApp: rawDebug?.request_context?.source_app || 'unknown',
        responseMode: 'json',
        userId: logRow.user_id || null,
        uploadToken: true,
        runId,
      },
      caseMeta: {
        test_run_id: runId,
        test_case_domain: logRow.record_type || 'unknown',
        test_case_date: dateStr,
        test_case_file: logRow.image_url || '',
      },
    }
    steps = buildTraceSteps({ payload, parsed, summary, aiLog: logRow, rawDebug })
  } else if (debugLevel === 'basic') {
    steps = buildBasicSteps(logRow, summary)
  } else {
    steps = buildMinimalSteps(logRow)
  }

  // 构建 db_targets
  const dbTargets = logRow.target_table || logRow.target_id ? [{
    table: logRow.target_table || null,
    id: logRow.target_id || null,
    record_type: logRow.record_type || null,
    status: logRow.status || null,
    domain_id: logRow.domain_id || null,
    staging_record_id: logRow.staging_record_id || null,
    data_record_id: logRow.data_record_id || null,
  }] : []

  // 构建 artifacts
  const artifacts = debugLevel === 'full' ? {
    raw_debug_available: true,
    prompt: rawDebug?.prompt || null,
    dispatcher: rawDebug?.dispatcher || null,
    model_raw: rawDebug?.model_raw || null,
    companion: rawDebug?.companion || null,
    notification: rawDebug?.notification || null,
  } : debugLevel === 'basic' ? {
    raw_debug_available: false,
    ai_response: aiResponse || null,
  } : {
    raw_debug_available: false,
  }

  // 构建 errors
  const errors = []
  if (logRow.error_message) {
    errors.push({
      code: logRow.status === 'ai_error' ? 'AI_ERROR' : (logRow.status === 'db_error' ? 'DB_ERROR' : 'REQUEST_ERROR'),
      message: logRow.error_message,
      source_step: logRow.status === 'db_error' ? 'archive_or_staging' : 'model_call',
    })
  }

  // 构建 status
  const traceStatus = logRow.status === 'success' ? 'done' : (logRow.status || 'unknown')

  return {
    trace_id: logRow.id,
    ai_log_id: logRow.id,
    run_id: runId,
    status: traceStatus,
    created_at: logRow.created_at,
    is_remote: true,
    debug_level: debugLevel,
    case: {
      test_run_id: runId,
      test_case_domain: logRow.record_type || 'unknown',
      test_case_date: dateStr,
      test_case_file: logRow.image_url || null,
      image_relative_path: logRow.image_url || null,
      image_status: imageStatus,
      mime: logRow.image_type || null,
    },
    user_context: {
      user_id: logRow.user_id || null,
      identity_source: 'upload_token',
      upload_token_used: true,
      is_test_account: false,
    },
    model_context: {
      vision_mode: rawDebug?.request_context?.vision_mode || null,
      photo_quality_mode: rawDebug?.request_context?.photo_quality_mode ?? null,
      model_provider: logRow.model_provider || null,
      model_name: logRow.model_name || null,
      prompt_version: logRow.prompt_version || rawDebug?.prompt?.version || null,
      prompt_hash: rawDebug?.prompt?.hash || null,
    },
    steps,
    user_visible_outputs: userVisibleOutputs,
    artifacts,
    db_targets: dbTargets,
    errors,
  }
}
