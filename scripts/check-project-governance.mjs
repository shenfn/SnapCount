import { existsSync, readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import path from 'node:path'

const root = process.cwd()
const errors = []
const warnings = []

function relativePath(file) {
  return path.relative(root, file).replaceAll(path.sep, '/')
}

function requireFile(relative) {
  const absolute = path.join(root, relative)
  if (!existsSync(absolute)) errors.push(`缺少治理入口文件：${relative}`)
  return absolute
}

function requireText(file, label, fragments) {
  if (!existsSync(file)) return
  const text = readFileSync(file, 'utf8')
  for (const fragment of fragments) {
    if (!text.includes(fragment)) errors.push(`${label} 缺少必要内容：${fragment}`)
  }
}

const agentsFile = requireFile('AGENTS.md')
const specIndexFile = requireFile('docs/spec/规格文档索引.md')
const phaseIndexFile = requireFile('docs/spec/03-阶段与任务索引.md')
const governanceSpecFile = requireFile('docs/spec/04-架构治理与进度保护规范.md')
const masterPlanFile = requireFile('docs/spec/05-仓库清洗与架构收拢实施计划.md')
requireFile('docs/decisions/ADR-模板.md')
requireFile('docs/handoff/任务交接快照模板.md')

requireText(agentsFile, 'AGENTS.md', [
  'docs/spec/规格文档索引.md',
  'docs/spec/03-阶段与任务索引.md',
  'docs/spec/04-架构治理与进度保护规范.md',
])
requireText(phaseIndexFile, '阶段与任务索引', ['当前阶段', '冻结范围', '下一步'])
requireText(governanceSpecFile, '架构治理规范', ['唯一入口与指针链', '工作区与分支', '收尾与接续'])
requireText(masterPlanFile, '清洗与架构总计划', ['Git 清洗线', '架构收拢线', '总体路线', '终止与回滚条件'])

if (existsSync(specIndexFile)) {
  const indexText = readFileSync(specIndexFile, 'utf8')
  const links = [...indexText.matchAll(/\[[^\]]+\]\(([^)#]+)(?:#[^)]+)?\)/g)]
  for (const [, link] of links) {
    if (/^(?:https?:|mailto:)/u.test(link)) continue
    const target = path.resolve(path.dirname(specIndexFile), link)
    if (!existsSync(target)) errors.push(`规格索引存在失效链接：${link}`)
  }
}

let branch = process.env.GITHUB_HEAD_REF || process.env.GITHUB_REF_NAME || ''
if (!branch) {
  try {
    branch = execFileSync('git', ['branch', '--show-current'], { encoding: 'utf8' }).trim()
  } catch {
    warnings.push('无法读取当前 Git 分支，跳过分支命名检查')
  }
}

if (branch && branch !== 'main') {
  const valid = /^(?:feature|fix|refactor|docs|test|chore|release)\/[^\s/]+$/u.test(branch)
  if (branch.startsWith('codex/')) {
    warnings.push(`历史分支命名仍为 ${branch}，新任务不得继续使用 codex/ 前缀`)
  } else if (!valid) {
    errors.push(`分支名不符合规范：${branch}；新分支应使用 feature/、fix/、refactor/、docs/、test/、chore/ 或 release/ 前缀`)
  }
}

if (process.argv.includes('--require-clean')) {
  const status = execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim()
  if (status) errors.push('要求 clean，但当前 worktree 存在未提交改动')
}

if (errors.length > 0) {
  console.error('治理检查失败：')
  for (const error of errors) console.error(`- ${error}`)
  process.exitCode = 1
} else {
  console.log(`治理检查通过：${relativePath(phaseIndexFile)} 已连接到当前入口`)
}

for (const warning of warnings) console.warn(`警告：${warning}`)
