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
  plannerClaimFingerprint,
} from "./expression-shadow-planner.ts";
import type { ShadowExpenseTransaction } from "./expression-shadow-planner.ts";
import { resolveExpressedSemanticKey } from "./context-packet.ts";
import type { ContextPacketCandidate } from "./context-packet.ts";

const RECORD_DETAIL_RENDER_VERSION = "surface-render-contract-v0.1";
const RECORD_DETAIL_DECISION_VERSION = "record-detail-decision-v0.1";
const RECORD_DETAIL_POLICY_NAME = "deterministic_rule";
const RECORD_DETAIL_POLICY_VERSION = "deterministic-record-detail-v0.1";
const RECORD_DETAIL_DECISION_MAX_BYTES = 64 * 1024;
type RecordKind = "expense" | "income" | "data";
export type ExpressionPresentationTarget = "feedback_card" | "companion_message";

interface ExpressionPresentation {
  target: ExpressionPresentationTarget;
  renderedPayload: Record<string, unknown>;
  visibleFieldPaths: string[];
  renderedTextFingerprint: string;
}

export interface PlannerVoiceBrief {
  candidate_id: string;
  semantic_key: string;
  dimension: string;
  canonical_text: string;
  source_surface: "record_detail";
  planner_version: string;
  numbers: number[];
  count_numbers: number[];
  number_facts: Array<{
    value: number;
    meaning: string | null;
    role: "count" | "measure";
  }>;
  claim_fingerprint: string;
}

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

export function expressionRenderedTextFingerprint(value: unknown): string {
  return plannerSourceFingerprint({
    fingerprint_schema_version: "expression-rendered-text-v0.1",
    rendered_text: text(value, 4000),
  });
}

function finiteNumber(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function plannerNumberFacts(candidate: Record<string, unknown>): PlannerVoiceBrief["number_facts"] {
  const numbers = Array.isArray(candidate.numbers) ? candidate.numbers : [];
  return numbers.flatMap((rawNumber) => {
    const descriptor = object(rawNumber);
    const value = finiteNumber(Object.keys(descriptor).length > 0 ? descriptor.value : rawNumber);
    if (value === null) return [];
    const meaning = text(descriptor.meaning, 120) || null;
    const explicitRole = text(descriptor.role, 40);
    const role: "count" | "measure" = explicitRole === "count"
      || /(?:count|occurrence|session|streak|consecutive)/i.test(meaning ?? "")
      ? "count"
      : "measure";
    return [{ value, meaning, role }];
  });
}

export function plannerVoiceBriefFromPlan(plan: Record<string, unknown>): PlannerVoiceBrief | null {
  if (plan.status !== "auto_planned") return null;
  const renderPlan = object(object(plan.render_plans).record_detail);
  const selected = Array.isArray(renderPlan.selected) ? renderPlan.selected : [];
  const selection = selected.find((item) => text(object(item).selection_mode, 80) === "threshold");
  if (!selection) return null;
  const selectedItem = object(selection);
  const candidateId = text(selectedItem.candidate_id, 200);
  const candidates = Array.isArray(plan.candidates) ? plan.candidates : [];
  const candidate = candidates.map(object).find((item) => text(item.candidate_id, 200) === candidateId);
  if (!candidate) return null;
  const claim = object(candidate.claim);
  const semanticKey = text(claim.semantic_key, 200);
  const canonicalText = text(selectedItem.canonical_text ?? claim.canonical_text, 1000);
  if (!candidateId || !semanticKey || !canonicalText) return null;
  const numberFacts = plannerNumberFacts(candidate);
  return {
    candidate_id: candidateId,
    semantic_key: semanticKey,
    dimension: text(candidate.dimension, 100),
    canonical_text: canonicalText,
    source_surface: "record_detail",
    planner_version: text(plan.planner_version, 100) || EXPRESSION_PLANNER_VERSION,
    numbers: numberFacts.map((item) => item.value),
    count_numbers: numberFacts.filter((item) => item.role === "count").map((item) => item.value),
    number_facts: numberFacts,
    claim_fingerprint: plannerClaimFingerprint(semanticKey, canonicalText),
  };
}

const HISTORY_PAGE_SIZE = 500;

async function loadHistoryPages(
  buildQuery: (from: number, to: number) => any,
): Promise<Record<string, unknown>[]> {
  const rows: Record<string, unknown>[] = [];
  for (let offset = 0; ; offset += HISTORY_PAGE_SIZE) {
    const query = buildQuery(offset, offset + HISTORY_PAGE_SIZE - 1);
    const { data, error } = await query;
    if (error) throw new Error(error.message);
    const page = Array.isArray(data) ? data as Record<string, unknown>[] : [];
    rows.push(...page);
    if (page.length < HISTORY_PAGE_SIZE) break;
  }
  return rows;
}

async function loadDomainProfile(
  supabase: DatabaseClient,
  userId: string,
  domainKey: string,
): Promise<Record<string, unknown>> {
  const { data, error } = await supabase.from("user_domain_profiles")
    .select("profile")
    .eq("user_id", userId)
    .eq("domain_key", domainKey)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return object(data?.profile);
}

function claimFingerprintFromCandidate(candidate: Record<string, unknown>): string {
  const claim = object(candidate.claim);
  return plannerClaimFingerprint(
    text(claim.semantic_key, 200),
    text(claim.canonical_text, 1000),
  );
}

function planCandidateClaimFingerprints(plan: Record<string, unknown>): Map<string, string> {
  const result = new Map<string, string>();
  for (const raw of Array.isArray(plan.candidates) ? plan.candidates : []) {
    const candidate = object(raw);
    const semanticKey = text(object(candidate.claim).semantic_key, 200);
    if (semanticKey) result.set(semanticKey, claimFingerprintFromCandidate(candidate));
  }
  return result;
}

function plannerContextCandidate(candidate: Record<string, unknown>): ContextPacketCandidate | null {
  const claim = object(candidate.claim);
  const candidateId = text(candidate.candidate_id, 200);
  const semanticKey = text(claim.semantic_key, 200);
  const canonicalText = text(claim.canonical_text, 2000);
  if (!candidateId || !semanticKey || !canonicalText) return null;
  const numberFacts = plannerNumberFacts(candidate);
  return {
    candidate_id: candidateId,
    semantic_key: semanticKey,
    kind: semanticKey,
    dimension: text(candidate.dimension, 100) || null,
    fact: canonicalText,
    numbers: numberFacts.map((item) => item.value),
    count_numbers: numberFacts.filter((item) => item.role === "count").map((item) => item.value),
    number_facts: numberFacts,
    source: "expression_planner",
    source_surface: "record_detail",
    planner_version: EXPRESSION_PLANNER_VERSION,
    claim_fingerprint: claimFingerprintFromCandidate(candidate),
  };
}

interface ValidatedCompanionCoverage {
  semanticKey: string;
  claimFingerprint: string;
  renderedTextFingerprint: string;
  companionMessage: string;
}

function validatedCompanionCoverage(
  value: unknown,
  currentPlan: Record<string, unknown>,
  companionMessageValue: unknown,
  recordFacts: Record<string, unknown>,
): ValidatedCompanionCoverage | null {
  const feedback = object(value);
  const coverage = object(feedback.expression_coverage);
  const semanticKey = text(coverage.expressed_semantic_key, 200);
  const claimFingerprint = text(coverage.claim_fingerprint, 200);
  const companionMessage = text(companionMessageValue, 4000);
  const renderedTextFingerprint = text(coverage.rendered_text_fingerprint, 200);
  if (
    text(coverage.coverage_version, 100) !== "expression-coverage-v1"
    || text(coverage.planner_version, 100) !== EXPRESSION_PLANNER_VERSION
    || text(coverage.source_surface, 100) !== "record_detail"
    || text(coverage.presentation_target, 100) !== "companion_message"
    || !text(coverage.packet_fingerprint, 200)
    || !semanticKey
    || !claimFingerprint
    || !companionMessage
    || !renderedTextFingerprint
    || renderedTextFingerprint !== expressionRenderedTextFingerprint(companionMessage)
  ) {
    return null;
  }

  const primary = selectedRecordDetail(currentPlan)[0];
  if (!primary) return null;
  const primarySemanticKey = text(object(primary.candidate.claim).semantic_key, 200);
  if (
    primarySemanticKey !== semanticKey
    || claimFingerprintFromCandidate(primary.candidate) !== claimFingerprint
  ) {
    return null;
  }
  const contextCandidate = plannerContextCandidate(primary.candidate);
  if (!contextCandidate) return null;
  const resolved = resolveExpressedSemanticKey({
    declaredSemanticKey: semanticKey,
    companionMessage,
    selectedCandidates: [contextCandidate],
    recordFacts,
  });
  return resolved === semanticKey
    ? { semanticKey, claimFingerprint, renderedTextFingerprint, companionMessage }
    : null;
}

function recordKind(value: unknown): RecordKind | null {
  const normalized = text(value, 40).toLowerCase();
  if (["expense", "transaction", "tx"].includes(normalized)) return "expense";
  if (normalized === "income") return "income";
  if (["data", "universal"].includes(normalized)) return "data";
  return null;
}

export function expressedSemanticKeysFromFeedback(
  value: unknown,
  currentPlan?: Record<string, unknown>,
  companionMessage?: unknown,
  recordFacts: Record<string, unknown> = {},
): string[] {
  const feedback = object(value);
  const coverage = object(feedback.expression_coverage);
  const claimFingerprint = text(coverage.claim_fingerprint, 200);
  if (
    text(coverage.coverage_version, 100) !== "expression-coverage-v1"
    || text(coverage.planner_version, 100) !== EXPRESSION_PLANNER_VERSION
    || text(coverage.source_surface, 100) !== "record_detail"
    || text(coverage.presentation_target, 100) !== "companion_message"
    || !text(coverage.packet_fingerprint, 200)
    || !claimFingerprint
    || !text(coverage.rendered_text_fingerprint, 200)
  ) {
    return [];
  }
  const keys = new Set<string>();
  const single = text(coverage.expressed_semantic_key, 200);
  if (single) keys.add(single);
  const multiple = Array.isArray(coverage.expressed_semantic_keys)
    ? coverage.expressed_semantic_keys
    : [];
  for (const rawKey of multiple) {
    const key = text(rawKey, 200);
    if (key) keys.add(key);
  }
  if (!currentPlan) return [...keys];
  if (companionMessage !== undefined) {
    const validated = validatedCompanionCoverage(value, currentPlan, companionMessage, recordFacts);
    return validated ? [validated.semanticKey] : [];
  }
  const currentFingerprints = planCandidateClaimFingerprints(currentPlan);
  return [...keys].filter((key) => currentFingerprints.get(key) === claimFingerprint);
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
    first_occurrence: "首次记录",
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
  presentation: ExpressionPresentation,
) {
  const renderPlan = object(object(deliveryPlan.render_plans).record_detail);
  return {
    status: "auto_planned",
    planner_version: deliveryPlan.planner_version,
    domain_key: deliveryPlan.domain_key,
    decision: recordDetailDecision(deliveryPlan, item),
    source_dependencies: item.candidate.source_dependencies,
    presentation: {
      target: presentation.target,
      rendered_payload: presentation.renderedPayload,
      visible_field_paths: presentation.visibleFieldPaths,
      rendered_text_fingerprint: presentation.renderedTextFingerprint,
    },
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
  presentation: ExpressionPresentation,
) {
  const plan = frozenDeliveryPlan(deliveryPlan, primary, presentation);
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

function feedbackPayload(
  item: ReturnType<typeof selectedRecordDetail>[number],
  exposureEventId = "",
  presentation?: ExpressionPresentation,
) {
  const claim = object(item.candidate.claim);
  const companionMessage = presentation?.target === "companion_message"
    ? text(presentation.renderedPayload.companion_message, 4000)
    : "";
  const presentationTarget = presentation?.target ?? "feedback_card";
  const renderedTextFingerprint = presentation?.renderedTextFingerprint
    ?? expressionRenderedTextFingerprint(item.canonicalText);
  return {
    version: "expression-planner-record-detail-v0.1",
    source: "expression_planner",
    icon: "sparkles",
    badge: dimensionLabel(text(item.candidate.dimension, 100)),
    band: "neutral",
    emotion_line: companionMessage || item.canonicalText,
    utility_line: "",
    detail_reason: candidateDetailReason(item),
    candidate_id: item.candidateId,
    semantic_key: text(claim.semantic_key, 200),
    claim_fingerprint: claimFingerprintFromCandidate(item.candidate),
    dimension: text(item.candidate.dimension, 100),
    presentation_target: presentationTarget,
    rendered_text_fingerprint: renderedTextFingerprint,
    ...(exposureEventId ? { exposure_event_id: exposureEventId } : {}),
  };
}

function candidateDetailReason(
  item: ReturnType<typeof selectedRecordDetail>[number],
): string {
  const candidate = item.candidate;
  const claim = object(candidate.claim);
  const quality = object(candidate.quality);
  const sampleCount = Number(quality.sample_count ?? 0);
  if (Number.isFinite(sampleCount) && sampleCount > 1) {
    return `基于 ${sampleCount} 条可用记录计算`;
  }

  const semanticKey = text(claim.semantic_key, 200);
  const dimension = text(candidate.dimension, 100);
  if (/first_occurrence/.test(semanticKey) || dimension === "first_occurrence") {
    return "依据当前记录与可用商户历史，未找到同一实体的更早记录";
  }
  if (/(?:previous_gap|recurrence|repeat)/.test(semanticKey)) {
    return "依据本条记录与上一条同类记录的发生时间";
  }
  if (/(?:current_record|current_metric|record_context)/.test(semanticKey) || dimension === "current_fact") {
    return "依据本条记录中已确认的对象、金额或时间字段";
  }

  const evidenceCount = Array.isArray(candidate.evidence) ? candidate.evidence.length : 0;
  if (evidenceCount > 0) return `依据 ${evidenceCount} 条可追溯记录证据`;
  return "依据代码已核实的当前候选事实";
}

function feedbackCardPresentation(
  item: ReturnType<typeof selectedRecordDetail>[number],
): ExpressionPresentation {
  const renderedTextFingerprint = expressionRenderedTextFingerprint(item.canonicalText);
  const provisional: ExpressionPresentation = {
    target: "feedback_card",
    renderedPayload: {},
    visibleFieldPaths: [],
    renderedTextFingerprint,
  };
  const renderedPayload = feedbackPayload(item, "", provisional);
  const visibleFieldPaths = ["badge", "emotion_line", "utility_line", "detail_reason"]
    .filter((key) => text(renderedPayload[key as keyof typeof renderedPayload], 2000))
    .map((key) => `feedback.${key}`);
  return { ...provisional, renderedPayload, visibleFieldPaths };
}

function companionMessagePresentation(
  coverage: ValidatedCompanionCoverage,
): ExpressionPresentation {
  return {
    target: "companion_message",
    renderedPayload: { companion_message: coverage.companionMessage },
    visibleFieldPaths: ["companion_message"],
    renderedTextFingerprint: coverage.renderedTextFingerprint,
  };
}

function frozenPresentation(
  deliveryPlan: Record<string, unknown>,
  primary: ReturnType<typeof selectedRecordDetail>[number],
): ExpressionPresentation | null {
  const raw = object(deliveryPlan.presentation);
  const target = text(raw.target, 100);
  const renderedPayload = object(raw.rendered_payload);
  const visibleFieldPaths = Array.isArray(raw.visible_field_paths)
    ? raw.visible_field_paths.map((value) => text(value, 200)).filter(Boolean)
    : [];
  const renderedTextFingerprint = text(raw.rendered_text_fingerprint, 200);
  if (
    !["feedback_card", "companion_message"].includes(target)
    || !visibleFieldPaths.length
    || !renderedTextFingerprint
  ) return null;
  const renderedText = target === "companion_message"
    ? text(renderedPayload.companion_message, 4000)
    : text(renderedPayload.emotion_line, 4000);
  if (
    !renderedText
    || renderedTextFingerprint !== expressionRenderedTextFingerprint(renderedText)
  ) return null;
  if (target === "feedback_card") {
    if (
      text(renderedPayload.candidate_id, 200) !== primary.candidateId
      || text(renderedPayload.claim_fingerprint, 200) !== claimFingerprintFromCandidate(primary.candidate)
    ) return null;
  }
  return {
    target: target as ExpressionPresentationTarget,
    renderedPayload,
    visibleFieldPaths,
    renderedTextFingerprint,
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

function expenseHistoryQuery(
  supabase: DatabaseClient,
  userId: string,
  _transactionDate: string,
  from: number,
  to: number,
) {
  return supabase.from("transactions")
    .select("id,transaction_date,transaction_time,occurred_at,created_at,amount,merchant_name,category,platform,payment_method,status,type,staging_record_id,image_hash,companion_message,ai_feedback")
    .eq("user_id", userId)
    .eq("type", "expense")
    .order("occurred_at", { ascending: false })
    .order("transaction_date", { ascending: false })
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .range(from, to);
}

function incomeHistoryQuery(
  supabase: DatabaseClient,
  userId: string,
  incomeDate: string,
  from: number,
  to: number,
) {
  return supabase.from("income_records")
    .select("id,income_date,occurred_at,created_at,amount,source_name,category,companion_message,ai_feedback")
    .eq("user_id", userId)
    .lte("income_date", incomeDate)
    .order("occurred_at", { ascending: false })
    .order("income_date", { ascending: false })
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .range(from, to);
}

function dataHistoryQuery(
  supabase: DatabaseClient,
  userId: string,
  domainKey: string,
  occurredAt: string | null,
  from: number,
  to: number,
) {
  let query = supabase.from("data_records")
    .select("id,created_at,occurred_at,title,summary,payload_jsonb,domain_key,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at")
    .eq("user_id", userId)
    .eq("domain_key", domainKey);
  if (occurredAt) query = query.lte("occurred_at", occurredAt);
  return query
    .order("occurred_at", { ascending: false })
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .range(from, to);
}

export async function buildPreInsertPlannerVoiceBrief(
  supabase: DatabaseClient,
  userId: string,
  input: {
    record_kind: "expense" | "income" | "data";
    domain_key: string;
    current_record: Record<string, unknown>;
    domain_profile?: Record<string, unknown>;
  },
): Promise<PlannerVoiceBrief | null> {
  if (!isRecordExpressionOwnerEnabled(userId)) return null;
  const current = input.current_record;
  const currentRecordId = text(current.id, 200);
  if (!currentRecordId) throw new Error("插入前 Planner 缺少临时记录编号");
  const personalization = await loadPlannerPersonalization(supabase, userId);

  if (input.record_kind === "expense") {
    const transactionDate = text(current.transaction_date, 20);
    if (!transactionDate) throw new Error("插入前支出 Planner 缺少记录日期");
    const history = await loadHistoryPages((from, to) =>
      expenseHistoryQuery(supabase, userId, transactionDate, from, to)
    );
    const transactions = includeCurrentRecord(history ?? [], current) as unknown as ShadowExpenseTransaction[];
    const plan = buildExpressionShadowPlan({
      transactions,
      currentRecordId,
      occurredAt: text(buildExpensePlannerSourceRecord(current as unknown as ShadowExpenseTransaction).occurred_at, 100),
      ...personalization,
    }) as Record<string, unknown>;
    return plannerVoiceBriefFromPlan(plan);
  }

  if (input.record_kind === "income") {
    const incomeDate = text(current.income_date, 20);
    if (!incomeDate) throw new Error("插入前收入 Planner 缺少记录日期");
    const history = await loadHistoryPages((from, to) =>
      incomeHistoryQuery(supabase, userId, incomeDate, from, to)
    );
    const records = includeCurrentRecord(history ?? [], current).map(buildIncomePlannerSourceRecord);
    const plan = buildGenericExpressionShadowPlan({
      domainKey: "income",
      records,
      currentRecordId,
      ...personalization,
    }) as Record<string, unknown>;
    return plannerVoiceBriefFromPlan(plan);
  }

  const domainKey = text(input.domain_key, 80);
  const occurredAt = text(current.occurred_at, 100);
  if (!domainKey || !occurredAt) throw new Error("插入前数据域 Planner 缺少域或发生时间");
  const history = await loadHistoryPages((from, to) =>
    dataHistoryQuery(supabase, userId, domainKey, occurredAt, from, to)
  );
  const records = includeCurrentRecord(history ?? [], current).map(buildDataPlannerSourceRecord);
  const domainProfile = input.domain_profile ?? await loadDomainProfile(supabase, userId, domainKey);
  const plan = buildGenericExpressionShadowPlan({
    domainKey,
    records,
    currentRecordId,
    domainProfile,
    ...personalization,
  }) as Record<string, unknown>;
  return plannerVoiceBriefFromPlan(plan);
}

async function buildCurrentRecordPlan(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  kind: RecordKind,
) {
  if (kind === "expense") {
    const { data: current, error } = await supabase.from("transactions")
      .select("id,transaction_date,transaction_time,occurred_at,created_at,amount,merchant_name,category,platform,payment_method,status,type,staging_record_id,image_hash,companion_message,ai_feedback")
      .eq("user_id", userId)
      .eq("id", recordId)
      .eq("type", "expense")
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!current) return null;
    const history = await loadHistoryPages((from, to) =>
      expenseHistoryQuery(supabase, userId, text(current.transaction_date, 20), from, to)
    );
    const personalization = await loadPlannerPersonalization(supabase, userId);
    const transactions = includeCurrentRecord(history ?? [], current) as unknown as ShadowExpenseTransaction[];
    const sourceRecord = buildExpensePlannerSourceRecord(current as ShadowExpenseTransaction);
    const plan = buildExpressionShadowPlan({
      transactions,
      currentRecordId: recordId,
      occurredAt: text(sourceRecord.occurred_at, 100),
      ...personalization,
    }) as Record<string, unknown>;
    const companionMessage = text(current.companion_message, 4000);
    const companionCoverage = validatedCompanionCoverage(
      current.ai_feedback,
      plan,
      companionMessage,
      current,
    );
    return {
      kind,
      domainKey: "expense",
      companionCoverage,
      plan,
    };
  }
  if (kind === "income") {
    const { data: current, error } = await supabase.from("income_records")
      .select("id,income_date,occurred_at,created_at,amount,source_name,category,companion_message,ai_feedback")
      .eq("user_id", userId)
      .eq("id", recordId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    if (!current) return null;
    const history = await loadHistoryPages((from, to) =>
      incomeHistoryQuery(supabase, userId, text(current.income_date, 20), from, to)
    );
    const personalization = await loadPlannerPersonalization(supabase, userId);
    const records = includeCurrentRecord(history ?? [], current).map(buildIncomePlannerSourceRecord);
    const plan = buildGenericExpressionShadowPlan({
      domainKey: "income",
      records,
      currentRecordId: recordId,
      ...personalization,
    }) as Record<string, unknown>;
    const companionMessage = text(current.companion_message, 4000);
    const companionCoverage = validatedCompanionCoverage(
      current.ai_feedback,
      plan,
      companionMessage,
      current,
    );
    return {
      kind,
      domainKey: "income",
      companionCoverage,
      plan,
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
  const history = await loadHistoryPages((from, to) =>
    dataHistoryQuery(supabase, userId, domainKey, text(current.occurred_at, 100) || null, from, to)
  );
  const personalization = await loadPlannerPersonalization(supabase, userId);
  const records = includeCurrentRecord(history ?? [], current).map(buildDataPlannerSourceRecord);
  const payload = object(current.payload_jsonb);
  const domainProfile = await loadDomainProfile(supabase, userId, domainKey);
  const plan = buildGenericExpressionShadowPlan({
    domainKey,
    records,
    currentRecordId: recordId,
    domainProfile,
    ...personalization,
  }) as Record<string, unknown>;
  const companionMessage = text(payload.companion_message, 4000);
  const companionCoverage = validatedCompanionCoverage(
    payload.ai_feedback,
    plan,
    companionMessage,
    { ...current, ...payload },
  );
  return {
    kind,
    domainKey,
    companionCoverage,
    plan,
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
    ? "id,transaction_date,transaction_time,occurred_at,created_at,amount,merchant_name,category,platform,payment_method,status,type,staging_record_id,image_hash"
    : sourceTable === "income_records"
    ? "id,income_date,occurred_at,created_at,amount,source_name,category"
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

async function currentClaimUnavailableReason(
  supabase: DatabaseClient,
  userId: string,
  recordId: string,
  kind: RecordKind,
  frozenCandidate: Record<string, unknown>,
) {
  const frozenClaim = object(frozenCandidate.claim);
  const semanticKey = text(frozenClaim.semantic_key, 200);
  const claimFingerprint = claimFingerprintFromCandidate(frozenCandidate);
  if (!semanticKey || !claimFingerprint) return "plan_claim_missing";
  const current = await buildCurrentRecordPlan(supabase, userId, recordId, kind);
  if (!current) return "plan_record_missing";
  const currentFingerprints = planCandidateClaimFingerprints(current.plan);
  return currentFingerprints.get(semanticKey) === claimFingerprint
    ? ""
    : "plan_claim_stale";
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
  const selected = selectedShortcutNotification(plan);
  const covered = context.companionCoverage
    ? selected.find((item) =>
      text(object(item.candidate.claim).semantic_key, 200) === context.companionCoverage?.semanticKey
      && claimFingerprintFromCandidate(item.candidate) === context.companionCoverage?.claimFingerprint
    )
    : null;
  const primary = covered ?? selected[0];
  if (!primary) return { available: false, reason: "no_selected_candidate" };
  const dependencyReason = await dependencyUnavailableReason(supabase, userId, primary.candidate);
  if (dependencyReason) return { available: false, reason: dependencyReason };
  const presentationTarget: ExpressionPresentationTarget = covered
    ? "companion_message"
    : "feedback_card";
  const renderedMessage = covered
    ? context.companionCoverage?.companionMessage ?? ""
    : primary.canonicalText;
  const renderedPayload = covered
    ? { companion_message: renderedMessage }
    : { message: renderedMessage };
  const visibleFieldPaths = covered ? ["companion_message"] : ["message"];
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
        rendered_payload: renderedPayload,
        visible_field_paths: visibleFieldPaths,
        expandable_field_paths: [],
        persisted_only_field_paths: [],
        presentation_target: presentationTarget,
        rendered_text_fingerprint: expressionRenderedTextFingerprint(renderedMessage),
      },
    },
    lifecycleState: "returned_to_shortcut",
    simulationOnly: false,
  });
  const exposure = exposures.find((item) => text(item.candidate_id, 200) === primary.candidateId);
  return {
    available: true,
    message: renderedMessage,
    candidate_id: primary.candidateId,
    semantic_key: text(object(primary.candidate.claim).semantic_key, 200),
    claim_fingerprint: claimFingerprintFromCandidate(primary.candidate),
    presentation_target: presentationTarget,
    rendered_text_fingerprint: expressionRenderedTextFingerprint(renderedMessage),
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
  if (!selected.length) {
    return {
      available: false,
      reason: "no_selected_candidate",
    };
  }
  const primary = selected[0];
  const dependencyReason = await dependencyUnavailableReason(supabase, userId, primary.candidate);
  if (dependencyReason) return { available: false, reason: dependencyReason };
  const presentation = context.companionCoverage
    ? companionMessagePresentation(context.companionCoverage)
    : feedbackCardPresentation(primary);
  const snapshot = await persistDeliverySnapshot(
    supabase,
    userId,
    recordId,
    context.kind,
    deliveryPlan,
    primary,
    presentation,
  );
  const frozenPlan = object(snapshot.delivery_plan);
  const frozenPrimary = selectedRecordDetail(frozenPlan)[0];
  if (!frozenPrimary || frozenPrimary.candidateId !== text(snapshot.candidate_id, 200)) {
    throw new Error("表达下发快照内容不完整");
  }
  const frozenTarget = frozenPresentation(frozenPlan, frozenPrimary);
  if (!frozenTarget) throw new Error("表达下发快照展示契约不完整");
  return {
    available: true,
    plan_token: String(snapshot.id),
    record_id: recordId,
    record_kind: context.kind,
    domain_key: context.domainKey,
    surface: "record_detail",
    candidate_id: frozenPrimary.candidateId,
    presentation_target: frozenTarget.target,
    rendered_text_fingerprint: frozenTarget.renderedTextFingerprint,
    feedback: feedbackPayload(frozenPrimary, "", frozenTarget),
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
  const presentation = frozenPresentation(deliveryPlan, primary);
  if (!presentation) throw new Error("表达下发快照展示契约已失效");
  const dependencyReason = await dependencyUnavailableReason(supabase, userId, primary.candidate);
  if (dependencyReason) throw new Error(`表达计划已失效：${dependencyReason}`);
  const snapshotKind = recordKind(snapshot.record_kind);
  if (!snapshotKind) throw new Error("表达下发快照记录类型已失效");
  const currentClaimReason = await currentClaimUnavailableReason(
    supabase,
    userId,
    recordId,
    snapshotKind,
    primary.candidate,
  );
  if (currentClaimReason) throw new Error(`表达计划已失效：${currentClaimReason}`);
  if (presentation.target === "companion_message") {
    const current = await buildCurrentRecordPlan(supabase, userId, recordId, snapshotKind);
    const currentCoverage = current?.companionCoverage;
    if (
      !currentCoverage
      || currentCoverage.semanticKey !== text(object(primary.candidate.claim).semantic_key, 200)
      || currentCoverage.claimFingerprint !== claimFingerprintFromCandidate(primary.candidate)
      || currentCoverage.renderedTextFingerprint !== presentation.renderedTextFingerprint
      || currentCoverage.companionMessage !== text(presentation.renderedPayload.companion_message, 4000)
    ) {
      throw new Error("表达计划已失效：plan_companion_stale");
    }
  }
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
        rendered_payload: presentation.renderedPayload,
        visible_field_paths: presentation.visibleFieldPaths,
        expandable_field_paths: [],
        persisted_only_field_paths: [],
        presentation_target: presentation.target,
        rendered_text_fingerprint: presentation.renderedTextFingerprint,
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
    presentation_target: presentation.target,
    rendered_text_fingerprint: presentation.renderedTextFingerprint,
    feedback: feedbackPayload(primary, exposureEventId, presentation),
  };
}
