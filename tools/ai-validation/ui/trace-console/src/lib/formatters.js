/**
 * ═══════════════════════════════════════════════
 * 格式化工具
 * ═══════════════════════════════════════════════
 */

/**
 * 格式化耗时
 * @param {number|null|undefined} ms
 * @returns {string}
 */
export function formatDuration(ms) {
  if (ms == null || isNaN(ms)) return '—'
  if (ms < 1) return '<1ms'
  if (ms < 1000) return `${Math.round(ms)}ms`
  const seconds = ms / 1000
  if (seconds < 60) return `${seconds.toFixed(1)}s`
  const minutes = Math.floor(seconds / 60)
  const remainSeconds = Math.round(seconds % 60)
  return `${minutes}m${remainSeconds}s`
}

/**
 * 截断文本
 * @param {string} text
 * @param {number} maxLen - 默认 2000
 * @returns {{text: string, truncated: boolean, fullLength: number}}
 */
export function truncateText(text, maxLen = 2000) {
  if (!text || typeof text !== 'string') return { text: '', truncated: false, fullLength: 0 }
  if (text.length <= maxLen) return { text, truncated: false, fullLength: text.length }
  return {
    text: text.slice(0, maxLen) + '\n... [已截断]',
    truncated: true,
    fullLength: text.length,
  }
}

/**
 * 剥离 markdown 代码块包裹
 * @param {string} text
 * @returns {string}
 */
export function stripMarkdownCodeBlock(text) {
  if (!text || typeof text !== 'string') return text
  // 匹配 ```json ... ``` 或 ``` ... ```
  const match = text.match(/^```(?:json)?\s*\n([\s\S]*?)\n```\s*$/)
  return match ? match[1] : text
}

/**
 * 格式化 JSON 字符串（带缩进）
 * @param {object|string} obj
 * @returns {string}
 */
export function formatJsonString(obj) {
  if (obj == null) return 'null'
  if (typeof obj === 'string') {
    try {
      const parsed = JSON.parse(obj)
      return JSON.stringify(parsed, null, 2)
    } catch {
      return obj
    }
  }
  try {
    return JSON.stringify(obj, null, 2)
  } catch {
    return String(obj)
  }
}

/**
 * 获取状态对应的颜色变量名
 * @param {string} status
 * @returns {string}
 */
export function getStatusColor(status) {
  const map = {
    success: 'var(--accent-green)',
    done: 'var(--accent-green)',
    skipped: 'var(--status-skipped)',
    unknown: 'var(--status-unknown)',
    error: 'var(--accent-red)',
    duplicate: 'var(--accent-yellow)',
    pending: 'var(--accent-yellow)',
    parse_error: 'var(--accent-red)',
    ai_error: 'var(--accent-red)',
    db_error: 'var(--accent-red)',
    auth_error: 'var(--accent-red)',
    network_error: 'var(--accent-red)',
  }
  return map[status] || 'var(--text-muted)'
}

/**
 * 获取状态对应的中文标签
 * @param {string} status
 * @returns {string}
 */
export function getStatusLabel(status) {
  const map = {
    success: '成功',
    done: '成功',
    skipped: '跳过',
    unknown: '未知',
    error: '错误',
    duplicate: '去重',
    pending: '待处理',
    parse_error: '解析失败',
    ai_error: 'AI错误',
    db_error: '数据库错误',
    auth_error: '鉴权错误',
    network_error: '网络错误',
  }
  return map[status] || status
}

/**
 * 格式化日期时间
 * @param {string|null|undefined} isoStr
 * @returns {string}
 */
export function formatDateTime(isoStr) {
  if (!isoStr) return '—'
  try {
    const d = new Date(isoStr)
    return d.toLocaleString('zh-CN', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
  } catch {
    return isoStr
  }
}
