import { createClient } from '@supabase/supabase-js'

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

export { SUPABASE_URL, SUPABASE_ANON_KEY }
export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
