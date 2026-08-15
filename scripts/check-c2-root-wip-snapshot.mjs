import { createHash } from 'node:crypto'
import { readFileSync, statSync } from 'node:fs'
import path from 'node:path'

const repoRoot = process.cwd()
const args = process.argv.slice(2)
const rootIndex = args.indexOf('--root')
const rootWorktree = path.resolve(
  rootIndex >= 0 && args[rootIndex + 1]
    ? args[rootIndex + 1]
    : process.env.C2_ROOT_WORKTREE || path.resolve(repoRoot, '..', '..'),
)
const snapshotPath = path.join(
  repoRoot,
  'docs',
  'handoff',
  'C2-根WIP导出前快照-2026-08-15.md',
)

const snapshot = readFileSync(snapshotPath, 'utf8')
const entries = []
for (const line of snapshot.split(/\r?\n/u)) {
  const match = line.match(/^\|\s+[^|]+\s+\|\s+`([^`]+)`\s+\|\s+(\d+)\s+\|\s+`([0-9a-f]{64})`/u)
  if (match) entries.push({ relativePath: match[1], bytes: Number(match[2]), sha256: match[3] })
}

const errors = []
if (entries.length !== 25) errors.push(`快照条目数为 ${entries.length}，预期 25`)

for (const entry of entries) {
  const filePath = path.join(rootWorktree, entry.relativePath)
  try {
    const stat = statSync(filePath)
    const digest = createHash('sha256').update(readFileSync(filePath)).digest('hex')
    if (stat.size !== entry.bytes) errors.push(`${entry.relativePath}: 字节数 ${stat.size} != ${entry.bytes}`)
    if (digest !== entry.sha256) errors.push(`${entry.relativePath}: SHA-256 已变化`)
  } catch (error) {
    errors.push(`${entry.relativePath}: 无法读取（${error.code || error.message}）`)
  }
}

if (errors.length > 0) {
  console.error(`C2 根 WIP 快照校验失败（${rootWorktree}）：`)
  for (const error of errors) console.error(`- ${error}`)
  process.exitCode = 1
} else {
  console.log(`C2 根 WIP 快照校验通过：${entries.length} 个文件未变化（${rootWorktree}）`)
}
