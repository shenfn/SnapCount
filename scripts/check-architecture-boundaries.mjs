import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const baselineFile = path.join(root, 'scripts/architecture-boundary-baseline.json')
const errors = []
const warnings = []

function relativePath(file) {
  return path.relative(root, file).replaceAll(path.sep, '/')
}

function readBaseline() {
  if (!existsSync(baselineFile)) {
    errors.push('缺少架构依赖基线：scripts/architecture-boundary-baseline.json')
    return { rules: {} }
  }
  try {
    return JSON.parse(readFileSync(baselineFile, 'utf8'))
  } catch (error) {
    errors.push(`架构依赖基线不是有效 JSON：${error.message}`)
    return { rules: {} }
  }
}

function listFiles(relativeDirectory, extensions) {
  const directory = path.join(root, relativeDirectory)
  if (!existsSync(directory)) return []
  const files = []
  const stack = [directory]
  while (stack.length) {
    const current = stack.pop()
    for (const entry of readdirSync(current)) {
      const absolute = path.join(current, entry)
      if (statSync(absolute).isDirectory()) stack.push(absolute)
      else if (extensions.some(extension => entry.endsWith(extension))) files.push(absolute)
    }
  }
  return files
}

function scanImports(relativeDirectories, pattern) {
  const findings = []
  for (const directory of relativeDirectories) {
    for (const file of listFiles(directory, ['.ts', '.js', '.mjs', '.vue'])) {
      const text = readFileSync(file, 'utf8')
      for (const [index, line] of text.split(/\r?\n/u).entries()) {
        const match = line.match(pattern)
        if (!match) continue
        findings.push({ file: relativePath(file), line: index + 1, target: match[1] ?? match[0].trim() })
      }
    }
  }
  return findings
}

function key(finding) {
  return `${finding.file}:${finding.target}`
}

function checkRatchet(ruleId, findings, baseline) {
  const known = new Set(baseline.rules?.[ruleId]?.known ?? [])
  const current = new Set(findings.map(key))
  const added = [...current].filter(value => !known.has(value)).sort()
  const removed = [...known].filter(value => !current.has(value)).sort()
  if (added.length) {
    errors.push(`${ruleId} 新增架构违规（${added.length}）：${added.join(', ')}`)
  }
  if (removed.length) {
    warnings.push(`${ruleId} 已移除基线项（${removed.length}），迁移完成后应更新例外清单：${removed.join(', ')}`)
  }
  return { current: [...current].sort(), added, removed }
}

const baseline = readBaseline()
const productionTools = scanImports(
  ['supabase/functions'],
  /from\s+["']([^"']*tools\/[^"']+)["']/u,
)
const pageSupabase = scanImports(
  ['src/components'],
  /from\s+["']([^"']*lib\/supabase)["']|((?:fetch|createClient)\s*\()/u,
)
const domainForbidden = scanImports(
  ['src/domains'],
  /from\s+["'](vue|@supabase\/|[^"']*supabase[^"']*)["']|(fetch\s*\()/u,
)

const results = {
  production_tools_imports: checkRatchet('production_tools_imports', productionTools, baseline),
  page_supabase_access: checkRatchet('page_supabase_access', pageSupabase, baseline),
  domain_forbidden_imports: checkRatchet('domain_forbidden_imports', domainForbidden, baseline),
}

for (const [ruleId, result] of Object.entries(results)) {
  const mode = baseline.rules?.[ruleId]?.mode ?? 'unknown'
  console.log(`${ruleId}: ${result.current.length} 项，模式 ${mode}`)
}

if (baseline.rules?.rpc_contracts?.mode === 'manual') {
  warnings.push('rpc_contracts 当前仍为人工清单；A3/A5 建立契约注册表后再启用自动检查')
}
if (baseline.rules?.duplicated_business_rules?.mode === 'manual') {
  warnings.push('duplicated_business_rules 当前仍为人工基线；A2 先确定 expression-core 权威边界')
}

if (errors.length) {
  console.error('架构依赖检查失败：')
  for (const error of errors) console.error(`- ${error}`)
  for (const warning of warnings) console.warn(`警告：${warning}`)
  process.exitCode = 1
} else {
  console.log('架构依赖检查通过：未发现超出基线的新违规')
  for (const warning of warnings) console.warn(`警告：${warning}`)
}
