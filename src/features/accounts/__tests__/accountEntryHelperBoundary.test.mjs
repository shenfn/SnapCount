import test from 'node:test'
import assert from 'node:assert/strict'
import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'

const SOURCE_EXTENSIONS = new Set(['.js', '.mjs', '.ts', '.vue'])
const FORBIDDEN = [
  /\bupsertAccountEntry\b/u,
  /\bvoidAccountEntries\b/u,
  /\bcreate_account_entry_for_record\b/u,
  /\bvoid_account_entries_for_record\b/u,
]

async function sourceFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const entryPath = path.join(directory, entry.name)
    if (entry.isDirectory()) files.push(...await sourceFiles(entryPath))
    else if (SOURCE_EXTENSIONS.has(path.extname(entry.name))) files.push(entryPath)
  }
  return files
}

test('PWA-069A product source does not expose or call legacy account entry helpers', async () => {
  const findings = []
  for (const file of await sourceFiles('src')) {
    const source = await readFile(file, 'utf8')
    for (const [index, line] of source.split(/\r?\n/u).entries()) {
      if (FORBIDDEN.some(pattern => pattern.test(line))) {
        findings.push(`${file.replaceAll('\\', '/')}:${index + 1}`)
      }
    }
  }

  assert.deepEqual(findings, [])
})
