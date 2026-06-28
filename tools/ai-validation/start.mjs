/**
 * ═══════════════════════════════════════════════
 * AI 识别链路追踪台 - 并行启动脚本
 * ═══════════════════════════════════════════════
 *
 * 同时启动 Express 本地服务和 Vite 开发服务器。
 * 用法: node tools/ai-validation/start.mjs
 *
 * 退出时按 Ctrl+C 会同时关闭两个服务。
 */

import { spawn } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const SERVER_DIR = path.join(__dirname, 'server')
const UI_DIR = path.join(__dirname, 'ui', 'trace-console')
const PROJECT_ROOT = path.resolve(__dirname, '..', '..')

// 检查是否 Windows
const isWindows = process.platform === 'win32'
const shell = isWindows ? true : false

console.log('═══════════════════════════════════════════════')
console.log('  AI 识别链路追踪台 - 并行启动')
console.log('═══════════════════════════════════════════════')
console.log('')

// 启动 Express 服务
const serverProc = spawn('node', ['index.mjs'], {
  cwd: SERVER_DIR,
  shell,
  stdio: 'inherit',
})

serverProc.on('error', (err) => {
  console.error('[server] 启动失败:', err.message)
  console.error('请先在 tools/ai-validation/server/ 下运行 npm install')
})

// 启动 Vite 开发服务器
const uiProc = spawn('npm', ['run', 'dev'], {
  cwd: UI_DIR,
  shell,
  stdio: 'inherit',
})

uiProc.on('error', (err) => {
  console.error('[ui] 启动失败:', err.message)
  console.error('请先在 tools/ai-validation/ui/trace-console/ 下运行 npm install')
})

// 任意一个进程退出时，关闭另一个
serverProc.on('exit', (code) => {
  console.log(`[server] 进程退出，code=${code}`)
  if (!uiProc.killed) uiProc.kill()
  process.exit(code || 0)
})

uiProc.on('exit', (code) => {
  console.log(`[ui] 进程退出，code=${code}`)
  if (!serverProc.killed) serverProc.kill()
  process.exit(code || 0)
})

// Ctrl+C 优雅退出
process.on('SIGINT', () => {
  console.log('\n正在关闭所有服务...')
  if (!serverProc.killed) serverProc.kill()
  if (!uiProc.killed) uiProc.kill()
  process.exit(0)
})

process.on('SIGTERM', () => {
  if (!serverProc.killed) serverProc.kill()
  if (!uiProc.killed) uiProc.kill()
  process.exit(0)
})
