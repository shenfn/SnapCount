const PREFERENCE_RULES = {
  direction_wrong: { dimension: 'semantic_preference', delta: -0.45 },
  not_relevant: { dimension: 'semantic_preference', delta: -0.35 },
  not_helpful: { dimension: 'semantic_preference', delta: -0.2 },
  too_repetitive: { dimension: 'repetition_tolerance', delta: -0.5 },
  tone_mismatch: { dimension: 'expression_style', delta: -0.45 },
  too_verbose: { dimension: 'verbosity_preference', delta: -0.4 },
  too_brief: { dimension: 'verbosity_preference', delta: 0.25 },
  missing_dimensions: { dimension: 'detail_breadth_preference', delta: 0.25 },
  wants_temporal_context: { dimension: 'temporal_context_preference', delta: 0.25 },
  too_vague: { dimension: 'specificity_preference', delta: 0.35 },
  bad_timing: { dimension: 'surface_timing_preference', delta: -0.4 },
  wrong_surface: { dimension: 'surface_preference', delta: -0.5 },
  should_have_asked: { dimension: 'interaction_mode_preference', delta: 0.4 },
}

const QUALITY_ONLY_ISSUES = new Set([
  'content_wrong_unspecified', 'fact_wrong', 'number_wrong', 'presentation_format_wrong',
  'duplicate_decision_wrong', 'output_inconsistent', 'reasoning_overreach',
  'missing_context', 'recognition_wrong', 'system_failure',
])

const SOURCE_WEIGHT = {
  user_explicit_detail: 1,
  user_primary_choice: 0.55,
  legacy_review_tag: 0.75,
  deterministic_note_rule: 0.65,
  analyst_annotation: 0.8,
  model_assisted: 0.35,
}

export function derivePreferenceSignals(feedback) {
  const signals = []
  const qualityIssues = []
  const suppressedSignals = []
  const annotations = feedback?.issue_annotations ?? []
  const hasSpecificQualityIssue = annotations.some(annotation => (
    QUALITY_ONLY_ISSUES.has(annotation.issue_code)
    && annotation.issue_code !== 'content_wrong_unspecified'
  ))

  for (const annotation of annotations) {
    if (QUALITY_ONLY_ISSUES.has(annotation.issue_code)) {
      qualityIssues.push(annotation.issue_code)
      continue
    }
    const rule = PREFERENCE_RULES[annotation.issue_code]
    if (!rule) continue
    if (hasSpecificQualityIssue && annotation.issue_code === 'not_helpful') {
      suppressedSignals.push({
        issue_code: annotation.issue_code,
        reason: 'specific_quality_issue_present',
      })
      continue
    }
    const confidence = Number(annotation.confidence ?? 0)
    const sourceWeight = SOURCE_WEIGHT[annotation.source] ?? 0.25
    signals.push({
      signal_key: `${feedback.feedback_key}:${annotation.issue_code}`,
      occurred_at: feedback.occurred_at,
      user_id: feedback.user_id,
      feedback_key: feedback.feedback_key,
      exposure_event_id: feedback.exposure_event_id,
      semantic_key: feedback.semantic_key,
      surface: feedback.surface,
      issue_code: annotation.issue_code,
      preference_dimension: rule.dimension,
      direction: rule.delta > 0 ? 'increase' : 'decrease',
      strength: Number((Math.abs(rule.delta) * confidence * sourceWeight).toFixed(4)),
      aggregation_policy: 'decay_and_repeat_required',
    })
  }

  return {
    signals,
    quality_issues: [...new Set(qualityIssues)],
    suppressed_signals: suppressedSignals,
  }
}
