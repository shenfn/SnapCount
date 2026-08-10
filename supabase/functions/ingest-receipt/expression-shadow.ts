import {
  buildDataPlannerSourceRecord,
  buildCrossRecordSourceRecord,
  buildExpressionShadowPlan,
  buildGenericExpressionShadowPlan,
  buildIncomePlannerSourceRecord,
  EXPRESSION_PLANNER_VERSION,
  plannerSourceFingerprint,
} from "./expression-shadow-planner.ts";
import { rebuildExpressionPreferenceSnapshot } from "./expression-feedback.ts";

type ExpressionShadowMode = "off" | "shadow" | "enforced_owner_only" | "canary";
type ShortcutResponseMode = "json" | "text";

interface ShadowCaptureInput {
  userId: string | null;
  payload: Record<string, unknown>;
  responseMode: ShortcutResponseMode;
  improvementConsent: boolean;
  occurredAt?: string | null;
}

interface ShadowDatabaseClient {
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
  // deno-lint-ignore no-explicit-any
  rpc: (name: string, params: Record<string, unknown>) => any;
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

function feedbackSignal(value: unknown): Record<string, unknown> | null {
  const feedback = objectValue(value);
  if (!feedback) return null;
  return {
    present: true,
    confidence: typeof feedback.confidence === "number" ? feedback.confidence : null,
  };
}

function normalizeTelemetryCode(value: unknown): string | null {
  const normalized = normalizeString(value);
  return normalized && /^[a-z0-9][a-z0-9_.:-]{0,127}$/i.test(normalized) ? normalized : null;
}

function stringList(value: unknown, limit = 20): string[] {
  if (!Array.isArray(value)) return [];
  return value.map(normalizeTelemetryCode).filter((item): item is string => item !== null).slice(0, limit);
}

function numericFlags(
  value: unknown,
  allowedKeys: ReadonlySet<string>,
): Record<string, number | boolean | null> {
  const source = objectValue(value);
  if (!source) return {};
  const result: Record<string, number | boolean | null> = {};
  for (const [key, item] of Object.entries(source)) {
    if (allowedKeys.has(key) && (typeof item === "number" || typeof item === "boolean" || item === null)) {
      result[key] = item;
    }
  }
  return result;
}

const QUALITY_TELEMETRY_FIELDS = new Set([
  "confidence",
  "sample_count",
  "data_coverage",
  "importance",
  "relevance",
  "novelty",
]);
const ELIGIBILITY_TELEMETRY_FIELDS = new Set([
  "total_candidates",
  "claim_eligible",
  "claim_blocked",
]);

function minimizedSurfaceEntries(value: unknown, includeScore: boolean): Record<string, unknown> {
  const source = objectValue(value);
  if (!source) return {};
  return Object.fromEntries(Object.entries(source).flatMap(([rawSurface, rawEntry]) => {
    const surface = normalizeTelemetryCode(rawSurface);
    if (!surface) return [];
    const entry = objectValue(rawEntry) ?? {};
    return [[surface, {
      eligible: entry.eligible === true,
      ...(includeScore && typeof entry.score === "number" ? { score: entry.score } : {}),
      ...(includeScore && typeof entry.passes_threshold === "boolean"
        ? { passes_threshold: entry.passes_threshold }
        : {}),
      ...(!includeScore ? { blocked_reasons: stringList(entry.blocked_reasons, 10) } : {}),
    }]];
  }));
}

function minimizedPlanSummary(value: unknown): Record<string, unknown> {
  const source = objectValue(value);
  if (!source) return {};
  return Object.fromEntries(Object.entries(source).flatMap(([rawSurface, rawPlan]) => {
    const surface = normalizeTelemetryCode(rawSurface);
    if (!surface) return [];
    const plan = objectValue(rawPlan) ?? {};
    const selected = Array.isArray(plan.selected)
      ? plan.selected.slice(0, 20).map((rawItem) => {
        const item = objectValue(rawItem) ?? {};
        return {
          semantic_key: normalizeTelemetryCode(item.semantic_key),
          score: typeof item.score === "number" ? item.score : null,
          selection_mode: normalizeTelemetryCode(item.selection_mode),
        };
      })
      : [];
    return [[surface, {
      capacity: typeof plan.capacity === "number" ? plan.capacity : null,
      selected_count: typeof plan.selected_count === "number" ? plan.selected_count : selected.length,
      selected,
      fallback_used: plan.fallback_used === true,
      silent: plan.silent === true,
    }]];
  }));
}

export function minimizeExpressionShadowPlan(plan: Record<string, unknown>): Record<string, unknown> {
  const candidates = Array.isArray(plan.candidates)
    ? plan.candidates.slice(0, 100).map((rawCandidate, candidateIndex) => {
      const candidate = objectValue(rawCandidate) ?? {};
      const claim = objectValue(candidate.claim) ?? {};
      const eligibility = objectValue(candidate.eligibility) ?? {};
      const scoring = objectValue(candidate.scoring) ?? {};
      return {
        candidate_index: candidateIndex,
        semantic_key: normalizeTelemetryCode(claim.semantic_key),
        claim_type: normalizeTelemetryCode(candidate.claim_type),
        dimension: normalizeTelemetryCode(candidate.dimension),
        quality: numericFlags(candidate.quality, QUALITY_TELEMETRY_FIELDS),
        eligibility: {
          eligible: eligibility.eligible === true,
          blocked_reasons: stringList(eligibility.blocked_reasons, 10),
          surfaces: minimizedSurfaceEntries(eligibility.surface_eligibility, false),
        },
        scoring: { surfaces: minimizedSurfaceEntries(scoring.surfaces, true) },
      };
    })
    : [];
  return {
    status: normalizeTelemetryCode(plan.status),
    reason: normalizeTelemetryCode(plan.reason),
    planner_version: normalizeTelemetryCode(plan.planner_version),
    domain_key: normalizeTelemetryCode(plan.domain_key),
    changes_user_output: false,
    candidate_count: typeof plan.candidate_count === "number" ? plan.candidate_count : candidates.length,
    candidates,
    plan_summary: minimizedPlanSummary(plan.plan_summary),
    eligibility_summary: numericFlags(plan.eligibility_summary, ELIGIBILITY_TELEMETRY_FIELDS),
  };
}

function visibleFieldPaths(payload: Record<string, unknown>): string[] {
  if (normalizeString(payload.notification)) return ["notification"];
  if (normalizeString(payload.message)) return ["message"];
  return [];
}

function persistedOnlyFieldPaths(payload: Record<string, unknown>): string[] {
  return feedbackSignal(payload.ai_feedback) ? ["ai_feedback"] : [];
}

export function buildExpressionShadowBaselinePayload(payload: Record<string, unknown>): Record<string, unknown> {
  const identity = recordIdentity(payload);
  return {
    status: normalizeString(payload.status),
    record_type: identity.recordType,
    possible_duplicate: payload.possible_duplicate === true,
    ai_ok: typeof payload.ai_ok === "boolean" ? payload.ai_ok : null,
    ai_feedback: feedbackSignal(payload.ai_feedback),
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

export function shouldCaptureExpressionShadow(
  improvementConsent: boolean,
  mode: ExpressionShadowMode,
): boolean {
  return improvementConsent && mode !== "off";
}

async function persistShadowPlan(
  supabase: ShadowDatabaseClient,
  params: { eventKey: string; collectorResult: Record<string, unknown> },
  plan: Record<string, unknown>,
): Promise<void> {
  const minimizedPlan = minimizeExpressionShadowPlan(plan);
  const scoreSummary = minimizedPlan.status === "auto_planned"
    ? { eligibility: minimizedPlan.eligibility_summary, plans: minimizedPlan.plan_summary }
    : {};
  const sourceRecordIds = Array.isArray(plan.source_dependencies)
    ? [...new Set(plan.source_dependencies.flatMap((rawDependency) => {
      const dependency = objectValue(rawDependency);
      const sourceRecordId = normalizeString(dependency?.source_record_id);
      return sourceRecordId ? [sourceRecordId] : [];
    }))]
    : [];
  const { error } = await supabase.from("expression_shadow_runs").update({
    collector_result: {
      ...params.collectorResult,
      planner_status: plan.status,
      planner_version: plan.planner_version ?? EXPRESSION_PLANNER_VERSION,
      candidate_generation: "shared_expression_planner_completed",
    },
    proposed_plan: minimizedPlan, proposed_score_summary: scoreSummary, source_record_ids: sourceRecordIds,
    processed_at: new Date().toISOString(), processing_error: null,
  }).eq("event_key", params.eventKey);
  if (error) throw new Error(error.message);
}

async function persistPlannerError(supabase: ShadowDatabaseClient, eventKey: string, error: unknown): Promise<void> {
  console.warn("[expression-shadow] planner failed", error instanceof Error ? error.name : "unknown_error");
  const { error: updateError } = await supabase.from("expression_shadow_runs")
    .update({ processed_at: new Date().toISOString(), processing_error: "planner_execution_failed" })
    .eq("event_key", eventKey);
  if (updateError) console.warn("[expression-shadow] planner error persistence failed:", updateError.message);
}

/**
 * Persist a candidate only at the point where a shared planner render is
 * actually delivered. Shadow previews return without writing so they cannot
 * consume novelty budget or violate the production exposure table contract.
 */
export async function persistPlannerExposureEvents(
  supabase: ShadowDatabaseClient,
  params: {
    userId: string;
    recordId?: string | null;
    recordType?: string | null;
    occurredAt: string;
    surface: string;
    deliveryAttemptId: string;
    plan: Record<string, unknown>;
    candidateIds?: string[];
    deliveryEvidenceByCandidateId?: Record<string, {
      rendered_payload?: Record<string, unknown>;
      visible_field_paths?: string[];
      expandable_field_paths?: string[];
      persisted_only_field_paths?: string[];
      presentation_target?: string;
      rendered_text_fingerprint?: string;
    }>;
    lifecycleState?: string;
    simulationOnly?: boolean;
  },
): Promise<Record<string, unknown>[]> {
  if (params.simulationOnly === true) return [];
  const renderPlans = objectValue(params.plan.render_plans) ?? {};
  const renderPlan = objectValue(renderPlans[params.surface]) ?? {};
  const decision = objectValue(params.plan.decision) ?? {};
  const decisionId = normalizeString(decision.decision_id);
  const selectionProbability = typeof decision.selection_probability === "number"
      && Number.isFinite(decision.selection_probability)
    ? decision.selection_probability
    : null;
  const allSelected = Array.isArray(renderPlan.selected)
    ? renderPlan.selected
    : normalizeString(params.plan.surface) === params.surface && Array.isArray(params.plan.selected)
    ? params.plan.selected
    : params.surface === "shortcut_notification" && Array.isArray(params.plan.selected)
    ? params.plan.selected
    : [];
  const requestedCandidateIds = new Set((params.candidateIds ?? []).filter(Boolean));
  const selected = requestedCandidateIds.size > 0
    ? allSelected.filter((item: Record<string, unknown>) => requestedCandidateIds.has(String(item.candidate_id ?? "")))
    : allSelected;
  const candidates = Array.isArray(params.plan.candidates) ? params.plan.candidates : [];
  const byId = new Map(candidates.map((candidate: Record<string, unknown>) => [candidate.candidate_id, candidate]));
  const deliveries = selected.map((item: Record<string, unknown>) => {
    const candidate = byId.get(item.candidate_id) ?? {};
    const claim = objectValue(candidate.claim) ?? {};
    const selectionHints = objectValue(candidate.selection_hints) ?? {};
    const deliveryEvidence = objectValue(
      params.deliveryEvidenceByCandidateId?.[String(item.candidate_id ?? "")],
    );
    const exposureKey = normalizeString(item.exposure_key)
      ?? normalizeString(selectionHints.exposure_key)
      ?? normalizeString(claim.semantic_key)
      ?? String(item.candidate_id ?? "unknown");
    const dedupeKey = normalizeString(item.dedupe_key)
      ?? normalizeString(selectionHints.dedupe_key)
      ?? exposureKey;
    const sources = Array.isArray(candidate.source_dependencies)
      ? candidate.source_dependencies.flatMap((rawDependency: unknown) => {
        const dependency = objectValue(rawDependency);
        const sourceTable = normalizeString(dependency?.source_table);
        const sourceRecordId = normalizeString(dependency?.source_record_id);
        const sourceFingerprint = normalizeString(dependency?.source_fingerprint);
        if (!sourceTable || !sourceRecordId || !sourceFingerprint) return [];
        return [{
          source_table: sourceTable,
          source_record_id: sourceRecordId,
          source_fingerprint: sourceFingerprint,
          is_primary: dependency?.is_primary === true,
        }];
      })
      : [];
    const renderedPayload = deliveryEvidence?.rendered_payload ?? {
      canonical_text: item.canonical_text ?? claim.canonical_text ?? null,
    };
    const contentFingerprint = plannerSourceFingerprint({
      planner_version: params.plan.planner_version,
      render_contract_version: renderPlan.render_contract_version,
      candidate_id: item.candidate_id,
      semantic_key: claim.semantic_key,
      exposure_key: exposureKey,
      dedupe_key: dedupeKey,
      rendered_payload: renderedPayload,
      presentation_target: normalizeString(deliveryEvidence?.presentation_target),
      rendered_text_fingerprint: normalizeString(deliveryEvidence?.rendered_text_fingerprint),
      sources,
    });
    const eventKey = [
      "planner",
      params.userId,
      params.recordId ?? "no-record",
      params.surface,
      params.deliveryAttemptId,
      String(item.candidate_id ?? "unknown"),
      contentFingerprint,
    ].join(":");
    const row = {
      event_key: eventKey,
      delivery_attempt_id: params.deliveryAttemptId,
      occurred_at: params.occurredAt,
      user_id: params.userId,
      record_id: params.recordId ?? null,
      record_type: params.recordType ?? null,
      domain_key: normalizeString(candidate.domain_key) ?? params.recordType ?? null,
      entity_id: normalizeString(claim.structured_value && objectValue(claim.structured_value)?.entity_id),
      candidate_id: String(item.candidate_id ?? "unknown"),
      semantic_key: normalizeString(claim.semantic_key) ?? "unknown",
      claim_type: normalizeString(candidate.claim_type) ?? "inference",
      dimension: normalizeString(candidate.dimension),
      surface: params.surface,
      lifecycle_state: params.lifecycleState ?? "client_rendered",
      selection_mode: normalizeString(item.selection_mode) ?? "threshold",
      score: typeof item.score === "number" ? item.score : null,
      expression_plan_version: normalizeString(renderPlan.expression_plan_version)
        ?? normalizeString(params.plan.planner_version)
        ?? EXPRESSION_PLANNER_VERSION,
      render_contract_version: normalizeString(renderPlan.render_contract_version) ?? "surface-render-contract-v0.1",
      scoring_version: normalizeString(objectValue(candidate.scoring)?.scoring_version),
      visible_field_paths: Array.isArray(deliveryEvidence?.visible_field_paths)
        ? deliveryEvidence.visible_field_paths
        : Array.isArray(item.visible_field_paths) ? item.visible_field_paths : [],
      expandable_field_paths: Array.isArray(deliveryEvidence?.expandable_field_paths)
        ? deliveryEvidence.expandable_field_paths
        : Array.isArray(item.expandable_field_paths) ? item.expandable_field_paths : [],
      persisted_only_field_paths: Array.isArray(deliveryEvidence?.persisted_only_field_paths)
        ? deliveryEvidence.persisted_only_field_paths
        : Array.isArray(item.persisted_only_field_paths) ? item.persisted_only_field_paths : [],
      rendered_payload: renderedPayload,
      metadata: {
        source: "shared_expression_planner",
        plan_token: params.deliveryAttemptId,
        content_fingerprint: contentFingerprint,
        exposure_key: exposureKey,
        scoped_exposure_key: `${params.surface}:${exposureKey}`,
        dedupe_key: dedupeKey,
        scoped_dedupe_key: `${params.surface}:${dedupeKey}`,
        ...(normalizeString(deliveryEvidence?.presentation_target)
          ? { presentation_target: normalizeString(deliveryEvidence?.presentation_target) }
          : {}),
        ...(normalizeString(deliveryEvidence?.rendered_text_fingerprint)
          ? { rendered_text_fingerprint: normalizeString(deliveryEvidence?.rendered_text_fingerprint) }
          : {}),
        ...(decisionId
          ? {
            decision_id: decisionId,
            decision_version: normalizeString(decision.decision_version),
            decided_at: normalizeString(decision.decided_at),
            policy_name: normalizeString(decision.policy_name),
            policy_version: normalizeString(decision.policy_version),
            planner_version: normalizeString(decision.planner_version),
            decision_scoring_version: normalizeString(decision.scoring_version),
            candidate_schema_version: normalizeString(decision.candidate_schema_version),
            chosen_action_id: normalizeString(decision.chosen_action_id),
            selection_probability: selectionProbability,
            decision_selection_mode: normalizeString(decision.selection_mode),
            action_set: Array.isArray(decision.action_set) ? decision.action_set : [],
          }
          : {}),
      },
      simulation_only: false,
      counts_for_novelty: true,
    };
    return { row, sources };
  });
  if (!deliveries.length) return [];
  return await Promise.all(deliveries.map(async ({ row, sources }) => {
    const { data, error } = await supabase.rpc("persist_expression_exposure_with_sources", {
      p_user_id: params.userId,
      p_event_key: row.event_key,
      p_exposure: row,
      p_sources: sources,
    });
    if (error) throw new Error(error.message);
    return objectValue(objectValue(data)?.exposure) ?? objectValue(data) ?? {};
  }));
}

async function processExpenseShadow(supabase: ShadowDatabaseClient, params: { eventKey: string; userId: string; recordId: string; occurredAt: string | null; collectorResult: Record<string, unknown> }): Promise<void> {
  try {
    const { data, error } = await supabase.from("transactions")
      .select("id,transaction_date,transaction_time,occurred_at,created_at,amount,merchant_name,category,platform,payment_method,note,status,type,staging_record_id,image_hash")
      .eq("user_id", params.userId).eq("type", "expense")
      .order("occurred_at", { ascending: false }).order("transaction_date", { ascending: false }).limit(500);
    if (error) throw new Error(error.message);
    const relatedRecords = await loadCrossDomainRecords(supabase, params.userId);
    const personalization = await loadPlannerPersonalization(supabase, params.userId);
    const plan = buildExpressionShadowPlan({ transactions: data ?? [], currentRecordId: params.recordId, occurredAt: params.occurredAt, relatedRecords, ...personalization });
    await persistShadowPlan(supabase, params, plan as Record<string, unknown>);
  } catch (error) { await persistPlannerError(supabase, params.eventKey, error); }
}

async function processIncomeShadow(supabase: ShadowDatabaseClient, params: { eventKey: string; userId: string; recordId: string; collectorResult: Record<string, unknown> }): Promise<void> {
  try {
    const { data, error } = await supabase.from("income_records")
      .select("id,income_date,occurred_at,created_at,amount,source_name,category")
      .eq("user_id", params.userId).order("occurred_at", { ascending: false }).order("income_date", { ascending: false }).limit(500);
    if (error) throw new Error(error.message);
    const records = (data ?? []).map(buildIncomePlannerSourceRecord);
    const relatedRecords = await loadCrossDomainRecords(supabase, params.userId);
    const personalization = await loadPlannerPersonalization(supabase, params.userId);
    const plan = buildGenericExpressionShadowPlan({ domainKey: "income", records, currentRecordId: params.recordId, relatedRecords, ...personalization });
    await persistShadowPlan(supabase, params, plan as Record<string, unknown>);
  } catch (error) { await persistPlannerError(supabase, params.eventKey, error); }
}

async function processBuiltinShadow(supabase: ShadowDatabaseClient, params: { eventKey: string; userId: string; recordId: string; domainKey: string; collectorResult: Record<string, unknown> }): Promise<void> {
  try {
    const { data, error } = await supabase.from("data_records")
      .select("id,created_at,occurred_at,title,summary,payload_jsonb,domain_key,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at")
      .eq("user_id", params.userId).eq("domain_key", params.domainKey).order("occurred_at", { ascending: false }).limit(500);
    if (error) throw new Error(error.message);
    const records = (data ?? []).map(buildDataPlannerSourceRecord);
    const relatedRecords = await loadCrossDomainRecords(supabase, params.userId);
    const personalization = await loadPlannerPersonalization(supabase, params.userId);
    const plan = buildGenericExpressionShadowPlan({ domainKey: params.domainKey, records, currentRecordId: params.recordId, relatedRecords, ...personalization });
    await persistShadowPlan(supabase, params, plan as Record<string, unknown>);
  } catch (error) { await persistPlannerError(supabase, params.eventKey, error); }
}

async function loadCrossDomainRecords(supabase: ShadowDatabaseClient, userId: string): Promise<import("./expression-shadow-planner.ts").ShadowRelatedRecord[]> {
  const [transactions, income, data] = await Promise.all([
    supabase.from("transactions")
      .select("id,occurred_at,created_at,merchant_name,note,status,type")
      .eq("user_id", userId).eq("type", "expense").order("occurred_at", { ascending: false }).limit(250),
    supabase.from("income_records")
      .select("id,occurred_at,created_at,source_name")
      .eq("user_id", userId).order("occurred_at", { ascending: false }).limit(250),
    supabase.from("data_records")
      .select("id,domain_key,occurred_at,created_at,title,summary,payload_jsonb")
      .eq("user_id", userId).order("occurred_at", { ascending: false }).limit(500),
  ]);
  for (const result of [transactions, income, data]) {
    if (result.error) throw new Error(result.error.message);
  }
  return [
    ...(transactions.data ?? []).map((row: Record<string, unknown>) => buildCrossRecordSourceRecord(row, "transactions")),
    ...(income.data ?? []).map((row: Record<string, unknown>) => buildCrossRecordSourceRecord(row, "income_records")),
    ...(data.data ?? []).map((row: Record<string, unknown>) => buildCrossRecordSourceRecord(row, "data_records")),
  ];
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
  return known[badge] ?? `${recordType ?? "unknown"}_baseline_feedback`;
}

export async function loadPlannerPersonalization(supabase: ShadowDatabaseClient, userId: string) {
  const [revisionResult, exposureResult] = await Promise.all([
    supabase.from("expression_preference_revisions").select("revision").eq("user_id", userId).maybeSingle(),
    supabase.from("expression_exposure_events").select("semantic_key,occurred_at,metadata,selection_mode,lifecycle_state,simulation_only,counts_for_novelty,surface")
      .eq("user_id", userId).eq("counts_for_novelty", true).order("occurred_at", { ascending: false }).limit(1000),
  ]);
  if (revisionResult.error) throw new Error(revisionResult.error.message);
  if (exposureResult.error) throw new Error(exposureResult.error.message);
  const { data: revision } = revisionResult;
  const { data: exposures } = exposureResult;
  const snapshotResult = await supabase.from("expression_preference_snapshots")
    .select("scoring_profile,source_revision")
    .eq("user_id", userId)
    .maybeSingle();
  if (snapshotResult.error) throw new Error(snapshotResult.error.message);
  const snapshot = snapshotResult.data;
  const exposureHistory: Record<string, { count: number; last_shown_at: string | null }> = {};
  for (const item of exposures ?? []) {
    if (item.simulation_only === true || item.counts_for_novelty !== true) continue;
    if (item.selection_mode === "legacy_voice") continue;
    const lifecycleState = normalizeString(item.lifecycle_state);
    if (lifecycleState && !["returned_to_shortcut", "client_rendered", "client_acknowledged", "user_reviewed"].includes(lifecycleState)) continue;
    const metadata = objectValue(item.metadata) ?? {};
    const exposureKey = normalizeString(metadata.exposure_key) ?? normalizeString(item.semantic_key);
    const dedupeKey = normalizeString(metadata.dedupe_key) ?? exposureKey;
    const surface = normalizeString(item.surface);
    if (!exposureKey || !surface) continue;
    const historyKeys = new Set([
      normalizeString(metadata.scoped_exposure_key) ?? `${surface}:${exposureKey}`,
      normalizeString(metadata.scoped_dedupe_key) ?? `${surface}:${dedupeKey}`,
    ]);
    for (const key of historyKeys) {
      if (!key) continue;
      const entry = exposureHistory[key] ?? { count: 0, last_shown_at: null };
      entry.count += 1;
      if (!entry.last_shown_at) entry.last_shown_at = item.occurred_at ?? null;
      exposureHistory[key] = entry;
    }
  }
  const currentRevision = Number(revision?.revision);
  const snapshotRevision = Number(snapshot?.source_revision);
  const snapshotIsCurrent = !Number.isFinite(currentRevision)
    || (Number.isFinite(snapshotRevision) && snapshotRevision === currentRevision);
  let preferenceProfile = snapshotIsCurrent ? objectValue(snapshot?.scoring_profile) ?? {} : {};
  if (!snapshotIsCurrent) {
    preferenceProfile = (await rebuildExpressionPreferenceSnapshot(supabase, userId)).scoringProfile;
  }
  return { preferenceProfile, exposureHistory };
}

async function captureBaselineExposure(
  supabase: ShadowDatabaseClient,
  params: {
    eventKey: string; occurredAt: string; userId: string; traceId: string | null; aiLogId: string | null;
    recordType: string | null; recordId: string | null; payload: Record<string, unknown>;
  },
): Promise<void> {
  const feedback = objectValue(params.payload.ai_feedback);
  if (!feedback || !params.recordId) return;
  const badge = normalizeString(feedback.badge) ?? "即时反馈";
  const semanticKey = baselineSemanticKey(params.recordType, badge);
  const exposureEventKey = `${params.eventKey}:baseline_ai_feedback`;
  const sourceTable = params.recordType === "expense"
    ? "transactions"
    : params.recordType === "income"
    ? "income_records"
    : "data_records";
  const source = {
    source_table: sourceTable,
    source_record_id: params.recordId,
    source_fingerprint: `legacy-record:${params.recordType ?? "unknown"}:${params.recordId}`,
    is_primary: true,
  };
  const row = {
    event_key: exposureEventKey, delivery_attempt_id: params.eventKey, occurred_at: params.occurredAt,
    user_id: params.userId, trace_id: params.traceId, ai_log_id: params.aiLogId, record_id: params.recordId,
    record_type: params.recordType, domain_key: params.recordType, entity_id: null,
    candidate_id: `baseline:${params.recordType ?? "unknown"}:${semanticKey}`,
    semantic_key: semanticKey, claim_type: "inference", dimension: "baseline_voice_feedback",
    surface: "shortcut_notification", lifecycle_state: "returned_to_shortcut", selection_mode: "legacy_voice",
    score: null, expression_plan_version: "legacy-voice-v1", render_contract_version: "shortcut-baseline-v1", scoring_version: null,
    visible_field_paths: ["rendered_feedback.badge", "rendered_feedback.emotion_line", "rendered_feedback.utility_line"],
    expandable_field_paths: [], persisted_only_field_paths: ["rendered_feedback.confidence"],
    rendered_payload: {
      semantic_key: semanticKey,
      feedback_present: true,
      feedback_confidence: typeof feedback.confidence === "number" ? feedback.confidence : null,
    },
    metadata: { source: "production_baseline", shadow_event_key: params.eventKey },
    simulation_only: false, counts_for_novelty: true,
  };
  const { error } = await supabase.rpc("persist_expression_exposure_with_sources", {
    p_user_id: params.userId,
    p_event_key: exposureEventKey,
    p_exposure: row,
    p_sources: [source],
  });
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
    baseline_payload: buildExpressionShadowBaselinePayload(input.payload),
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
      await processExpenseShadow(supabase, { ...plannerParams, occurredAt: input.occurredAt ?? null });
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
  if (!shouldCaptureExpressionShadow(input.improvementConsent, mode)) return;
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
