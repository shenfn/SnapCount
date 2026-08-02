import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { normalizeExposureFeedback, primaryChoiceFromLegacyReview } from './lib/exposure-feedback-contract.mjs'
import { derivePreferenceSignals } from './lib/preference-signal-deriver.mjs'
import { aggregatePreferenceSignals, toScoringPreferenceProfile } from './lib/preference-signal-aggregator.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../..')
const sourceDir = path.join(root, 'test-results', 'remote-2026-07-12', 'remote', '2026-07-12')
const outputPath = path.join(root, 'test-results', 'expression-planner', 'feedback-preview-2026-07-12.json')
const userId = process.argv.find(arg => arg.startsWith('--user-id='))?.slice(10)
if (!userId) throw new Error('Missing required --user-id=<uuid>')

const filenames = (await readdir(sourceDir)).filter(name => name.endsWith('.review.json')).sort()
const previews = []
for (const filename of filenames) {
  const review = JSON.parse(await readFile(path.join(sourceDir, filename), 'utf8'))
  const primaryChoice = primaryChoiceFromLegacyReview(review)
  const feedback = normalizeExposureFeedback({
    primaryChoice,
    legacyIssueTags: review.issue_tags,
    notes: review.notes,
    suggestedAction: review.suggested_action,
  }, {
    feedbackKey: `legacy:${review.case_key}`,
    occurredAt: review.reviewed_at,
    userId,
    legacyImport: true,
    sourceReviewSchema: review.schema_version,
    sourceReviewKey: review.case_key,
    metadata: { source: 'local_review_v1_preview', filename },
  })
  previews.push({ feedback, derived: derivePreferenceSignals(feedback) })
}

const signals = previews.flatMap(item => item.derived.signals)
const preferenceSnapshot = aggregatePreferenceSignals(signals, { asOf: '2026-07-13T12:00:00+08:00' })
const scoringPreferenceProfile = toScoringPreferenceProfile(preferenceSnapshot)

await mkdir(path.dirname(outputPath), { recursive: true })
await writeFile(outputPath, JSON.stringify({
  generated_at: new Date().toISOString(),
  simulation_only: true,
  insert_executed: false,
  source_date: '2026-07-12',
  count: previews.length,
  preference_snapshot: preferenceSnapshot,
  scoring_preference_profile: scoringPreferenceProfile,
  previews,
}, null, 2))
console.log(`Wrote ${previews.length} feedback previews to ${outputPath}`)
