/**
 * Cloudflare Worker: supabase-proxy
 * 部署到 api.snapflow.me，全路径反向代理到 Supabase，并注入 anon key。
 *
 * Worker 环境变量（Settings > Variables）：
 *   SUPABASE_URL      = https://igbghrhsdaolxljgiisf.supabase.co
 *   SUPABASE_ANON_KEY = eyJ...（anon key）
 *
 * 设计要点（友好错误回传）：
 *   1. 上游 fetch 失败时，按错误关键字识别 TLS / DNS / 超时 / 重置等场景；
 *   2. 返回 JSON 结构化错误体：{ code, title, userAction[], detail, target }，
 *      让前端（尤其是 iOS Safari，无法看 console 的环境）能直接渲染指导文案；
 *   3. HTTP 状态码语义化：
 *        504 = 上游 TLS / 超时（可重试）
 *        502 = 上游连接异常（可重试）
 *        500 = Worker 自身异常（极少出现）
 *   4. 增加分路径超时控制（AbortController），避免链路异常时长时间挂起。
 *      普通 Supabase API 保持 30s，AI 图片识别链路允许更长等待。
 */

const ALLOWED_ORIGINS = [
  'https://snapflow.me',
  'http://localhost:5173',
  'http://localhost:5174',
  'http://localhost:4173',
  'http://localhost:3000',
]

// 上游请求超时（毫秒）。普通 API 不应长时间挂起，AI 识别原图/拍照链路可能需要更久。
const DEFAULT_UPSTREAM_TIMEOUT_MS = 30_000
const INGEST_RECEIPT_TIMEOUT_MS = 120_000

function buildCorsHeaders(requestOrigin, requestedHeaders) {
  const origin = ALLOWED_ORIGINS.includes(requestOrigin)
    ? requestOrigin
    : 'https://snapflow.me'
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    // 关键：回显浏览器请求的 headers，避免预检因 header 不匹配失败
    'Access-Control-Allow-Headers': requestedHeaders || '*',
    'Access-Control-Expose-Headers': 'Content-Range, X-Total-Count, Content-Profile, X-Proxy-Error-Code',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin, Access-Control-Request-Headers',
  }
}

/**
 * 把上游 fetch 抛出的错误归类为可读的错误码 + 用户指导。
 * Cloudflare Worker 的 fetch 错误大多形如：
 *   - "fetch failed"
 *   - "Network connection lost"
 *   - "TLS handshake error" / "SSL handshake failed"
 *   - "Aborted" / "The operation was aborted"
 *   - "Name resolution failed"
 *
 * @param {Error} err
 * @returns {{
 *   status: number,
 *   code: string,
 *   title: string,
 *   userAction: string[],
 * }}
 */
function isIngestReceiptRequest(method, pathname) {
  return method === 'POST' && pathname === '/functions/v1/ingest-receipt'
}

function getUpstreamTimeoutMs(request) {
  const url = new URL(request.url)
  if (isIngestReceiptRequest(request.method, url.pathname)) {
    return INGEST_RECEIPT_TIMEOUT_MS
  }
  return DEFAULT_UPSTREAM_TIMEOUT_MS
}

function classifyUpstreamError(err, { timeoutMs, isIngestReceipt }) {
  const msg = (err && (err.message || String(err))) || ''
  const lower = msg.toLowerCase()

  if (/aborted|timeout|timed out/.test(lower)) {
    return {
      status: 504,
      code: 'UPSTREAM_TIMEOUT',
      title: isIngestReceipt ? 'AI 识别耗时较长' : '后端请求超时',
      userAction: isIngestReceipt
        ? [
            `本次请求超过 ${Math.round(timeoutMs / 1000)} 秒仍未完成，可能是图片较大或模型识别较慢`,
            '请稍后重试，或尝试使用压缩后的截图/照片',
            '若多次出现，请联系开发者',
          ]
        : [
            `本次请求超过 ${Math.round(timeoutMs / 1000)} 秒仍未完成`,
            '请稍后重试',
            '若多次出现，请联系开发者',
          ],
    }
  }

  if (/tls|ssl|handshake|certificate|cipher/.test(lower)) {
    return {
      status: 504,
      code: 'UPSTREAM_TLS',
      title: '后端到数据库的安全连接异常',
      userAction: [
        '此问题与你的本地网络无关，请稍后 1-2 分钟再试',
        '若长时间不恢复，请联系开发者',
      ],
    }
  }

  if (/dns|name resolution|getaddrinfo|enotfound/.test(lower)) {
    return {
      status: 502,
      code: 'UPSTREAM_DNS',
      title: '后端无法解析数据库域名',
      userAction: [
        '请稍后重试',
        '若多次出现，请联系开发者',
      ],
    }
  }

  if (/connection|reset|closed|network/.test(lower)) {
    return {
      status: 502,
      code: 'UPSTREAM_CONNECTION',
      title: '后端到数据库的连接被中断',
      userAction: [
        '请稍后重试',
        '若多次出现，请联系开发者',
      ],
    }
  }

  return {
    status: 502,
    code: 'UPSTREAM_UNKNOWN',
    title: '后端代理出现未知错误',
    userAction: [
      '请稍后重试',
      '若多次出现，请联系开发者并附带错误码',
    ],
  }
}

/**
 * 构造统一的错误响应体（JSON）。
 */
function buildErrorResponse(classification, detail, targetUrl, corsHeaders, timeoutMs) {
  const body = {
    error: classification.title,
    code: classification.code,
    title: classification.title,
    userAction: classification.userAction,
    detail,
    target: targetUrl,
    timeoutMs,
    timestamp: new Date().toISOString(),
  }
  return new Response(JSON.stringify(body), {
    status: classification.status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      // 把错误码也放进自定义 header，便于前端在不解析 body 的情况下也能拿到
      'X-Proxy-Error-Code': classification.code,
      ...(timeoutMs ? { 'X-Proxy-Timeout-Ms': String(timeoutMs) } : {}),
      ...corsHeaders,
    },
  })
}

export default {
  async fetch(request, env) {
    const supabaseUrl = env.SUPABASE_URL || 'https://igbghrhsdaolxljgiisf.supabase.co'
    const anonKey = env.SUPABASE_ANON_KEY

    const url = new URL(request.url)
    const requestOrigin = request.headers.get('Origin') || ''
    const requestedHeaders = request.headers.get('Access-Control-Request-Headers') || ''
    const corsHeaders = buildCorsHeaders(requestOrigin, requestedHeaders)

    // 诊断日志（可在 Cloudflare Workers Logs 中查看）
    console.log(`[proxy] ${request.method} ${url.pathname}${url.search} origin=${requestOrigin} req-headers=${requestedHeaders}`)

    // CORS 预检
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders })
    }

    // anon key 缺失时直接返回明确错误，避免上游因鉴权失败掩盖根因
    if (!anonKey) {
      return buildErrorResponse(
        {
          status: 500,
          code: 'PROXY_MISCONFIGURED',
          title: '后端代理未正确配置',
          userAction: [
            '此为后端配置问题，请联系开发者',
            '错误原因：Worker 未配置 SUPABASE_ANON_KEY',
          ],
        },
        'Missing SUPABASE_ANON_KEY env var',
        url.toString(),
        corsHeaders,
        null,
      )
    }

    const targetUrl = supabaseUrl + url.pathname + url.search
    const isIngestReceipt = isIngestReceiptRequest(request.method, url.pathname)
    const timeoutMs = getUpstreamTimeoutMs(request)

    // 转发请求头：注入 anon key，移除 Cloudflare 内部 header 避免干扰
    const headers = new Headers(request.headers)
    headers.set('apikey', anonKey)
    headers.delete('host')
    headers.delete('cf-connecting-ip')
    headers.delete('cf-ipcountry')
    headers.delete('cf-ray')
    headers.delete('cf-visitor')

    // 用 AbortController 加超时，避免 TLS 异常时永远挂起
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs)

    const fetchOptions = {
      method: request.method,
      headers,
      signal: controller.signal,
    }
    if (!['GET', 'HEAD'].includes(request.method)) {
      fetchOptions.body = request.body
    }

    try {
      const response = await fetch(targetUrl, fetchOptions)
      clearTimeout(timeoutId)

      const respHeaders = new Headers(response.headers)
      Object.entries(corsHeaders).forEach(([k, v]) => respHeaders.set(k, v))
      respHeaders.set('X-Proxy-Timeout-Ms', String(timeoutMs))

      return new Response(response.body, {
        status: response.status,
        headers: respHeaders,
      })
    } catch (err) {
      clearTimeout(timeoutId)
      const classification = classifyUpstreamError(err, { timeoutMs, isIngestReceipt })
      console.error(`[proxy-error] code=${classification.code} timeout=${timeoutMs} target=${targetUrl} detail=${err.message}`)
      return buildErrorResponse(classification, err.message, targetUrl, corsHeaders, timeoutMs)
    }
  },
}
