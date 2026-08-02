// Shared Shadow planner: production invokes the same deterministic modules used by the offline lab.
// @ts-ignore JavaScript experiment modules intentionally remain framework-neutral.
import {
  compileMerchantAliases,
  resolveMerchant,
  summarizeMerchantObservation,
} from "../../../tools/ai-validation/expression-planner/lib/entity-normalizer.mjs";
import merchantAliasConfig from "../../../tools/ai-validation/expression-planner/configs/entity-aliases.public.v0.1.json" with { type: "json" };
// @ts-ignore See note above.
import { generateFactCandidates } from "../../../tools/ai-validation/expression-planner/lib/fact-candidates.mjs";
// @ts-ignore See note above.
import { generateComparisonCandidates } from "../../../tools/ai-validation/expression-planner/lib/comparison-candidates.mjs";
// @ts-ignore See note above.
import { generateIncomeCandidates, generateBuiltinDomainCandidates } from "../../../tools/ai-validation/expression-planner/lib/generic-domain-candidates.mjs";
// @ts-ignore See note above.
import { evaluateCandidates, summarizeEligibility } from "../../../tools/ai-validation/expression-planner/lib/eligibility-gates.mjs";
// @ts-ignore See note above.
import { scoreCandidates, summarizeScores } from "../../../tools/ai-validation/expression-planner/lib/deterministic-scoring.mjs";
// @ts-ignore See note above.
import { buildExpressionPlans, summarizePlans } from "../../../tools/ai-validation/expression-planner/lib/expression-plan.mjs";
// @ts-ignore See note above.
import { buildRenderPlans } from "../../../tools/ai-validation/expression-planner/lib/render-contract.mjs";
// @ts-ignore Pure shared data contract is bundled with the Edge Function.
import { normalizeExpenseCategory } from "../../../src/domains/expenseCategories.js";

export interface ShadowExpenseTransaction {
  id: string; transaction_date: string; transaction_time?: string | null; created_at?: string | null;
  amount: number | string; merchant_name?: string | null; category?: string | null;
  platform?: string | null; payment_method?: string | null; status?: string | null;
}

export interface ShadowGenericRecord {
  id: string; occurred_at: string; amount?: number | string | null; source_name?: string | null;
  title?: string | null; summary?: string | null; payload?: Record<string, unknown>; source_type?: string;
}

interface ShadowPlannerOptions { preferenceProfile?: Record<string, unknown>; exposureHistory?: Record<string, unknown>; }
interface ShadowPlannerInput extends ShadowPlannerOptions { transactions: ShadowExpenseTransaction[]; currentRecordId: string; occurredAt?: string | null; }
interface GenericPlannerInput extends ShadowPlannerOptions { domainKey: string; records: ShadowGenericRecord[]; currentRecordId: string; }

const MERCHANT_ALIAS_MAP = compileMerchantAliases(merchantAliasConfig);

function numberOrNull(value: unknown): number | null { const number = Number(value); return Number.isFinite(number) ? number : null; }
function occurredAtOf(row: ShadowExpenseTransaction): string {
  return row.transaction_date ? `${row.transaction_date}T${row.transaction_time || "12:00:00"}+08:00` : row.created_at || new Date().toISOString();
}
function toRecord(row: ShadowExpenseTransaction, aliasMap: Map<string, unknown>) {
  return { id: row.id, transaction_date: row.transaction_date, occurred_at: occurredAtOf(row), amount: numberOrNull(row.amount),
    merchant: resolveMerchant(row.merchant_name, aliasMap), category: normalizeExpenseCategory(row.category), platform: row.platform ?? null, payment_method: row.payment_method ?? null };
}
function toFactEvent(record: ReturnType<typeof toRecord>) {
  return { event_id: `transaction:${record.id}`, source_type: "transaction", ledger_status: "confirmed_transaction", trust_level: "confirmed",
    count_in_facts: record.amount !== null, event_at: record.occurred_at, event_time_source: "transaction_time", event_time_confidence: 0.95,
    known_at: record.occurred_at, amount: record.amount, merchant: record.merchant, category: record.category, platform: record.platform,
    payment_method: record.payment_method, target_table: "transactions", target_id: record.id };
}

function finalizePlan(domainKey: string, currentRecord: Record<string, unknown>, candidates: Record<string, unknown>[], options: ShadowPlannerOptions, coveredSemanticKeys: string[] = []) {
  const eligibleCandidates = evaluateCandidates(candidates);
  const scoredCandidates = scoreCandidates(eligibleCandidates, { context: {}, preferenceProfile: options.preferenceProfile ?? {}, exposureHistory: options.exposureHistory ?? {} });
  const expressionPlans = buildExpressionPlans(scoredCandidates, { shortcut_notification: { covered_semantic_keys: coveredSemanticKeys } });
  const renderPlans = buildRenderPlans(expressionPlans, scoredCandidates);
  return {
    status: "auto_planned", planner_version: "expression-shadow-auto-v0.2", domain_key: domainKey,
    shared_modules: ["fact-candidates", "comparison-candidates", "generic-domain-candidates", "eligibility-gates", "deterministic-scoring", "expression-plan", "render-contract"],
    changes_user_output: false, current_record: currentRecord, candidate_count: scoredCandidates.length,
    candidates: scoredCandidates.map((candidate: Record<string, unknown>) => ({ candidate_id: candidate.candidate_id, claim_type: candidate.claim_type, dimension: candidate.dimension, claim: candidate.claim, quality: candidate.quality, eligibility: candidate.eligibility, scoring: candidate.scoring })),
    selected: renderPlans.shortcut_notification.selected, shortcut_plan: expressionPlans.shortcut_notification,
    plan_summary: summarizePlans(expressionPlans), score_summary: summarizeScores(scoredCandidates), eligibility_summary: summarizeEligibility(scoredCandidates),
  };
}

export function buildExpressionShadowPlan(input: ShadowPlannerInput) {
  const records = input.transactions.filter(row => row.status !== "pending").map(row => toRecord(row, MERCHANT_ALIAS_MAP)).filter(row => row.amount !== null && row.merchant.entity_id);
  const currentRecord = records.find(row => row.id === input.currentRecordId) ?? null;
  if (!currentRecord) return { status: "skipped", reason: "current_expense_record_missing", changes_user_output: false };
  const localDate = currentRecord.transaction_date; const entityId = currentRecord.merchant.entity_id;
  const currentOccurredAt = new Date(currentRecord.occurred_at).getTime();
  const priorMerchants = records
    .filter(row => row.id !== currentRecord.id && new Date(row.occurred_at).getTime() < currentOccurredAt)
    .map(row => row.merchant);
  const merchantObservation = summarizeMerchantObservation(currentRecord.merchant, priorMerchants);
  const currentDayEvents = records.filter(row => row.transaction_date === localDate).map(toFactEvent);
  const currentEntityDayCount = currentDayEvents.filter(event => event.merchant.entity_id === entityId).length;
  let factCandidates = generateFactCandidates(currentDayEvents, { entityId, localDate, timeZone: "Asia/Shanghai" });
  if (currentEntityDayCount <= 1) factCandidates = factCandidates.filter((candidate: Record<string, unknown>) => !["merchant_daily_count_total", "merchant_daily_amount_structure", "merchant_daily_activity_span"].includes((candidate.claim as Record<string, unknown>)?.semantic_key as string));
  const comparisonCandidates = generateComparisonCandidates({ records, currentDayEvents, entityId, localDate });
  return finalizePlan("expense", {
    id: currentRecord.id,
    entity_id: entityId,
    merchant_name: currentRecord.merchant.canonical_name,
    raw_merchant_name: currentRecord.merchant.raw_name,
    merchant_observation: merchantObservation,
    transaction_date: localDate,
    amount: currentRecord.amount,
    category: currentRecord.category,
    occurred_at: currentRecord.occurred_at,
  }, [...factCandidates, ...comparisonCandidates], input);
}

export function buildGenericExpressionShadowPlan(input: GenericPlannerInput) {
  const currentRecord = input.records.find(record => record.id === input.currentRecordId) ?? null;
  if (!currentRecord) return { status: "skipped", reason: "current_domain_record_missing", domain_key: input.domainKey, changes_user_output: false };
  const candidates = input.domainKey === "income"
    ? generateIncomeCandidates(input.records, input.currentRecordId)
    : generateBuiltinDomainCandidates(input.domainKey, input.records, input.currentRecordId);
  const covered = input.domainKey === "income" ? ["income_current_amount", "income_month_total_count"] : [];
  return finalizePlan(input.domainKey, currentRecord, candidates, input, covered);
}
