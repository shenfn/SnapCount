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
