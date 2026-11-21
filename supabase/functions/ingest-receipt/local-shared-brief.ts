import { EXPRESSION_PLANNER_VERSION } from "./expression-shadow-planner.ts";
import { evidenceReference, localClaimFingerprint } from "./local-expression-contract.ts";
import type { PlannerEvidenceReference } from "./local-expression-contract.ts";
import type { PlannerVoiceBrief } from "./planner-voice-brief.ts";

const DOMAIN_KEYS: Record<string, ReadonlySet<string>> = {
  expense: new Set([
    "expense_current_record_context", "expense_merchant_first_occurrence", "merchant_daily_count_total",
    "merchant_daily_amount_structure", "expense_record_name_previous_gap", "merchant_daily_vs_active_day_median",
    "merchant_week_to_date_vs_previous_week_same_period", "expense_category_week_to_date_vs_previous_week_same_period",
  ]),
  income: new Set(["income_current_amount", "income_month_total_count", "income_source_month_pattern"]),
  food: new Set(["food_current_metric", "food_vs_personal_median", "food_record_context", "food_composition", "food_meal_vs_personal_median", "food_recurring_dish"]),
  sleep: new Set(["sleep_current_metric", "sleep_vs_personal_median", "sleep_timing", "sleep_timing_vs_typical", "sleep_quality_current", "sleep_stage_composition"]),
  sport: new Set(["sport_current_metric", "sport_vs_personal_median"]),
  reading: new Set(["reading_current_metric", "reading_vs_personal_median"]),
  wallet: new Set(["wallet_current_metric", "wallet_change_previous"]),
};

function object(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function boundedText(value: unknown, max: number): string | null {
  return typeof value === "string" && value.trim() && value.length <= max ? value.trim() : null;
}

function references(
  value: unknown,
  currentID: string,
  ids?: ReadonlySet<string>,
): PlannerEvidenceReference[] | null {
  if (!Array.isArray(value) || !value.length || value.length > 8) return null;
  const refs = [];
  for (const raw of value) {
    const item = object(raw);
    const id = boundedText(item?.reference, 200);
    const field = item?.field === null ? null : boundedText(item?.field, 120);
    const kind = id === currentID ? "current_fact" : "recent_fact";
    if (!id || !/^[a-zA-Z0-9_-]+$/.test(id) || (ids && !ids.has(id)) ||
      item?.kind !== kind || item.source !== "local_record" ||
      (item.field !== null && field === null)) return null;
    refs.push(evidenceReference(kind, id, field));
  }
  return refs;
}

/** The authenticated device computed this advisory observation from its local
 * store. Edge validates its envelope and provenance references. It neither reads
 * the underlying history nor promotes the claim to a stored business fact. */
export function normalizeLocalSharedBrief(
  value: unknown,
  currentFact: Record<string, unknown>,
): PlannerVoiceBrief | null {
  const brief = object(value);
  const currentID = boundedText(currentFact.id, 200);
  const domain = boundedText(currentFact.domain_key, 40);
  const candidateID = boundedText(brief?.candidate_id, 200);
  const key = boundedText(brief?.semantic_key, 100);
  const dimension = boundedText(brief?.dimension, 100);
  const fact = boundedText(brief?.canonical_text, 400);
  if (!brief || !currentID || !domain || !candidateID || !key || !dimension || !fact ||
    !Object.hasOwn(DOMAIN_KEYS, domain) ||
    (!DOMAIN_KEYS[domain].has(key) && (key !== "cross_record_possible_life_chain" ||
      dimension !== "cross_record_relationship" || fact !== "两条记录可能属于同一条生活安排")) ||
    brief.source_surface !== "record_detail" || brief.planner_version !== EXPRESSION_PLANNER_VERSION ||
    brief.claim_fingerprint !== localClaimFingerprint(key, fact)) return null;
  const evidence = references(brief.evidence, currentID);
  if (!evidence || !evidence.some(ref => ref.kind === "current_fact")) return null;
  const ids = new Set(evidence.map(ref => ref.reference));
  if (key === "cross_record_possible_life_chain" && ids.size !== 2) return null;
  if (!Array.isArray(brief.number_facts) || brief.number_facts.length > 12) return null;
  const numberFacts: PlannerVoiceBrief["number_facts"] = [];
  for (const raw of brief.number_facts) {
    const number = object(raw);
    const refs = references(number?.evidence, currentID, ids);
    if (!number || typeof number.value !== "number" || !Number.isFinite(number.value) ||
      !refs || (number.role !== "count" && number.role !== "measure") ||
      (number.role === "count" && (!Number.isSafeInteger(number.value) || number.value < 0))) return null;
    numberFacts.push({
      value: number.value,
      meaning: boundedText(number.meaning, 120),
      role: number.role,
      evidence: refs,
    });
  }
  return {
    candidate_id: candidateID,
    semantic_key: key,
    dimension,
    canonical_text: fact,
    planner_version: EXPRESSION_PLANNER_VERSION,
    source_surface: "record_detail",
    claim_fingerprint: localClaimFingerprint(key, fact),
    evidence,
    number_facts: numberFacts,
    numbers: numberFacts.map(fact => fact.value),
    count_numbers: numberFacts.filter(fact => fact.role === "count").map(fact => fact.value),
  };
}
