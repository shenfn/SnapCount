import { createClient } from '@supabase/supabase-js'
import { toFriendlyNetworkError, NetworkErrorCode } from './networkError.js'

// 生产环境应设为 Cloudflare Worker 地址 https://api.snapflow.me，
// 避免前端直连 Supabase 新加坡节点（国内移动网络不稳定）。
// 本地开发可设为 Supabase 直连地址。
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!SUPABASE_URL) {
  throw new Error('Missing VITE_SUPABASE_URL in environment (set to https://api.snapflow.me for production)')
}
if (!SUPABASE_ANON_KEY) {
  throw new Error('Missing VITE_SUPABASE_ANON_KEY in local environment')
}

/**
 * 自定义错误类：让上层（useStore、AuthPage 等）能直接拿到 friendly 字段，
 * 而不需要每个调用点都自己跑一遍错误识别。
 */
export class FriendlyNetworkError extends Error {
  constructor(friendly) {
    super(friendly.message || friendly.title)
    this.name = 'FriendlyNetworkError'
    this.friendly = friendly
    this.code = friendly.code
    this.userAction = friendly.userAction
    this.title = friendly.title
    this.retryable = friendly.retryable
  }
}

/**
 * 包装后的 fetch：
 *   1. 捕获底层 fetch 抛出的 TypeError（含 TLS/DNS/网络错误）；
 *   2. 解析 Worker 返回的结构化错误体（4xx/5xx 且 Content-Type=application/json 且含 code/userAction）；
 *   3. 命中以上两类时抛 FriendlyNetworkError，让上层拿到 friendly。
 *
 * 设计要点：
 *   - 只在 **网络层** 错误或 **Worker 自定义错误** 时抛出；
 *     业务层（如 Postgres 返回的 4xx）保持原响应直通，
 *     由 supabase-js 自己解析成 { data: null, error } —— 不破坏 SDK 的契约。
 */
async function friendlyFetch(input, init) {
  const url = typeof input === 'string' ? input : input.url

  let response
  try {
    response = await fetch(input, init)
  } catch (err) {
    // 网络层失败（TLS / DNS / CORS / 离线 / 超时 等），浏览器只会抛 TypeError
    const friendly = toFriendlyNetworkError(err, { endpoint: url })
    // 控制台留一份完整堆栈，方便 Web Inspector / vConsole 排查
    console.error('[supabase-fetch] network error', { url, code: friendly.code, raw: err })
    // 挂到全局，供 supabase-js 包装后的上层代码读取（supabase-js 会吞掉 FriendlyNetworkError 实例）
    if (typeof window !== 'undefined') {
      friendly.__timestamp = Date.now()
      window.__lastSupabaseNetworkError = friendly
    }
    throw new FriendlyNetworkError(friendly)
  }

  // Worker 自定义错误：通过自定义 header 快速识别，避免误吞业务层 5xx
  const proxyErrorCode = response.headers.get('X-Proxy-Error-Code')
  if (proxyErrorCode) {
    // 克隆一份用于解析，原始 response 不能消费（supabase-js 后续可能要读 body）
    let body = null
    try {
      body = await response.clone().json()
    } catch (_) {
      // 非 JSON 也没关系，按状态码兜底
    }
    const friendly = toFriendlyNetworkError(
      new Error(body?.detail || body?.error || `Upstream error ${response.status}`),
      { endpoint: url, status: response.status, body },
    )
    // 若 Worker 已经给出了 userAction，直接覆盖前端默认文案，更精准
    if (body && Array.isArray(body.userAction) && body.userAction.length) {
      friendly.userAction = body.userAction
    }
    if (body && body.title) friendly.title = body.title
    console.error('[supabase-fetch] proxy error', { url, status: response.status, code: friendly.code, body })
    throw new FriendlyNetworkError(friendly)
  }

  return response
}

export { SUPABASE_URL, SUPABASE_ANON_KEY }
export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: {
    fetch: friendlyFetch,
  },
})

// 同步导出错误码与转换工具，业务层可以按需直接 import
export { NetworkErrorCode, toFriendlyNetworkError }
