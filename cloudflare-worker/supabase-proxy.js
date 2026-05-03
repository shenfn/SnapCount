/**
 * Cloudflare Worker: supabase-proxy
 * 部署到 api.snapflow.me，全路径反向代理到 Supabase，并注入 anon key。
 *
 * Worker 环境变量（Settings > Variables）：
 *   SUPABASE_URL      = https://igbghrhsdaolxljgiisf.supabase.co
 *   SUPABASE_ANON_KEY = eyJ...（anon key）
 *
 * ALLOWED_ORIGIN 变量可以删除，不再使用（改为代码内多 origin 匹配）。
 */

const ALLOWED_ORIGINS = [
  'https://snapflow.me',
  'http://localhost:5173',
  'http://localhost:4173',
  'http://localhost:3000',
]

function buildCorsHeaders(requestOrigin, requestedHeaders) {
  const origin = ALLOWED_ORIGINS.includes(requestOrigin)
    ? requestOrigin
    : 'https://snapflow.me'
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    // 关键：回显浏览器请求的 headers，避免预检因 header 不匹配失败
    'Access-Control-Allow-Headers': requestedHeaders || '*',
    'Access-Control-Expose-Headers': 'Content-Range, X-Total-Count, Content-Profile',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin, Access-Control-Request-Headers',
  }
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

    const targetUrl = supabaseUrl + url.pathname + url.search

    // 转发请求头：注入 anon key，移除 Cloudflare 内部 header 避免干扰
    const headers = new Headers(request.headers)
    headers.set('apikey', anonKey)
    headers.delete('host')
    headers.delete('cf-connecting-ip')
    headers.delete('cf-ipcountry')
    headers.delete('cf-ray')
    headers.delete('cf-visitor')

    const fetchOptions = {
      method: request.method,
      headers,
    }
    if (!['GET', 'HEAD'].includes(request.method)) {
      fetchOptions.body = request.body
    }

    try {
      const response = await fetch(targetUrl, fetchOptions)

      const respHeaders = new Headers(response.headers)
      Object.entries(corsHeaders).forEach(([k, v]) => respHeaders.set(k, v))

      return new Response(response.body, {
        status: response.status,
        headers: respHeaders,
      })
    } catch (err) {
      return new Response(
        JSON.stringify({ error: 'Proxy error', detail: err.message }),
        { status: 502, headers: { 'Content-Type': 'application/json', ...corsHeaders } }
      )
    }
  },
}
