import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 追踪台独立 Vite 配置
// 端口 5180，避免与主 PWA(5173) 冲突
// /api 代理到本地 Express 服务(5181)
export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5180,
    strictPort: true,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:5181',
        changeOrigin: false,
      },
    },
  },
})
