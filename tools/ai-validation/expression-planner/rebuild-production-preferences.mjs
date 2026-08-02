import { createClient } from '@supabase/supabase-js'
import { inferIssueAnnotations } from './lib/exposure-feedback-contract.mjs'
import { derivePreferenceSignals } from './lib/preference-signal-deriver.mjs'
import { aggregatePreferenceSignals, toScoringPreferenceProfile } from './lib/preference-signal-aggregator.mjs'

function argument(name) {
  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : null
}

const userId = argument('--user-id')
const supabaseUrl = process.env.VITE_SUPABASE_URL
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!userId) throw new Error('Missing --user-id')
if (!supabaseUrl || !serviceRoleKey) throw new Error('Missing Supabase environment variables')

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const { data: feedbackRows, error: feedbackError } = await supabase
  .from('expression_feedback_events')
  .select('feedback_key,occurred_at,user_id,exposure_event_id,candidate_id,semantic_key,surface,visible_field_paths,primary_choice,issue_annotations,free_text')
  .eq('user_id', userId)
  .order('occurred_at', { ascending: true })
  .limit(2000)

if (feedbackError) throw new Error(feedbackError.message)

const signalRows = []
for (const row of feedbackRows ?? []) {
  const issueAnnotations = inferIssueAnnotations({
    primaryChoice: row.primary_choice,
    explicitIssueCodes: (row.issue_annotations ?? [])
      .filter(item => item?.source === 'user_explicit_detail')
      .map(item => item.issue_code),
    notes: row.free_text ?? '',
  })
  const derived = derivePreferenceSignals({ ...row, issue_annotations: issueAnnotations })
  signalRows.push(...derived.signals.map(signal => ({
    ...signal,
    metadata: { source: 'deterministic_feedback_rebuild' },
  })))
}

if (signalRows.length) {
  const { error } = await supabase.from('expression_preference_signals')
    .upsert(signalRows, { onConflict: 'signal_key' })
  if (error) throw new Error(error.message)
}

const { data: persistedSignals, error: signalError } = await supabase
  .from('expression_preference_signals')
  .select('signal_key,occurred_at,user_id,feedback_key,exposure_event_id,semantic_key,surface,issue_code,preference_dimension,direction,strength,aggregation_policy')
  .eq('user_id', userId)
  .order('occurred_at', { ascending: true })
  .limit(2000)

if (signalError) throw new Error(signalError.message)

const asOf = new Date().toISOString()
const snapshot = aggregatePreferenceSignals(persistedSignals ?? [], { asOf })
const scoringProfile = toScoringPreferenceProfile(snapshot)
const { error: snapshotError } = await supabase.from('expression_preference_snapshots').upsert({
  user_id: userId,
  updated_at: asOf,
  snapshot_version: snapshot.snapshot_version,
  source_feedback_count: feedbackRows?.length ?? 0,
  source_signal_count: persistedSignals?.length ?? 0,
  snapshot,
  scoring_profile: scoringProfile,
}, { onConflict: 'user_id' })

if (snapshotError) throw new Error(snapshotError.message)

console.log(JSON.stringify({
  user_id: userId,
  feedback_count: feedbackRows?.length ?? 0,
  derived_signal_count: signalRows.length,
  persisted_signal_count: persistedSignals?.length ?? 0,
  evidence: snapshot.evidence.map(item => ({
    group_key: item.group_key,
    support_count: item.support_count,
    maturity: item.maturity,
    multiplier: item.multiplier,
  })),
}, null, 2))
