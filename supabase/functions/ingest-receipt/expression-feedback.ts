import { plannerSourceFingerprint } from "./expression-shadow-planner.ts";

interface DatabaseClient {
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
  // deno-lint-ignore no-explicit-any
  rpc: (name: string, params: Record<string, unknown>) => any;
}

type FeedbackChoice =
  | "helpful"
  | "good_angle"
  | "just_what_i_wanted"
  | "no_change_needed"
  | "incorrect"
  | "not_helpful"
  | "repetitive"
  | "style_dislike"
  | "other";

const CHOICES = new Set<FeedbackChoice>([
  "helpful",
  "good_angle",
  "just_what_i_wanted",
  "no_change_needed",
  "incorrect",
  "not_helpful",
  "repetitive",
  "style_dislike",
  "other",
]);

const PRIMARY_ISSUES: Record<FeedbackChoice, string[]> = {
  helpful: ["helpful"],
  good_angle: ["good_angle"],
  just_what_i_wanted: ["just_what_i_wanted"],
  no_change_needed: ["no_change_needed"],
  incorrect: ["content_wrong_unspecified"],
  not_helpful: ["not_helpful"],
  repetitive: ["too_repetitive"],
  style_dislike: ["tone_mismatch"],
  other: [],
};

const PREFERENCE_RULES: Record<string, { dimension: string; delta: number }> = {
  helpful: { dimension: "semantic_preference", delta: 0.25 },
  good_angle: { dimension: "semantic_preference", delta: 0.3 },
  just_what_i_wanted: { dimension: "semantic_preference", delta: 0.4 },
  no_change_needed: { dimension: "semantic_preference", delta: 0.2 },
  not_relevant: { dimension: "semantic_preference", delta: -0.35 },
  not_helpful: { dimension: "semantic_preference", delta: -0.2 },
  too_repetitive: { dimension: "repetition_tolerance", delta: -0.5 },
  tone_mismatch: { dimension: "expression_style", delta: -0.45 },
  too_verbose: { dimension: "verbosity_preference", delta: -0.4 },
  too_brief: { dimension: "verbosity_preference", delta: 0.25 },
  too_vague: { dimension: "specificity_preference", delta: 0.35 },
  bad_timing: { dimension: "surface_timing_preference", delta: -0.4 },
};

const QUALITY_ONLY_ISSUES = new Set([
  "content_wrong_unspecified",
  "fact_wrong",
  "number_wrong",
  "reasoning_overreach",
  "recognition_wrong",
  "system_failure",
]);

function text(value: unknown, max = 2000): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function renderedFeedback(value: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const key of ["icon", "badge", "band", "emotion_line", "utility_line", "detail_reason"]) {
    const normalized = text(value[key], 2000);
    if (normalized) result[key] = normalized;
  }
  const timingSignal = object(value.timing_signal);
  const timingLabel = text(timingSignal.label, 200);
  if (timingLabel) result.timing_signal = { label: timingLabel };
  return result;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string").slice(0, 20)
    : [];
}

function inferIssueAnnotations(choice: FeedbackChoice, explicitCodes: string[], notes: string) {
  const annotations = new Map<string, { issue_code: string; source: string; confidence: number; evidence: string | null }>();
  const add = (issueCode: string, source: string, confidence: number, evidence: string | null = null) => {
    const current = annotations.get(issueCode);
    if (!current || confidence > current.confidence) {
      annotations.set(issueCode, { issue_code: issueCode, source, confidence, evidence });
    }
  };
  for (const issueCode of PRIMARY_ISSUES[choice]) add(issueCode, "user_primary_choice", 0.6);
  for (const issueCode of explicitCodes) add(issueCode, "user_explicit_detail", 1);
  const noteRules: Array<[RegExp, string]> = [
    [/没帮助|没有帮助|没什么用/, "not_helpful"],
    [/不相关|没关系|无关/, "not_relevant"],
    [/重复|每次都|老是说/, "too_repetitive"],
    [/太泛|含糊|不明确|没懂/, "too_vague"],
    [/语气|说教|表达不喜欢/, "tone_mismatch"],
    [/太长|啰嗦/, "too_verbose"],
    [/太短|内容太少|多说一点/, "too_brief"],
    [/时机不对|现在不需要/, "bad_timing"],
    [/数字不对|数值不对|金额错误/, "number_wrong"],
    [/编造|事实错误|幻觉/, "fact_wrong"],
  ];
  for (const [pattern, issueCode] of noteRules) {
    const match = notes.match(pattern);
    if (match) add(issueCode, "deterministic_note_rule", 0.7, match[0]);
  }
  return [...annotations.values()];
}

async function loadPersistedRecord(supabase: DatabaseClient, userId: string, recordId: string) {
  const targets = [
    {
      table: "transactions",
      select: "id,created_at,occurred_at,transaction_date,ai_feedback,companion_message",
      domainKey: "expense",
      feedback: (row: Record<string, unknown>) => object(row.ai_feedback),
    },
    {
      table: "income_records",
      select: "id,created_at,occurred_at,income_date,ai_feedback,companion_message",
      domainKey: "income",
      feedback: (row: Record<string, unknown>) => object(row.ai_feedback),
    },
    {
      table: "data_records",
      select: "id,created_at,occurred_at,domain_key,payload_jsonb",
      domainKey: "data",
      feedback: (row: Record<string, unknown>) => object(object(row.payload_jsonb).ai_feedback),
    },
  ];
  for (const target of targets) {
    const { data, error } = await supabase.from(target.table)
      .select(target.select)
      .eq("id", recordId)
      .eq("user_id", userId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!data) continue;
    const row = data as Record<string, unknown>;
    return {
      table: target.table,
      domainKey: text(row.domain_key, 80) || target.domainKey,
      occurredAt: text(row.occurred_at ?? row.transaction_date ?? row.income_date ?? row.created_at, 100)
        || new Date().toISOString(),
      feedback: target.feedback(row),
    };
  }
  throw new Error("没有找到可点评的记录");
}

async function createPersistedRecordExposure(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
) {
  const record = await loadPersistedRecord(supabase, userId, recordId);
  const visibleFeedback = renderedFeedback(record.feedback);
  if (!Object.keys(visibleFeedback).length) throw new Error("这条记录没有可点评的反馈内容");
  const contentFingerprint = plannerSourceFingerprint({
    source_table: record.table,
    source_record_id: recordId,
    domain_key: record.domainKey,
    rendered_feedback: visibleFeedback,
  });
  const eventKey = `record-feedback:${userId}:${recordId}:record-detail:${contentFingerprint}`;
  const visibleFieldPaths = Object.keys(visibleFeedback).flatMap((key) => key === "timing_signal"
    ? ["ai_feedback.timing_signal.label"]
    : [`ai_feedback.${key}`]);
  const score = Number(record.feedback.internal_score);
  const exposure = {
    occurred_at: new Date().toISOString(),
    user_id: userId,
    event_key: eventKey,
    delivery_attempt_id: eventKey,
    record_id: recordId,
    record_type: record.domainKey,
    domain_key: record.domainKey,
    candidate_id: `persisted-ai-feedback:${recordId}`,
    semantic_key: `record:${record.domainKey}:ai_feedback`,
    claim_type: "inference",
    dimension: "record_feedback",
    surface: "record_detail",
    lifecycle_state: "client_rendered",
    selection_mode: "persisted_record_fallback",
    score: Number.isFinite(score) ? Math.max(0, Math.min(100, score)) : null,
    expression_plan_version: "persisted-record-feedback-v1",
    render_contract_version: text(record.feedback.version, 80) || "feedback-v1",
    scoring_version: "persisted-record-feedback-v1",
    visible_field_paths: visibleFieldPaths,
    expandable_field_paths: [],
    persisted_only_field_paths: [],
    rendered_payload: visibleFeedback,
    metadata: {
      source: "persisted_record_feedback",
      source_table: record.table,
      content_fingerprint: contentFingerprint,
      exposure_key: `record:${record.domainKey}:ai_feedback`,
      scoped_exposure_key: `record_detail:record:${record.domainKey}:ai_feedback`,
      dedupe_key: `record:${record.domainKey}:ai_feedback:${recordId}`,
      scoped_dedupe_key: `record_detail:record:${record.domainKey}:ai_feedback:${recordId}`,
    },
    simulation_only: false,
    counts_for_novelty: true,
  };
  const { data, error } = await supabase.rpc("persist_expression_exposure_with_sources", {
    p_user_id: userId,
    p_event_key: eventKey,
    p_exposure: exposure,
    p_sources: [{
      source_table: record.table,
      source_record_id: recordId,
      source_fingerprint: contentFingerprint,
      is_primary: true,
    }],
  });
  if (error) throw new Error(error.message);
  const persisted = object(object(data).exposure);
  if (!persisted.id) throw new Error("点评曝光写入失败");
  return persisted;
}

async function resolveReviewedExposure(
  supabase: DatabaseClient,
  userId: string,
  input: Record<string, unknown>,
) {
  const exposureId = text(input.exposure_event_id, 100);
  const recordId = text(input.record_id, 100);
  if (!recordId && !exposureId) throw new Error("缺少点评记录编号");
  if (!exposureId) {
    // No exposure id means the client is reviewing the record's persisted
    // legacy feedback. Do not guess a newer Planner exposure for that record.
    return await createPersistedRecordExposure(supabase, userId, recordId);
  }
  const { data, error } = await supabase.from("expression_exposure_events")
    .select("*")
    .eq("user_id", userId)
    .eq("id", exposureId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("点评对应的曝光不存在或已失效");
  if (recordId && text(data.record_id, 100) !== recordId) {
    throw new Error("点评记录与曝光不匹配");
  }
  if (
    data.surface !== "record_detail"
    || data.simulation_only === true
    || data.counts_for_novelty !== true
    || !["client_rendered", "client_acknowledged", "user_reviewed"].includes(text(data.lifecycle_state, 80))
  ) {
    throw new Error("点评对应的内容尚未在记录详情中展示");
  }
  return data;
}

function derivePreferenceSignals(feedback: Record<string, unknown>) {
  const signals: Record<string, unknown>[] = [];
  const qualityIssues: string[] = [];
  const annotations = Array.isArray(feedback.issue_annotations) ? feedback.issue_annotations : [];
  for (const rawAnnotation of annotations) {
    const annotation = object(rawAnnotation);
    const issueCode = text(annotation.issue_code, 100);
    if (QUALITY_ONLY_ISSUES.has(issueCode)) {
      qualityIssues.push(issueCode);
      continue;
    }
    const rule = PREFERENCE_RULES[issueCode];
    if (!rule) continue;
    const confidence = Number(annotation.confidence ?? 0);
    const strength = Number((Math.abs(rule.delta) * confidence * 0.55).toFixed(4));
    signals.push({
      signal_key: `${feedback.feedback_key}:${issueCode}`,
      occurred_at: feedback.occurred_at,
      user_id: feedback.user_id,
      feedback_key: feedback.feedback_key,
      exposure_event_id: feedback.exposure_event_id,
      semantic_key: feedback.semantic_key,
      surface: feedback.surface,
      issue_code: issueCode,
      preference_dimension: rule.dimension,
      direction: rule.delta > 0 ? "increase" : "decrease",
      strength,
      aggregation_policy: "decay_and_repeat_required",
      metadata: { source: "record_feedback_deriver" },
    });
  }
  const uniqueQualityIssues = [...new Set(qualityIssues)];
  const suppressedSignals = uniqueQualityIssues.length > 0
    ? signals.filter((signal) => signal.preference_dimension === "semantic_preference")
    : [];
  const suppressedKeys = new Set(suppressedSignals.map((signal) => signal.signal_key));
  return {
    signals: signals.filter((signal) => !suppressedKeys.has(signal.signal_key)),
    suppressedSignals,
    qualityIssues: uniqueQualityIssues,
  };
}

export async function rebuildExpressionPreferenceSnapshot(
  supabase: DatabaseClient,
  userId: string,
  retryCount = 0,
) {
  const { data: source, error: sourceError } = await supabase.rpc(
    "get_expression_preference_source",
    { p_user_id: userId },
  );
  if (sourceError) throw new Error(sourceError.message);
  const preferenceSource = object(source);
  const sourceRevision = Number(preferenceSource.source_revision ?? 0);
  if (!Number.isSafeInteger(sourceRevision) || sourceRevision < 0) {
    throw new Error("偏好源版本无效");
  }
  const feedbackRows = Array.isArray(preferenceSource.feedback_rows)
    ? preferenceSource.feedback_rows as Record<string, unknown>[]
    : [];
  const signalRows = Array.isArray(preferenceSource.signal_rows)
    ? preferenceSource.signal_rows as Record<string, unknown>[]
    : [];

  const dimensions: Record<string, { net: number; support: number }> = {};
  const semanticDimensions: Record<string, { net: number; support: number }> = {};
  const surfaceDimensions: Record<string, { net: number; support: number }> = {};
  const fallbackSurfaceSemanticDimensions: Record<string, { net: number; support: number }> = {};
  for (const row of signalRows ?? []) {
    const surface = text(row.surface, 80) || "all";
    const preferenceDimension = text(row.preference_dimension, 100);
    if (!preferenceDimension) continue;
    const semanticKey = text(row.semantic_key, 200);
    const direction = row.direction === "increase" ? 1 : -1;
    const delta = direction * Number(row.strength ?? 0);
    const add = (target: Record<string, { net: number; support: number }>, key: string) => {
      const current = target[key] ?? { net: 0, support: 0 };
      current.net += delta;
      current.support += 1;
      target[key] = current;
    };
    add(dimensions, `${surface}:${preferenceDimension}`);
    if (semanticKey && preferenceDimension === "semantic_preference" && !semanticKey.startsWith("record:")) {
      add(semanticDimensions, `${surface}:${semanticKey}`);
    }
    if (semanticKey.startsWith("record:") && preferenceDimension === "semantic_preference") {
      add(fallbackSurfaceSemanticDimensions, surface);
    }
    add(surfaceDimensions, `${surface}:${preferenceDimension}`);
  }
  const weight = (value: { net: number; support: number }) => {
    const activation = value.support === 1 ? 0.35 : value.support === 2 ? 0.65 : 1;
    return Math.max(0.7, Math.min(1.15, 1 + value.net * activation));
  };
  const renderingPreferences: Record<string, number> = Object.fromEntries(
    Object.entries(dimensions).map(([key, value]) => [key, weight(value)]),
  );
  const dimensionWeights: Record<string, number> = {};
  const surfaceSemanticWeights: Record<string, Record<string, number>> = {};
  const surfaceWeights: Record<string, number> = {};
  const repetitionTolerance: Record<string, number> = {};
  const surfaceWeightFactors: Record<string, number[]> = {};
  for (const [key, value] of Object.entries(semanticDimensions)) {
    const separator = key.indexOf(":");
    const surface = key.slice(0, separator);
    const semanticKey = key.slice(separator + 1);
    if (!surfaceSemanticWeights[surface]) surfaceSemanticWeights[surface] = {};
    surfaceSemanticWeights[surface][semanticKey] = weight(value);
  }
  for (const [key, value] of Object.entries(surfaceDimensions)) {
    const separator = key.indexOf(":");
    const surface = key.slice(0, separator);
    const dimension = key.slice(separator + 1);
    const valueWeight = weight(value);
    if (dimension === "repetition_tolerance") {
      repetitionTolerance[surface] = valueWeight;
    } else if (["expression_style", "verbosity_preference", "specificity_preference", "surface_timing_preference"].includes(dimension)) {
      if (!surfaceWeightFactors[surface]) surfaceWeightFactors[surface] = [];
      surfaceWeightFactors[surface].push(valueWeight);
    } else if (dimension.startsWith("candidate_dimension:")) {
      dimensionWeights[dimension.slice("candidate_dimension:".length)] = valueWeight;
    }
  }
  for (const [surface, value] of Object.entries(fallbackSurfaceSemanticDimensions)) {
    if (!surfaceWeightFactors[surface]) surfaceWeightFactors[surface] = [];
    surfaceWeightFactors[surface].push(weight(value));
  }
  for (const [surface, factors] of Object.entries(surfaceWeightFactors)) {
    surfaceWeights[surface] = Math.max(0.7, Math.min(1.15, factors.reduce((product, factor) => product * factor, 1)));
  }
  const sourceTimes = [...feedbackRows, ...signalRows]
    .map((row) => new Date(text(row.occurred_at, 100)).getTime())
    .filter(Number.isFinite);
  const asOf = sourceTimes.length > 0
    ? new Date(Math.max(...sourceTimes)).toISOString()
    : new Date().toISOString();
  const snapshot = {
    snapshot_version: "preference-snapshot-v0.1",
    as_of: asOf,
    signal_count: signalRows.length,
    feedback_choice_counts: feedbackRows.reduce((counts: Record<string, number>, row: Record<string, unknown>) => {
      const choice = text(row.primary_choice, 40) || "other";
      counts[choice] = (counts[choice] ?? 0) + 1;
      return counts;
    }, {}),
    rendering_preferences: renderingPreferences,
    scoring_profile: {
      semantic_key_weights: {},
      dimension_weights: dimensionWeights,
      surface_semantic_weights: surfaceSemanticWeights,
      surface_weights: surfaceWeights,
      repetition_tolerance: repetitionTolerance,
    },
  };
  const scoringProfile = {
    profile_version: "scoring-preference-profile-v0.1",
    generated_from_snapshot: snapshot.snapshot_version,
    as_of: asOf,
    semantic_key_weights: {},
    dimension_weights: dimensionWeights,
    surface_semantic_weights: surfaceSemanticWeights,
    surface_weights: surfaceWeights,
    repetition_tolerance: repetitionTolerance,
    rendering_preferences: renderingPreferences,
  };
  const { data: snapshotStored, error: snapshotError } = await supabase.rpc(
    "upsert_expression_preference_snapshot_if_newer",
    {
      p_user_id: userId,
      p_source_revision: sourceRevision,
      p_source_as_of: asOf,
      p_snapshot_version: snapshot.snapshot_version,
      p_source_feedback_count: feedbackRows.length,
      p_source_signal_count: signalRows.length,
      p_snapshot: snapshot,
      p_scoring_profile: scoringProfile,
    },
  );
  if (snapshotError) throw new Error(snapshotError.message);
  if (snapshotStored === false) {
    const { data: latest, error: latestError } = await supabase.from("expression_preference_snapshots")
      .select("snapshot,scoring_profile,source_revision")
      .eq("user_id", userId)
      .maybeSingle();
    if (latestError) throw new Error(latestError.message);
    if (latest && Number(latest.source_revision) === sourceRevision) {
      return {
        snapshot: object(latest.snapshot),
        scoringProfile: object(latest.scoring_profile),
      };
    }
    if (retryCount < 2) {
      return await rebuildExpressionPreferenceSnapshot(supabase, userId, retryCount + 1);
    }
    throw new Error("偏好源在快照生成期间持续变化，请重试");
  }
  return { snapshot, scoringProfile };
}

export async function submitExpressionFeedback(
  supabase: DatabaseClient,
  userId: string,
  input: Record<string, unknown>,
) {
  const primaryChoice = text(input.primary_choice ?? input.primaryChoice, 40) as FeedbackChoice;
  if (!CHOICES.has(primaryChoice)) throw new Error("无效的点评选项");
  const exposure = await resolveReviewedExposure(supabase, userId, input);
  const occurredAt = new Date().toISOString();
  // One exposure has one current review. Keeping the key server-owned prevents
  // cross-user key collisions and makes a changed choice replace the old one.
  const feedbackKey = `feedback:${userId}:${exposure.id}`;
  const freeText = text(input.free_text ?? input.notes, 2000);
  const issueAnnotations = inferIssueAnnotations(
    primaryChoice,
    stringArray(input.issue_codes ?? input.explicitIssueCodes),
    freeText,
  );
  const feedback = {
    feedback_key: feedbackKey,
    occurred_at: occurredAt,
    user_id: userId,
    exposure_event_id: exposure.id,
    candidate_id: exposure.candidate_id,
    semantic_key: exposure.semantic_key,
    surface: text(exposure.surface, 80) || "record_detail",
    visible_field_paths: exposure.visible_field_paths ?? [],
    primary_choice: primaryChoice,
    issue_annotations: issueAnnotations,
    free_text: freeText,
    suggested_action: text(input.suggested_action ?? input.suggestedAction, 500),
    source_review_schema: "record-feedback-v1",
    source_review_key: `record:${exposure.record_id ?? exposure.id}`,
    metadata: { source: "native_or_pwa_record_detail", record_id: exposure.record_id },
  };
  const derived = derivePreferenceSignals(feedback);
  const { data: feedbackRow, error: feedbackError } = await supabase.rpc(
    "replace_expression_feedback_bundle",
    {
      p_user_id: userId,
      p_exposure_event_id: exposure.id,
      p_feedback: feedback,
      p_signals: derived.signals,
    },
  );
  if (feedbackError) throw new Error(feedbackError.message);
  const { snapshot, scoringProfile } = await rebuildExpressionPreferenceSnapshot(supabase, userId);
  return {
    feedback_id: object(object(feedbackRow).feedback).id ?? null,
    feedback_key: feedbackKey,
    primary_choice: primaryChoice,
    issue_annotations: issueAnnotations,
    quality_issues: derived.qualityIssues,
    preference_signal_count: derived.signals.length,
    suppressed_preference_signal_count: derived.suppressedSignals.length,
    snapshot_version: snapshot.snapshot_version,
    scoring_profile: scoringProfile,
  };
}
