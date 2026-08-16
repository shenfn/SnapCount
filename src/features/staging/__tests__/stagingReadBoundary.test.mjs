import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

test('PWA-049 useStore delegates staging list transport to the repository', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')

  assert.match(source, /stagingRepository\.listOpen\(/)
  assert.match(source, /stagingRepository\.listProcessed\(/)
  assert.doesNotMatch(source, /sb\.from\(['"]staging_records['"]\)/)
  assert.match(source, /const isCurrentDataLoad = \(\) =>/)
  assert.match(source, /if \(!isCurrentDataLoad\(\)\) return \{ ok: false, stale: true \}/)
})

test('PWA-050 staging repository does not own image signing or repayment candidates', async () => {
  const source = await readFile('src/repositories/stagingRepository.js', 'utf8')

  assert.doesNotMatch(source, /getSignedImageUrlMap|createSignedUrl|sign\(/)
  assert.doesNotMatch(source, /repaymentCandidate|ensure_liability_repayment_cycles|buildRepaymentCandidate/)
})
