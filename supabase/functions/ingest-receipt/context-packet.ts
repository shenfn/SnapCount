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

export interface ContextPacketCandidate {
  candidate_id: string | null;
  semantic_key: string;
  kind: string;
  dimension: string | null;
  fact: string;
  numbers: number[];
  count_numbers: number[];
  number_facts: Array<{
    value: number;
    meaning: string | null;
    role: "count" | "measure";
  }>;
  source: "domain_profile_signal" | "expression_planner";
  source_surface: string | null;
  planner_version: string | null;
  claim_fingerprint?: string | null;
}

export interface ContextPacket {
  packet_version: "context-packet-v2";
  record_facts: Record<string, unknown>;
  selected_candidates: ContextPacketCandidate[];
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
    fallback_reason: string | null;
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
    ? payload.dishes.flatMap((dish) => typeof dish === "string" ? [dish] : isRecord(dish) ? [dish.name] : [])
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
  selectedCandidates?: ContextPacketCandidate[];
  memory?: Record<string, unknown> | null;
  expressionPreferences?: Record<string, unknown>;
  recentExpressionContext?: string[];
  fallbackReason?: string | null;
}): ContextPacket {
  const normalizedMemories = normalizeSemanticMemories(input.memory);
  const semantic = normalizedMemories.filter((item) => isRelevant(item, input.domainKey, input.recordFacts)).slice(0, 3);
  const packetCreatedAt = new Date().toISOString();
  const selectedCandidates = (input.selectedCandidates ?? input.signals.map((signal) => ({
    candidate_id: null,
    semantic_key: signal.kind,
    kind: signal.kind,
    dimension: null,
    fact: signal.fact,
    numbers: signal.numbers,
    count_numbers: signal.countNumbers ?? [],
    number_facts: signal.numbers.map((value) => ({
      value,
      meaning: null,
      role: (signal.countNumbers ?? []).includes(value) ? "count" as const : "measure" as const,
    })),
    source: "domain_profile_signal" as const,
    source_surface: null,
    planner_version: null,
  }))).slice(0, 2);
  const packetCore = {
    packet_version: "context-packet-v2" as const,
    record_facts: input.recordFacts,
    selected_candidates: selectedCandidates,
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
      source: selectedCandidates.some((candidate) => candidate.source === "expression_planner")
        ? "expression_planner+semantic_memory"
        : "domain_profiles+signals+semantic_memory",
      packet_created_at: packetCreatedAt,
      content_fingerprint: contentFingerprint(packetCore),
      memory_count: semantic.length,
      memory_loaded_count: normalizedMemories.length,
      memory_filtered_count: Math.max(0, normalizedMemories.length - semantic.length),
      selected_memory_ids: semantic.map((item) => item.memoryId).filter((id): id is string => !!id),
      candidate_count: selectedCandidates.length,
      candidate_kinds: selectedCandidates.map((candidate) => candidate.semantic_key),
      fallback_reason: input.fallbackReason ?? null,
    },
  };
}

type CoverageUnit = "clock" | "count" | "currency" | "day" | "distance" | "gram" | "hour" | "kcal" | "minute" | "percent" | "score" | "unknown";

interface CoverageNumberFact {
  value: number;
  meaning: string;
  role: "count" | "measure";
}

function coverageCanonical(value: string): string {
  return value.toLocaleLowerCase().replace(/[\s\-_，。！？；：、,.;:!?"'“”‘’「」『』（）()\[\]{}]/g, "");
}

function quotedCoverageEntities(value: string): string[] {
  return [...value.matchAll(/[「『“"]([^」』”"]{2,80})[」』”"]/g)]
    .map((match) => match[1].trim())
    .filter(Boolean);
}

function coverageEntities(
  candidate: ContextPacketCandidate,
  recordFacts?: Record<string, unknown>,
): string[] {
  const values = [
    ...quotedCoverageEntities(candidate.fact),
    ...(recordFacts ? recordEntityValues(recordFacts) : []),
  ];
  return [...new Set(values.map(coverageCanonical).filter((value) => value.length >= 2))];
}

function candidateNumberFacts(candidate: ContextPacketCandidate): CoverageNumberFact[] {
  const explicit = candidate.number_facts
    .filter((item) => Number.isFinite(item.value))
    .map((item) => ({
      value: item.value,
      meaning: item.meaning?.trim().toLocaleLowerCase() ?? "",
      role: item.role,
    }));
  if (explicit.length > 0) return explicit;
  return candidate.numbers
    .filter(Number.isFinite)
    .map((value) => ({
      value,
      meaning: "",
      role: candidate.count_numbers.includes(value) ? "count" as const : "measure" as const,
    }));
}

function unitNearNumber(value: string, start: number, end: number): CoverageUnit {
  const before = value.slice(Math.max(0, start - 10), start);
  const after = value.slice(end, Math.min(value.length, end + 8));
  if (/^(?:\s)*(?:千卡|大卡|kcal)/i.test(after)) return "kcal";
  if (/^(?:\s)*(?:公里|千米|km)/i.test(after)) return "distance";
  if (/^(?:\s)*(?:克|g)(?![a-z])/i.test(after)) return "gram";
  if (/^(?:\s)*分(?!钟)(?:数)?/.test(after) && /(?:评分|得分|打分|分数|score)(?:为|是|[:：])?\s*$/i.test(before)) return "score";
  if (/^(?:\s)*分钟/.test(after)) return "minute";
  if (/^(?:\s)*分(?!钟|数)/.test(after) && /(?:深睡|浅睡|rem|时长|持续|用时|相隔|间隔|过去|运动|阅读)(?:为|是|[:：])?\s*$/i.test(before)) return "minute";
  if (/^(?:\s)*(?:小时|钟头)/.test(after)) return "hour";
  if (/^(?:\s)*(?:天|日)/.test(after)) return "day";
  if (/[¥￥]\s*$/.test(before)) return "currency";
  if (/^(?:\s)*(?:元|块钱|块)/.test(after)) return "currency";
  if (/^(?:\s)*(?:%|％|百分比)/.test(after)) return "percent";
  if (/^(?:\s)*(?:分|分数)/.test(after)) return "score";
  if (/^(?:\s)*(?:次|笔|顿|晚|家|条|本|道|个|页|章|期|餐|回)/.test(after)) return "count";
  return "unknown";
}

function numericMentions(value: string): Array<{ value: number; start: number; end: number; unit: CoverageUnit }> {
  const mentions: Array<{ value: number; start: number; end: number; unit: CoverageUnit }> = [];
  for (const match of value.matchAll(/[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?/g)) {
    const parsed = Number(match[0].replace(/,/g, ""));
    const start = match.index ?? 0;
    if (!Number.isFinite(parsed)) continue;
    mentions.push({
      value: parsed,
      start,
      end: start + match[0].length,
      unit: unitNearNumber(value, start, start + match[0].length),
    });
  }
  return mentions;
}

function clockMinuteValues(value: string): number[] {
  const output: number[] = [];
  for (const match of value.matchAll(/(?:^|[^\d])([01]?\d|2[0-3])[:：]([0-5]\d)(?!\d)/g)) {
    output.push(Number(match[1]) * 60 + Number(match[2]));
  }
  return output;
}

function inferredFactUnit(fact: CoverageNumberFact, canonicalFact: string): CoverageUnit {
  const meaning = fact.meaning;
  if (/clock_minutes/.test(meaning)) return "clock";
  if (/(?:kcal|calorie)/.test(meaning)) return "kcal";
  if (/(?:distance|kilomet)/.test(meaning)) return "distance";
  if (/(?:protein_g|carb_g|fat_g|grams?)/.test(meaning)) return "gram";
  if (/(?:day_component|calendar_days?|day_count|streak.*day|consecutive.*day)/.test(meaning)) return "day";
  if (/(?:hour_component|duration_hours?)/.test(meaning)) return "hour";
  if (/(?:minute|elapsed)/.test(meaning)) return "minute";
  if (/(?:percent|ratio|rate)/.test(meaning)) return "percent";
  if (/(?:score|rating)/.test(meaning)) return "score";
  if (fact.role === "count") return "count";
  if (/(?:amount|balance|price|spend|expense|income|current_day_total|median_total|period_total)/.test(meaning)) return "currency";

  const occurrence = numericMentions(canonicalFact).find((item) => Math.abs(item.value - fact.value) < 1e-9);
  return occurrence?.unit ?? "unknown";
}

function unitCompatible(expected: CoverageUnit, actual: CoverageUnit): boolean {
  if (expected === actual) return true;
  return expected === "score" && actual === "unknown";
}

function coreNumberFacts(candidate: ContextPacketCandidate): CoverageNumberFact[] {
  const canonicalClocks = new Set(clockMinuteValues(candidate.fact));
  const canonicalNumbers = numericMentions(candidate.fact);
  return candidateNumberFacts(candidate).filter((fact) => {
    const expectedUnit = inferredFactUnit(fact, candidate.fact);
    if (expectedUnit === "clock") return canonicalClocks.has(fact.value);
    return canonicalNumbers.some((mention) =>
      Math.abs(mention.value - fact.value) < 1e-9 && unitCompatible(expectedUnit, mention.unit)
    );
  });
}

function matchedCoreNumberFacts(message: string, candidate: ContextPacketCandidate): {
  core: CoverageNumberFact[];
  matched: CoverageNumberFact[];
} {
  const core = coreNumberFacts(candidate);
  const numeric = numericMentions(message);
  const clocks = clockMinuteValues(message);
  const usedNumeric = new Set<number>();
  const usedClocks = new Set<number>();
  const matchedIndexes = new Set<number>();
  const ordered = core
    .map((fact, index) => ({ fact, index, unit: inferredFactUnit(fact, candidate.fact) }))
    .sort((left, right) => Number(left.unit === "unknown") - Number(right.unit === "unknown"));

  for (const item of ordered) {
    if (item.unit === "clock") {
      const clockIndex = clocks.findIndex((value, index) => !usedClocks.has(index) && value === item.fact.value);
      if (clockIndex < 0) continue;
      usedClocks.add(clockIndex);
      matchedIndexes.add(item.index);
      continue;
    }
    const numericIndex = numeric.findIndex((mention, index) =>
      !usedNumeric.has(index)
      && Math.abs(mention.value - item.fact.value) < 1e-9
      && unitCompatible(item.unit, mention.unit)
    );
    if (numericIndex < 0) continue;
    usedNumeric.add(numericIndex);
    matchedIndexes.add(item.index);
  }

  return {
    core,
    matched: core.filter((_, index) => matchedIndexes.has(index)),
  };
}

function matchedCoreNumberCount(message: string, candidate: ContextPacketCandidate): { matched: number; total: number } {
  const result = matchedCoreNumberFacts(message, candidate);
  return { matched: result.matched.length, total: result.core.length };
}

function hasCurrentAndBaselineNumbers(message: string, candidate: ContextPacketCandidate): boolean {
  const result = matchedCoreNumberFacts(message, candidate);
  if (result.core.length === 0) return false;
  const currentFacts = result.core.filter((fact) => /(?:^|_)(?:current|today|this)(?:_|$)/.test(fact.meaning));
  const baselineFacts = result.core.filter((fact) =>
    /(?:previous|prior|baseline|historical|median|typical)/.test(fact.meaning)
  );
  if (currentFacts.length > 0 && baselineFacts.length > 0) {
    return result.matched.some((fact) => currentFacts.includes(fact))
      && result.matched.some((fact) => baselineFacts.includes(fact));
  }
  return result.matched.length >= Math.min(2, result.core.length);
}

function hasExpectedEntity(
  message: string,
  candidate: ContextPacketCandidate,
  recordFacts?: Record<string, unknown>,
): boolean {
  const entities = coverageEntities(candidate, recordFacts);
  if (entities.length === 0) return false;
  const normalizedMessage = coverageCanonical(message);
  return entities.some((entity) => normalizedMessage.includes(entity));
}

function candidateFactsByMeaning(candidate: ContextPacketCandidate, pattern: RegExp): CoverageNumberFact[] {
  return candidateNumberFacts(candidate).filter((fact) => pattern.test(fact.meaning));
}

function numberFactMentionIndexes(message: string, fact: CoverageNumberFact, allowAbsolute = false): number[] {
  const expectedUnit = inferredFactUnit(fact, "");
  return numericMentions(message).flatMap((mention, index) => {
    const exact = Math.abs(mention.value - fact.value) < 1e-9;
    const absolute = allowAbsolute && Math.abs(Math.abs(mention.value) - Math.abs(fact.value)) < 1e-9;
    return (exact || absolute) && unitCompatible(expectedUnit, mention.unit) ? [index] : [];
  });
}

function hasLabeledNumberFact(input: {
  message: string;
  fact: CoverageNumberFact;
  label: RegExp;
  allowAbsolute?: boolean;
  radius?: number;
  labelPosition?: "before" | "around";
}): boolean {
  const mentions = numericMentions(input.message);
  const indexes = new Set(numberFactMentionIndexes(input.message, input.fact, input.allowAbsolute));
  const radius = input.radius ?? 12;
  return mentions.some((mention, index) => {
    if (!indexes.has(index)) return false;
    const before = input.message.slice(Math.max(0, mention.start - radius), mention.start);
    const context = input.labelPosition === "around"
      ? input.message.slice(Math.max(0, mention.start - radius), Math.min(input.message.length, mention.end + radius))
      : before;
    return input.label.test(context);
  });
}

function allCoreNumbersMatched(message: string, candidate: ContextPacketCandidate, minimum = 1): boolean {
  const numbers = matchedCoreNumberCount(message, candidate);
  return numbers.total >= minimum && numbers.matched === numbers.total;
}

function calendarDateKeys(value: string): string[] {
  return [...value.matchAll(/(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})(?:\s*日)?/g)]
    .map((match) => `${match[1]}-${String(Number(match[2])).padStart(2, "0")}-${String(Number(match[3])).padStart(2, "0")}`);
}

function calendarMonthKeys(value: string): string[] {
  return [...value.matchAll(/(\d{4})\s*[-/.年]\s*(\d{1,2})(?:\s*月)?/g)]
    .map((match) => `${match[1]}-${String(Number(match[2])).padStart(2, "0")}`);
}

function hasMatchingDailyAnchor(message: string, candidate: ContextPacketCandidate): boolean {
  const normalized = message.replace(/\s+/g, "");
  if (/(?:今天|今日|当天|当日)/.test(normalized)) return true;
  const expected = new Set(calendarDateKeys(candidate.fact));
  return expected.size > 0 && calendarDateKeys(message).some((key) => expected.has(key));
}

function hasMatchingMonthAnchor(message: string, candidate: ContextPacketCandidate): boolean {
  const normalized = message.replace(/\s+/g, "");
  if (/(?:本月|这个月|当月)/.test(normalized)) return true;
  const expected = new Set(calendarMonthKeys(candidate.fact));
  return expected.size > 0 && calendarMonthKeys(message).some((key) => expected.has(key));
}

function hasAmountStructureEvidence(
  message: string,
  candidate: ContextPacketCandidate,
  recordFacts?: Record<string, unknown>,
): boolean {
  const normalized = message.replace(/\s+/g, "");
  if (!/(?:金额|每笔|单笔|分别|分布)/.test(normalized)) return false;
  if (!/(?:最高|最大|最贵|高的一笔)/.test(normalized)) return false;
  if (!hasExpectedEntity(message, candidate, recordFacts)) return false;
  if (!allCoreNumbersMatched(message, candidate)) return false;
  const amounts = candidateFactsByMeaning(candidate, /transaction_amount/);
  if (amounts.length === 0) return false;
  const maximum = amounts.reduce((left, right) => right.value > left.value ? right : left);
  return hasLabeledNumberFact({ message, fact: maximum, label: /最高|最大|最贵|高的一笔/ });
}

function expectedDishEntities(candidate: ContextPacketCandidate, recordFacts?: Record<string, unknown>): string[] {
  const listed = candidate.fact.match(/道菜[：:]([^；;]+)/)?.[1]
    ?.replace(/等\s*$/, "")
    .split(/[、,，]/)
    .map(coverageCanonical)
    .filter((value) => value.length >= 2) ?? [];
  if (listed.length > 0) return [...new Set(listed)];
  if (!recordFacts) return [];
  const payload = isRecord(recordFacts.payload) ? recordFacts.payload : {};
  if (!Array.isArray(payload.dishes)) return [];
  return [...new Set(payload.dishes.flatMap((dish) => {
    if (typeof dish === "string") return [coverageCanonical(dish)];
    return isRecord(dish) && typeof dish.name === "string" ? [coverageCanonical(dish.name)] : [];
  }).filter((value) => value.length >= 2))];
}

function hasExpectedDishes(message: string, candidate: ContextPacketCandidate, recordFacts?: Record<string, unknown>): boolean {
  const dishes = expectedDishEntities(candidate, recordFacts);
  if (dishes.length === 0) return false;
  const normalized = coverageCanonical(message);
  return dishes.every((dish) => normalized.includes(dish));
}

function hasFoodCompositionEvidence(
  message: string,
  candidate: ContextPacketCandidate,
  recordFacts?: Record<string, unknown>,
): boolean {
  const normalized = message.replace(/\s+/g, "");
  if (!/(?:道菜|组成|包括|包含|搭配|蛋白质|碳水|脂肪)/.test(normalized)) return false;
  if (!hasExpectedDishes(message, candidate, recordFacts)) return false;

  const dishCounts = candidateFactsByMeaning(candidate, /(?:dish_count|recognized_dish_count)/);
  if (dishCounts.length > 0 && !dishCounts.every((fact) =>
    hasLabeledNumberFact({ message, fact, label: /(?:道菜|种菜|份菜|菜品)/, labelPosition: "around" })
  )) return false;

  const macroContracts = [
    { meaning: /protein_g/, label: /蛋白质|蛋白/ },
    { meaning: /carb_g/, label: /碳水|碳水化合物/ },
    { meaning: /fat_g/, label: /脂肪/ },
  ];
  for (const contract of macroContracts) {
    const facts = candidateFactsByMeaning(candidate, contract.meaning);
    if (facts.length > 0 && !facts.every((fact) => hasLabeledNumberFact({ message, fact, label: contract.label }))) {
      return false;
    }
  }
  return allCoreNumbersMatched(message, candidate);
}

function hasSleepQualityEvidence(message: string, candidate: ContextPacketCandidate): boolean {
  const normalized = message.replace(/\s+/g, "");
  if (!/(?:睡眠)?(?:评分|得分|分数)/.test(normalized)) return false;
  if (!/(?:设备|手表|监测)/.test(normalized)) return false;
  const current = candidateFactsByMeaning(candidate, /(?:^|_)current(?:_|).*?(?:score|rating)|(?:score|rating).*?(?:^|_)current(?:_|)/);
  const baseline = candidateFactsByMeaning(candidate, /(?:median|baseline|historical).*?(?:score|rating)|(?:score|rating).*?(?:median|baseline|historical)/);
  if (current.length > 0 && !current.every((fact) =>
    hasLabeledNumberFact({ message, fact, label: /(?:睡眠)?(?:评分|得分|分数)/ })
  )) return false;
  if (baseline.length > 0) {
    if (!/(?:历史|中位数|基线|平时|通常)/.test(normalized)) return false;
    if (!baseline.every((fact) => hasLabeledNumberFact({ message, fact, label: /历史|中位数|基线|平时|通常/ }))) return false;
  }
  return allCoreNumbersMatched(message, candidate);
}

function hasSleepStructureEvidence(message: string, candidate: ContextPacketCandidate): boolean {
  const normalized = message.replace(/\s+/g, "");
  if (!/(?:设备|手表|监测|估算)/.test(normalized)) return false;
  if (!/(?:睡眠|阶段|深睡|浅睡|rem)/i.test(normalized)) return false;
  const contracts = [
    { meaning: /deep_sleep_minutes/, label: /深睡/ },
    { meaning: /light_sleep_minutes/, label: /浅睡/ },
    { meaning: /(?:^|_)rem(?:_|).*minutes|rem_sleep_minutes/, label: /rem/i },
  ];
  let expected = 0;
  for (const contract of contracts) {
    const facts = candidateFactsByMeaning(candidate, contract.meaning);
    expected += facts.length;
    if (!facts.every((fact) => hasLabeledNumberFact({ message, fact, label: contract.label }))) return false;
  }
  return expected > 0;
}

function hasDirectedDelta(input: {
  message: string;
  fact: CoverageNumberFact;
  label: RegExp;
  positive: RegExp;
  negative: RegExp;
}): boolean {
  const mentions = numericMentions(input.message);
  const expectedUnit = inferredFactUnit(input.fact, "");
  return mentions.some((mention) => {
    if (Math.abs(Math.abs(mention.value) - Math.abs(input.fact.value)) >= 1e-9) return false;
    if (!unitCompatible(expectedUnit, mention.unit)) return false;
    const beforeBoundary = Math.max(
      input.message.lastIndexOf("，", mention.start - 1),
      input.message.lastIndexOf(",", mention.start - 1),
      input.message.lastIndexOf("；", mention.start - 1),
      input.message.lastIndexOf(";", mention.start - 1),
      input.message.lastIndexOf("。", mention.start - 1),
      input.message.lastIndexOf("、", mention.start - 1),
    );
    const boundaryIndexes = ["，", ",", "；", ";", "。", "、"]
      .map((separator) => input.message.indexOf(separator, mention.end))
      .filter((index) => index >= 0);
    const afterBoundary = boundaryIndexes.length > 0 ? Math.min(...boundaryIndexes) : input.message.length;
    const around = input.message.slice(beforeBoundary + 1, afterBoundary);
    if (!input.label.test(around)) return false;
    if (input.fact.value > 0) return input.positive.test(around) && !input.negative.test(around);
    if (input.fact.value < 0) return input.negative.test(around) && !input.positive.test(around);
    return false;
  });
}

function hasTimingBaselineEvidence(message: string, candidate: ContextPacketCandidate): boolean {
  const normalized = message.replace(/\s+/g, "");
  if (!/(?:典型|平时|通常|作息|基线)/.test(normalized)) return false;
  const contracts = [
    { meaning: /sleep_start_delta_minutes/, label: /入睡|睡着/ },
    { meaning: /wake_delta_minutes/, label: /醒来|起床/ },
  ];
  let expected = 0;
  for (const contract of contracts) {
    const facts = candidateFactsByMeaning(candidate, contract.meaning);
    expected += facts.length;
    if (!facts.every((fact) => hasDirectedDelta({
      message,
      fact,
      label: contract.label,
      positive: /晚|延后|推迟/,
      negative: /早|提前/,
    }))) return false;
  }
  return expected > 0;
}

function hasWalletStateChangeEvidence(
  message: string,
  candidate: ContextPacketCandidate,
  recordFacts?: Record<string, unknown>,
): boolean {
  const normalized = message.replace(/\s+/g, "");
  if (!/(?:余额|待还金额|账户)/.test(normalized)) return false;
  if (!/(?:上次|前次|之前|变化|增加|减少|上升|下降|多了|少了)/.test(normalized)) return false;
  const accountEntities = recordFacts ? [
    recordFacts.account_name,
    isRecord(recordFacts.payload) ? recordFacts.payload.account_name : null,
  ].filter((value): value is string => typeof value === "string" && value.trim() !== "") : [];
  if (accountEntities.length > 0) {
    const canonicalMessage = coverageCanonical(message);
    if (!accountEntities.some((entity) => canonicalMessage.includes(coverageCanonical(entity)))) return false;
  }

  const current = candidateFactsByMeaning(candidate, /(?:current_wallet|current_account|current_balance|wallet_current)/);
  if (current.length === 0 || !current.every((fact) =>
    hasLabeledNumberFact({ message, fact, label: /当前|现在|目前|余额|待还/ })
  )) return false;

  const deltas = candidateFactsByMeaning(candidate, /(?:wallet_delta|balance_delta|change_amount|delta_amount)/);
  const previous = candidateFactsByMeaning(candidate, /(?:previous_wallet|previous_account|previous_balance|wallet_previous)/);
  const deltaMatched = deltas.length > 0 && deltas.every((fact) => hasDirectedDelta({
    message,
    fact,
    label: /变化|增加|减少|上升|下降|多了|少了|较上次|比上次/,
    positive: /增加|上升|多了|涨|\+/,
    negative: /减少|下降|少了|降|-/,
  }));
  const previousMatched = previous.length > 0 && previous.every((fact) =>
    hasLabeledNumberFact({
      message,
      fact,
      label: /(?:上次|前次|之前)(?:的)?(?:余额|待还金额|金额)?(?:是|为|[:：])?\s*$/,
    })
  );
  return deltaMatched || previousMatched;
}

function hasScopedFirstOccurrence(message: string): boolean {
  const normalized = message.replace(/\s+/g, "");
  return /(?:本周|这周|上周|本月|这个月|上月|今天|今日|当天|近\d+天|最近).{0,10}(?:第一次|首次|头一回|初次)/.test(normalized);
}

function hasDurationEvidence(message: string, candidate: ContextPacketCandidate): boolean {
  const result = matchedCoreNumberCount(message, candidate);
  return result.total > 0 && result.matched === result.total;
}

function hasComparisonEvidence(message: string, candidate: ContextPacketCandidate): boolean {
  const normalized = message.replace(/\s+/g, "");
  const dimension = candidate.dimension ?? "";
  const periodComparison = /period_comparison/.test(dimension)
    || /week_to_date|month_to_date|same_period/.test(candidate.semantic_key);
  const currentAnchor = periodComparison
    ? /(?:本周|这周|本月|这个月|本期|当前周期)/.test(normalized)
    : /(?:本次|这次|这顿|当前|今天|当天|本周|这周|本月|这个月|\d{4}[-/.年]\d{1,2})/.test(normalized);
  const baselineAnchor = periodComparison
    ? /(?:上周|上月|同期|上一周期)/.test(normalized)
    : /(?:历史|中位数|平均|基线|平时|通常|典型|同期|上周|上月|相比|对比|较)/.test(normalized);
  return currentAnchor && baselineAnchor && hasCurrentAndBaselineNumbers(message, candidate);
}

function hasCoverageEvidence(input: {
  companionMessage: string;
  candidate: ContextPacketCandidate;
  recordFacts?: Record<string, unknown>;
}): boolean {
  const { companionMessage: message, candidate, recordFacts } = input;
  const normalized = message.replace(/\s+/g, "");
  const dimension = candidate.dimension?.trim().toLocaleLowerCase() ?? "";
  const semanticKey = candidate.semantic_key.toLocaleLowerCase();

  if (dimension === "first_occurrence" || semanticKey.includes("first_occurrence")) {
    return /(?:第一次|首次|头一回|初次)/.test(normalized)
      && !hasScopedFirstOccurrence(normalized)
      && hasExpectedEntity(message, candidate, recordFacts);
  }

  if (dimension === "record_context") {
    const semanticAnchor = /(?:记录于|已记录|记下|这笔|本次|这次|支出|收入|早餐|午餐|晚餐|夜宵)/.test(normalized);
    const numbers = matchedCoreNumberCount(message, candidate);
    const factClocks = clockMinuteValues(candidate.fact);
    const messageClocks = new Set(clockMinuteValues(message));
    const clockMatched = factClocks.length > 0 && factClocks.some((value) => messageClocks.has(value));
    return semanticAnchor && (numbers.matched > 0 || clockMatched || hasExpectedEntity(message, candidate, recordFacts));
  }

  if (dimension === "daily_aggregation") {
    return hasMatchingDailyAnchor(message, candidate)
      && hasExpectedEntity(message, candidate, recordFacts)
      && allCoreNumbersMatched(message, candidate, 2);
  }

  if (dimension === "amount_structure") {
    return hasAmountStructureEvidence(message, candidate, recordFacts);
  }

  if (dimension === "record_composition") {
    return hasFoodCompositionEvidence(message, candidate, recordFacts);
  }

  if (dimension === "recurrence") {
    const historyAnchor = /(?:历史|以前|过去|再次|又|复现|出现|常见|熟悉)/.test(normalized);
    return historyAnchor
      && hasExpectedEntity(message, candidate, recordFacts)
      && allCoreNumbersMatched(message, candidate);
  }

  if (dimension === "quality") {
    return hasSleepQualityEvidence(message, candidate);
  }

  if (dimension === "sleep_structure") {
    return hasSleepStructureEvidence(message, candidate);
  }

  if (dimension === "source_pattern") {
    const occurrenceAnchor = /(?:出现|已有|已经|已是|次数|第\d+次)/.test(normalized);
    return hasMatchingMonthAnchor(message, candidate)
      && occurrenceAnchor
      && /(?:收入|到账|收到|进账)/.test(normalized)
      && hasExpectedEntity(message, candidate, recordFacts)
      && allCoreNumbersMatched(message, candidate);
  }

  if (dimension === "state_change") {
    return hasWalletStateChangeEvidence(message, candidate, recordFacts);
  }

  if (dimension === "timing_baseline") {
    return hasTimingBaselineEvidence(message, candidate);
  }

  if (dimension === "repeat_interval") {
    return /(?:距离|相隔|间隔|隔了|过去).{0,12}(?:上一次|上次|上一笔|前一次|前一笔)|(?:上一次|上次|上一笔|前一次|前一笔).{0,12}(?:距离|相隔|间隔|隔了|过去)/.test(normalized)
      && !/(?:最早|最晚|首笔|末笔)/.test(normalized)
      && hasDurationEvidence(message, candidate);
  }

  if (dimension === "temporal_rhythm") {
    const candidateHasSleepWindow = /(?:入睡|睡着)/.test(candidate.fact) && /(?:醒来|起床)/.test(candidate.fact);
    if (candidateHasSleepWindow) {
      const expectedClocks = clockMinuteValues(candidate.fact);
      const actualClocks = new Set(clockMinuteValues(message));
      return /(?:入睡|睡着)/.test(normalized)
        && /(?:醒来|起床)/.test(normalized)
        && expectedClocks.length > 0
        && expectedClocks.every((value) => actualClocks.has(value));
    }
    const boundarySpan = /(?:首笔|最早)/.test(candidate.fact) && /(?:末笔|最晚)/.test(candidate.fact);
    if (boundarySpan) {
      return /(?:首笔|最早)/.test(normalized)
        && /(?:末笔|最晚)/.test(normalized)
        && hasDurationEvidence(message, candidate);
    }
    return /(?:时间|时段|节奏|入睡|醒来|起床|相隔|间隔)/.test(normalized)
      && hasDurationEvidence(message, candidate);
  }

  if (dimension === "personal_baseline" || dimension === "meal_baseline") {
    const currentAnchor = /(?:本次|这次|这顿|当前|今天|当天)/.test(normalized);
    const baselineAnchor = /(?:历史|同餐次|中位数|平均|基线|平时|通常|典型)/.test(normalized);
    return currentAnchor && baselineAnchor && hasCurrentAndBaselineNumbers(message, candidate);
  }

  if (dimension.includes("comparison") || semanticKey.includes("_vs_")) {
    return hasComparisonEvidence(message, candidate);
  }

  if (dimension === "period_aggregation") {
    const numbers = matchedCoreNumberCount(message, candidate);
    return /(?:本周|这周|本月|这个月|本期|累计)/.test(normalized)
      && numbers.total > 0
      && numbers.matched >= Math.min(2, numbers.total);
  }

  if (dimension === "current_fact") {
    const currentAnchor = /(?:本次|这次|当前|余额|收入|支出|消费|睡眠|入睡|运动|跑|阅读|读了|热量|时长|距离|评分|待还)/.test(normalized);
    const numbers = matchedCoreNumberCount(message, candidate);
    return currentAnchor && numbers.matched > 0;
  }

  return false;
}

export function resolveExpressedSemanticKey(input: {
  declaredSemanticKey?: unknown;
  companionMessage?: unknown;
  selectedCandidates: ContextPacketCandidate[];
  recordFacts?: Record<string, unknown>;
}): string | null {
  const declared = typeof input.declaredSemanticKey === "string"
    ? input.declaredSemanticKey.trim()
    : "";
  const companion = typeof input.companionMessage === "string"
    ? input.companionMessage.trim()
    : "";
  if (!declared || !companion) return null;
  const candidate = input.selectedCandidates.find((item) => item.semantic_key === declared);
  if (!candidate) return null;
  return hasCoverageEvidence({
    companionMessage: companion,
    candidate,
    recordFacts: input.recordFacts,
  }) ? declared : null;
}
