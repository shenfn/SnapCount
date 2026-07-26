import test from 'node:test'
import assert from 'node:assert/strict'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')
const entryPoint = path.join(root, 'supabase/functions/ingest-receipt/expression-feedback.ts')

async function loadModule() {
  const bundle = await build({
    absWorkingDir: root,
    entryPoints: [entryPoint],
    bundle: true,
    platform: 'node',
    format: 'esm',
    write: false,
  })
  const url = `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}#${Math.random()}`
  return import(url)
}

function queryRows(rows) {
  return {
    select() { return this },
    eq() { return this },
    order() { return this },
    limit() { return Promise.resolve({ data: rows, error: null }) },
  }
}

function database(exposure) {
  const state = { exposureBundles: [], feedback: [], signals: [], snapshot: null, revision: 0 }
  return {
    state,
    client: {
      async rpc(name, params) {
        if (name === 'persist_expression_exposure_with_sources') {
          const persisted = { id: 'legacy-exposure-1', ...params.p_exposure }
          state.exposureBundles.push({ exposure: persisted, sources: params.p_sources })
          return { data: { exposure: persisted, created: true }, error: null }
        }
        if (name === 'replace_expression_feedback_bundle') {
          state.revision += 1
          const reviewedExposure = exposure ?? state.exposureBundles.at(-1)?.exposure ?? {}
          const exposureMetadata = reviewedExposure.metadata ?? {}
          state.feedback = [{
            id: 'feedback-1',
            ...params.p_feedback,
            metadata: {
              source: 'native_or_pwa_record_detail',
              record_id: reviewedExposure.record_id,
              semantic_bundle: {},
              decision_id: exposureMetadata.decision_id ?? null,
              policy_name: exposureMetadata.policy_name ?? null,
              policy_version: exposureMetadata.policy_version ?? null,
              selection_probability: exposureMetadata.selection_probability ?? null,
            },
          }]
          state.signals = params.p_signals
          return {
            data: { feedback: state.feedback[0], source_revision: state.revision },
            error: null,
          }
        }
        if (name === 'get_expression_preference_source') {
          return {
            data: {
              source_revision: state.revision,
              feedback_rows: state.feedback,
              signal_rows: state.signals,
            },
            error: null,
          }
        }
        if (name === 'upsert_expression_preference_snapshot_if_newer') {
          if (params.p_source_revision !== state.revision) return { data: false, error: null }
          state.snapshot = {
            snapshot: params.p_snapshot,
            scoring_profile: params.p_scoring_profile,
            source_revision: params.p_source_revision,
          }
          return { data: true, error: null }
        }
        throw new Error(`Unexpected RPC: ${name}`)
      },
      from(table) {
        if (table === 'transactions') {
          return {
            select() { return this },
            eq() { return this },
            async maybeSingle() {
              return {
                data: {
                  id: 'record-1',
                  created_at: '2026-07-25T08:00:00Z',
                  transaction_date: '2026-07-25',
                  ai_feedback: {
                    version: 'feedback-v1',
                    icon: 'sparkles',
                    badge: '记录洞察',
                    emotion_line: '这次记录很清楚',
                    utility_line: '可以继续保持',
                    internal_score: 87,
                    structured_value: { private: true },
                  },
                  companion_message: 'not rendered in the feedback card',
                },
                error: null,
              }
            },
          }
        }
        if (table === 'expression_exposure_events') {
          return {
            select() {
              return {
                eq() { return this },
                async maybeSingle() { return { data: exposure, error: null } },
              }
            },
          }
        }
        if (table === 'expression_feedback_events') {
          return {
            upsert(row) {
              state.feedback = [row]
              return { select() { return { async single() { return { data: { id: 'feedback-1', ...row }, error: null } } } } }
            },
            ...queryRows(state.feedback),
          }
        }
        if (table === 'expression_preference_signals') {
          return {
            delete() {
              state.signals = []
              return {
                eq() { return this },
                then(resolve) { resolve({ error: null }) },
              }
            },
            upsert(rows) {
              state.signals = rows
              return Promise.resolve({ error: null })
            },
            ...queryRows(state.signals),
          }
        }
        if (table === 'expression_preference_snapshots') {
          return {
            upsert(row) {
              state.snapshot = row
              return Promise.resolve({ error: null })
            },
          }
        }
        throw new Error(`Unexpected table: ${table}`)
      },
    },
  }
}

const exposure = {
  id: 'exposure-1',
  record_id: 'record-1',
  candidate_id: 'candidate-1',
  semantic_key: 'expense_record_name_previous_gap',
  surface: 'record_detail',
  lifecycle_state: 'client_rendered',
  simulation_only: false,
  counts_for_novelty: true,
  visible_field_paths: ['rendered_feedback.emotion_line'],
  metadata: {
    decision_id: 'decision-1',
    policy_name: 'deterministic_rule',
    policy_version: 'deterministic-record-detail-v0.1',
    selection_probability: 1,
  },
}

test('a positive review creates a surface-semantic weight the scorer can consume', async () => {
  const module = await loadModule()
  const { client, state } = database(exposure)
  const result = await module.submitExpressionFeedback(client, 'user-1', {
    exposure_event_id: 'exposure-1',
    record_id: 'record-1',
    primary_choice: 'helpful',
  })

  const profile = state.snapshot.scoring_profile
  assert.equal(result.preference_signal_count, 1)
  assert.ok(profile.surface_semantic_weights.record_detail.expense_record_name_previous_gap > 1)
  assert.equal(profile.surface_weights.record_detail, undefined)
  assert.equal(profile.repetition_tolerance.record_detail, undefined)
  assert.equal(state.feedback[0].metadata.decision_id, 'decision-1')
  assert.equal(state.feedback[0].metadata.selection_probability, 1)
})

test('a factual-error review suppresses an ambiguous not-helpful preference signal', async () => {
  const module = await loadModule()
  const { client, state } = database(exposure)
  const result = await module.submitExpressionFeedback(client, 'user-1', {
    exposure_event_id: 'exposure-1',
    record_id: 'record-1',
    primary_choice: 'incorrect',
    free_text: '数字不对，所以没帮助',
  })

  assert.deepEqual(result.quality_issues.sort(), ['content_wrong_unspecified', 'number_wrong'])
  assert.equal(result.preference_signal_count, 0)
  assert.equal(result.suppressed_preference_signal_count, 1)
  assert.equal(state.signals.length, 0)
})

test('an explicit exposure cannot be reviewed through a different record', async () => {
  const module = await loadModule()
  const { client } = database(exposure)

  await assert.rejects(
    module.submitExpressionFeedback(client, 'user-1', {
      exposure_event_id: 'exposure-1',
      record_id: 'record-2',
      primary_choice: 'helpful',
    }),
    /点评记录与曝光不匹配/,
  )
})

test('an unknown explicit exposure never falls back to a guessed record exposure', async () => {
  const module = await loadModule()
  const { client } = database(null)

  await assert.rejects(
    module.submitExpressionFeedback(client, 'user-1', {
      exposure_event_id: 'missing-exposure',
      record_id: 'record-1',
      primary_choice: 'helpful',
    }),
    /点评对应的曝光不存在或已失效/,
  )
})

test('legacy feedback review persists only rendered fields with a structured source', async () => {
  const module = await loadModule()
  const { client, state } = database(null)

  await module.submitExpressionFeedback(client, 'user-1', {
    record_id: 'record-1',
    primary_choice: 'helpful',
  })

  assert.equal(state.exposureBundles.length, 1)
  const bundle = state.exposureBundles[0]
  assert.deepEqual(bundle.sources.map(source => [source.source_table, source.source_record_id]), [
    ['transactions', 'record-1'],
  ])
  assert.equal(bundle.exposure.lifecycle_state, 'client_rendered')
  assert.equal(bundle.exposure.rendered_payload.emotion_line, '这次记录很清楚')
  assert.equal('internal_score' in bundle.exposure.rendered_payload, false)
  assert.equal('structured_value' in bundle.exposure.rendered_payload, false)
  assert.equal('companion_message' in bundle.exposure.rendered_payload, false)
})

test('a changed choice replaces the previous review and its preference signals', async () => {
  const module = await loadModule()
  const { client, state } = database(exposure)
  const first = await module.submitExpressionFeedback(client, 'user-1', {
    exposure_event_id: 'exposure-1',
    record_id: 'record-1',
    primary_choice: 'helpful',
    feedback_key: 'client-controlled-key',
  })
  const second = await module.submitExpressionFeedback(client, 'user-1', {
    exposure_event_id: 'exposure-1',
    record_id: 'record-1',
    primary_choice: 'not_helpful',
    feedback_key: 'another-client-key',
  })

  assert.equal(first.feedback_key, 'feedback:user-1:exposure-1')
  assert.equal(second.feedback_key, first.feedback_key)
  assert.equal(state.feedback.length, 1)
  assert.equal(state.feedback[0].primary_choice, 'not_helpful')
  assert.deepEqual(state.signals.map(signal => signal.issue_code), ['not_helpful'])
  assert.ok(state.snapshot.scoring_profile.surface_semantic_weights.record_detail.expense_record_name_previous_gap < 1)
})
