import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const coreDirectory = path.join(root, 'supabase/functions/_shared/expression-core')
const errors = []

function collectSourceFiles(directory) {
  if (!existsSync(directory)) return []
  const files = []
  const pending = [directory]
  while (pending.length) {
    const current = pending.pop()
    for (const entry of readdirSync(current)) {
      const absolute = path.join(current, entry)
      if (statSync(absolute).isDirectory()) pending.push(absolute)
      else if (entry.endsWith('.mjs') && !entry.endsWith('.test.mjs') && !entry.endsWith('_test.mjs')) files.push(absolute)
    }
  }
  return files
}

if (!existsSync(coreDirectory)) {
  errors.push('缺少表达核心目录：supabase/functions/_shared/expression-core')
} else {
  const forbidden = [
    { pattern: /tools\//u, label: 'tools/ 实验目录' },
    { pattern: /(?:supabase|@supabase)/u, label: 'Supabase 客户端或类型' },
    { pattern: /\bfetch\s*\(/u, label: 'HTTP fetch' },
    { pattern: /\bDeno\b/u, label: 'Deno 专属 API' },
    { pattern: /\bprocess\b/u, label: 'Node process API' },
    { pattern: /from\s+["']node:/u, label: 'Node 专属模块' },
  ]
  for (const file of collectSourceFiles(coreDirectory)) {
    const relative = path.relative(root, file).replaceAll(path.sep, '/')
    const source = readFileSync(file, 'utf8')
    for (const rule of forbidden) {
      if (rule.pattern.test(source)) errors.push(`${relative} 依赖 ${rule.label}`)
    }
  }
}

if (errors.length) {
  console.error('表达核心边界检查失败：')
  for (const error of errors) console.error(`- ${error}`)
  process.exitCode = 1
} else {
  console.log('表达核心边界检查通过：纯函数源文件未发现环境或反向依赖')
}
