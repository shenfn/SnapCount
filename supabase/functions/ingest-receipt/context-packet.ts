import type { DomainSignal } from "./signals.ts";

export type MemoryOrigin = "user_explicit" | "record_derived" | "model_inferred" | "unknown";
export type MemoryAuthority = "confirmed" | "supported" | "hypothesis";
export type MemoryState = "hypothesis" | "confirmed" | "denied" | "superseded" | "expired" | "deleted";
export type MemoryClaimability = "expressible" | "context_only" | "ranking_only";

export interface NormalizedSemanticMemory {
  memoryId: string | null;
  key: string;
  type: string;
  content: string;
  origin: MemoryOrigin;
  authority: MemoryAuthority;
  state: MemoryState;
  claimability: MemoryClaimability;
  domainKey: string | null;
  entityKey: string | null;
  aliases: string[];
  confidence: number | null;
  weight: number;
  lastSeenAt: string | null;
  sourceTable: string | null;
  sourceId: string | null;
  evidence: Record<string, unknown>;
}

export interface ContextPacket {
  packet_version: "context-packet-v1";
  record_facts: Record<string, unknown>;
  selected_candidates: Array<{
    kind: string;
    fact: string;
    numbers: number[];
    count_numbers: number[];
    source: "domain_profile_signal";
  }>;
  semantic_context: Array<{
    key: string;
    type: string;
    content: string;
    claimability: MemoryClaimability;
    domain_key: string | null;
    entity_key: string | null;
  }>;
  expression_preferences: Record<string, unknown>;
  recent_expression_context: string[];
  trace: {
    domain_key: string;
    source: string;
    packet_created_at: string;
    content_fingerprint: string;
    memory_count: number;
    memory_loaded_count: number;
    memory_filtered_count: number;
    selected_memory_ids: string[];
    candidate_count: number;
    candidate_kinds: string[];
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (isRecord(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

// This is an audit fingerprint, not a security hash. It stays synchronous so
// packet assembly remains a pure, single-pass operation before the model call.
function contentFingerprint(value: unknown): string {
  let hash = 2166136261;
  for (const char of stableJson(value)) {
    hash ^= char.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function numberValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function canonical(value: string): string {
  return value.toLocaleLowerCase().replace(/[\s\-_（）()「」『』]/g, "");
}

function domainForMemory(type: string, key: string): string | null {
  if (/^(merchant|merchant_context|expense_category):/.test(key) || type === "spending_pattern" || type === "merchant_pattern") return "expense";
  if (/^income_source:/.test(key) || type === "income_pattern") return "wallet";
  if (type === "sleep_pattern") return "sleep";
  if (type === "sport_pattern") return "sport";
  if (type === "food_pattern") return "food";
  if (type === "reading_pattern") return "reading";
  return null;
}

function entityForMemory(key: string, evidence: Record<string, unknown>): { entityKey: string | null; aliases: string[] } {
  const separator = key.indexOf(":");
  const keyEntity = separator >= 0 ? key.slice(separator + 1).trim() : null;
  const evidenceEntity = stringValue(evidence.merchant)
    ?? stringValue(evidence.source_name)
    ?? stringValue(evidence.account_name)
    ?? stringValue(evidence.book_name)
    ?? stringValue(evidence.sport_type)
    ?? stringValue(evidence.entity);
  const aliases = Array.isArray(evidence.merchant_aliases)
    ? evidence.merchant_aliases.filter((item): item is string => typeof item === "string" && item.trim() !== "")
    : [];
  const entityKey = keyEntity && !["pattern", "context"].includes(keyEntity) ? keyEntity : evidenceEntity;
  return { entityKey, aliases };
}

function deriveOrigin(row: Record<string, unknown>, evidence: Record<string, unknown>): MemoryOrigin {
  const explicitOrigin = stringValue(row.origin) ?? stringValue(row.memory_origin);
  if (explicitOrigin === "user_explicit" || explicitOrigin === "record_derived" || explicitOrigin === "model_inferred") {
    return explicitOrigin;
  }
  const source = stringValue(evidence.source) ?? stringValue(evidence.source_kind);
  if (source === "user_explicit_feedback" || source === "user_explicit" || source === "user_confirmed") return "user_explicit";
  if (
    stringValue(row.source_table)
    || stringValue(row.source_id)
    || stringValue(evidence.source_table)
    || stringValue(evidence.source_record_id)
    || stringValue(evidence.record_id)
  ) return "record_derived";
  if (source === "model_inferred" || source === "model") return "model_inferred";
  return "unknown";
}

function normalizeRow(row: Record<string, unknown>): NormalizedSemanticMemory | null {
  const key = stringValue(row.key) ?? stringValue(row.memory_key);
  const content = stringValue(row.content);
  if (!key || !content) return null;
  const type = stringValue(row.type) ?? stringValue(row.memory_type) ?? "unknown";
  const evidence = isRecord(row.evidence) ? row.evidence : isRecord(row.evidence_jsonb) ? row.evidence_jsonb : {};
  const origin = deriveOrigin(row, evidence);
  const expiresAt = stringValue(row.expires_at);
  const expired = !!expiresAt && Date.parse(expiresAt) <= Date.now();
  const stateValue = stringValue(row.state) ?? stringValue(row.status);
  const state: MemoryState = stateValue === "deleted" || stateValue === "denied" || stateValue === "superseded"
    ? stateValue
    : expired
      ? "expired"
      : origin === "user_explicit"
        ? "confirmed"
        : "hypothesis";
  const authority: MemoryAuthority = origin === "user_explicit" ? "confirmed" : "hypothesis";
  const claimability: MemoryClaimability = state === "confirmed" && origin === "user_explicit"
    ? "expressible"
    : origin === "record_derived"
      ? "ranking_only"
      : "context_only";
  const entity = entityForMemory(key, evidence);
  return {
    memoryId: stringValue(row.id),
    key,
    type,
    content,
    origin,
    authority,
    state,
    claimability,
    domainKey: domainForMemory(type, key),
    entityKey: entity.entityKey,
    aliases: entity.aliases,
    confidence: numberValue(row.confidence),
    weight: numberValue(row.weight) ?? 0,
    lastSeenAt: stringValue(row.last_seen_at),
    sourceTable: stringValue(row.source_table) ?? stringValue(evidence.source_table),
    sourceId: stringValue(row.source_id) ?? stringValue(evidence.source_record_id) ?? stringValue(evidence.record_id),
    evidence,
  };
}

export function normalizeSemanticMemories(memory: Record<string, unknown> | null | undefined): NormalizedSemanticMemory[] {
  if (!memory) return [];
  const rawItems = Array.isArray(memory.long_term)
    ? memory.long_term
    : Array.isArray(memory.items)
      ? memory.items
      : [];
  return rawItems
    .filter(isRecord)
    .map(normalizeRow)
    .filter((item): item is NormalizedSemanticMemory => !!item)
    .sort((left, right) => right.weight - left.weight || (right.lastSeenAt ?? "").localeCompare(left.lastSeenAt ?? ""));
}

function recordEntityValues(recordFacts: Record<string, unknown>): string[] {
  const payload = isRecord(recordFacts.payload) ? recordFacts.payload : {};
  const payloadDishes = Array.isArray(payload.dishes)
    ? payload.dishes.flatMap((dish) => isRecord(dish) ? [dish.name] : [])
    : [];
  return [
    recordFacts.merchant_name,
    recordFacts.source_name,
    recordFacts.account_name,
    recordFacts.book_name,
    recordFacts.title,
    recordFacts.sport_type,
    payload.merchant_name,
    payload.source_name,
    payload.account_name,
    payload.book_name,
    payload.title,
    payload.sport_type,
    payload.meal_type,
    ...payloadDishes,
  ].filter((value): value is string => typeof value === "string" && value.trim() !== "");
}

function isRelevant(memory: NormalizedSemanticMemory, domainKey: string, recordFacts: Record<string, unknown>): boolean {
  if (memory.state !== "confirmed" || memory.claimability !== "expressible") return false;
  const comparableDomain = domainKey === "income" ? "wallet" : domainKey;
  if (memory.domainKey && memory.domainKey !== comparableDomain) return false;
  if (!memory.entityKey) return true;
  const entities = recordEntityValues(recordFacts).map(canonical);
  const candidates = [memory.entityKey, ...memory.aliases].map(canonical).filter(Boolean);
  return candidates.some((candidate) => entities.some((entity) => entity === candidate || entity.includes(candidate) || candidate.includes(entity)));
}

export function selectSemanticContext(
  memory: Record<string, unknown> | null | undefined,
  domainKey: string,
  recordFacts: Record<string, unknown>,
  limit = 3,
): NormalizedSemanticMemory[] {
  return normalizeSemanticMemories(memory).filter((item) => isRelevant(item, domainKey, recordFacts)).slice(0, limit);
}

export function buildContextPacket(input: {
  domainKey: string;
  recordFacts: Record<string, unknown>;
  signals: DomainSignal[];
  memory?: Record<string, unknown> | null;
  expressionPreferences?: Record<string, unknown>;
  recentExpressionContext?: string[];
}): ContextPacket {
  const normalizedMemories = normalizeSemanticMemories(input.memory);
  const semantic = normalizedMemories.filter((item) => isRelevant(item, input.domainKey, input.recordFacts)).slice(0, 3);
  const packetCreatedAt = new Date().toISOString();
  const packetCore = {
    packet_version: "context-packet-v1" as const,
    record_facts: input.recordFacts,
    selected_candidates: input.signals.map((signal) => ({
      kind: signal.kind,
      fact: signal.fact,
      numbers: signal.numbers,
      count_numbers: signal.countNumbers ?? [],
      source: "domain_profile_signal" as const,
    })),
    semantic_context: semantic.map((item) => ({
      key: item.key,
      type: item.type,
      content: item.content,
      claimability: item.claimability,
      domain_key: item.domainKey,
      entity_key: item.entityKey,
    })),
    expression_preferences: input.expressionPreferences ?? {},
    recent_expression_context: (input.recentExpressionContext ?? []).slice(0, 5),
  };
  return {
    ...packetCore,
    trace: {
      domain_key: input.domainKey,
      source: "domain_profiles+signals+semantic_memory",
      packet_created_at: packetCreatedAt,
      content_fingerprint: contentFingerprint(packetCore),
      memory_count: semantic.length,
      memory_loaded_count: normalizedMemories.length,
      memory_filtered_count: Math.max(0, normalizedMemories.length - semantic.length),
      selected_memory_ids: semantic.map((item) => item.memoryId).filter((id): id is string => !!id),
      candidate_count: input.signals.length,
      candidate_kinds: input.signals.map((signal) => signal.kind),
    },
  };
}
