#!/usr/bin/env node

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptDir = dirname(fileURLToPath(import.meta.url))
const tokenPath = join(scriptDir, '..', 'tokens', 'design-tokens.json')
const tokens = JSON.parse(readFileSync(tokenPath, 'utf8'))

const requirements = [
  { foreground: 'ink', background: 'paper', minimum: 7, usage: 'primary text' },
  { foreground: 'muted', background: 'paper', minimum: 4.5, usage: 'secondary text' },
  { foreground: 'brand', background: 'paper', minimum: 4.5, usage: 'brand text and links' },
  { foreground: 'coral', background: 'paper', minimum: 4.5, usage: 'error and destructive text' },
  { foreground: 'paper', background: 'space', minimum: 4.5, usage: 'text on deep surfaces' },
]

function parseHex(value) {
  if (!/^#[0-9a-f]{6}$/i.test(value)) {
    throw new Error(`Invalid color value: ${value}`)
  }
  return [1, 3, 5].map((index) => Number.parseInt(value.slice(index, index + 2), 16) / 255)
}

function relativeLuminance(value) {
  const [red, green, blue] = parseHex(value).map((channel) => (
    channel <= 0.04045
      ? channel / 12.92
      : ((channel + 0.055) / 1.055) ** 2.4
  ))
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue
}

function contrastRatio(foreground, background) {
  const foregroundLuminance = relativeLuminance(foreground)
  const backgroundLuminance = relativeLuminance(background)
  const lighter = Math.max(foregroundLuminance, backgroundLuminance)
  const darker = Math.min(foregroundLuminance, backgroundLuminance)
  return (lighter + 0.05) / (darker + 0.05)
}

const failures = []

for (const theme of tokens.color.themes) {
  console.log(`${theme.name} (${theme.id})`)
  for (const requirement of requirements) {
    const ratio = contrastRatio(
      theme.colors[requirement.foreground],
      theme.colors[requirement.background]
    )
    const passed = ratio >= requirement.minimum
    const result = `${passed ? 'PASS' : 'FAIL'} ${requirement.foreground}/${requirement.background} ${ratio.toFixed(2)}:1 (min ${requirement.minimum}:1)`
    console.log(`  ${result}`)
    if (!passed) {
      failures.push(`${theme.id}: ${result} for ${requirement.usage}`)
    }
  }
}

if (failures.length > 0) {
  console.error(`\nContrast validation failed with ${failures.length} issue(s):`)
  failures.forEach((failure) => console.error(`- ${failure}`))
  process.exit(1)
}

console.log(`\nContrast validation passed for ${tokens.color.themes.length} themes.`)
