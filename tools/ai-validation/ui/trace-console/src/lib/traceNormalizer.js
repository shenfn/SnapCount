/**
 * ═══════════════════════════════════════════════
 * Trace 数据标准化
 * ═══════════════════════════════════════════════
 *
 * 职责：
 *   - 补全 trace.json 中缺失的字段，统一数据结构
 *   - 处理 partial trace（去重、错误等分支的大量 null 字段）
 *   - 计算总请求耗时
 *   - 提取慢节点排行（排除 upload_request）
 *
 * 设计原则：
 *   - 入参格式与未来"线上日志转换器"输出格式保持一致
 *   - 无论是本地 trace.json 还是未来从 ai_recognition_logs 转换的数据，都走同一个 normalize 函数
 */

/**
 * 标准化单个 step
 * @param {object} rawStep
 * @returns {object}
 */
function normalizeStep(rawStep) {
  if (!rawStep || typeof rawStep !== 'object') {
    return {
      step_id: 'unknown',
      name: '未知节点',
      status: 'unknown',
      duration_ms: null,
      input_snapshot: {},
      output_snapshot: {},
      user_visible: false,
      visibility_level: 'L2',
      artifact_refs: [],
    }
  }
  return {
    step_id: rawStep.step_id || 'unknown',
    name: rawStep.name || rawStep.step_id || '未知节点',
    status: rawStep.status || 'unknown',
    duration_ms: rawStep.duration_ms ?? null,
    input_snapshot: rawStep.input_snapshot || {},
    output_snapshot: rawStep.output_snapshot || {},
    user_visible: rawStep.user_visible ?? false,
    visibility_level: rawStep.visibility_level || 'L2',
    artifact_refs: rawStep.artifact_refs || [],
    loss_or_transform_notes: rawStep.loss_or_transform_notes || [],
  }
}

/**
 * 标准化 user_visible_output
 * @param {object} rawOutput
 * @returns {object}
 */
function normalizeOutput(rawOutput) {
  if (!rawOutput || typeof rawOutput !== 'object') {
    return {
      output_type: 'unknown',
      label: '未知输出',
      value: null,
      source_step: null,
      user_visible: true,
    }
  }
  return {
    output_type: rawOutput.output_type || 'unknown',
    label: rawOutput.label || rawOutput.output_type || '未知输出',
    value: rawOutput.value ?? null,
    source_step: rawOutput.source_step || null,
    user_visible: rawOutput.user_visible ?? true,
  }
}

/**
 * 标准化 db_target
 * @param {object} rawTarget
 * @returns {object}
 */
function normalizeDbTarget(rawTarget) {
  if (!rawTarget || typeof rawTarget !== 'object') {
    return { table: null, id: null, record_type: null, status: null }
  }
  return {
    table: rawTarget.table || null,
    id: rawTarget.id || null,
    record_type: rawTarget.record_type || null,
    status: rawTarget.status || null,
    domain_id: rawTarget.domain_id || null,
    staging_record_id: rawTarget.staging_record_id || null,
    data_record_id: rawTarget.data_record_id || null,
  }
}

/**
 * 标准化完整 trace
 * @param {object} raw - 原始 trace.json 内容
 * @returns {object} 标准化后的 trace
 */
export function normalizeTrace(raw) {
  if (!raw || typeof raw !== 'object') {
    return {
      trace_id: null,
      ai_log_id: null,
      run_id: null,
      status: 'parse_error',
      created_at: null,
      case: {},
      user_context: {},
      request_context: {},
      model_context: {},
      steps: [],
      user_visible_outputs: [],
      artifacts: {},
      db_targets: [],
      errors: ['Trace data is null or not an object'],
      _total_duration_ms: null,
      _slow_nodes: [],
    }
  }

  const steps = Array.isArray(raw.steps) ? raw.steps.map(normalizeStep) : []
  const user_visible_outputs = Array.isArray(raw.user_visible_outputs)
    ? raw.user_visible_outputs.map(normalizeOutput)
    : []
  const db_targets = Array.isArray(raw.db_targets) ? raw.db_targets.map(normalizeDbTarget) : []
  const errors = Array.isArray(raw.errors) ? raw.errors : []

  // 计算总请求耗时
  const totalDuration = calcTotalDuration(steps, raw)

  // 提取慢节点排行（排除 upload_request）
  const slowNodes = extractSlowNodes(steps)

  return {
    trace_id: raw.trace_id || null,
    ai_log_id: raw.ai_log_id || null,
    run_id: raw.run_id || null,
    status: raw.status || 'unknown',
    created_at: raw.created_at || null,
    case: raw.case || {},
    user_context: raw.user_context || {},
    request_context: raw.request_context || {},
    model_context: raw.model_context || {},
    steps,
    user_visible_outputs,
    artifacts: raw.artifacts || {},
    db_targets,
    errors,
    // 以下为计算字段，用 _ 前缀标识
    _total_duration_ms: totalDuration,
    _slow_nodes: slowNodes,
  }
}

/**
 * 计算总请求耗时
 * 优先取 upload_request 的 duration_ms（这是端到端总耗时）
 * 回退到 steps 中所有 duration_ms 的总和
 * @param {Array} steps
 * @param {object} raw
 * @returns {number|null}
 */
function calcTotalDuration(steps, raw) {
  // 优先取 upload_request.duration_ms（端到端总耗时）
  const uploadStep = steps.find((s) => s.step_id === 'upload_request')
  if (uploadStep?.duration_ms != null) {
    return uploadStep.duration_ms
  }
  // 回退：所有 duration_ms 求和
  const sum = steps.reduce((acc, s) => {
    if (s.duration_ms != null && !isNaN(s.duration_ms)) return acc + s.duration_ms
    return acc
  }, 0)
  return sum > 0 ? sum : null
}

/**
 * 提取慢节点排行
 * 排除 upload_request（它是总耗时，不是内部节点）
 * 只统计 duration_ms != null 的节点
 * 按耗时降序，取前 3
 * @param {Array} steps
 * @returns {Array<{step_id, name, duration_ms, status}>}
 */
function extractSlowNodes(steps) {
  return steps
    .filter((s) => s.step_id !== 'upload_request' && s.duration_ms != null && s.duration_ms > 0)
    .sort((a, b) => b.duration_ms - a.duration_ms)
    .slice(0, 3)
    .map((s) => ({
      step_id: s.step_id,
      name: s.name,
      duration_ms: s.duration_ms,
      status: s.status,
    }))
}

/**
 * 从 trace 摘要列表中提取可用的筛选状态
 * @param {Array} traces - trace 摘要列表
 * @returns {Array<{key, label, count}>}
 */
export function extractFilterOptions(traces) {
  const counts = {}
  for (const t of traces) {
    const status = t.status || 'unknown'
    counts[status] = (counts[status] || 0) + 1
  }
  // 转为筛选选项
  const statusLabelMap = {
    done: '成功',
    success: '成功',
    duplicate: '去重',
    pending: '待处理',
    error: '错误',
    parse_error: '解析失败',
    unknown: '未知',
  }
  const options = [{ key: 'all', label: '全部', count: traces.length }]
  for (const [status, count] of Object.entries(counts)) {
    const label = statusLabelMap[status] || status
    // 避免重复标签（done 和 success 都映射到"成功"）
    if (!options.find((o) => o.label === label)) {
      options.push({ key: status, label, count })
    }
  }
  return options
}
