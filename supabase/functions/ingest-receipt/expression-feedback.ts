interface DatabaseClient {
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
}

type FeedbackChoice = "incorrect" | "not_helpful" | "repetitive" | "style_dislike" | "other";

const CHOICES = new Set<FeedbackChoice>(["incorrect", "not_helpful", "repetitive", "style_dislike", "other"]);

const PRIMARY_ISSUES: Record<FeedbackChoice, string[]> = {
  incorrect: ["content_wrong_unspecified"],
  not_helpful: ["not_helpful"],
  repetitive: ["too_repetitive"],
  style_dislike: ["tone_mismatch"],
  other: [],
};

const PREFERENCE_RULES: Record<string, { dimension: string; delta: number }> = {
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
      select: "id,created_at,transaction_date,ai_feedback,companion_message",
      domainKey: "expense",
      feedback: (row: Record<string, unknown>) => object(row.ai_feedback),
    },
    {
      table: "income_records",
      select: "id,created_at,income_date,ai_feedback,companion_message",
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
  const eventKey = `record-feedback:${userId}:${recordId}:record-detail`;
  const visibleFieldPaths = ["emotion_line", "utility_line", "detail_reason"]
    .filter((key) => text(record.feedback[key], 200).length > 0)
    .map((key) => `ai_feedback.${key}`);
  const score = Number(record.feedback.internal_score);
  const { data, error } = await supabase.from("expression_exposure_events").upsert({
    occurred_at: record.occurredAt,
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
    lifecycle_state: "user_reviewed",
    selection_mode: "persisted_record_fallback",
    score: Number.isFinite(score) ? Math.max(0, Math.min(100, score)) : null,
    expression_plan_version: "persisted-record-feedback-v1",
    render_contract_version: text(record.feedback.version, 80) || "feedback-v1",
    scoring_version: "persisted-record-feedback-v1",
    visible_field_paths: visibleFieldPaths,
    expandable_field_paths: [],
    persisted_only_field_paths: [],
    rendered_payload: record.feedback,
    metadata: { source: "persisted_record_feedback", source_table: record.table },
    simulation_only: false,
    counts_for_novelty: true,
  }, { onConflict: "event_key" }).select().single();
  if (error) throw new Error(error.message);
  return data;
}

async function resolveReviewedExposure(
  supabase: DatabaseClient,
  userId: string,
  input: Record<string, unknown>,
) {
  const exposureId = text(input.exposure_event_id, 100);
  const recordId = text(input.record_id, 100);
  if (!recordId && !exposureId) throw new Error("缺少点评记录编号");
  let query = supabase.from("expression_exposure_events").select("*").eq("user_id", userId);
  query = exposureId
    ? query.eq("id", exposureId)
    : query.eq("record_id", recordId).order("occurred_at", { ascending: false });
  const { data, error } = exposureId ? await query.maybeSingle() : await query.limit(1).maybeSingle();
  if (error) throw new Error(error.message);
  if (data) return data;
  return await createPersistedRecordExposure(supabase, userId, recordId);
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
  return { signals, qualityIssues: [...new Set(qualityIssues)] };
}

async function rebuildPreferenceSnapshot(supabase: DatabaseClient, userId: string) {
  const { data: feedbackRows, error: feedbackError } = await supabase.from("expression_feedback_events")
    .select("feedback_key,occurred_at,primary_choice")
    .eq("user_id", userId)
    .order("occurred_at", { ascending: true })
    .limit(2000);
  if (feedbackError) throw new Error(feedbackError.message);
  const { data: signalRows, error: signalError } = await supabase.from("expression_preference_signals")
    .select("signal_key,occurred_at,semantic_key,surface,preference_dimension,direction,strength")
    .eq("user_id", userId)
    .order("occurred_at", { ascending: true })
    .limit(2000);
  if (signalError) throw new Error(signalError.message);

  const dimensions: Record<string, { net: number; support: number }> = {};
  for (const row of signalRows ?? []) {
    const key = `${row.surface ?? "all"}:${row.preference_dimension}`;
    const current = dimensions[key] ?? { net: 0, support: 0 };
    const direction = row.direction === "increase" ? 1 : -1;
    current.net += direction * Number(row.strength ?? 0);
    current.support += 1;
    dimensions[key] = current;
  }
  const renderingPreferences: Record<string, number> = {};
  for (const [key, value] of Object.entries(dimensions)) {
    const activation = value.support === 1 ? 0.35 : value.support === 2 ? 0.65 : 1;
    renderingPreferences[key] = Math.max(0.7, Math.min(1.15, 1 + value.net * activation));
  }
  const asOf = new Date().toISOString();
  const snapshot = {
    snapshot_version: "preference-snapshot-v0.1",
    as_of: asOf,
    signal_count: signalRows?.length ?? 0,
    feedback_choice_counts: (feedbackRows ?? []).reduce((counts: Record<string, number>, row: Record<string, unknown>) => {
      const choice = text(row.primary_choice, 40) || "other";
      counts[choice] = (counts[choice] ?? 0) + 1;
      return counts;
    }, {}),
    rendering_preferences: renderingPreferences,
  };
  const scoringProfile = {
    profile_version: "scoring-preference-profile-v0.1",
    generated_from_snapshot: snapshot.snapshot_version,
    as_of: asOf,
    rendering_preferences: renderingPreferences,
  };
  const { error: snapshotError } = await supabase.from("expression_preference_snapshots").upsert({
    user_id: userId,
    updated_at: asOf,
    snapshot_version: snapshot.snapshot_version,
    source_feedback_count: feedbackRows?.length ?? 0,
    source_signal_count: signalRows?.length ?? 0,
    snapshot,
    scoring_profile: scoringProfile,
  }, { onConflict: "user_id" });
  if (snapshotError) throw new Error(snapshotError.message);
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
  const feedbackKey = text(input.feedback_key, 200)
    || `feedback:${userId}:${exposure.id}:${primaryChoice}`;
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
    surface: "record_detail",
    visible_field_paths: exposure.visible_field_paths ?? [],
    primary_choice: primaryChoice,
    issue_annotations: issueAnnotations,
    free_text: freeText,
    suggested_action: text(input.suggested_action ?? input.suggestedAction, 500),
    source_review_schema: "record-feedback-v1",
    source_review_key: `record:${exposure.record_id ?? exposure.id}`,
    metadata: { source: "native_or_pwa_record_detail", record_id: exposure.record_id },
  };
  const { data: feedbackRow, error: feedbackError } = await supabase.from("expression_feedback_events")
    .upsert(feedback, { onConflict: "feedback_key" })
    .select()
    .single();
  if (feedbackError) throw new Error(feedbackError.message);

  const derived = derivePreferenceSignals(feedback);
  if (derived.signals.length > 0) {
    const { error: signalError } = await supabase.from("expression_preference_signals")
      .upsert(derived.signals, { onConflict: "signal_key" });
    if (signalError) throw new Error(signalError.message);
  }
  const { snapshot, scoringProfile } = await rebuildPreferenceSnapshot(supabase, userId);
  return {
    feedback_id: feedbackRow?.id ?? null,
    feedback_key: feedbackKey,
    primary_choice: primaryChoice,
    issue_annotations: issueAnnotations,
    quality_issues: derived.qualityIssues,
    preference_signal_count: derived.signals.length,
    snapshot_version: snapshot.snapshot_version,
    scoring_profile: scoringProfile,
  };
}
