import {
  getExpressionShadowMode,
  loadPlannerPersonalization,
  persistPlannerExposureEvents,
} from "./expression-shadow.ts";
import {
  buildDataPlannerSourceRecord,
  buildExpensePlannerSourceRecord,
  buildIncomePlannerSourceRecord,
  canonicalPlannerSource,
  EXPRESSION_PLANNER_VERSION,
  plannerSourceFingerprint,
} from "./expression-shadow-planner.ts";
import type { ShadowExpenseTransaction } from "./expression-shadow-planner.ts";
import { evaluateCandidates } from "../../../tools/ai-validation/expression-planner/lib/eligibility-gates.mjs";
import { scoreCandidates } from "../../../tools/ai-validation/expression-planner/lib/deterministic-scoring.mjs";
import { buildExpressionPlans } from "../../../tools/ai-validation/expression-planner/lib/expression-plan.mjs";
import { buildRenderPlans } from "../../../tools/ai-validation/expression-planner/lib/render-contract.mjs";

const RECORD_DETAIL_RENDER_VERSION = "surface-render-contract-v0.1";

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

function deliveryEnabledFor(userId: string): boolean {
  if (getExpressionShadowMode() !== "enforced_owner_only") return false;
  const ownerIds = (Deno.env.get("EXPRESSION_PLANNER_OWNER_USER_IDS") ?? Deno.env.get("EXPRESSION_PLANNER_OWNER_USER_ID") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return ownerIds.includes(userId);
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

async function currentDeliveryPlan(
  supabase: DatabaseClient,
  userId: string,
  storedPlan: Record<string, unknown>,
) {
  const candidates = Array.isArray(storedPlan.candidates)
    ? storedPlan.candidates as Record<string, unknown>[]
    : [];
  const personalization = await loadPlannerPersonalization(supabase, userId);
  const eligible = evaluateCandidates(candidates, { planningContext: "record_event" });
  const scored = scoreCandidates(eligible, {
    context: {},
    preferenceProfile: personalization.preferenceProfile,
    exposureHistory: personalization.exposureHistory,
  });
  const expressionPlans = buildExpressionPlans(scored);
  return {
    ...storedPlan,
    candidates: scored,
    render_plans: buildRenderPlans(expressionPlans, scored),
  };
}

function frozenDeliveryPlan(
  storedPlan: Record<string, unknown>,
  deliveryPlan: Record<string, unknown>,
  item: ReturnType<typeof selectedRecordDetail>[number],
) {
  const renderPlan = object(object(deliveryPlan.render_plans).record_detail);
  return {
    status: "auto_planned",
    planner_version: storedPlan.planner_version,
    domain_key: storedPlan.domain_key,
    source_record: storedPlan.source_record,
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
  shadowRow: Record<string, unknown>,
  deliveryPlan: Record<string, unknown>,
  primary: ReturnType<typeof selectedRecordDetail>[number],
) {
  const plan = frozenDeliveryPlan(object(shadowRow.proposed_plan), deliveryPlan, primary);
  const contentFingerprint = plannerSourceFingerprint(plan);
  const snapshot = {
    user_id: userId,
    shadow_run_id: shadowRow.id,
    record_id: shadowRow.record_id,
    surface: "record_detail",
    candidate_id: primary.candidateId,
    content_fingerprint: contentFingerprint,
    delivery_plan: plan,
  };
  const { data: inserted, error } = await supabase.from("expression_delivery_snapshots")
    .upsert(snapshot, {
      onConflict: "user_id,shadow_run_id,surface,content_fingerprint",
      ignoreDuplicates: true,
    })
    .select("id,created_at,shadow_run_id,record_id,candidate_id,content_fingerprint,delivery_plan")
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (inserted) return inserted as Record<string, unknown>;
  const { data, error: lookupError } = await supabase.from("expression_delivery_snapshots")
    .select("id,created_at,shadow_run_id,record_id,candidate_id,content_fingerprint,delivery_plan")
    .eq("user_id", userId)
    .eq("shadow_run_id", shadowRow.id)
    .eq("surface", "record_detail")
    .eq("content_fingerprint", contentFingerprint)
    .maybeSingle();
  if (lookupError) throw new Error(lookupError.message);
  if (!data) throw new Error("表达下发快照写入失败");
  return data as Record<string, unknown>;
}

async function loadDeliverySnapshot(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  deliveryToken: string,
) {
  const { data, error } = await supabase.from("expression_delivery_snapshots")
    .select("id,created_at,shadow_run_id,record_id,candidate_id,content_fingerprint,delivery_plan")
    .eq("id", deliveryToken)
    .eq("user_id", userId)
    .eq("record_id", recordId)
    .eq("surface", "record_detail")
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

async function latestPlan(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  planToken = "",
) {
  let query = supabase.from("expression_shadow_runs")
    .select("id,created_at,occurred_at,user_id,record_id,record_type,rollout_mode,proposed_plan,processed_at,processing_error")
    .eq("user_id", userId)
    .eq("record_id", recordId);
  if (planToken) query = query.eq("id", planToken);
  const { data, error } = await query.order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (error) throw new Error(error.message);
  return data as Record<string, unknown> | null;
}

async function currentSourceRecord(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  domainKey: string,
) {
  if (domainKey === "expense") {
    const { data, error } = await supabase.from("transactions")
      .select("id,transaction_date,transaction_time,created_at,amount,merchant_name,category,platform,payment_method,status,type")
      .eq("user_id", userId)
      .eq("id", recordId)
      .eq("type", "expense")
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data ? buildExpensePlannerSourceRecord(data) : null;
  }
  if (domainKey === "income") {
    const { data, error } = await supabase.from("income_records")
      .select("id,income_date,created_at,amount,source_name,category")
      .eq("user_id", userId)
      .eq("id", recordId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data ? buildIncomePlannerSourceRecord(data) : null;
  }
  const { data, error } = await supabase.from("data_records")
    .select("id,occurred_at,title,summary,payload_jsonb,domain_key,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at")
    .eq("user_id", userId)
    .eq("id", recordId)
    .eq("domain_key", domainKey)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data ? buildDataPlannerSourceRecord(data) : null;
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
    ? "id,transaction_date,transaction_time,created_at,amount,merchant_name,category,platform,payment_method,status,type"
    : sourceTable === "income_records"
    ? "id,income_date,created_at,amount,source_name,category"
    : "id,occurred_at,title,summary,payload_jsonb,domain_key,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at";
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

async function planUnavailableReason(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  row: Record<string, unknown>,
  plan: Record<string, unknown>,
) {
  if (row.rollout_mode !== "enforced_owner_only") return "plan_rollout_mismatch";
  if (plan.planner_version !== EXPRESSION_PLANNER_VERSION) return "plan_version_mismatch";
  const detailRenderPlan = object(object(plan.render_plans).record_detail);
  if (detailRenderPlan.render_contract_version !== RECORD_DETAIL_RENDER_VERSION) return "render_version_mismatch";
  const sourceRecord = object(plan.source_record);
  if (!Object.keys(sourceRecord).length) return "plan_source_missing";
  const domainKey = text(plan.domain_key ?? row.record_type, 80);
  if (!domainKey) return "plan_domain_missing";
  const current = await currentSourceRecord(supabase, userId, recordId, domainKey);
  if (!current) return "record_missing";
  return canonicalPlannerSource(sourceRecord) === canonicalPlannerSource(current)
    ? ""
    : "plan_stale";
}

export async function getRecordExpressionPlan(
  supabase: DatabaseClient,
  userId: string,
  input: Record<string, unknown>,
) {
  if (!deliveryEnabledFor(userId)) return { available: false, reason: "rollout_not_enabled" };
  const recordId = text(input.record_id, 100);
  if (!recordId) throw new Error("缺少记录编号");
  const row = await latestPlan(supabase, userId, recordId);
  if (!row) return { available: false, reason: "plan_not_ready" };
  if (!row.processed_at) return { available: false, reason: "plan_not_ready" };
  if (row.processing_error) return { available: false, reason: "plan_failed" };
  const plan = object(row.proposed_plan);
  if (plan.status !== "auto_planned") return { available: false, reason: "plan_not_ready" };
  const unavailableReason = await planUnavailableReason(supabase, userId, recordId, row, plan);
  if (unavailableReason) return { available: false, reason: unavailableReason };
  const deliveryPlan = await currentDeliveryPlan(supabase, userId, plan);
  const selected = selectedRecordDetail(deliveryPlan);
  if (!selected.length) return { available: false, reason: "no_selected_candidate" };
  const primary = selected[0];
  const dependencyReason = await dependencyUnavailableReason(supabase, userId, primary.candidate);
  if (dependencyReason) return { available: false, reason: dependencyReason };
  const snapshot = await persistDeliverySnapshot(supabase, userId, row, deliveryPlan, primary);
  const frozenPlan = object(snapshot.delivery_plan);
  const frozenPrimary = selectedRecordDetail(frozenPlan)[0];
  if (!frozenPrimary || frozenPrimary.candidateId !== text(snapshot.candidate_id, 200)) {
    throw new Error("表达下发快照内容不完整");
  }
  return {
    available: true,
    plan_token: String(snapshot.id),
    record_id: recordId,
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
  if (!deliveryEnabledFor(userId)) throw new Error("当前账号未启用表达规划器灰度");
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
