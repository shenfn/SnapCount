// Shared Shadow planner: production invokes the same deterministic modules used by the offline lab.
// @ts-ignore JavaScript experiment modules intentionally remain framework-neutral.
import {
  compileMerchantAliases,
  resolveMerchant,
  summarizeMerchantObservation,
} from "../../../tools/ai-validation/expression-planner/lib/entity-normalizer.mjs";
import merchantAliasConfig from "../../../tools/ai-validation/expression-planner/configs/entity-aliases.public.v0.1.json" with { type: "json" };
// @ts-ignore See note above.
import {
  generateCurrentExpenseRecordCandidate,
  generateFactCandidates,
  generateMerchantFirstOccurrenceCandidate,
} from "../../../tools/ai-validation/expression-planner/lib/fact-candidates.mjs";
// @ts-ignore See note above.
import { generateRecordNameRecurrenceCandidates } from "../../../tools/ai-validation/expression-planner/lib/recurrence-candidates.mjs";
// @ts-ignore See note above.
import { generateCategoryComparisonCandidates, generateComparisonCandidates } from "../../../tools/ai-validation/expression-planner/lib/comparison-candidates.mjs";
// @ts-ignore See note above.
import { buildExpenseFactContract } from "../../../tools/ai-validation/expression-planner/lib/expense-fact-contract.mjs";
// @ts-ignore See note above.
import {
  generateIncomeCandidates,
  generateBuiltinDomainCandidates,
  parseFiniteNumber,
  prepareDomainRecords,
} from "../../../tools/ai-validation/expression-planner/lib/generic-domain-candidates.mjs";
// @ts-ignore See note above.
import { evaluateCandidates, summarizeEligibility } from "../../../tools/ai-validation/expression-planner/lib/eligibility-gates.mjs";
// @ts-ignore See note above.
import { scoreCandidates, summarizeScores } from "../../../tools/ai-validation/expression-planner/lib/deterministic-scoring.mjs";
// @ts-ignore See note above.
import {
  buildExpressionPlans,
  buildSurfacePlan,
  summarizePlans,
  SURFACE_CAPACITY,
} from "../../../tools/ai-validation/expression-planner/lib/expression-plan.mjs";
// @ts-ignore See note above.
import { buildRenderPlans } from "../../../tools/ai-validation/expression-planner/lib/render-contract.mjs";
// @ts-ignore Pure shared data contract is bundled with the Edge Function.
import { normalizeExpenseCategory } from "../../../src/domains/expenseCategories.js";

export interface ShadowExpenseTransaction {
  id: string; transaction_date: string; transaction_time?: string | null; occurred_at?: string | null; created_at?: string | null;
  amount: number | string | null; merchant_name?: string | null; category?: string | null;
  platform?: string | null; payment_method?: string | null; status?: string | null; type?: string | null;
  staging_record_id?: string | null; image_hash?: string | null; batch_alias?: string | null;
}

export interface ShadowGenericRecord {
  [key: string]: unknown;
  id: string; occurred_at: string; amount?: number | string | null; source_name?: string | null;
  created_at?: string | null;
  title?: string | null; summary?: string | null; payload?: Record<string, unknown>; source_type?: string;
  linked_account_id?: string | null; account_snapshot_kind?: string | null;
  snapshot_balance?: number | string | null; snapshot_at?: string | null;
}

interface ShadowPlannerOptions { preferenceProfile?: Record<string, unknown>; exposureHistory?: Record<string, unknown>; }
interface ShadowPlannerInput extends ShadowPlannerOptions {
  transactions: ShadowExpenseTransaction[];
  currentRecordId: string;
  occurredAt?: string | null;
}
interface GenericPlannerInput extends ShadowPlannerOptions { domainKey: string; records: ShadowGenericRecord[]; currentRecordId: string; domainProfile?: Record<string, unknown>; }

export const EXPRESSION_PLANNER_VERSION = "expression-shadow-auto-v0.6";
const MERCHANT_ALIAS_MAP = compileMerchantAliases(merchantAliasConfig);

export interface PlannerSourceDependency {
  source_table: "transactions" | "income_records" | "data_records";
  source_record_id: string;
  source_fingerprint: string;
  is_primary: boolean;
}

function numberOrNull(value: unknown): number | null { return parseFiniteNumber(value); }
function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function objectOrEmpty(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function canonicalOccurredAt(row: ShadowExpenseTransaction): string | null {
  const occurredAt = stringOrNull(row.occurred_at);
  return occurredAt && Number.isFinite(new Date(occurredAt).getTime()) ? occurredAt : null;
}
function occurredAtOf(row: ShadowExpenseTransaction): string {
  return canonicalOccurredAt(row)
    ?? (row.transaction_date ? `${row.transaction_date}T12:00:00+08:00` : "");
}
function toRecord(row: ShadowExpenseTransaction, aliasMap: Map<string, unknown>) {
  const category = normalizeExpenseCategory(row.category);
  const hasPreciseEventTime = canonicalOccurredAt(row) !== null;
  return { id: row.id, transaction_date: row.transaction_date, occurred_at: occurredAtOf(row), amount: numberOrNull(row.amount),
    merchant: resolveMerchant(row.merchant_name, aliasMap), category, platform: row.platform ?? null, payment_method: row.payment_method ?? null,
    status: row.status ?? null, created_at: row.created_at ?? null,
    has_precise_event_time: hasPreciseEventTime,
    event_time_source: hasPreciseEventTime ? "occurred_at" : "date_noon_proxy",
    event_time_confidence: hasPreciseEventTime ? 0.95 : 0.35,
    observation_group: row.staging_record_id ?? row.image_hash ?? row.batch_alias ?? null,
    fact_contract: buildExpenseFactContract({ status: row.status, category }) };
}

export function buildExpensePlannerSourceRecord(row: ShadowExpenseTransaction) {
  const record = toRecord(row, MERCHANT_ALIAS_MAP);
  return {
    id: record.id,
    transaction_date: record.transaction_date,
    occurred_at: record.occurred_at,
    amount: record.amount,
    merchant_name: record.merchant.raw_name,
    category: record.category,
    platform: record.platform,
    payment_method: record.payment_method,
    observation_group: record.observation_group,
    status: record.status,
    type: row.type ?? null,
  };
}

export function buildIncomePlannerSourceRecord(row: Record<string, unknown>): ShadowGenericRecord {
  const incomeDate = stringOrNull(row.income_date);
  const canonicalOccurredAt = stringOrNull(row.occurred_at);
  return {
    id: stringOrNull(row.id) ?? "",
    created_at: stringOrNull(row.created_at),
    occurred_at: canonicalOccurredAt
      ?? (incomeDate
      ? `${incomeDate}T12:00:00+08:00`
      : ""),
    amount: numberOrNull(row.amount),
    source_name: stringOrNull(row.source_name),
    payload: { category: stringOrNull(row.category) },
    source_type: "income_record",
  };
}

export function buildDataPlannerSourceRecord(row: Record<string, unknown>): ShadowGenericRecord {
  return {
    id: stringOrNull(row.id) ?? "",
    created_at: stringOrNull(row.created_at),
    occurred_at: stringOrNull(row.occurred_at) ?? "",
    title: stringOrNull(row.title),
    summary: stringOrNull(row.summary),
    payload: objectOrEmpty(row.payload_jsonb),
    linked_account_id: stringOrNull(row.linked_account_id),
    account_snapshot_kind: stringOrNull(row.account_snapshot_kind),
    snapshot_balance: numberOrNull(row.snapshot_balance),
    snapshot_at: stringOrNull(row.snapshot_at),
    source_type: "data_record",
  };
}

function canonicalValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .filter(([, item]) => item !== undefined)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, item]) => [key, canonicalValue(item)]),
    );
  }
  if (typeof value === "number" && !Number.isFinite(value)) return null;
  return value;
}

export function canonicalPlannerSource(value: unknown): string {
  return JSON.stringify(canonicalValue(value));
}

export function plannerSourceFingerprint(value: unknown): string {
  const bytes = new TextEncoder().encode(canonicalPlannerSource(value));
  let hash = 0xcbf29ce484222325n;
  for (const byte of bytes) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return `fnv1a64:${hash.toString(16).padStart(16, "0")}`;
}

export function plannerClaimFingerprint(semanticKey: string, canonicalText: string): string {
  return plannerSourceFingerprint({
    semantic_key: semanticKey.trim(),
    canonical_text: canonicalText.trim(),
  });
}

function evidenceRecordId(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const sourceId = value.trim();
  for (const prefix of ["transaction:", "income_record:", "data_record:"]) {
    if (sourceId.startsWith(prefix)) return sourceId.slice(prefix.length) || null;
  }
  return sourceId;
}

function sourceDependencies(
  sourceTable: PlannerSourceDependency["source_table"],
  records: Record<string, unknown>[],
  primaryRecordId: string,
) {
  const dependencies = records.flatMap((record) => {
    const sourceRecordId = typeof record.id === "string" ? record.id : "";
    if (!sourceRecordId) return [];
    return [{
      source_table: sourceTable,
      source_record_id: sourceRecordId,
      source_fingerprint: plannerSourceFingerprint(record),
      is_primary: sourceRecordId === primaryRecordId,
    } satisfies PlannerSourceDependency];
  });
  return new Map(dependencies.map((dependency) => [dependency.source_record_id, dependency]));
}

function attachCandidateDependencies(
  candidate: Record<string, unknown>,
  dependencyById: Map<string, PlannerSourceDependency>,
  primaryRecordId: string,
) {
  const referencedIds = new Set<string>([primaryRecordId]);
  const evidence = Array.isArray(candidate.evidence) ? candidate.evidence : [];
  for (const rawEvidence of evidence) {
    const evidenceItem = rawEvidence && typeof rawEvidence === "object"
      ? rawEvidence as Record<string, unknown>
      : {};
    const sourceRecordId = evidenceRecordId(evidenceItem.source_id);
    if (sourceRecordId) referencedIds.add(sourceRecordId);
  }
  const dependencies = [...referencedIds]
    .map((sourceRecordId) => dependencyById.get(sourceRecordId))
    .filter((dependency): dependency is PlannerSourceDependency => Boolean(dependency))
    .sort((left, right) => left.source_record_id.localeCompare(right.source_record_id));
  return { ...candidate, source_dependencies: dependencies };
}
function toFactEvent(record: ReturnType<typeof toRecord>) {
  const confirmed = record.fact_contract.fact_status === "confirmed";
  return { event_id: `transaction:${record.id}`, source_type: "transaction", ledger_status: confirmed ? "confirmed_transaction" : "pending_review", trust_level: confirmed ? "confirmed" : "provisional",
    count_in_facts: record.amount !== null && record.fact_contract.expense_total_scope === "include", event_at: record.occurred_at,
    event_time_source: record.event_time_source, event_time_precision: record.has_precise_event_time ? "second" : "date_only",
    event_time_confidence: record.event_time_confidence,
    known_at: record.created_at ?? record.occurred_at, transaction_date: record.transaction_date,
    amount: record.amount, merchant: record.merchant, category: record.category, platform: record.platform,
    payment_method: record.payment_method, observation_group: record.observation_group,
    fact_contract: record.fact_contract, target_table: "transactions", target_id: record.id };
}

function knownAt(record: ReturnType<typeof toRecord>): number | null {
  const timestamp = new Date(record.created_at ?? "").getTime();
  return Number.isFinite(timestamp) ? timestamp : null;
}

function wasKnownBeforeCurrent(record: ReturnType<typeof toRecord>, currentRecord: ReturnType<typeof toRecord>, currentOccurredAt: number) {
  if (record.id === currentRecord.id) return false;
  const recordKnownAt = knownAt(record);
  const currentKnownAt = knownAt(currentRecord);
  if (currentKnownAt !== null) return recordKnownAt !== null && recordKnownAt < currentKnownAt;
  const occurredAt = new Date(record.occurred_at).getTime();
  return Number.isFinite(occurredAt) && occurredAt < currentOccurredAt;
}

function isCausalCurrentDayRecord(record: ReturnType<typeof toRecord>, currentRecord: ReturnType<typeof toRecord>, currentOccurredAt: number) {
  if (record.transaction_date !== currentRecord.transaction_date) return false;
  if (record.id === currentRecord.id) return true;
  if (!wasKnownBeforeCurrent(record, currentRecord, currentOccurredAt)) return false;
  const recordKnownAt = knownAt(record);
  const currentKnownAt = knownAt(currentRecord);
  if (!record.has_precise_event_time || !currentRecord.has_precise_event_time) {
    return recordKnownAt !== null && currentKnownAt !== null;
  }
  const occurredAt = new Date(record.occurred_at).getTime();
  if (!Number.isFinite(occurredAt)) return false;
  if (occurredAt < currentOccurredAt) return true;
  return occurredAt === currentOccurredAt && recordKnownAt !== null && currentKnownAt !== null;
}

function finalizePlan(
  domainKey: string,
  currentRecord: Record<string, unknown>,
  candidates: Record<string, unknown>[],
  options: ShadowPlannerOptions,
  coveredSemanticKeys: string[] = [],
  sourceRecord: Record<string, unknown> = currentRecord,
  sourceTable: PlannerSourceDependency["source_table"] = "data_records",
  sourceRecords: Record<string, unknown>[] = [sourceRecord],
) {
  const eligibleCandidates = evaluateCandidates(candidates, { planningContext: "record_event" });
  const scoredCandidates = scoreCandidates(eligibleCandidates, { context: {}, preferenceProfile: options.preferenceProfile ?? {}, exposureHistory: options.exposureHistory ?? {} });
  const expressionPlans = buildExpressionPlans(scoredCandidates, { shortcut_notification: { covered_semantic_keys: coveredSemanticKeys } });
  const renderPlans = buildRenderPlans(expressionPlans, scoredCandidates);
  const primaryRecordId = String(sourceRecord.id ?? currentRecord.id ?? "");
  const dependencyById = sourceDependencies(sourceTable, sourceRecords, primaryRecordId);
  const candidatesWithDependencies = scoredCandidates.map((candidate: Record<string, unknown>) =>
    attachCandidateDependencies(candidate, dependencyById, primaryRecordId)
  );
  const planDependencies = [...new Map<string, PlannerSourceDependency>(
    candidatesWithDependencies
      .flatMap((candidate: Record<string, unknown>) =>
        (candidate.source_dependencies as PlannerSourceDependency[] | undefined) ?? []
      )
      .map((dependency: PlannerSourceDependency) => [
        `${dependency.source_table}:${dependency.source_record_id}`,
        dependency,
      ]),
  ).values()];
  return {
    status: "auto_planned", planner_version: EXPRESSION_PLANNER_VERSION, domain_key: domainKey,
    shared_modules: ["fact-candidates", "recurrence-candidates", "comparison-candidates", "generic-domain-candidates", "eligibility-gates", "deterministic-scoring", "expression-plan", "render-contract"],
    changes_user_output: false, current_record: currentRecord, source_record: sourceRecord, source_dependencies: planDependencies, candidate_count: scoredCandidates.length,
    candidates: candidatesWithDependencies.map((candidate: Record<string, unknown>) => ({ candidate_id: candidate.candidate_id, claim_type: candidate.claim_type, dimension: candidate.dimension, claim: candidate.claim, evidence: candidate.evidence, source_dependencies: candidate.source_dependencies, numbers: candidate.numbers, quality: candidate.quality, eligibility: candidate.eligibility, scoring: candidate.scoring, selection_hints: candidate.selection_hints })),
    selected: renderPlans.shortcut_notification.selected, shortcut_plan: expressionPlans.shortcut_notification,
    render_plans: renderPlans,
    plan_summary: summarizePlans(expressionPlans), score_summary: summarizeScores(scoredCandidates), eligibility_summary: summarizeEligibility(scoredCandidates),
  };
}

export function recomposeExpressionPlanSurface(
  plan: Record<string, unknown>,
  surface: string,
  coveredSemanticKeys: string[],
) {
  const candidates = Array.isArray(plan.candidates)
    ? plan.candidates as Record<string, unknown>[]
    : [];
  const surfaceCapacity = (SURFACE_CAPACITY as Record<string, Record<string, unknown>>)[surface] ?? {};
  const existingSurfacePlan = surface === "shortcut_notification"
    ? objectOrEmpty(plan.shortcut_plan)
    : objectOrEmpty(objectOrEmpty(plan.render_plans)[surface]);
  const configuredCoverage = Array.isArray(existingSurfacePlan.covered_semantic_keys)
    ? existingSurfacePlan.covered_semantic_keys
    : surfaceCapacity.covered_semantic_keys;
  const fixedCoverage = Array.isArray(configuredCoverage)
    ? configuredCoverage.filter((value): value is string => typeof value === "string")
    : [];
  const coverage = [...new Set([...fixedCoverage, ...coveredSemanticKeys.filter(Boolean)])];
  const expressionPlan = buildSurfacePlan(candidates, surface, { covered_semantic_keys: coverage });
  const renderPlan = buildRenderPlans({ [surface]: expressionPlan }, candidates)[surface];
  return {
    ...plan,
    render_plans: {
      ...objectOrEmpty(plan.render_plans),
      [surface]: {
        ...renderPlan,
        covered_semantic_keys: coverage,
      },
    },
    surface_composition: {
      ...objectOrEmpty(plan.surface_composition),
      [surface]: {
        covered_semantic_keys: coverage,
        reason: coveredSemanticKeys.length > 0 ? "covered_by_companion" : "fixed_surface_content",
      },
    },
  };
}

export function buildExpressionShadowPlan(input: ShadowPlannerInput) {
  const normalizedRecords = input.transactions
    .filter(row => row.type === undefined || row.type === null || row.type === "expense")
    .map(row => toRecord(row, MERCHANT_ALIAS_MAP));
  const currentRecord = normalizedRecords.find(row => row.id === input.currentRecordId) ?? null;
  if (!currentRecord || currentRecord.amount === null) return { status: "skipped", reason: "current_expense_record_missing", changes_user_output: false };
  const localDate = currentRecord.transaction_date; const entityId = currentRecord.merchant.entity_id;
  const currentOccurredAt = new Date(currentRecord.occurred_at).getTime();
  const causalRecords = normalizedRecords.filter(row => row.id === currentRecord.id || wasKnownBeforeCurrent(row, currentRecord, currentOccurredAt));
  const records = causalRecords.filter(row => row.amount !== null && row.fact_contract.fact_status === "confirmed" && row.merchant.entity_id);
  // Merchant novelty is about whether the entity was seen before, not whether
  // the earlier record was complete enough for financial aggregation.
  const priorMerchants = causalRecords
    .filter(row => row.id !== currentRecord.id)
    .filter(row => Boolean(row.merchant.entity_id))
    .map(row => row.merchant);
  const merchantObservation = summarizeMerchantObservation(currentRecord.merchant, priorMerchants);
  const currentDayEvents = entityId
    ? records.filter(row => isCausalCurrentDayRecord(row, currentRecord, currentOccurredAt)).map(toFactEvent)
    : [];
  const currentEntityDayCount = currentDayEvents.filter(event => event.count_in_facts && event.merchant.entity_id === entityId).length;
  const currentRecordCandidates = generateCurrentExpenseRecordCandidate(toFactEvent(currentRecord), {
    timeZone: "Asia/Shanghai",
  });
  const firstOccurrenceCandidates = generateMerchantFirstOccurrenceCandidate(
    toFactEvent(currentRecord),
    merchantObservation,
  );
  const currentRecordConfirmed = currentRecord.fact_contract.fact_status === "confirmed";
  let factCandidates = currentRecordConfirmed && entityId ? generateFactCandidates(currentDayEvents, {
    entityId,
    localDate,
    timeZone: "Asia/Shanghai",
    currentRecordId: currentRecord.id,
  }) : [];
  if (currentEntityDayCount <= 1) factCandidates = factCandidates.filter((candidate: Record<string, unknown>) => !["merchant_daily_count_total", "merchant_daily_amount_structure"].includes((candidate.claim as Record<string, unknown>)?.semantic_key as string));
  const recurrenceCandidates = currentRecordConfirmed ? generateRecordNameRecurrenceCandidates(records.map(toFactEvent), {
    currentEventId: `transaction:${currentRecord.id}`,
    timeZone: "Asia/Shanghai",
  }) : [];
  const comparisonCandidates = currentRecordConfirmed && entityId ? generateComparisonCandidates({
    records,
    currentDayEvents,
    entityId,
    localDate,
    currentRecordId: currentRecord.id,
  }) : [];
  const categoryComparisonCandidates = currentRecordConfirmed
    ? generateCategoryComparisonCandidates({ records: causalRecords, currentRecord })
    : [];
  return finalizePlan("expense", {
    id: currentRecord.id,
    entity_id: entityId,
    merchant_name: currentRecord.merchant.canonical_name,
    raw_merchant_name: currentRecord.merchant.raw_name,
    merchant_observation: merchantObservation,
    transaction_date: localDate,
    amount: currentRecord.amount,
    category: currentRecord.category,
    fact_contract: currentRecord.fact_contract,
    occurred_at: currentRecord.occurred_at,
  }, [...currentRecordCandidates, ...firstOccurrenceCandidates, ...factCandidates, ...recurrenceCandidates, ...comparisonCandidates, ...categoryComparisonCandidates], input, [],
  buildExpensePlannerSourceRecord(input.transactions.find(row => row.id === input.currentRecordId)!), "transactions",
  input.transactions.map(buildExpensePlannerSourceRecord));
}

export function buildGenericExpressionShadowPlan(input: GenericPlannerInput) {
  const planningRecords = prepareDomainRecords(input.domainKey, input.records, input.currentRecordId);
  const currentRecord = planningRecords.find((record: ShadowGenericRecord) => record.id === input.currentRecordId) ?? null;
  if (!currentRecord) return { status: "skipped", reason: "current_domain_record_missing", domain_key: input.domainKey, changes_user_output: false };
  const candidates = input.domainKey === "income"
    ? generateIncomeCandidates(planningRecords, input.currentRecordId)
    : generateBuiltinDomainCandidates(input.domainKey, planningRecords, input.currentRecordId, input.domainProfile ?? {});
  const covered = input.domainKey === "income" ? ["income_current_amount", "income_month_total_count"] : [];
  const sourceTable = input.domainKey === "income" ? "income_records" : "data_records";
  return finalizePlan(input.domainKey, currentRecord, candidates, input, covered, currentRecord, sourceTable, planningRecords);
}
