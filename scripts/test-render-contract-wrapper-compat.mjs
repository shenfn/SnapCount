import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import * as core from '../supabase/functions/_shared/expression-core/render-contract.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/render-contract.mjs'

test('CORE-083 Planner Lab wrapper re-exports production render contract', () => {
  assert.equal(plannerLab.SURFACE_RENDER_CONTRACT_VERSION, core.SURFACE_RENDER_CONTRACT_VERSION)
  assert.equal(plannerLab.SURFACE_RENDER_CONTRACTS, core.SURFACE_RENDER_CONTRACTS)
  assert.equal(plannerLab.buildRenderPlans, core.buildRenderPlans)
  assert.equal(plannerLab.buildExposureEvents, core.buildExposureEvents)
  assert.equal(plannerLab.compileExposureHistory, core.compileExposureHistory)
})

test('CORE-083 Edge runtime imports production render authority without duplicate version literals', async () => {
  const planner = await readFile(new URL('../supabase/functions/ingest-receipt/expression-shadow-planner.ts', import.meta.url), 'utf8')
  const delivery = await readFile(new URL('../supabase/functions/ingest-receipt/expression-delivery.ts', import.meta.url), 'utf8')
  const shadow = await readFile(new URL('../supabase/functions/ingest-receipt/expression-shadow.ts', import.meta.url), 'utf8')

  assert.match(planner, /from "\.\.\/_shared\/expression-core\/render-contract\.mjs"/)
  assert.doesNotMatch(planner, /tools\/ai-validation\/expression-planner\/lib\/render-contract\.mjs/)
  for (const source of [delivery, shadow]) {
    assert.match(source, /SURFACE_RENDER_CONTRACT_VERSION/)
    assert.doesNotMatch(source, /["']surface-render-contract-v0\.1["']/)
  }
})
