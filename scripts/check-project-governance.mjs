import { existsSync, readdirSync, readFileSync } from 'node:fs'
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

// Legal consent version parity check: iOS LegalDocuments vs public HTML vs latest handle_new_user() migration.
const legalSwiftFile = path.join(root, 'ios/SnapCount/Models/LegalDocuments.swift')
const privacyHtmlFile = path.join(root, 'public/privacy.html')
const termsHtmlFile = path.join(root, 'public/terms.html')
const migrationsDir = path.join(root, 'supabase/migrations')
if (existsSync(legalSwiftFile) && existsSync(migrationsDir)) {
  const legalSwift = readFileSync(legalSwiftFile, 'utf8')
  const versionMatch = legalSwift.match(
    /var\s+version:\s*String\s*\{\s*self\s*==\s*\.privacy\s*\?\s*"(\d{4}-\d{2}-\d{2})"\s*:\s*"(\d{4}-\d{2}-\d{2})"\s*\}/,
  )
  if (!versionMatch) {
    errors.push('无法从 ios/SnapCount/Models/LegalDocuments.swift 解析 privacy/terms 版本号（须为 YYYY-MM-DD）')
  } else {
    const [, iosPrivacyVersion, iosTermsVersion] = versionMatch
    if (existsSync(privacyHtmlFile) && !readFileSync(privacyHtmlFile, 'utf8').includes(iosPrivacyVersion)) {
      errors.push(`public/privacy.html 缺少与 iOS 一致的隐私政策版本 ${iosPrivacyVersion}`)
    }
    if (existsSync(termsHtmlFile) && !readFileSync(termsHtmlFile, 'utf8').includes(iosTermsVersion)) {
      errors.push(`public/terms.html 缺少与 iOS 一致的服务协议版本 ${iosTermsVersion}`)
    }
    const handleNewUserFiles = readdirSync(migrationsDir)
      .filter((name) => name.endsWith('.sql'))
      .sort()
      .filter((name) => /create\s+or\s+replace\s+function\s+public\.handle_new_user\s*\(/i.test(
        readFileSync(path.join(migrationsDir, name), 'utf8'),
      ))
    if (handleNewUserFiles.length === 0) {
      errors.push('未找到 public.handle_new_user() 迁移定义')
    } else {
      const latestSql = readFileSync(path.join(migrationsDir, handleNewUserFiles[handleNewUserFiles.length - 1]), 'utf8')
      const privacyFloor = latestSql.match(/submitted_privacy_version\s*<\s*'(\d{4}-\d{2}-\d{2})'/i)?.[1]
      const termsFloor = latestSql.match(/submitted_terms_version\s*<\s*'(\d{4}-\d{2}-\d{2})'/i)?.[1]
      if (privacyFloor) {
        if (iosPrivacyVersion < privacyFloor) {
          errors.push(`iOS privacy_version (${iosPrivacyVersion}) 低于 handle_new_user 最低版本门槛 (${privacyFloor})`)
        }
      } else if (!latestSql.includes(`'${iosPrivacyVersion}'`)) {
        errors.push(`最新 handle_new_user() 迁移未允许 iOS privacy_version (${iosPrivacyVersion})`)
      }
      if (termsFloor) {
        if (iosTermsVersion < termsFloor) {
          errors.push(`iOS terms_version (${iosTermsVersion}) 低于 handle_new_user 最低版本门槛 (${termsFloor})`)
        }
      } else if (!latestSql.includes(`'${iosTermsVersion}'`)) {
        errors.push(`最新 handle_new_user() 迁移未允许 iOS terms_version (${iosTermsVersion})`)
      }
    }
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
