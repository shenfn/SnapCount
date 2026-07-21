import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

const supabaseProxyTarget = process.env.VITE_SUPABASE_PROXY_TARGET || 'https://api.snapflow.me'

function supabaseProxy() {
  return {
    target: supabaseProxyTarget,
    changeOrigin: true,
    secure: true,
    ws: true,
    headers: {
      Origin: 'https://snapflow.me',
      Referer: 'https://snapflow.me/',
    },
  }
}

export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: {
      '/auth/v1': supabaseProxy(),
      '/rest/v1': supabaseProxy(),
      '/storage/v1': supabaseProxy(),
      '/functions/v1': supabaseProxy(),
      '/realtime/v1': supabaseProxy(),
      '/graphql/v1': supabaseProxy(),
    },
  },
})
