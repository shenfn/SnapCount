import {
  loadPlannerPersonalization,
  persistPlannerExposureEvents,
} from "./expression-shadow.ts";
import {
  buildDataPlannerSourceRecord,
  buildExpensePlannerSourceRecord,
  buildExpressionShadowPlan,
  buildGenericExpressionShadowPlan,
  buildIncomePlannerSourceRecord,
  EXPRESSION_PLANNER_VERSION,
  plannerSourceFingerprint,
} from "./expression-shadow-planner.ts";
import type { ShadowExpenseTransaction } from "./expression-shadow-planner.ts";

const RECORD_DETAIL_RENDER_VERSION = "surface-render-contract-v0.1";
const RECORD_DETAIL_DECISION_VERSION = "record-detail-decision-v0.1";
const RECORD_DETAIL_POLICY_NAME = "deterministic_rule";
const RECORD_DETAIL_POLICY_VERSION = "deterministic-record-detail-v0.1";
const RECORD_DETAIL_DECISION_MAX_BYTES = 64 * 1024;
type RecordKind = "expense" | "income" | "data";

interface DatabaseClient {
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
  // deno-lint-ignore no-explicit-any
  rpc: (name: string, params: Record<string, unknown>) => any;
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function text(value: unknown, max = 500): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function recordKind(value: unknown): RecordKind | null {
  const normalized = text(value, 40).toLowerCase();
  if (["expense", "transaction", "tx"].includes(normalized)) return "expense";
  if (normalized === "income") return "income";
  if (["data", "universal"].includes(normalized)) return "data";
  return null;
}

function environmentText(name: string): string {
  try {
    return text(Deno.env.get(name), 200);
  } catch {
    return "";
  }
}

export function isRecordExpressionOwnerEnabled(userId: string): boolean {
  const enabled = ["1", "true", "yes", "on"].includes(
    environmentText("EXPRESSION_PLANNER_OWNER_ENABLED").toLowerCase(),
  );
  const ownerUserId = environmentText("EXPRESSION_PLANNER_OWNER_USER_ID");
  return enabled && Boolean(ownerUserId) && ownerUserId === userId;
}

function dimensionLabel(dimension: string): string {
  const labels: Record<string, string> = {
    current_fact: "本次记录",
    record_context: "记录情境",
    repeat_interval: "记录间隔",
    daily_aggregation: "当天情况",
    amount_structure: "金额结构",
    personal_baseline: "个人基线",
    meal_baseline: "同餐次基线",
    period_comparison: "本周变化",
    category_period_comparison: "分类变化",
    temporal_rhythm: "时间节奏",
  };
  return labels[dimension] ?? "记录洞察";
}

function selectedRecordDetail(plan: Record<string, unknown>) {
  const renderPlan = object(object(plan.render_plans).record_detail);
  const selected = Array.isArray(renderPlan.selected)
    ? renderPlan.selected
    : [];
  const candidates = Array.isArray(plan.candidates) ? plan.candidates : [];
  const byId = new Map(candidates.map((candidate: Record<string, unknown>) => [String(candidate.candidate_id ?? ""), candidate]));
  return selected.flatMap((selection: Record<string, unknown>) => {
    const candidateId = text(selection.candidate_id, 200);
    const candidate = byId.get(candidateId);
    if (!candidate) return [];
    const claim = object(candidate.claim);
    const canonicalText = text(selection.canonical_text ?? claim.canonical_text, 2000);
    if (!canonicalText) return [];
    return [{ selection, candidate, candidateId, canonicalText }];
  });
}

function recordDetailActionId(candidate: Record<string, unknown>): string {
  const claim = object(candidate.claim);
  return plannerSourceFingerprint({
    action_schema_version: "record-detail-action-v0.1",
    domain_key: text(candidate.domain_key, 80),
    semantic_key: text(claim.semantic_key, 200),
    dimension: text(candidate.dimension, 100),
    claim_type: text(candidate.claim_type, 80),
  });
}

function recordDetailDecision(
  deliveryPlan: Record<string, unknown>,
  primary: ReturnType<typeof selectedRecordDetail>[number],
) {
  const renderPlan = object(object(deliveryPlan.render_plans).record_detail);
  const selected = Array.isArray(renderPlan.selected) ? renderPlan.selected : [];
  const selectedById = new Map(selected.map((item: Record<string, unknown>, index: number) => [
    text(item.candidate_id, 200),
    { item, index },
  ]));
  const candidates = Array.isArray(deliveryPlan.candidates) ? deliveryPlan.candidates : [];
  const actions = candidates.flatMap((candidate: Record<string, unknown>, sourceIndex: number) => {
    const candidateId = text(candidate.candidate_id, 200);
    if (!candidateId) return [];
    const claim = object(candidate.claim);
    const scoring = object(candidate.scoring);
    const surfaceScore = object(object(scoring.surfaces).record_detail);
    const isChosen = candidateId === primary.candidateId;
    const hints = object(candidate.selection_hints);
    const tieBreak = Number(object(hints.tie_break_priority).record_detail ?? 0);
    const deterministicScore = Number(surfaceScore.score);
    const selectedEntry = selectedById.get(candidateId);
    const maxExposureCount = Number(object(hints.max_exposure_count).record_detail);
    const dedupeExposure = object(object(scoring.dedupe_exposure_by_surface).record_detail);
    const exposure = object(object(scoring.exposure_by_surface).record_detail);
    const currentExposureCount = Number(dedupeExposure.count ?? exposure.count ?? 0);
    const cooldownReached = Number.isFinite(maxExposureCount)
      && Number.isFinite(currentExposureCount)
      && currentExposureCount >= maxExposureCount;
    const policyEligible = surfaceScore.eligible === true
      && surfaceScore.passes_threshold === true
      && !cooldownReached;
    if (!policyEligible) {
      if (isChosen) throw new Error("记录详情主候选未通过策略准入");
      return [];
    }
    const deterministicReason = !isChosen && !selectedEntry ? "composition_not_selected" : "";
    const exposureKey = text(hints.exposure_key, 300) || text(claim.semantic_key, 200) || candidateId;
    const dedupeKey = text(hints.dedupe_key, 300) || exposureKey;
    const actionId = recordDetailActionId(candidate);
    const candidateFingerprint = plannerSourceFingerprint({ candidate_id: candidateId });
    return [{
      action_id: actionId,
      candidate_fingerprint: candidateFingerprint,
      semantic_key: text(claim.semantic_key, 200),
      dimension: text(candidate.dimension, 100),
      claim_type: text(candidate.claim_type, 80),
      deterministic_score: Number.isFinite(deterministicScore) ? deterministicScore : null,
      passes_threshold: surfaceScore.passes_threshold === true,
      deterministic_status: isChosen
        ? "chosen"
        : selectedEntry ? "selected_secondary" : "eligible_not_selected",
      deterministic_reason: deterministicReason,
      exposure_key_fingerprint: plannerSourceFingerprint({ exposure_key: exposureKey }),
      dedupe_key_fingerprint: plannerSourceFingerprint({ dedupe_key: dedupeKey }),
      selection_probability: isChosen ? 1 : 0,
      tie_break_priority: Number.isFinite(tieBreak) ? tieBreak : 0,
      source_index: sourceIndex,
    }];
  }).sort((left, right) => {
    const scoreDelta = Number(right.deterministic_score ?? -1) - Number(left.deterministic_score ?? -1);
    return scoreDelta || right.tie_break_priority - left.tie_break_priority || left.source_index - right.source_index;
  }).map((action, index) => {
    const { source_index: _sourceIndex, tie_break_priority: _tieBreak, ...persisted } = action;
    return { ...persisted, rank_before_policy: index + 1 };
  });
  const chosenScoring = object(primary.candidate.scoring);
  const decision = {
    decision_version: RECORD_DETAIL_DECISION_VERSION,
    decision_id: crypto.randomUUID(),
    decided_at: new Date().toISOString(),
    surface: "record_detail",
    policy_name: RECORD_DETAIL_POLICY_NAME,
    policy_version: RECORD_DETAIL_POLICY_VERSION,
    planner_version: text(deliveryPlan.planner_version, 100),
    scoring_version: text(chosenScoring.scoring_version, 100),
    candidate_schema_version: "candidate-v0.1",
    chosen_action_id: recordDetailActionId(primary.candidate),
    selection_probability: 1,
    selection_mode: text(primary.selection.selection_mode, 100) || "threshold",
    action_count: actions.length,
    action_set: actions,
  };
  const serializedBytes = new TextEncoder().encode(JSON.stringify(decision)).byteLength;
  if (serializedBytes > RECORD_DETAIL_DECISION_MAX_BYTES) {
    throw new Error("记录详情决策元数据超过 64 KiB 上限");
  }
  return decision;
}

function frozenDeliveryPlan(
  deliveryPlan: Record<string, unknown>,
  item: ReturnType<typeof selectedRecordDetail>[number],
) {
  const renderPlan = object(object(deliveryPlan.render_plans).record_detail);
  return {
    status: "auto_planned",
    planner_version: deliveryPlan.planner_version,
    domain_key: deliveryPlan.domain_key,
    decision: recordDetailDecision(deliveryPlan, item),
    source_dependencies: item.candidate.source_dependencies,
    candidates: [{
      candidate_id: item.candidate.candidate_id,
      domain_key: item.candidate.domain_key,
      dimension: item.candidate.dimension,
      claim_type: item.candidate.claim_type,
      claim: {
        semantic_key: object(item.candidate.claim).semantic_key,
        canonical_text: item.canonicalText,
      },
      quality: item.candidate.quality,
      scoring: item.candidate.scoring,
      selection_hints: item.candidate.selection_hints,
      source_dependencies: item.candidate.source_dependencies,
    }],
    render_plans: {
      record_detail: {
        expression_plan_version: renderPlan.expression_plan_version,
        render_contract_version: renderPlan.render_contract_version,
        selected: [item.selection],
      },
    },
  };
}

async function persistDeliverySnapshot(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  kind: RecordKind,
  deliveryPlan: Record<string, unknown>,
  primary: ReturnType<typeof selectedRecordDetail>[number],
) {
  const plan = frozenDeliveryPlan(deliveryPlan, primary);
  const contentFingerprint = plannerSourceFingerprint(plan);
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  const snapshot = {
    user_id: userId,
    shadow_run_id: null,
    record_id: recordId,
    record_kind: kind,
    domain_key: text(deliveryPlan.domain_key, 80),
    surface: "record_detail",
    candidate_id: primary.candidateId,
    content_fingerprint: contentFingerprint,
    delivery_plan: plan,
    expires_at: expiresAt,
  };
  const { data, error } = await supabase.from("expression_delivery_snapshots")
    .insert(snapshot)
    .select("id,created_at,expires_at,shadow_run_id,record_id,record_kind,domain_key,candidate_id,content_fingerprint,delivery_plan")
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("表达下发快照写入失败");
  return data as Record<string, unknown>;
}

async function loadDeliverySnapshot(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  deliveryToken: string,
) {
  const now = new Date().toISOString();
  const { data, error } = await supabase.from("expression_delivery_snapshots")
    .select("id,created_at,expires_at,shadow_run_id,record_id,record_kind,domain_key,candidate_id,content_fingerprint,delivery_plan")
    .eq("id", deliveryToken)
    .eq("user_id", userId)
    .eq("record_id", recordId)
    .eq("surface", "record_detail")
    .gt("expires_at", now)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data as Record<string, unknown> | null;
}

function feedbackPayload(item: ReturnType<typeof selectedRecordDetail>[number], exposureEventId = "") {
  const claim = object(item.candidate.claim);
  const quality = object(item.candidate.quality);
  const sampleCount = Number(quality.sample_count ?? 0);
  return {
    version: "expression-planner-record-detail-v0.1",
    source: "expression_planner",
    icon: "sparkles",
    badge: dimensionLabel(text(item.candidate.dimension, 100)),
    band: "neutral",
    emotion_line: item.canonicalText,
    utility_line: "",
    detail_reason: Number.isFinite(sampleCount) && sampleCount > 1
      ? `基于 ${sampleCount} 条可用记录计算`
      : "",
    candidate_id: item.candidateId,
    semantic_key: text(claim.semantic_key, 200),
    dimension: text(item.candidate.dimension, 100),
    ...(exposureEventId ? { exposure_event_id: exposureEventId } : {}),
  };
}

function includeCurrentRecord(
  rows: Record<string, unknown>[],
  current: Record<string, unknown>,
) {
  const byId = new Map(rows.map((row) => [text(row.id, 100), row]));
  byId.set(text(current.id, 100), current);
  return [...byId.values()];
}

async function buildCurrentRecordPlan(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  kind: RecordKind,
) {
  if (kind === "expense") {
    const { data: current, error } = await supabase.from("transactions")
      .select("id,transaction_date,transaction_time,created_at,amount,merchant_name,category,platform,payment_method,status,type,staging_record_id,image_hash")
      .eq("user_id", userId)
      .eq("id", recordId)
      .eq("type", "expense")
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!current) return null;
    const { data: history, error: historyError } = await supabase.from("transactions")
      .select("id,transaction_date,transaction_time,created_at,amount,merchant_name,category,platform,payment_method,status,type,staging_record_id,image_hash")
      .eq("user_id", userId)
      .eq("type", "expense")
      .lte("transaction_date", current.transaction_date)
      .order("transaction_date", { ascending: false })
      .order("transaction_time", { ascending: false })
      .limit(500);
    if (historyError) throw new Error(historyError.message);
    const personalization = await loadPlannerPersonalization(supabase, userId);
    const transactions = includeCurrentRecord(history ?? [], current) as unknown as ShadowExpenseTransaction[];
    const sourceRecord = buildExpensePlannerSourceRecord(current as ShadowExpenseTransaction);
    return {
      kind,
      domainKey: "expense",
      plan: buildExpressionShadowPlan({
        transactions,
        currentRecordId: recordId,
        occurredAt: text(sourceRecord.occurred_at, 100),
        ...personalization,
      }) as Record<string, unknown>,
    };
  }
  if (kind === "income") {
    const { data: current, error } = await supabase.from("income_records")
      .select("id,income_date,created_at,amount,source_name,category")
      .eq("user_id", userId)
      .eq("id", recordId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!current) return null;
    const { data: history, error: historyError } = await supabase.from("income_records")
      .select("id,income_date,created_at,amount,source_name,category")
      .eq("user_id", userId)
      .lte("income_date", current.income_date)
      .order("income_date", { ascending: false })
      .limit(500);
    if (historyError) throw new Error(historyError.message);
    const personalization = await loadPlannerPersonalization(supabase, userId);
    const records = includeCurrentRecord(history ?? [], current).map(buildIncomePlannerSourceRecord);
    return {
      kind,
      domainKey: "income",
      plan: buildGenericExpressionShadowPlan({
        domainKey: "income",
        records,
        currentRecordId: recordId,
        ...personalization,
      }) as Record<string, unknown>,
    };
  }
  const { data: current, error } = await supabase.from("data_records")
    .select("id,created_at,occurred_at,title,summary,payload_jsonb,domain_key,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at")
    .eq("user_id", userId)
    .eq("id", recordId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!current) return null;
  const domainKey = text(current.domain_key, 80);
  if (!domainKey) return null;
  let historyQuery = supabase.from("data_records")
    .select("id,created_at,occurred_at,title,summary,payload_jsonb,domain_key,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at")
    .eq("user_id", userId)
    .eq("domain_key", domainKey);
  if (current.occurred_at) historyQuery = historyQuery.lte("occurred_at", current.occurred_at);
  const { data: history, error: historyError } = await historyQuery
    .order("occurred_at", { ascending: false })
    .limit(500);
  if (historyError) throw new Error(historyError.message);
  const personalization = await loadPlannerPersonalization(supabase, userId);
  const records = includeCurrentRecord(history ?? [], current).map(buildDataPlannerSourceRecord);
  return {
    kind,
    domainKey,
    plan: buildGenericExpressionShadowPlan({
      domainKey,
      records,
      currentRecordId: recordId,
      ...personalization,
    }) as Record<string, unknown>,
  };
}

type SourceDependency = {
  source_table: "transactions" | "income_records" | "data_records";
  source_record_id: string;
  source_fingerprint: string;
  is_primary: boolean;
};

function candidateSourceDependencies(candidate: Record<string, unknown>): SourceDependency[] {
  const allowedTables = new Set(["transactions", "income_records", "data_records"]);
  const dependencies = Array.isArray(candidate.source_dependencies)
    ? candidate.source_dependencies
    : [];
  return dependencies.flatMap((rawDependency) => {
    const dependency = object(rawDependency);
    const sourceTable = text(dependency.source_table, 80);
    const sourceRecordId = text(dependency.source_record_id, 100);
    const sourceFingerprint = text(dependency.source_fingerprint, 100);
    if (!allowedTables.has(sourceTable) || !sourceRecordId || !sourceFingerprint) return [];
    return [{
      source_table: sourceTable as SourceDependency["source_table"],
      source_record_id: sourceRecordId,
      source_fingerprint: sourceFingerprint,
      is_primary: dependency.is_primary === true,
    }];
  });
}

async function currentDependencyRecords(
  supabase: DatabaseClient,
  userId: string,
  sourceTable: SourceDependency["source_table"],
  recordIds: string[],
) {
  if (!recordIds.length) return [];
  const fields = sourceTable === "transactions"
    ? "id,transaction_date,transaction_time,created_at,amount,merchant_name,category,platform,payment_method,status,type,staging_record_id,image_hash"
    : sourceTable === "income_records"
    ? "id,income_date,created_at,amount,source_name,category"
    : "id,created_at,occurred_at,title,summary,payload_jsonb,domain_key,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at";
  const rows: Record<string, unknown>[] = [];
  for (let offset = 0; offset < recordIds.length; offset += 100) {
    let query = supabase.from(sourceTable)
      .select(fields)
      .eq("user_id", userId)
      .in("id", recordIds.slice(offset, offset + 100));
    if (sourceTable === "transactions") query = query.eq("type", "expense");
    const { data, error } = await query;
    if (error) throw new Error(error.message);
    if (Array.isArray(data)) rows.push(...data);
  }
  return rows.map((row) => sourceTable === "transactions"
    ? buildExpensePlannerSourceRecord(row as unknown as ShadowExpenseTransaction)
    : sourceTable === "income_records"
    ? buildIncomePlannerSourceRecord(row)
    : buildDataPlannerSourceRecord(row));
}

async function dependencyUnavailableReason(
  supabase: DatabaseClient,
  userId: string,
  candidate: Record<string, unknown>,
) {
  const dependencies = candidateSourceDependencies(candidate);
  if (!dependencies.length || !dependencies.some((dependency) => dependency.is_primary)) {
    return "plan_dependencies_missing";
  }
  for (const sourceTable of ["transactions", "income_records", "data_records"] as const) {
    const expected = dependencies.filter((dependency) => dependency.source_table === sourceTable);
    if (!expected.length) continue;
    const current = await currentDependencyRecords(
      supabase,
      userId,
      sourceTable,
      expected.map((dependency) => dependency.source_record_id),
    );
    const currentById = new Map(current.map((record) => [String(record.id ?? ""), record]));
    for (const dependency of expected) {
      const record = currentById.get(dependency.source_record_id);
      if (!record) return "plan_dependency_missing";
      if (plannerSourceFingerprint(record) !== dependency.source_fingerprint) return "plan_dependency_stale";
    }
  }
  return "";
}

function selectedShortcutNotification(plan: Record<string, unknown>) {
  const renderPlan = object(object(plan.render_plans).shortcut_notification);
  const selected = Array.isArray(renderPlan.selected) ? renderPlan.selected : [];
  const candidates = Array.isArray(plan.candidates) ? plan.candidates : [];
  const byId = new Map(candidates.map((candidate: Record<string, unknown>) => [
    text(candidate.candidate_id, 200),
    candidate,
  ]));
  return selected.flatMap((selection: Record<string, unknown>) => {
    const candidateId = text(selection.candidate_id, 200);
    const candidate = byId.get(candidateId);
    if (!candidate) return [];
    const claim = object(candidate.claim);
    const canonicalText = text(selection.canonical_text ?? claim.canonical_text, 500);
    if (!candidateId || !canonicalText) return [];
    return [{ selection, candidate, candidateId, canonicalText }];
  });
}

export async function deliverShortcutExpressionPlan(
  supabase: DatabaseClient,
  userId: string,
  input: {
    record_id: string;
    record_kind: string;
    occurred_at: string;
    delivery_attempt_id: string;
  },
) {
  if (!isRecordExpressionOwnerEnabled(userId)) {
    return { available: false, reason: "owner_only_unavailable" };
  }
  const recordId = text(input.record_id, 100);
  const kind = recordKind(input.record_kind);
  const deliveryAttemptId = text(input.delivery_attempt_id, 200);
  if (!recordId || !kind || !deliveryAttemptId) {
    return { available: false, reason: "invalid_delivery_input" };
  }
  const context = await buildCurrentRecordPlan(supabase, userId, recordId, kind);
  if (!context) return { available: false, reason: "record_missing" };
  const plan = context.plan;
  if (plan.status !== "auto_planned" || plan.planner_version !== EXPRESSION_PLANNER_VERSION) {
    return { available: false, reason: text(plan.reason, 100) || "no_selected_candidate" };
  }
  const primary = selectedShortcutNotification(plan)[0];
  if (!primary) return { available: false, reason: "no_selected_candidate" };
  const dependencyReason = await dependencyUnavailableReason(supabase, userId, primary.candidate);
  if (dependencyReason) return { available: false, reason: dependencyReason };
  const exposures = await persistPlannerExposureEvents(supabase, {
    userId,
    recordId,
    recordType: context.domainKey,
    occurredAt: text(input.occurred_at, 100) || new Date().toISOString(),
    surface: "shortcut_notification",
    deliveryAttemptId,
    plan,
    candidateIds: [primary.candidateId],
    deliveryEvidenceByCandidateId: {
      [primary.candidateId]: {
        rendered_payload: { message: primary.canonicalText },
        visible_field_paths: ["message"],
        expandable_field_paths: [],
        persisted_only_field_paths: [],
      },
    },
    lifecycleState: "returned_to_shortcut",
    simulationOnly: false,
  });
  const exposure = exposures.find((item) => text(item.candidate_id, 200) === primary.candidateId);
  return {
    available: true,
    message: primary.canonicalText,
    candidate_id: primary.candidateId,
    semantic_key: text(object(primary.candidate.claim).semantic_key, 200),
    exposure_event_id: text(exposure?.id, 100),
  };
}

export async function getRecordExpressionPlan(
  supabase: DatabaseClient,
  userId: string,
  input: Record<string, unknown>,
) {
  if (!isRecordExpressionOwnerEnabled(userId)) {
    return { available: false, reason: "owner_only_unavailable" };
  }
  const recordId = text(input.record_id, 100);
  const kind = recordKind(input.record_kind);
  if (!recordId || !kind) throw new Error("缺少有效的记录编号或类型");
  const context = await buildCurrentRecordPlan(supabase, userId, recordId, kind);
  if (!context) return { available: false, reason: "record_missing" };
  const deliveryPlan = context.plan;
  if (deliveryPlan.status !== "auto_planned") {
    return { available: false, reason: text(deliveryPlan.reason, 100) || "no_selected_candidate" };
  }
  if (deliveryPlan.planner_version !== EXPRESSION_PLANNER_VERSION) {
    return { available: false, reason: "plan_version_mismatch" };
  }
  if (object(object(deliveryPlan.render_plans).record_detail).render_contract_version !== RECORD_DETAIL_RENDER_VERSION) {
    return { available: false, reason: "render_version_mismatch" };
  }
  const selected = selectedRecordDetail(deliveryPlan);
  if (!selected.length) return { available: false, reason: "no_selected_candidate" };
  const primary = selected[0];
  const dependencyReason = await dependencyUnavailableReason(supabase, userId, primary.candidate);
  if (dependencyReason) return { available: false, reason: dependencyReason };
  const snapshot = await persistDeliverySnapshot(
    supabase,
    userId,
    recordId,
    context.kind,
    deliveryPlan,
    primary,
  );
  const frozenPlan = object(snapshot.delivery_plan);
  const frozenPrimary = selectedRecordDetail(frozenPlan)[0];
  if (!frozenPrimary || frozenPrimary.candidateId !== text(snapshot.candidate_id, 200)) {
    throw new Error("表达下发快照内容不完整");
  }
  return {
    available: true,
    plan_token: String(snapshot.id),
    record_id: recordId,
    record_kind: context.kind,
    domain_key: context.domainKey,
    surface: "record_detail",
    candidate_id: frozenPrimary.candidateId,
    feedback: feedbackPayload(frozenPrimary),
  };
}

export async function acknowledgeRecordExpressionPlan(
  supabase: DatabaseClient,
  userId: string,
  input: Record<string, unknown>,
) {
  if (!isRecordExpressionOwnerEnabled(userId)) {
    throw new Error("表达规划器当前未启用");
  }
  const recordId = text(input.record_id, 100);
  const planToken = text(input.plan_token, 100);
  const candidateId = text(input.candidate_id, 200);
  if (!recordId || !planToken || !candidateId) throw new Error("缺少表达曝光信息");
  const snapshot = await loadDeliverySnapshot(supabase, userId, recordId, planToken);
  if (!snapshot) throw new Error("表达下发快照不存在或已失效");
  if (text(snapshot.candidate_id, 200) !== candidateId) {
    throw new Error("候选不是本次下发的记录详情内容");
  }
  const deliveryPlan = object(snapshot.delivery_plan);
  if (
    deliveryPlan.status !== "auto_planned"
    || deliveryPlan.planner_version !== EXPRESSION_PLANNER_VERSION
    || object(object(deliveryPlan.render_plans).record_detail).render_contract_version !== RECORD_DETAIL_RENDER_VERSION
    || text(snapshot.content_fingerprint, 100) !== plannerSourceFingerprint(deliveryPlan)
  ) {
    throw new Error("表达下发快照内容已失效");
  }
  const primary = selectedRecordDetail(deliveryPlan)[0];
  if (!primary || primary.candidateId !== candidateId) {
    throw new Error("候选不是本次下发的记录详情内容");
  }
  const dependencyReason = await dependencyUnavailableReason(supabase, userId, primary.candidate);
  if (dependencyReason) throw new Error(`表达计划已失效：${dependencyReason}`);
  const deliveredFeedback = feedbackPayload(primary);
  const visibleFieldPaths = ["badge", "emotion_line", "utility_line", "detail_reason"]
    .filter((key) => text(deliveredFeedback[key as keyof typeof deliveredFeedback], 2000))
    .map((key) => `feedback.${key}`);
  const exposures = await persistPlannerExposureEvents(supabase, {
    userId,
    recordId,
    recordType: text(deliveryPlan.domain_key, 80) || null,
    occurredAt: new Date().toISOString(),
    surface: "record_detail",
    deliveryAttemptId: planToken,
    plan: deliveryPlan,
    candidateIds: [candidateId],
    deliveryEvidenceByCandidateId: {
      [candidateId]: {
        rendered_payload: deliveredFeedback,
        visible_field_paths: visibleFieldPaths,
        expandable_field_paths: [],
        persisted_only_field_paths: [],
      },
    },
    lifecycleState: "client_rendered",
    simulationOnly: false,
  });
  const exposure = exposures.find((item) => item.candidate_id === candidateId);
  const exposureEventId = text(exposure?.id, 100);
  if (!exposureEventId) throw new Error("表达曝光写入失败");
  return {
    exposure_event_id: exposureEventId,
    candidate_id: candidateId,
    feedback: feedbackPayload(primary, exposureEventId),
  };
}
