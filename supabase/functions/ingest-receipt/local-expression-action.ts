import {
  type LocalPlannerCandidateContract,
  validateLocalPlannerCandidate,
} from "./local-expression-contract.ts";
import {
  normalizeLocalMemoryContext,
  type LocalMemoryContextEntry,
} from "./context-packet.ts";
import { buildTimeContext, type TimeContext } from "./time.ts";

const ALLOWED_DOMAINS = new Set(["expense", "income", "food", "sleep", "sport", "reading", "wallet"]);
const MAX_RECENT_FACTS = 12;
const MAX_CANDIDATE_EVIDENCE = 8;
const MAX_CANDIDATE_NUMBERS = 8;
const MAX_CANDIDATE_NUMBER_FACTS = 8;
const MAX_CANDIDATE_TEXT = 300;
const MAX_ID_LENGTH = 200;
const MAX_FIELD_LENGTH = 240;
const PAYLOAD_STRING_FIELDS = new Set([
  "occurred_at", "order_finished_at", "meal_type", "sport_type", "avg_pace", "book_name",
  "record_kind", "account_name", "category", "income_category", "merchant_name", "source_name",
  "platform", "payment_method", "dish_name", "food_name", "meal_name",
]);
const PAYLOAD_NUMBER_FIELDS = new Set([
  "amount", "amount_minor", "balance_minor", "snapshot_balance_minor", "sleep_hours", "sleep_minutes",
  "quality_score", "duration_minutes", "distance_km", "total_calorie_kcal", "reading_minutes", "progress_percent",
]);
const CURRENT_FACT_STRING_FIELDS = new Set([
  "id", "domain_key", "title", "summary", "merchant_name", "platform", "category", "payment_method",
  "source_name", "record_date", "record_time", "occurred_at", "order_finished_at",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function boundedString(value: unknown, max = MAX_FIELD_LENGTH): string | null {
  const normalized = stringValue(value);
  return normalized ? normalized.slice(0, max) : null;
}

function boundedNumber(value: unknown): number | string | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const normalized = boundedString(value, 64);
  if (normalized && Number.isFinite(Number(normalized))) return normalized;
  return null;
}

function sanitizePayload(value: unknown): Record<string, unknown> | null {
  if (!isRecord(value)) return null;
  const result: Record<string, unknown> = {};
  for (const [key, raw] of Object.entries(value)) {
    if (PAYLOAD_STRING_FIELDS.has(key)) {
      const normalized = boundedString(raw);
      if (normalized) result[key] = normalized;
      continue;
    }
    if (PAYLOAD_NUMBER_FIELDS.has(key)) {
      const normalized = boundedNumber(raw);
      if (normalized !== null) result[key] = normalized;
      continue;
    }
    if (key === "dishes" || key === "food_items") {
      if (!Array.isArray(raw)) continue;
      const items = raw.slice(0, 8).flatMap((item) => {
        if (typeof item === "string") {
          const normalized = boundedString(item);
          return normalized ? [normalized] : [];
        }
        if (!isRecord(item)) return [];
        const name = boundedString(item.name ?? item.dish_name ?? item.food_name);
        if (!name) return [];
        const entry: Record<string, unknown> = { name };
        const amount = boundedNumber(item.amount ?? item.grams);
        if (amount !== null) entry.amount = amount;
        const kcal = boundedNumber(item.kcal ?? item.calorie_kcal);
        if (kcal !== null) entry.kcal = kcal;
        return [entry];
      });
      if (items.length > 0) result[key] = items;
    }
  }
  return Object.keys(result).length > 0 ? result : null;
}

function sanitizeFact(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) return {};
  const result: Record<string, unknown> = {};
  for (const key of CURRENT_FACT_STRING_FIELDS) {
    const normalized = boundedString(value[key], key === "id" ? MAX_ID_LENGTH : MAX_FIELD_LENGTH);
    if (normalized) result[key] = normalized;
  }
  if (value.amount !== undefined) {
    const amount = boundedNumber(value.amount);
    if (amount !== null) result.amount = amount;
  }
  const payload = sanitizePayload(value.payload_json);
  if (payload) result.payload_json = payload;
  return result;
}

function recordEventFallback(currentFact: Record<string, unknown>): string | null {
  const payload = isRecord(currentFact.payload_json) ? currentFact.payload_json : null;
  const date = stringValue(currentFact.record_date) ?? stringValue(payload?.record_date);
  const time = stringValue(currentFact.record_time) ?? stringValue(payload?.record_time);
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  if (time && /^\d{1,2}:\d{2}(?::\d{2})?$/.test(time)) return `${date}T${time}+08:00`;
  return date;
}

function normalizeRecentFacts(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord).slice(0, MAX_RECENT_FACTS).map(sanitizeFact);
}

function candidateBoundsReason(candidate: Record<string, unknown>): string | null {
  const identityLimits: Array<[string, number]> = [
    ["candidate_id", MAX_ID_LENGTH], ["semantic_key", MAX_ID_LENGTH], ["dimension", 100],
    ["claim_fingerprint", MAX_ID_LENGTH], ["canonical_text", MAX_CANDIDATE_TEXT],
  ];
  for (const [key, limit] of identityLimits) {
    if (typeof candidate[key] === "string" && candidate[key].length > limit) return "candidate_bounds_exceeded";
  }
  const evidence = candidate.evidence;
  const evidenceWithinBounds = (items: unknown): boolean => {
    if (!Array.isArray(items)) return true;
    if (items.length > MAX_CANDIDATE_EVIDENCE) return false;
    return items.every((item) => {
      if (!isRecord(item)) return true;
      return !(typeof item.reference === "string" && item.reference.length > MAX_ID_LENGTH)
        && !(typeof item.field === "string" && item.field.length > 80);
    });
  };
  if (Array.isArray(evidence)) {
    if (evidence.length > MAX_CANDIDATE_EVIDENCE) return "candidate_bounds_exceeded";
    for (const item of evidence) {
      if (!isRecord(item)) continue;
      if (typeof item.reference === "string" && item.reference.length > MAX_ID_LENGTH) return "candidate_bounds_exceeded";
      if (typeof item.field === "string" && item.field.length > 80) return "candidate_bounds_exceeded";
    }
  }
  for (const key of ["numbers", "count_numbers"]) {
    if (Array.isArray(candidate[key]) && candidate[key].length > MAX_CANDIDATE_NUMBERS) return "candidate_bounds_exceeded";
  }
  const numberFacts = candidate.number_facts;
  if (Array.isArray(numberFacts)) {
    if (numberFacts.length > MAX_CANDIDATE_NUMBER_FACTS) return "candidate_bounds_exceeded";
    for (const item of numberFacts) {
      if (!isRecord(item)) continue;
      if (typeof item.meaning === "string" && item.meaning.length > MAX_FIELD_LENGTH) return "candidate_bounds_exceeded";
      if (!evidenceWithinBounds(item.evidence)) return "candidate_bounds_exceeded";
    }
  }
  return null;
}

export interface NormalizeLocalExpressionActionInput {
  currentFact: unknown;
  plannerCandidate: unknown;
  localMemoryContext: unknown;
  recentFacts?: unknown;
  clientLocalTime?: unknown;
  clientCapturedAt?: unknown;
  requestReceivedAt: string;
}

export interface NormalizedLocalExpressionAction {
  currentFact: Record<string, unknown>;
  domainKey: string;
  recentFacts: Record<string, unknown>[];
  localMemoryContext: { facts: LocalMemoryContextEntry[] } | null;
  candidate: LocalPlannerCandidateContract | null;
  plannerVersion: string;
  plannerFallbackReason: string | null;
  clientLocalTime: string | null;
  timeContext: TimeContext;
}

/**
 * Normalizes the read-only Hosted Companion packet before it reaches Voice.
 * Invalid planner material is discarded as a unit, while current-fact
 * generation remains available with a deterministic fallback reason.
 */
export function normalizeLocalExpressionAction(
  input: NormalizeLocalExpressionActionInput,
): NormalizedLocalExpressionAction {
  const rawCurrentFact = isRecord(input.currentFact) ? input.currentFact : {};
  const currentFact = sanitizeFact(rawCurrentFact);
  const domainKeyValue = stringValue(currentFact.domain_key);
  const domainKey = domainKeyValue && ALLOWED_DOMAINS.has(domainKeyValue)
    ? domainKeyValue
    : "expense";
  const normalizedMemory = normalizeLocalMemoryContext(input.localMemoryContext, domainKey);
  const localMemoryContext = normalizedMemory.length > 0 ? { facts: normalizedMemory } : null;
  const memoryFacts = normalizedMemory as unknown as Record<string, unknown>[];
  const recentFacts = normalizeRecentFacts(input.recentFacts ?? rawCurrentFact.recent_facts);
  const candidateInput = isRecord(input.plannerCandidate) ? input.plannerCandidate : null;
  const plannerVersion = stringValue(candidateInput?.planner_version)?.slice(0, 100) ?? "local-planner-v1";
  let candidate: LocalPlannerCandidateContract | null = null;
  let plannerFallbackReason: string | null = null;
  if (input.plannerCandidate !== undefined && input.plannerCandidate !== null && !candidateInput) {
    plannerFallbackReason = "invalid_planner_candidate";
  }
  if (candidateInput) {
    const boundsReason = candidateBoundsReason(candidateInput);
    if (boundsReason) {
      plannerFallbackReason = boundsReason;
    }
    const validation = boundsReason ? null : validateLocalPlannerCandidate({
      candidate_id: candidateInput.candidate_id,
      semantic_key: candidateInput.semantic_key,
      canonical_text: candidateInput.canonical_text,
      dimension: candidateInput.dimension,
      claim_fingerprint: candidateInput.claim_fingerprint,
      // Preserve the raw array so malformed entries cannot be filtered out
      // before the public contract validator sees them.
      evidence: candidateInput.evidence,
      numbers: candidateInput.numbers,
      count_numbers: candidateInput.count_numbers,
      number_facts: candidateInput.number_facts,
    }, {
      currentFactId: stringValue(currentFact.id) ?? "current_fact",
      currentFact,
      recentFactIds: recentFacts.flatMap((item) => {
        const id = stringValue(item.id);
        return id ? [id] : [];
      }),
      recentFacts,
      memoryKeys: normalizedMemory.map((item) => item.key),
      memoryFacts,
    });
    if (validation?.ok) candidate = validation.candidate;
    else if (validation) plannerFallbackReason = validation.reason;
  }

  const rawClientLocalTime = stringValue(input.clientLocalTime);
  const clientLocalTime = rawClientLocalTime && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(rawClientLocalTime)
    ? rawClientLocalTime
    : null;
  const localPayload = isRecord(currentFact.payload_json) ? currentFact.payload_json : null;
  const occurredAt = stringValue(currentFact.occurred_at) ?? stringValue(localPayload?.occurred_at);
  const orderFinishedAt = stringValue(currentFact.order_finished_at) ?? stringValue(localPayload?.order_finished_at);
  const timeContext = buildTimeContext({
    occurredAt,
    orderFinishedAt,
    clientCapturedAt: input.clientCapturedAt ?? clientLocalTime,
    requestReceivedAt: input.requestReceivedAt,
    fallbackEventTime: recordEventFallback(currentFact),
  });
  return {
    currentFact,
    domainKey,
    recentFacts,
    localMemoryContext,
    candidate,
    plannerVersion,
    plannerFallbackReason,
    clientLocalTime,
    timeContext,
  };
}
