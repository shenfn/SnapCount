// @ts-ignore Shared framework-neutral contract.
import { inferIssueAnnotations, normalizeExposureFeedback } from "../../../tools/ai-validation/expression-planner/lib/exposure-feedback-contract.mjs";
// @ts-ignore Shared framework-neutral preference logic.
import { derivePreferenceSignals } from "../../../tools/ai-validation/expression-planner/lib/preference-signal-deriver.mjs";
// @ts-ignore Shared framework-neutral preference logic.
import { aggregatePreferenceSignals, toScoringPreferenceProfile } from "../../../tools/ai-validation/expression-planner/lib/preference-signal-aggregator.mjs";

interface DatabaseClient {
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
}

const CHOICES = new Set(["incorrect", "not_helpful", "repetitive", "style_dislike", "other"]);

function text(value: unknown, max = 2000): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string").slice(0, 20) : [];
}

async function resolveReviewedExposure(supabase: DatabaseClient, userId: string, input: Record<string, unknown>) {
  const exposureId = text(input.exposure_event_id, 100);
  let query = supabase.from("expression_exposure_events")
    .select("*").eq("user_id", userId);
  query = exposureId
    ? query.eq("id", exposureId)
    : query.eq("record_id", text(input.record_id, 100)).order("occurred_at", { ascending: false });
  const { data, error } = exposureId ? await query.maybeSingle() : await query.limit(1).maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("没有找到可点评的 AI 展示记录");
  if (data.surface === "record_detail" && data.lifecycle_state === "user_reviewed") return data;
  const eventKey = `${data.event_key}:record_detail:user_reviewed`;
  const reviewedRow = {
    ...data, id: undefined, created_at: undefined, event_key: eventKey,
    delivery_attempt_id: `${data.delivery_attempt_id}:record_detail`,
    surface: "record_detail", lifecycle_state: "user_reviewed", counts_for_novelty: true,
    metadata: { ...(data.metadata ?? {}), source: "pwa_record_detail_feedback", parent_exposure_event_id: data.id },
  };
  const { data: reviewed, error: reviewedError } = await supabase.from("expression_exposure_events")
    .upsert(reviewedRow, { onConflict: "event_key" }).select().single();
  if (reviewedError) throw new Error(reviewedError.message);
  return reviewed;
}

async function rebuildPreferenceSnapshot(supabase: DatabaseClient, userId: string) {
  const { data: feedbackRows, error: feedbackError } = await supabase.from("expression_feedback_events")
    .select("feedback_key,occurred_at,user_id,exposure_event_id,candidate_id,semantic_key,surface,visible_field_paths,primary_choice,issue_annotations,free_text")
    .eq("user_id", userId).order("occurred_at", { ascending: true }).limit(2000);
  if (feedbackError) throw new Error(feedbackError.message);
  const rebuiltSignals = (feedbackRows ?? []).flatMap((row: Record<string, unknown>) => {
    const storedAnnotations = Array.isArray(row.issue_annotations) ? row.issue_annotations : [];
    const issueAnnotations = inferIssueAnnotations({
      primaryChoice: row.primary_choice,
      explicitIssueCodes: storedAnnotations
        .filter((item: Record<string, unknown>) => item?.source === "user_explicit_detail")
        .map((item: Record<string, unknown>) => item.issue_code),
      notes: row.free_text ?? "",
    });
    const derived = derivePreferenceSignals({ ...row, issue_annotations: issueAnnotations });
    return derived.signals.map((signal: Record<string, unknown>) => ({
      ...signal, metadata: { source: "deterministic_feedback_rebuild" },
    }));
  });
  if (rebuiltSignals.length) {
    const { error: rebuildError } = await supabase.from("expression_preference_signals")
      .upsert(rebuiltSignals, { onConflict: "signal_key", ignoreDuplicates: true });
    if (rebuildError) throw new Error(rebuildError.message);
  }
  const { data: signals, error } = await supabase.from("expression_preference_signals")
    .select("signal_key,occurred_at,user_id,feedback_key,exposure_event_id,semantic_key,surface,issue_code,preference_dimension,direction,strength,aggregation_policy")
    .eq("user_id", userId).order("occurred_at", { ascending: true }).limit(2000);
  if (error) throw new Error(error.message);
  const asOf = new Date().toISOString();
  const snapshot = aggregatePreferenceSignals(signals ?? [], { asOf });
  const scoringProfile = toScoringPreferenceProfile(snapshot);
  const { error: upsertError } = await supabase.from("expression_preference_snapshots").upsert({
    user_id: userId, updated_at: asOf, snapshot_version: snapshot.snapshot_version,
    source_feedback_count: feedbackRows?.length ?? 0, source_signal_count: signals?.length ?? 0,
    snapshot, scoring_profile: scoringProfile,
  }, { onConflict: "user_id" });
  if (upsertError) throw new Error(upsertError.message);
  return { snapshot, scoringProfile };
}

export async function submitExpressionFeedback(
  supabase: DatabaseClient, userId: string, input: Record<string, unknown>,
) {
  const primaryChoice = text(input.primary_choice ?? input.primaryChoice, 40);
  if (!CHOICES.has(primaryChoice)) throw new Error("无效的点评选项");
  const exposure = await resolveReviewedExposure(supabase, userId, input);
  const occurredAt = new Date().toISOString();
  const feedbackKey = text(input.feedback_key, 200) || `feedback:${userId}:${exposure.id}:${crypto.randomUUID()}`;
  const feedback = normalizeExposureFeedback({
    primaryChoice,
    explicitIssueCodes: stringArray(input.issue_codes ?? input.explicitIssueCodes),
    notes: text(input.free_text ?? input.notes, 2000),
    suggestedAction: text(input.suggested_action ?? input.suggestedAction, 500),
  }, {
    feedbackKey, occurredAt, userId, exposureEventId: exposure.id, candidateId: exposure.candidate_id,
    semanticKey: exposure.semantic_key, surface: exposure.surface, visibleFieldPaths: exposure.visible_field_paths ?? [],
    metadata: { source: "pwa_record_detail", record_id: exposure.record_id },
  });
  const feedbackInsert = {
    feedback_key: feedback.feedback_key, occurred_at: feedback.occurred_at, user_id: feedback.user_id,
    exposure_event_id: feedback.exposure_event_id, candidate_id: feedback.candidate_id, semantic_key: feedback.semantic_key,
    surface: feedback.surface, visible_field_paths: feedback.visible_field_paths, primary_choice: feedback.primary_choice,
    issue_annotations: feedback.issue_annotations, free_text: feedback.free_text, suggested_action: feedback.suggested_action,
    source_review_schema: feedback.source_review_schema, source_review_key: feedback.source_review_key, metadata: feedback.metadata,
  };
  const { data: feedbackRow, error: feedbackError } = await supabase.from("expression_feedback_events")
    .upsert(feedbackInsert, { onConflict: "feedback_key", ignoreDuplicates: true }).select().single();
  if (feedbackError) throw new Error(feedbackError.message);
  const derived = derivePreferenceSignals(feedback);
  if (derived.signals.length) {
    const rows = derived.signals.map((signal: Record<string, unknown>) => ({ ...signal, metadata: { source: "deterministic_feedback_deriver" } }));
    const { error: signalError } = await supabase.from("expression_preference_signals")
      .upsert(rows, { onConflict: "signal_key", ignoreDuplicates: true });
    if (signalError) throw new Error(signalError.message);
  }
  const { snapshot, scoringProfile } = await rebuildPreferenceSnapshot(supabase, userId);
  return {
    feedback_id: feedbackRow?.id ?? null, feedback_key: feedbackKey, primary_choice: primaryChoice,
    issue_annotations: feedback.issue_annotations, quality_issues: derived.quality_issues,
    preference_signal_count: derived.signals.length, snapshot_version: snapshot.snapshot_version,
    scoring_profile: scoringProfile,
  };
}
