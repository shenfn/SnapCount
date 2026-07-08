/**
 * ═══════════════════════════════════════════════
 * AI 识别链路追踪台 - 并行启动脚本
 * ═══════════════════════════════════════════════
 *
 * 同时启动 Express 本地服务和 Vite 开发服务器。
 * 启动前自动清理 5180/5181 端口的残留进程，避免 EADDRINUSE。
 * 用法: node tools/ai-validation/start.mjs
 *
 * 退出时按 Ctrl+C 会同时关闭两个服务。
 */

import { spawn, execSync } from 'node:child_process'
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

const PORTS = [5180, 5181]

console.log('═══════════════════════════════════════════════')
console.log('  AI 识别链路追踪台 - 并行启动')
console.log('═══════════════════════════════════════════════')
console.log('')

// ═══════════════════════════════════════════════
// 启动前自动清理端口残留进程
// ═══════════════════════════════════════════════
function killPortOccupants() {
  for (const port of PORTS) {
    try {
      if (isWindows) {
        // Windows: 用 netstat 找到占用端口的 PID，再 taskkill
        const output = execSync(`netstat -ano | findstr ":${port} "`, {
          encoding: 'utf8',
          stdio: ['pipe', 'pipe', 'pipe'],
        })
        const pids = new Set()
        for (const line of output.split('\n')) {
          const parts = line.trim().split(/\s+/)
          // LISTENING 状态的才是真正占用端口的进程
          if (parts.length >= 5 && parts[3] === 'LISTENING') {
            const pid = parseInt(parts[4], 10)
            if (pid > 0) pids.add(pid)
          }
        }
        for (const pid of pids) {
          try {
            execSync(`taskkill /PID ${pid} /F`, {
              encoding: 'utf8',
              stdio: ['pipe', 'pipe', 'pipe'],
            })
            console.log(`  端口 ${port}: 已清理旧进程 (PID ${pid})`)
          } catch {
            // 权限不足或进程已退出，忽略
          }
        }
      } else {
        // macOS/Linux: 用 lsof
        try {
          execSync(`lsof -ti:${port} | xargs kill -9`, {
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'pipe'],
          })
          console.log(`  端口 ${port}: 已清理旧进程`)
        } catch {
          // 没有进程占用，忽略
        }
      }
    } catch {
      // netstat/findstr 没找到匹配行时会返回非零退出码，正常情况
    }
  }
}

console.log('检查端口占用...')
killPortOccupants()
console.log('')

// 启动 Express 服务
const serverProc = spawn('node', ['index.mjs'], {
  cwd: SERVER_DIR,
  shell,
  stdio: 'inherit',
  env: {
    ...process.env,
    // 透传项目根目录的 .env.local 环境变量
    PROJECT_ROOT,
  },
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
