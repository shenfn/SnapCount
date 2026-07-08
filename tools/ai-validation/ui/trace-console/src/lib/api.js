/**
 * ═══════════════════════════════════════════════
 * API 调用封装
 * ═══════════════════════════════════════════════
 * 所有接口通过 Vite proxy 转发到 Express 服务(5181)
 */

const API_BASE = '/api'

/**
 * 统一请求封装
 * @param {string} url
 * @returns {Promise<{data: any|null, error: string|null}>}
 */
async function request(url) {
  try {
    const res = await fetch(url)
    if (!res.ok) {
      const errBody = await res.json().catch(() => ({}))
      return { data: null, error: errBody.error || `HTTP ${res.status}` }
    }
    const data = await res.json()
    return { data, error: null }
  } catch (err) {
    return { data: null, error: err.message }
  }
}

/**
 * 列出所有批次
 * @returns {Promise<{data: {runs: Array}|null, error: string|null}>}
 */
export function fetchRuns() {
  return request(`${API_BASE}/runs`)
}

/**
 * 读取批次 summary
 * @param {string} runId
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchSummary(runId) {
  return request(`${API_BASE}/runs/${encodeURIComponent(runId)}/summary`)
}

/**
 * 列出批次内所有 trace 摘要
 * @param {string} runId
 * @returns {Promise<{data: {traces: Array}|null, error: string|null}>}
 */
export function fetchTraces(runId) {
  return request(`${API_BASE}/runs/${encodeURIComponent(runId)}/traces`)
}

/**
 * 读取单个完整 trace
 * @param {string} runId
 * @param {string} caseKey - 如 "sport/2026-06-27/001-cycling-9_79km"
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchTrace(runId, caseKey) {
  const encodedCaseKey = encodeURIComponent(caseKey)
  return request(`${API_BASE}/runs/${encodeURIComponent(runId)}/traces/${encodedCaseKey}`)
}

/**
 * 生成图片 URL
 * @param {string|null} relativePath - 如 "test-cases/sport/2026-06-27/001.png"
 * @returns {string|null} 完整的图片请求 URL，如果路径为空返回 null
 */
export function imageUrl(relativePath) {
  if (!relativePath) return null
  return `${API_BASE}/images?path=${encodeURIComponent(relativePath)}`
}

/**
 * 获取 prompt 快照（完整 prompt 文本）
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchPrompt() {
  return request(`${API_BASE}/prompt`)
}

/**
 * 本地 prompt 模拟
 * @param {Object} payload - { mode, imageBase64?, existingPath? }
 * @returns {Promise<{data: {jobId: string}|null, error: string|null}>}
 */
export async function localSimulate(payload) {
  try {
    const res = await fetch(`${API_BASE}/local-simulate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    if (!res.ok) {
      const errBody = await res.json().catch(() => ({}))
      return { data: null, error: errBody.error || `HTTP ${res.status}` }
    }
    const data = await res.json()
    return { data, error: null }
  } catch (err) {
    return { data: null, error: err.message }
  }
}

/**
 * 轮询本地模拟状态
 * @param {string} jobId
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export async function fetchSimulateStatus(jobId) {
  return request(`${API_BASE}/local-simulate/${encodeURIComponent(jobId)}/status`)
}

/**
 * 获取 prompt 历史版本列表
 * @returns {Promise<{data: {versions: Array}|null, error: string|null}>}
 */
export function fetchPromptHistory() {
  return request(`${API_BASE}/prompt-history`)
}

/**
 * 刷新 prompt 快照（运行 extract-prompt.mjs）
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export async function refreshPrompt() {
  try {
    const res = await fetch(`${API_BASE}/refresh-prompt`, { method: 'POST' })
    if (!res.ok) {
      return { data: null, error: `HTTP ${res.status}` }
    }
    const data = await res.json()
    return { data, error: data.success ? null : (data.error || '刷新失败') }
  } catch (err) {
    return { data: null, error: err.message }
  }
}

/**
 * 读取指定历史版本详情
 * @param {string} file
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchPromptHistoryFile(file) {
  return request(`${API_BASE}/prompt-history/${encodeURIComponent(file)}`)
}

/**
 * 上传图片执行测试
 * @param {Object} payload - { mode, imageBase64?, existingPath?, runId? }
 * @returns {Promise<{data: {jobId: string, runId: string}|null, error: string|null}>}
 */
export async function uploadTest(payload) {
  try {
    const res = await fetch(`${API_BASE}/upload-test`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    if (!res.ok) {
      const errBody = await res.json().catch(() => ({}))
      return { data: null, error: errBody.error || `HTTP ${res.status}` }
    }
    const data = await res.json()
    return { data, error: null }
  } catch (err) {
    return { data: null, error: err.message }
  }
}

/**
 * 轮询上传任务状态
 * @param {string} jobId
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export async function fetchUploadStatus(jobId) {
  return request(`${API_BASE}/upload-test/${encodeURIComponent(jobId)}/status`)
}

/**
 * 健康检查
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchHealth() {
  return request(`${API_BASE}/health`)
}

// ═══════════════════════════════════════════════
// 点评相关 API
// ═══════════════════════════════════════════════

/**
 * 保存点评
 * @param {string} runId
 * @param {string} caseKey - 如 "food/2026-06-27/001-meal-tray"
 * @param {Object} payload - { ratings, issue_tags, notes, suggested_action, mode, sim_snapshot? }
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export async function saveReview(runId, caseKey, payload) {
  try {
    const encodedCaseKey = encodeURIComponent(caseKey)
    const res = await fetch(`${API_BASE}/runs/${encodeURIComponent(runId)}/reviews/${encodedCaseKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    if (!res.ok) {
      const errBody = await res.json().catch(() => ({}))
      return { data: null, error: errBody.error || `HTTP ${res.status}` }
    }
    const data = await res.json()
    return { data, error: null }
  } catch (err) {
    return { data: null, error: err.message }
  }
}

/**
 * 读取单个点评
 * @param {string} runId
 * @param {string} caseKey
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchReview(runId, caseKey) {
  const encodedCaseKey = encodeURIComponent(caseKey)
  return request(`${API_BASE}/runs/${encodeURIComponent(runId)}/reviews/${encodedCaseKey}`)
}

/**
 * 列出批次内全部点评摘要
 * @param {string} runId
 * @returns {Promise<{data: {reviews: Array}|null, error: string|null}>}
 */
export function fetchReviews(runId) {
  return request(`${API_BASE}/runs/${encodeURIComponent(runId)}/reviews`)
}

// ═══════════════════════════════════════════════
// 远程模式 API（只读查询线上数据）
// ═══════════════════════════════════════════════

/**
 * 列出可用账号
 * @returns {Promise<{data: {accounts: Array}|null, error: string|null}>}
 */
export function fetchAccounts() {
  return request(`${API_BASE}/accounts`)
}

/**
 * 查询远程日期列表（有记录的天）
 * @param {string} accountKey - 账号 key（如 'test2'）
 * @returns {Promise<{data: {days: Array}|null, error: string|null}>}
 */
export function fetchRemoteDays(accountKey) {
  return request(`${API_BASE}/remote/accounts/${encodeURIComponent(accountKey)}/days`)
}

/**
 * 查询某天的远程记录列表
 * @param {string} accountKey
 * @param {string} date - YYYY-MM-DD（北京时间）
 * @returns {Promise<{data: {traces: Array}|null, error: string|null}>}
 */
export function fetchRemoteTraces(accountKey, date) {
  return request(`${API_BASE}/remote/accounts/${encodeURIComponent(accountKey)}/days/${encodeURIComponent(date)}/traces`)
}

/**
 * 查询单条远程记录详情
 * @param {string} accountKey
 * @param {string} date - YYYY-MM-DD
 * @param {string} logId - AI 日志 ID
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchRemoteTraceDetail(accountKey, date, logId) {
  const base = `${API_BASE}/remote/accounts/${encodeURIComponent(accountKey)}/days/${encodeURIComponent(date)}/traces/${encodeURIComponent(logId)}`
  return request(base)
}

/**
 * 生成远程图片 URL
 * @param {string} logId - AI 日志 ID
 * @param {string} accountKey
 * @returns {string} 完整的图片请求 URL
 */
export function remoteImageUrl(logId, accountKey) {
  return `${API_BASE}/remote/images?logId=${encodeURIComponent(logId)}&accountKey=${encodeURIComponent(accountKey)}`
}

/**
 * 查询记忆上下文
 * @param {string} accountKey
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchRemoteMemory(accountKey) {
  return request(`${API_BASE}/remote/accounts/${encodeURIComponent(accountKey)}/memory`)
}
