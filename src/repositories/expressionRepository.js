export function createExpressionRepository({
  client,
  baseUrl,
  anonKey,
  fetchImpl = globalThis.fetch,
}) {
  if (!client?.auth?.getSession) throw new Error('表达服务缺少鉴权客户端')
  if (typeof fetchImpl !== 'function') throw new Error('表达服务缺少请求实现')

  async function postAction(action, input, { keepalive = false, signal } = {}) {
    const { data: sessionData, error: sessionError } = await client.auth.getSession()
    if (sessionError) throw sessionError
    const token = sessionData?.session?.access_token
    if (!token) throw new Error('登录状态已失效，请重新登录')

    const response = await fetchImpl(`${baseUrl}/functions/v1/ingest-receipt`, {
      method: 'POST',
      keepalive,
      signal,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'apikey': anonKey,
      },
      body: JSON.stringify({
        action,
        ...input,
      }),
    })
    const payload = await response.json().catch(() => ({}))
    if (!response.ok || !payload?.ok) {
      const error = new Error(payload?.error || '表达服务请求失败')
      error.status = response.status
      error.retryable = [408, 425, 429].includes(response.status) || response.status >= 500
      throw error
    }
    return payload.data || null
  }

  return { postAction }
}
