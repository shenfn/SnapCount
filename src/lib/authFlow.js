const CALLBACK_QUERY_KEYS = [
  'auth_action',
  'code',
  'error',
  'error_code',
  'error_description',
]

function asURL(input) {
  if (input instanceof URL) return new URL(input.toString())
  return new URL(String(input), 'https://snapflow.me')
}

function hashParameters(url) {
  return new URLSearchParams(url.hash.replace(/^#/, ''))
}

export function hasAuthCallbackPayload(input) {
  const url = asURL(input)
  const hash = hashParameters(url)
  return Boolean(
    url.searchParams.get('code')
      || url.searchParams.get('error')
      || url.searchParams.get('error_code')
      || hash.get('access_token')
      || hash.get('error')
      || hash.get('error_code'),
  )
}

export function readAuthCallbackIntent(input) {
  const url = asURL(input)
  const hash = hashParameters(url)
  const action = url.searchParams.get('auth_action')
  const type = hash.get('type')
  const hasCallbackPayload = hasAuthCallbackPayload(url)

  if (type === 'recovery' || (action === 'recovery' && hasCallbackPayload)) {
    return 'recovery'
  }
  if (
    ['signup', 'email', 'magiclink'].includes(type)
      || (action === 'confirm' && hasCallbackPayload)
  ) {
    return 'confirmation'
  }
  return null
}

export function authCallbackError(input) {
  const url = asURL(input)
  const hash = hashParameters(url)
  const code = url.searchParams.get('error_code') || hash.get('error_code') || ''
  const description = url.searchParams.get('error_description') || hash.get('error_description') || ''
  if (!code && !description && !url.searchParams.get('error') && !hash.get('error')) return null
  return { code, message: description }
}

export function authRedirectURL(action, origin = window.location.origin) {
  const url = new URL('/', origin)
  url.searchParams.set('auth_action', action)
  return url.toString()
}

export function sanitizedAuthCallbackPath(input) {
  const url = asURL(input)
  for (const key of CALLBACK_QUERY_KEYS) url.searchParams.delete(key)
  url.hash = ''
  return `${url.pathname}${url.search}` || '/'
}

export function friendlyAuthError(error, context = 'default') {
  const clientMessage = String(error?.message || '')
  const allowedClientMessages = new Set([
    '请输入注册邮箱',
    '新密码至少需要 8 位',
    '两次输入的新密码不一致',
    '重置链接尚未验证',
    '登录未建立有效会话，请确认邮箱后重试',
    '注册未建立有效会话，请稍后重试',
  ])
  if (allowedClientMessages.has(clientMessage)) return clientMessage

  const code = String(error?.code || error?.name || '').toLowerCase()
  const message = clientMessage.toLowerCase()
  const value = `${code} ${message}`

  if (value.includes('invalid login credentials')) return '邮箱或密码不正确'
  if (value.includes('email not confirmed')) return '请先完成邮箱确认，再返回登录'
  if (value.includes('user already registered')) return '该邮箱已注册，请直接登录或找回密码'
  if (value.includes('email_address_invalid') || value.includes('invalid email')) return '请输入有效的邮箱地址'
  if (value.includes('weak_password') || value.includes('password should be')) return '密码强度不足，请设置更长的密码'
  if (value.includes('same_password')) return '新密码不能与当前密码相同'
  if (
    value.includes('over_email_send_rate_limit')
      || value.includes('rate limit')
      || value.includes('too many requests')
  ) return '操作过于频繁，请稍后再试'
  if (
    value.includes('otp_expired')
      || value.includes('flow_state_not_found')
      || value.includes('bad_code_verifier')
      || value.includes('expired')
  ) return context === 'confirmation' ? '确认链接已失效，请重新发送确认邮件' : '重置链接已失效，请重新发送'
  if (
    value.includes('load failed')
      || value.includes('failed to fetch')
      || value.includes('networkerror')
      || value.includes('network error')
      || value.includes('timeout')
  ) return '网络连接不稳定，请检查网络后重试'

  if (context === 'recovery-email') return '重置邮件暂时无法发送，请稍后重试'
  if (context === 'confirmation') return '邮箱确认暂时失败，请重新发送确认邮件'
  if (context === 'resend') return '确认邮件暂时无法发送，请稍后重试'
  if (context === 'password-update') return '密码更新失败，请重新打开重置链接后再试'
  return '操作失败，请稍后重试'
}
