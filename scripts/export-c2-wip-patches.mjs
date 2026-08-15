import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'

const repoRoot = process.cwd()
const args = process.argv.slice(2)
const rootIndex = args.indexOf('--root')
const rootWorktree = path.resolve(
  rootIndex >= 0 && args[rootIndex + 1]
    ? args[rootIndex + 1]
    : process.env.C2_ROOT_WORKTREE || path.resolve(repoRoot, '..', '..'),
)
const outputDir = path.join(repoRoot, 'docs', 'handoff', 'C2-补丁-2026-08-15')

const tracked = {
  personal: [
    'supabase/functions/ingest-receipt/index.ts',
    'supabase/functions/ingest-receipt/prompts.ts',
    'supabase/functions/ingest-receipt/signals.ts',
    'supabase/functions/ingest-receipt/signals_test.ts',
  ],
  security: [
    'scripts/check-security-contracts.mjs',
    'scripts/security-migration-fixture.sql',
    'scripts/test-security-migration.sql',
  ],
  shared: ['.github/workflows/release-validation.yml'],
}

const untracked = {
  personal: [
    'supabase/functions/ingest-receipt/context-packet.ts',
    'supabase/functions/ingest-receipt/context-packet_test.ts',
    'supabase/functions/ingest-receipt/prompts_test.ts',
    'docs/personal-context-architecture-v0.1.md',
    'docs/personal-context-development-log-v0.1.md',
  ],
  security: [],
  shared: [],
}

function runGit(args) {
  return execFileSync('git', args, {
    cwd: rootWorktree,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  })
}

function trackedPatch(files) {
  if (files.length === 0) return ''
  return runGit(['diff', '--binary', 'HEAD', '--', ...files])
}

function untrackedPatch(file) {
  try {
    return runGit(['diff', '--no-index', '--binary', '--', 'NUL', file])
  } catch (error) {
    if (error.status !== 1) throw error
    return error.stdout?.toString() || ''
  }
}

function combinePatch(files, untrackedFiles) {
  return [...[trackedPatch(files)], ...untrackedFiles.map(untrackedPatch)]
    .filter(Boolean)
    .join('\n')
}

const baseCommit = runGit(['rev-parse', 'HEAD']).trim()
mkdirSync(outputDir, { recursive: true })

const outputs = [
  ['personal-context.patch', combinePatch(tracked.personal, untracked.personal)],
  ['security-contract.patch', combinePatch(tracked.security, untracked.security)],
  ['shared-release-validation.patch', combinePatch(tracked.shared, untracked.shared)],
]
for (const [name, content] of outputs) writeFileSync(path.join(outputDir, name), content, 'utf8')

const manifest = `# C2 根 WIP 补丁导出\n\n- 来源工作区：\`${rootWorktree}\`\n- 基线提交：\`${baseCommit}\`\n- 导出时间：2026-08-15\n- 说明：补丁只表达根工作区相对自身 HEAD 的 WIP，不包含 origin/main 的提交漂移。\n\n## 补丁\n\n- \`personal-context.patch\`：Personal Context tracked 修改与 5 个未跟踪文本文件。\n- \`security-contract.patch\`：Security contract 的 3 个脚本文件。\n- \`shared-release-validation.patch\`：共享 workflow 的完整当前差异，后续合并前必须按 hunk 拆分。\n\n## 排除\n\n迁移文件因与 origin/main 内容相同未导出；二进制素材只由 C2 快照登记，不进入文本补丁。\n`
writeFileSync(path.join(outputDir, 'README.md'), manifest, 'utf8')
console.log(`C2 补丁导出完成：${outputDir}`)
console.log(`基线：${baseCommit}`)
