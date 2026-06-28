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
 * 健康检查
 * @returns {Promise<{data: object|null, error: string|null}>}
 */
export function fetchHealth() {
  return request(`${API_BASE}/health`)
}
