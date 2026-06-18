/**
 * 网络错误友好化工具
 * ----------------------------------------------------
 * 在 iOS Safari / 微信内置浏览器等环境下，开发者无法直接看到 console，
 * 用户也只会看到 "TLS 错误导致安全连接失败" 这种系统级提示。
 * 本模块将底层的 fetch / TLS / DNS 失败映射为：
 *   - title:       一句话告诉用户发生了什么
 *   - userAction:  用户接下来可以采取的具体动作（多条）
 *   - code:        机器可读的错误码，便于上报和日志聚合
 *   - retryable:   是否值得自动重试
 *
 * 使用方式：
 *   try { ... } catch (e) {
 *     const friendly = toFriendlyNetworkError(e)
 *     showError(friendly)
 *   }
 */

/**
 * 错误码枚举：用于上报、日志聚合、UI 区分。
 */
export const NetworkErrorCode = Object.freeze({
  TLS_HANDSHAKE: 'NET_TLS_HANDSHAKE',          // TLS 握手失败（证书 / 协议 / SNI）
  TLS_CERT_INVALID: 'NET_TLS_CERT_INVALID',    // 证书被拒（自签 / 过期 / 域名不匹配）
  CONNECTION_RESET: 'NET_CONNECTION_RESET',    // 连接被中断
  DNS_FAILURE: 'NET_DNS_FAILURE',              // 域名解析失败
  OFFLINE: 'NET_OFFLINE',                      // 浏览器判定离线
  TIMEOUT: 'NET_TIMEOUT',                      // 请求超时
  CORS: 'NET_CORS',                            // 浏览器 CORS 拦截
  UPSTREAM_TLS: 'NET_UPSTREAM_TLS',            // Worker 报告的上游 TLS 错误
  UPSTREAM_5XX: 'NET_UPSTREAM_5XX',            // 上游 5xx
  GENERIC_FETCH: 'NET_GENERIC_FETCH',          // 兜底 fetch 失败
  UNKNOWN: 'NET_UNKNOWN',
})

/**
 * 用户在不同错误下的指导话术（按优先级展示，最多 3 条）。
 * 写成中文短句，避免技术黑话，便于普通用户理解。
 */
const USER_ACTIONS = {
  [NetworkErrorCode.TLS_HANDSHAKE]: [
    '请尝试关闭手机上的 VPN 或代理软件后重试',
    '切换到其他 Wi-Fi 或改用蜂窝网络试试',
    '若仍失败，请稍后再试，可能是当前网络对加密连接有限制',
  ],
  [NetworkErrorCode.TLS_CERT_INVALID]: [
    '检测到证书异常，常见于 VPN 或公司网络的安全审计',
    '请关闭 VPN / 代理，或切换到不做证书拦截的网络',
    '如使用公司网络，请联系 IT 导入企业根证书',
  ],
  [NetworkErrorCode.CONNECTION_RESET]: [
    '网络连接被中断，请检查 Wi-Fi 信号或切换到 4G/5G',
    '关闭 VPN/加速器后重试',
    '稍等几秒后点击「重新加载」',
  ],
  [NetworkErrorCode.DNS_FAILURE]: [
    '域名解析失败，请检查网络是否正常',
    '尝试切换 DNS 为 1.1.1.1 或 8.8.8.8',
    '若使用 VPN，请关闭后重试',
  ],
  [NetworkErrorCode.OFFLINE]: [
    '设备当前处于离线状态',
    '请打开 Wi-Fi 或开启移动数据后重试',
  ],
  [NetworkErrorCode.TIMEOUT]: [
    '请求超时，可能是网络不稳定',
    '请稍后重试，或切换到信号更好的网络',
  ],
  [NetworkErrorCode.CORS]: [
    '浏览器拒绝了跨域响应，可能是服务端临时异常',
    '请稍后重试，多次失败请反馈给开发者',
  ],
  [NetworkErrorCode.UPSTREAM_TLS]: [
    '后端到数据库的安全连接出现异常（与你的本地网络无关）',
    '稍等 1-2 分钟后重试通常会恢复',
    '若长时间不恢复，请联系开发者',
  ],
  [NetworkErrorCode.UPSTREAM_5XX]: [
    '服务端临时异常，请稍后重试',
    '若多次出现，请反馈给开发者',
  ],
  [NetworkErrorCode.GENERIC_FETCH]: [
    '网络请求失败，请检查网络连接',
    '关闭 VPN/代理后重试',
    '稍后点击「重新加载」',
  ],
  [NetworkErrorCode.UNKNOWN]: [
    '出现未知错误，请稍后重试',
    '若反复出现，请反馈给开发者',
  ],
}

const TITLE_BY_CODE = {
  [NetworkErrorCode.TLS_HANDSHAKE]: '安全连接建立失败',
  [NetworkErrorCode.TLS_CERT_INVALID]: '安全证书验证失败',
  [NetworkErrorCode.CONNECTION_RESET]: '网络连接被中断',
  [NetworkErrorCode.DNS_FAILURE]: '域名解析失败',
  [NetworkErrorCode.OFFLINE]: '当前处于离线状态',
  [NetworkErrorCode.TIMEOUT]: '请求超时',
  [NetworkErrorCode.CORS]: '跨域响应被拦截',
  [NetworkErrorCode.UPSTREAM_TLS]: '后端到数据库的连接异常',
  [NetworkErrorCode.UPSTREAM_5XX]: '服务端临时异常',
  [NetworkErrorCode.GENERIC_FETCH]: '网络请求失败',
  [NetworkErrorCode.UNKNOWN]: '未知错误',
}

const RETRYABLE_CODES = new Set([
  NetworkErrorCode.CONNECTION_RESET,
  NetworkErrorCode.TIMEOUT,
  NetworkErrorCode.UPSTREAM_5XX,
  NetworkErrorCode.GENERIC_FETCH,
  NetworkErrorCode.UPSTREAM_TLS, // 上游可能只是抖动
])

/**
 * 通过原始错误对象推断错误码。
 * 浏览器 fetch 在 TLS 失败时统一抛 TypeError: Failed to fetch / Load failed，
 * 无法拿到底层细节，因此需要结合 navigator.onLine、消息文本、自定义响应体等多维度判断。
 *
 * @param {Error|any} err  原始错误（fetch 抛出 / Response 解析后构造）
 * @param {{ status?: number, body?: any }} [meta]  HTTP 响应元信息，可选
 * @returns {string} NetworkErrorCode
 */
export function detectErrorCode(err, meta = {}) {
  // 1. 服务端返回的结构化错误（来自 Cloudflare Worker）
  if (meta && meta.body && typeof meta.body === 'object') {
    if (meta.body.code === 'UPSTREAM_TLS') return NetworkErrorCode.UPSTREAM_TLS
    if (meta.body.code === 'UPSTREAM_TIMEOUT') return NetworkErrorCode.TIMEOUT
  }
  if (meta && typeof meta.status === 'number') {
    if (meta.status === 504) return NetworkErrorCode.UPSTREAM_TLS
    if (meta.status >= 500) return NetworkErrorCode.UPSTREAM_5XX
  }

  // 2. 浏览器离线
  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    return NetworkErrorCode.OFFLINE
  }

  const msg = (err && (err.message || String(err))) || ''
  const lower = msg.toLowerCase()

  // 3. 关键字匹配：覆盖 Chrome / Safari / Firefox / Node fetch 的常见错误文案
  if (/timeout|timed out|aborted/.test(lower)) return NetworkErrorCode.TIMEOUT
  if (/cert|certificate|self.signed|untrusted|unable to verify/.test(lower)) {
    return NetworkErrorCode.TLS_CERT_INVALID
  }
  if (/ssl|tls|handshake|protocol|cipher/.test(lower)) {
    return NetworkErrorCode.TLS_HANDSHAKE
  }
  if (/econnreset|connection reset|connection closed|socket hang up/.test(lower)) {
    return NetworkErrorCode.CONNECTION_RESET
  }
  if (/dns|getaddrinfo|enotfound|name not resolved/.test(lower)) {
    return NetworkErrorCode.DNS_FAILURE
  }
  if (/cors|cross.origin|blocked by/.test(lower)) {
    return NetworkErrorCode.CORS
  }
  // Safari: "Load failed"；Chrome/Firefox: "Failed to fetch"
  // 这两个都是兜底信号——浏览器把所有底层错误（含 TLS）都抹成同一句话，
  // 因此没有更明确线索时，按"通用 fetch 失败 + 提示可能是 TLS/VPN"处理。
  if (/load failed|failed to fetch|networkerror/.test(lower)) {
    return NetworkErrorCode.GENERIC_FETCH
  }

  return NetworkErrorCode.UNKNOWN
}

/**
 * 把任意错误转换为对用户友好的错误对象。
 * 返回的对象始终包含 title / message / userAction / code / retryable / cause 字段。
 *
 * @param {Error|any} err
 * @param {{ status?: number, body?: any, endpoint?: string }} [meta]
 * @returns {{
 *   title: string,
 *   message: string,
 *   userAction: string[],
 *   code: string,
 *   retryable: boolean,
 *   endpoint: string|undefined,
 *   cause: any,
 * }}
 */
export function toFriendlyNetworkError(err, meta = {}) {
  const code = detectErrorCode(err, meta)
  const title = TITLE_BY_CODE[code] || TITLE_BY_CODE[NetworkErrorCode.UNKNOWN]
  const userAction = USER_ACTIONS[code] || USER_ACTIONS[NetworkErrorCode.UNKNOWN]
  const rawMsg = (err && (err.message || String(err))) || '未知错误'

  // 对于 GENERIC_FETCH，加一句"也可能是 TLS/VPN"提示——
  // 因为浏览器把 TLS 错误也抹成同一句 "Failed to fetch"，
  // 用户看到 VPN 提示能少走很多弯路。
  const hint = code === NetworkErrorCode.GENERIC_FETCH
    ? '（浏览器无法返回详细原因，常见原因为 TLS 加密连接失败或 VPN/代理拦截）'
    : ''

  return {
    title,
    message: hint ? `${rawMsg} ${hint}` : rawMsg,
    userAction: [...userAction],
    code,
    retryable: RETRYABLE_CODES.has(code),
    endpoint: meta.endpoint,
    cause: err,
  }
}

/**
 * 把友好错误对象拍平为多行字符串，用于 toast / alert / 简单 UI 渲染。
 *
 * @param {ReturnType<typeof toFriendlyNetworkError>} friendly
 * @returns {string}
 */
export function formatFriendlyError(friendly) {
  if (!friendly) return ''
  const lines = [friendly.title]
  if (friendly.userAction && friendly.userAction.length) {
    friendly.userAction.forEach((tip, i) => lines.push(`${i + 1}. ${tip}`))
  }
  lines.push(`错误码：${friendly.code}`)
  return lines.join('\n')
}
