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

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
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
  return value.filter(isRecord).slice(0, 12);
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
  const currentFact = isRecord(input.currentFact) ? input.currentFact : {};
  const domainKeyValue = stringValue(currentFact.domain_key);
  const domainKey = domainKeyValue && ALLOWED_DOMAINS.has(domainKeyValue)
    ? domainKeyValue
    : "expense";
  const normalizedMemory = normalizeLocalMemoryContext(input.localMemoryContext, domainKey);
  const localMemoryContext = normalizedMemory.length > 0 ? { facts: normalizedMemory } : null;
  const memoryFacts = normalizedMemory as unknown as Record<string, unknown>[];
  const recentFacts = normalizeRecentFacts(input.recentFacts ?? currentFact.recent_facts);
  const candidateInput = isRecord(input.plannerCandidate) ? input.plannerCandidate : null;
  const plannerVersion = stringValue(candidateInput?.planner_version)?.slice(0, 100) ?? "local-planner-v1";
  let candidate: LocalPlannerCandidateContract | null = null;
  let plannerFallbackReason: string | null = null;
  if (input.plannerCandidate !== undefined && input.plannerCandidate !== null && !candidateInput) {
    plannerFallbackReason = "invalid_planner_candidate";
  }
  if (candidateInput) {
    const validation = validateLocalPlannerCandidate({
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
    if (validation.ok) candidate = validation.candidate;
    else plannerFallbackReason = validation.reason;
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
