export const CURRENT_TERMS_VERSION = '2026-07-19'
export const CURRENT_PRIVACY_VERSION = '2026-07-22'

function throwIfError(error) {
  if (error) throw error
}

export function createAuthRepository({ client, now = () => new Date() }) {
  if (!client?.auth) throw new Error('认证服务缺少 Auth 客户端')

  async function getSession() {
    const { data, error } = await client.auth.getSession()
    throwIfError(error)
    return data?.session || null
  }

  function subscribe(listener) {
    if (typeof listener !== 'function') throw new Error('认证订阅缺少监听器')
    const { data } = client.auth.onAuthStateChange((event, session) => listener(event, session))
    return () => data?.subscription?.unsubscribe?.()
  }

  async function signIn({ email, password }) {
    const { data, error } = await client.auth.signInWithPassword({
      email: String(email || '').trim(),
      password,
    })
    throwIfError(error)
    return { user: data?.user || null, session: data?.session || null }
  }

  async function signUp({
    email,
    password,
    acceptedTerms,
    acceptedSensitiveData,
  }) {
    if (!acceptedTerms) throw new Error('请先同意服务协议和隐私政策')
    if (!acceptedSensitiveData) throw new Error('请先同意敏感数据处理')
    const acceptedAt = now().toISOString()
    const { data, error } = await client.auth.signUp({
      email: String(email || '').trim(),
      password,
      options: {
        data: {
          legal_consent_at: acceptedAt,
          sensitive_data_consent_at: acceptedAt,
          terms_version: CURRENT_TERMS_VERSION,
          privacy_version: CURRENT_PRIVACY_VERSION,
        },
      },
    })
    throwIfError(error)
    return { user: data?.user || null, session: data?.session || null }
  }

  async function signOut() {
    const { error } = await client.auth.signOut()
    throwIfError(error)
    return { ok: true }
  }

  return { getSession, subscribe, signIn, signUp, signOut }
}
