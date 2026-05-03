/**
 * Cloudflare Worker: supabase-proxy
 * 部署到 api.snapflow.me，将所有请求转发到 Supabase，并注入 anon key。
 * 环境变量（Worker Settings > Variables）：
 *   SUPABASE_URL       = https://igbghrhsdaolxljgiisf.supabase.co
 *   SUPABASE_ANON_KEY  = eyJ...（anon key，不暴露到前端）
 *   ALLOWED_ORIGIN     = https://snapflow.me
 */

const CORS_HEADERS = (origin) => ({
  'Access-Control-Allow-Origin': origin,
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey, x-client-info, x-supabase-api-version, prefer, range',
  'Access-Control-Expose-Headers': 'Content-Range, X-Total-Count',
  'Access-Control-Max-Age': '86400',
})

export default {
  async fetch(request, env) {
    const allowedOrigin = env.ALLOWED_ORIGIN || 'https://snapflow.me'
    const supabaseUrl = env.SUPABASE_URL || 'https://igbghrhsdaolxljgiisf.supabase.co'
    const anonKey = env.SUPABASE_ANON_KEY

    const origin = request.headers.get('Origin') || ''
    const corsHeaders = CORS_HEADERS(allowedOrigin)

    // CORS 预检
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders })
    }

    const url = new URL(request.url)

    // 仅代理 Supabase API 路径（REST / Auth / Storage / Functions）
    const validPaths = ['/rest/v1/', '/auth/v1/', '/storage/v1/', '/functions/v1/', '/realtime/v1/']
    const isValid = validPaths.some(p => url.pathname.startsWith(p))
    if (!isValid) {
      return new Response('Not found', { status: 404, headers: corsHeaders })
    }

    const targetUrl = supabaseUrl + url.pathname + url.search

    // 构建转发请求头：注入 anon key，保留 Authorization JWT
    const headers = new Headers(request.headers)
    headers.set('apikey', anonKey)
    headers.delete('host')

    let body = undefined
    if (!['GET', 'HEAD'].includes(request.method)) {
      body = request.body
    }

    try {
      const response = await fetch(targetUrl, {
        method: request.method,
        headers,
        body,
        redirect: 'follow',
      })

      const respHeaders = new Headers(response.headers)
      Object.entries(corsHeaders).forEach(([k, v]) => respHeaders.set(k, v))

      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: respHeaders,
      })
    } catch (err) {
      return new Response(JSON.stringify({ error: 'Proxy error', detail: err.message }), {
        status: 502,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      })
    }
  },
}
