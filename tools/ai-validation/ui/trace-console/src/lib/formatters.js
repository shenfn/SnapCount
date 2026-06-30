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

/**
 * 将本地测试 run_id 转成更适合下拉框阅读的中文批次名。
 * 原始 run_id 仍会保留，方便回到 test-results 目录定位文件。
 * @param {object|string} run
 * @returns {string}
 */
export function formatRunLabel(run) {
  const runId = typeof run === 'string' ? run : run?.run_id
  if (!runId) return '未命名批次'

  const suffix = typeof run === 'object' && run?.total_cases != null
    ? ` (${run.success_cases ?? 0}/${run.total_cases})`
    : ''

  const normalized = runId.toLowerCase()
  const numberMatch = runId.match(/(?:^|-)(\d{3,})(?:-|$)/)
  const serial = numberMatch ? ` ${numberMatch[1]}` : ''

  let label = runId
  if (normalized.includes('trace-prototype')) {
    label = `原型验证批次${serial}`
  } else if (normalized.includes('trace-v02') || normalized.includes('trace-v0.2')) {
    const domain = normalized.includes('food') ? '食物' : normalized.includes('sport') ? '运动' : ''
    const mode = normalized.includes('direct') ? '直连' : ''
    label = `V0.2 ${domain}${mode}烟测${serial}`.replace(/\s+/g, ' ').trim()
  } else if (normalized.includes('verify-fix')) {
    label = `修复验证批次${serial}`
  } else if (normalized.includes('verify-link')) {
    label = `链路验证批次${serial}`
  }

  return label === runId ? `${runId}${suffix}` : `${label}${suffix} · ${runId}`
}
