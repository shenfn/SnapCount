import {
  evidenceReference,
  localClaimFingerprint,
} from "./local-expression-contract.ts";
import { normalizeLocalExpressionAction } from "./local-expression-action.ts";
import { buildContextPacket } from "./context-packet.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

const assertEquals = <T>(actual: T, expected: T, message: string) => {
  if (actual !== expected) throw new Error(`${message}: expected ${String(expected)}, got ${String(actual)}`);
};

const currentFact = {
  id: "fact-1",
  domain_key: "expense",
  amount: 12.8,
  title: "便利店",
  record_date: "2026-11-14",
  record_time: "08:30",
};

function candidate(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const semanticKey = "expense_current_record_context";
  const canonicalText = "已记录一笔 12.8 元支出";
  const evidence = [evidenceReference("current_fact", "fact-1", "amount")];
  return {
    candidate_id: "candidate-1",
    semantic_key: semanticKey,
    canonical_text: canonicalText,
    dimension: "current_fact",
    claim_fingerprint: localClaimFingerprint(semanticKey, canonicalText),
    evidence,
    number_facts: [{ value: 12.8, meaning: "amount", role: "measure", evidence }],
    numbers: [12.8],
    ...overrides,
  };
}

const baseInput = (plannerCandidate: unknown = candidate()) => ({
  currentFact,
  plannerCandidate,
  localMemoryContext: null,
  requestReceivedAt: "2026-11-14T01:00:00Z",
  clientCapturedAt: "2026-11-14T09:00:00+08:00",
  clientLocalTime: "2026-11-14 09:00",
});

Deno.test("Hosted action accepts a valid current-fact candidate", () => {
  const result = normalizeLocalExpressionAction(baseInput());
  assert(result.candidate !== null, "current-fact candidate should be selected");
  assertEquals(result.plannerFallbackReason, null, "valid candidate should have no fallback reason");
});

Deno.test("Hosted action accepts bounded recent-fact evidence", () => {
  const recent = {
    id: "fact-2",
    amount: 8,
  };
  const semanticKey = "expense_recent_amount";
  const text = "近期记录过 8 元支出";
  const evidence = [evidenceReference("recent_fact", "fact-2", "amount")];
  const result = normalizeLocalExpressionAction({
    ...baseInput({
      candidate_id: "candidate-recent",
      semantic_key: semanticKey,
      canonical_text: text,
      claim_fingerprint: localClaimFingerprint(semanticKey, text),
      dimension: "recent_fact",
      evidence,
      numbers: [8],
      number_facts: [{ value: 8, meaning: "recent_amount", role: "measure", evidence }],
    }),
    recentFacts: [recent],
  });
  assert(result.candidate !== null, "bounded recent candidate should be selected");
});

Deno.test("Hosted action accepts bounded local-memory evidence", () => {
  const memoryKey = "local_ai.expense.recent_30d";
  const semanticKey = "expense_memory_context";
  const text = "结合本地记忆观察消费节奏";
  const evidence = [evidenceReference("local_memory", memoryKey, "summary")];
  const result = normalizeLocalExpressionAction({
    ...baseInput({
      candidate_id: "candidate-memory",
      semantic_key: semanticKey,
      canonical_text: text,
      claim_fingerprint: localClaimFingerprint(semanticKey, text),
      dimension: "memory_context",
      evidence,
      number_facts: [],
    }),
    localMemoryContext: {
      facts: [{ key: memoryKey, type: "derived_trend", confidence: 0.9, value: "近30天重复消费" }],
    },
  });
  assert(result.candidate !== null, "bounded memory candidate should be selected");
  assertEquals(result.localMemoryContext?.facts.length, 1, "same-domain memory should be retained");
  const packet = buildContextPacket({
    domainKey: "expense",
    recordFacts: { record_type: "expense" },
    signals: [],
    localMemoryContext: result.localMemoryContext,
  });
  assertEquals(packet.local_memory_context.length, 1, "normalized memory must reach the final context packet");
});

Deno.test("Hosted action omits disabled or empty local memory", () => {
  const disabled = normalizeLocalExpressionAction({
    ...baseInput(null),
    localMemoryContext: {
      enabled: false,
      facts: [{ key: "local_ai.expense.recent_30d", type: "derived_trend", confidence: 0.9, value: "被禁用" }],
    },
  });
  assertEquals(disabled.localMemoryContext, null, "disabled memory must not reach Voice");
  const empty = normalizeLocalExpressionAction({ ...baseInput(null), localMemoryContext: { facts: [] } });
  assertEquals(empty.localMemoryContext, null, "empty memory must stay absent");
});

Deno.test("Hosted action rejects forged fingerprint and evidence", () => {
  const forged = normalizeLocalExpressionAction(baseInput(candidate({
    claim_fingerprint: "fnv1a64:0000000000000000",
  })));
  assertEquals(forged.candidate, null, "forged fingerprint must not reach Voice");
  assertEquals(forged.plannerFallbackReason, "claim_fingerprint_mismatch", "fingerprint reason must be traceable");

  const unsupported = normalizeLocalExpressionAction(baseInput(candidate({
    evidence: [evidenceReference("current_fact", "fact-other", "amount")],
  })));
  assertEquals(unsupported.candidate, null, "unsupported evidence must not reach Voice");
  assertEquals(unsupported.plannerFallbackReason, "unsupported_evidence_reference", "unsupported evidence reason must be traceable");
});

Deno.test("Hosted action strips unknown evidence fields before the planner packet", () => {
  const evidence = {
    ...evidenceReference("current_fact", "fact-1", "amount"),
    extra: "untrusted".repeat(2_000),
  };
  const result = normalizeLocalExpressionAction(baseInput(candidate({
    evidence: [evidence],
    number_facts: [{ value: 12.8, meaning: "amount", role: "measure", evidence: [evidence] }],
  })));
  assert(result.candidate !== null, "valid evidence fields should remain accepted");
  const sanitizedEvidence = result.candidate?.evidence[0] as unknown as Record<string, unknown>;
  assertEquals(Object.keys(sanitizedEvidence).sort().join(","), "field,kind,reference,source", "unknown evidence keys must be stripped");
  assertEquals(JSON.stringify(result.candidate).includes("untrusted"), false, "unknown evidence content must not reach the packet");
});

Deno.test("Hosted action rejects fabricated current-fact identity", () => {
  const missingIdentity = normalizeLocalExpressionAction({
    ...baseInput(candidate()),
    currentFact: { ...currentFact, id: undefined },
  });
  assertEquals(missingIdentity.candidate, null, "current evidence needs a real fact identity");
  assertEquals(missingIdentity.plannerFallbackReason, "missing_current_fact_identity", "missing identity reason must be deterministic");

  const syntheticIdentity = normalizeLocalExpressionAction({
    ...baseInput(candidate()),
    currentFact: { ...currentFact, id: "current_fact" },
  });
  assertEquals(syntheticIdentity.candidate, null, "synthetic identity must not authorize evidence");
  assertEquals(syntheticIdentity.plannerFallbackReason, "missing_current_fact_identity", "synthetic identity reason must be deterministic");
});

Deno.test("Hosted action rejects unsupported number provenance and malformed arrays", () => {
  const missingProvenance = normalizeLocalExpressionAction(baseInput(candidate({
    number_facts: [],
  })));
  assertEquals(missingProvenance.candidate, null, "numbers without provenance must fail closed");
  assertEquals(missingProvenance.plannerFallbackReason, "number_without_provenance", "number provenance reason must be traceable");

  const malformed = normalizeLocalExpressionAction(baseInput(candidate({
    numbers: [12.8, "bad"],
  })));
  assertEquals(malformed.candidate, null, "malformed numeric arrays must fail closed");
  assertEquals(malformed.plannerFallbackReason, "invalid_number_array", "numeric array reason must be traceable");
});

Deno.test("Hosted action bounds untrusted candidate and fact fields before Voice", () => {
  const oversizedText = normalizeLocalExpressionAction(baseInput(candidate({ canonical_text: "x".repeat(301) })));
  assertEquals(oversizedText.candidate, null, "oversized canonical text must not reach Voice");
  assertEquals(oversizedText.plannerFallbackReason, "candidate_bounds_exceeded", "candidate size reason must be deterministic");

  const oversizedEvidence = normalizeLocalExpressionAction(baseInput(candidate({
    evidence: Array.from({ length: 9 }, () => evidenceReference("current_fact", "fact-1", "amount")),
  })));
  assertEquals(oversizedEvidence.candidate, null, "oversized evidence must not reach Voice");

  const oversizedNumberEvidence = normalizeLocalExpressionAction(baseInput(candidate({
    number_facts: [{
      value: 12.8,
      meaning: "amount",
      role: "measure",
      evidence: Array.from({ length: 9 }, () => evidenceReference("current_fact", "fact-1", "amount")),
    }],
  })));
  assertEquals(oversizedNumberEvidence.candidate, null, "oversized number evidence must not reach Voice");

  const oversizedFact = normalizeLocalExpressionAction({
    ...baseInput(null),
    currentFact: {
      ...currentFact,
      summary: "untrusted".repeat(200),
      payload_json: { ignored_secret: "x".repeat(5000), sport_type: "跑步" },
    },
    recentFacts: Array.from({ length: 20 }, (_, index) => ({ id: `recent-${index}`, summary: "y".repeat(5000) })),
  });
  assert((oversizedFact.currentFact.summary as string).length <= 240, "current fact text must be clipped");
  assert(!("ignored_secret" in ((oversizedFact.currentFact.payload_json ?? {}) as Record<string, unknown>)), "unknown payload fields must be removed");
  assertEquals(oversizedFact.recentFacts.length, 12, "recent facts must be cardinality bounded");
  assert((oversizedFact.recentFacts[0].summary as string).length <= 240, "recent fact text must be clipped");
});

Deno.test("Hosted action derives event time from record date/time after invalid AI timestamps", () => {
  const result = normalizeLocalExpressionAction({
    ...baseInput(null),
    currentFact: {
      ...currentFact,
      occurred_at: "not-a-date",
      order_finished_at: "also-not-a-date",
    },
  });
  assertEquals(result.timeContext.event_time, "2026-11-14T08:30:00+08:00", "record date/time should be the event fallback");
  assertEquals(result.timeContext.event_time_source, "fallback", "fallback source should be explicit");
  assertEquals(result.timeContext.client_captured_at, "2026-11-14T09:00:00+08:00", "capture time remains separate");
});

Deno.test("Hosted action falls back to capture/reference context when event and record time are absent", () => {
  const result = normalizeLocalExpressionAction({
    ...baseInput(null),
    currentFact: { id: "fact-1", domain_key: "expense" },
  });
  assertEquals(result.timeContext.event_time, null, "missing event evidence must not invent an instant");
  assertEquals(result.timeContext.reference_time_source, "client_captured_at", "capture remains reference context");
});

Deno.test("Hosted action records a deterministic current-fact-only fallback reason", () => {
  const result = normalizeLocalExpressionAction(baseInput(candidate({
    evidence: [{ kind: "current_fact", source: "local_record", reference: "fact-1", field: "amount" }, { bad: true }],
  })));
  assertEquals(result.candidate, null, "invalid candidate must be discarded");
  assertEquals(result.plannerFallbackReason, "invalid_evidence_reference", "fallback reason must be deterministic");
});
