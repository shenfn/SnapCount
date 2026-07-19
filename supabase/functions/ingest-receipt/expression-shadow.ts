import { buildExpressionShadowPlan, buildGenericExpressionShadowPlan } from "./expression-shadow-planner.ts";

type ExpressionShadowMode = "off" | "shadow" | "enforced_owner_only" | "canary";
type ShortcutResponseMode = "json" | "text";

interface ShadowCaptureInput {
  userId: string | null;
  payload: Record<string, unknown>;
  responseMode: ShortcutResponseMode;
  occurredAt?: string | null;
}

interface ShadowDatabaseClient {
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
}

const SUPPORTED_MODES = new Set<ExpressionShadowMode>([
  "off",
  "shadow",
  "enforced_owner_only",
  "canary",
]);

function normalizeString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function recordIdentity(payload: Record<string, unknown>): {
  recordType: string | null;
  recordId: string | null;
} {
  const data = objectValue(payload.data);
  return {
    recordType: normalizeString(payload.record_type)
      ?? normalizeString(data?.record_type)
      ?? normalizeString(data?.domain_key)
      ?? (data?.transaction_date || data?.merchant_name ? "expense" : null)
      ?? (data?.income_date || data?.source_name ? "income" : null),
    recordId: normalizeString(payload.id) ?? normalizeString(data?.id),
  };
}

function normalizeMode(value: string | undefined): ExpressionShadowMode {
  const normalized = (value ?? "off").trim().toLowerCase() as ExpressionShadowMode;
  return SUPPORTED_MODES.has(normalized) ? normalized : "off";
}

function compactFeedback(value: unknown): Record<string, unknown> | null {
  const feedback = objectValue(value);
  if (!feedback) return null;
  return {
    badge: normalizeString(feedback.badge),
    band: normalizeString(feedback.band),
    emotion_line: normalizeString(feedback.emotion_line),
    utility_line: normalizeString(feedback.utility_line),
    confidence: typeof feedback.confidence === "number" ? feedback.confidence : null,
  };
}

function visibleFieldPaths(payload: Record<string, unknown>): string[] {
  if (normalizeString(payload.notification)) return ["notification"];
  if (normalizeString(payload.message)) return ["message"];
  return [];
}

function persistedOnlyFieldPaths(payload: Record<string, unknown>): string[] {
  return compactFeedback(payload.ai_feedback) ? ["ai_feedback"] : [];
}

function baselinePayload(payload: Record<string, unknown>): Record<string, unknown> {
  const identity = recordIdentity(payload);
  return {
    status: normalizeString(payload.status),
    record_type: identity.recordType,
    record_id: identity.recordId,
    notification: normalizeString(payload.notification),
    message: normalizeString(payload.message),
    possible_duplicate: payload.possible_duplicate === true,
    ai_ok: typeof payload.ai_ok === "boolean" ? payload.ai_ok : null,
    ai_feedback: compactFeedback(payload.ai_feedback),
  };
}

function buildCollectorResult(payload: Record<string, unknown>): Record<string, unknown> {
  const identity = recordIdentity(payload);
  const status = normalizeString(payload.status);
  return {
    planner_version: "expression-shadow-collector-v0.1",
    planner_status: "captured_for_offline_planner",
    changes_user_output: false,
    surface: "shortcut_notification",
    observed_facts: [{
      semantic_key: "record_delivery_result",
      claim_type: "fact",
      structured_value: {
        record_type: identity.recordType,
        status,
        record_id: identity.recordId,
      },
      fixed_content_covered: true,
    }],
    candidate_generation: ["expense", "income", "sleep", "sport", "food", "reading", "wallet"].includes(identity.recordType ?? "")
      ? "shared_expression_planner_available"
      : "awaiting_domain_candidate_generator",
  };
}

export function getExpressionShadowMode(): ExpressionShadowMode {
  return normalizeMode(Deno.env.get("EXPRESSION_PLANNER_MODE"));
}

async function persistShadowPlan(
  supabase: ShadowDatabaseClient,
  params: { eventKey: string; collectorResult: Record<string, unknown> },
  plan: Record<string, unknown>,
): Promise<void> {
  const scoreSummary = plan.status === "auto_planned"
    ? { eligibility: plan.eligibility_summary, scoring: plan.score_summary, plans: plan.plan_summary }
    : {};
  const { error } = await supabase.from("expression_shadow_runs").update({
    collector_result: {
      ...params.collectorResult,
      planner_status: plan.status,
      planner_version: plan.planner_version ?? "expression-shadow-auto-v0.2",
      candidate_generation: "shared_expression_planner_completed",
    },
    proposed_plan: plan, proposed_score_summary: scoreSummary,
    processed_at: new Date().toISOString(), processing_error: null,
  }).eq("event_key", params.eventKey);
  if (error) throw new Error(error.message);
}

async function persistPlannerError(supabase: ShadowDatabaseClient, eventKey: string, error: unknown): Promise<void> {
  const message = error instanceof Error ? error.message : String(error);
  console.warn("[expression-shadow] planner failed:", message);
  const { error: updateError } = await supabase.from("expression_shadow_runs")
    .update({ processed_at: new Date().toISOString(), processing_error: message.slice(0, 500) })
    .eq("event_key", eventKey);
  if (updateError) console.warn("[expression-shadow] planner error persistence failed:", updateError.message);
}

async function processExpenseShadow(supabase: ShadowDatabaseClient, params: { eventKey: string; userId: string; recordId: string; occurredAt: string; collectorResult: Record<string, unknown> }): Promise<void> {
  try {
    const { data, error } = await supabase.from("transactions")
      .select("id,transaction_date,transaction_time,created_at,amount,merchant_name,category,platform,payment_method,status")
      .eq("user_id", params.userId).order("transaction_date", { ascending: false }).order("transaction_time", { ascending: false }).limit(500);
    if (error) throw new Error(error.message);
    const personalization = await loadPlannerPersonalization(supabase, params.userId);
    const plan = buildExpressionShadowPlan({ transactions: data ?? [], currentRecordId: params.recordId, occurredAt: params.occurredAt, ...personalization });
    await persistShadowPlan(supabase, params, plan as Record<string, unknown>);
  } catch (error) { await persistPlannerError(supabase, params.eventKey, error); }
}

async function processIncomeShadow(supabase: ShadowDatabaseClient, params: { eventKey: string; userId: string; recordId: string; collectorResult: Record<string, unknown> }): Promise<void> {
  try {
    const { data, error } = await supabase.from("income_records")
      .select("id,income_date,created_at,amount,source_name,category")
      .eq("user_id", params.userId).order("income_date", { ascending: false }).limit(500);
    if (error) throw new Error(error.message);
    const records = (data ?? []).map((row: Record<string, unknown>) => ({
      id: row.id, occurred_at: `${row.income_date}T12:00:00+08:00`, amount: row.amount, source_name: row.source_name, payload: { category: row.category }, source_type: "income_record",
    }));
    const personalization = await loadPlannerPersonalization(supabase, params.userId);
    const plan = buildGenericExpressionShadowPlan({ domainKey: "income", records, currentRecordId: params.recordId, ...personalization });
    await persistShadowPlan(supabase, params, plan as Record<string, unknown>);
  } catch (error) { await persistPlannerError(supabase, params.eventKey, error); }
}

async function processBuiltinShadow(supabase: ShadowDatabaseClient, params: { eventKey: string; userId: string; recordId: string; domainKey: string; collectorResult: Record<string, unknown> }): Promise<void> {
  try {
    const { data, error } = await supabase.from("data_records")
      .select("id,occurred_at,title,summary,payload_jsonb,domain_key")
      .eq("user_id", params.userId).eq("domain_key", params.domainKey).order("occurred_at", { ascending: false }).limit(500);
    if (error) throw new Error(error.message);
    const records = (data ?? []).map((row: Record<string, unknown>) => ({
      id: row.id, occurred_at: row.occurred_at, title: row.title, summary: row.summary, payload: row.payload_jsonb ?? {}, source_type: "data_record",
    }));
    const personalization = await loadPlannerPersonalization(supabase, params.userId);
    const plan = buildGenericExpressionShadowPlan({ domainKey: params.domainKey, records, currentRecordId: params.recordId, ...personalization });
    await persistShadowPlan(supabase, params, plan as Record<string, unknown>);
  } catch (error) { await persistPlannerError(supabase, params.eventKey, error); }
}
function baselineSemanticKey(recordType: string | null, badge: string): string {
  const known: Record<string, string> = {
    "高频日常": "merchant_daily_count_total",
    "重复商户": "merchant_daily_count_total",
    "开发充值": "merchant_daily_count_total",
    "消费加速": "merchant_week_to_date_vs_previous_week_same_period",
    "收入入账": "income_current_amount",
    "工资到账": "income_current_amount",
    "餐饮入账": "food_expense_recorded",
  };
  return known[badge] ?? `${recordType ?? "unknown"}_baseline_${badge.toLowerCase().replace(/\s+/g, "_").slice(0, 32)}`;
}

async function loadPlannerPersonalization(supabase: ShadowDatabaseClient, userId: string) {
  const [{ data: snapshot }, { data: exposures }] = await Promise.all([
    supabase.from("expression_preference_snapshots").select("scoring_profile").eq("user_id", userId).maybeSingle(),
    supabase.from("expression_exposure_events").select("semantic_key,occurred_at")
      .eq("user_id", userId).eq("counts_for_novelty", true).order("occurred_at", { ascending: false }).limit(1000),
  ]);
  const exposureHistory: Record<string, { count: number; last_shown_at: string | null }> = {};
  for (const item of exposures ?? []) {
    const key = normalizeString(item.semantic_key);
    if (!key) continue;
    const entry = exposureHistory[key] ?? { count: 0, last_shown_at: null };
    entry.count += 1;
    if (!entry.last_shown_at) entry.last_shown_at = item.occurred_at ?? null;
    exposureHistory[key] = entry;
  }
  return { preferenceProfile: objectValue(snapshot?.scoring_profile) ?? {}, exposureHistory };
}

async function captureBaselineExposure(
  supabase: ShadowDatabaseClient,
  params: {
    eventKey: string; occurredAt: string; userId: string; traceId: string | null; aiLogId: string | null;
    recordType: string | null; recordId: string | null; payload: Record<string, unknown>;
  },
): Promise<void> {
  const feedback = compactFeedback(params.payload.ai_feedback);
  if (!feedback || !params.recordId) return;
  const badge = normalizeString(feedback.badge) ?? "即时反馈";
  const semanticKey = baselineSemanticKey(params.recordType, badge);
  const exposureEventKey = `${params.eventKey}:baseline_ai_feedback`;
  const row = {
    event_key: exposureEventKey, delivery_attempt_id: params.eventKey, occurred_at: params.occurredAt,
    user_id: params.userId, trace_id: params.traceId, ai_log_id: params.aiLogId, record_id: params.recordId,
    record_type: params.recordType, domain_key: params.recordType, entity_id: null,
    candidate_id: `baseline:${params.recordType ?? "unknown"}:${params.recordId}:${semanticKey}`,
    semantic_key: semanticKey, claim_type: "inference", dimension: "baseline_voice_feedback",
    surface: "shortcut_notification", lifecycle_state: "returned_to_shortcut", selection_mode: "legacy_voice",
    score: null, expression_plan_version: "legacy-voice-v1", render_contract_version: "shortcut-baseline-v1", scoring_version: null,
    visible_field_paths: ["rendered_feedback.badge", "rendered_feedback.emotion_line", "rendered_feedback.utility_line"],
    expandable_field_paths: [], persisted_only_field_paths: ["rendered_feedback.confidence"],
    rendered_payload: { feedback, notification: normalizeString(params.payload.notification) },
    metadata: { source: "production_baseline", shadow_event_key: params.eventKey },
    simulation_only: false, counts_for_novelty: true,
  };
  const { error } = await supabase.from("expression_exposure_events")
    .upsert(row, { onConflict: "event_key", ignoreDuplicates: true });
  if (error) console.warn("[expression-shadow] exposure capture failed:", error.message);
}

async function captureExpressionShadow(
  supabase: ShadowDatabaseClient,
  input: ShadowCaptureInput,
  mode: ExpressionShadowMode,
): Promise<void> {
  if (!input.userId) return;
  const traceId = normalizeString(input.payload.trace_id);
  const aiLogId = normalizeString(input.payload.ai_log_id);
  const identity = recordIdentity(input.payload);
  const eventKey = [
    traceId ?? crypto.randomUUID(),
    aiLogId ?? "no-ai-log",
    identity.recordType ?? "unknown",
    identity.recordId ?? "no-record",
    "shortcut_notification",
  ].join(":");
  const collectorResult = buildCollectorResult(input.payload);
  const row = {
    event_key: eventKey,
    occurred_at: input.occurredAt ?? new Date().toISOString(),
    user_id: input.userId,
    trace_id: traceId,
    ai_log_id: aiLogId,
    record_type: identity.recordType,
    record_id: identity.recordId,
    surface: "shortcut_notification",
    response_mode: input.responseMode,
    rollout_mode: mode,
    lifecycle_state: "returned_to_shortcut",
    baseline_payload: baselinePayload(input.payload),
    visible_field_paths: visibleFieldPaths(input.payload),
    persisted_only_field_paths: persistedOnlyFieldPaths(input.payload),
    collector_result: collectorResult,
    proposed_plan: {},
    proposed_score_summary: {},
    changes_user_output: false,
    collector_version: "expression-shadow-collector-v0.1",
  };
  const { error } = await supabase.from("expression_shadow_runs").upsert(row, {
    onConflict: "event_key",
    ignoreDuplicates: true,
  });
  if (error) throw new Error(error.message);
  await captureBaselineExposure(supabase, {
    eventKey, occurredAt: input.occurredAt ?? new Date().toISOString(), userId: input.userId, traceId, aiLogId,
    recordType: identity.recordType, recordId: identity.recordId, payload: input.payload,
  });
  if (normalizeString(input.payload.status) === "done" && identity.recordId) {
    const plannerParams = { eventKey, userId: input.userId, recordId: identity.recordId, collectorResult };
    if (identity.recordType === "expense") {
      await processExpenseShadow(supabase, { ...plannerParams, occurredAt: input.occurredAt ?? new Date().toISOString() });
    } else if (identity.recordType === "income") {
      await processIncomeShadow(supabase, plannerParams);
    } else if (["sleep", "sport", "food", "reading", "wallet"].includes(identity.recordType ?? "")) {
      await processBuiltinShadow(supabase, { ...plannerParams, domainKey: identity.recordType! });
    }
  }
}

export function scheduleExpressionShadowCapture(
  supabase: ShadowDatabaseClient,
  input: ShadowCaptureInput,
): void {
  const mode = getExpressionShadowMode();
  if (mode === "off") return;
  const task = captureExpressionShadow(supabase, input, mode).catch((error) => {
    console.warn("[expression-shadow] capture failed:", error instanceof Error ? error.message : String(error));
  });
  try {
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(task) ?? task;
  } catch {
    // waitUntil unavailable: the promise already has its own rejection handler.
  }
}
