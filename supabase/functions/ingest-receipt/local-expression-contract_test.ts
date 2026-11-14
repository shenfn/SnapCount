import {
  evidenceReference,
  localClaimFingerprint,
  validateLocalPlannerCandidate,
} from "./local-expression-contract.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

const currentEvidence = [evidenceReference("current_fact", "fact-1", "amount")];

Deno.test("local candidate contract fingerprints claims and validates current-fact evidence", () => {
  const candidate = {
    candidate_id: "local-planner-expense-1",
    semantic_key: "expense_current_record_context",
    canonical_text: "已记录一笔 12.80 元支出",
    dimension: "current_fact",
    claim_fingerprint: localClaimFingerprint("expense_current_record_context", "已记录一笔 12.80 元支出"),
    evidence: currentEvidence,
    number_facts: [{ value: 12.8, meaning: "current_record_amount", role: "measure", evidence: currentEvidence }],
  };
  const result = validateLocalPlannerCandidate(candidate, { currentFactId: "fact-1" });
  assert(result.ok, "current fact evidence should validate");
  assert(candidate.claim_fingerprint === "fnv1a64:1d29f4363af06560", "fingerprint must be stable across clients");
  assert(!validateLocalPlannerCandidate({ ...candidate, canonical_text: "篡改后的金额 99 元" }, { currentFactId: "fact-1" }).ok,
    "changing claim text must invalidate the stable fingerprint");
});

Deno.test("memory candidate cannot inherit current-fact number provenance", () => {
  const memory = evidenceReference("local_memory", "local_ai.expense.recent_30d", "summary");
  const candidate = {
    candidate_id: "local-planner-expense-memory-1",
    semantic_key: "expense_memory_context",
    canonical_text: "结合本地记忆观察消费节奏",
    dimension: "memory_context",
    claim_fingerprint: localClaimFingerprint("expense_memory_context", "结合本地记忆观察消费节奏"),
    evidence: [memory],
    number_facts: [],
  };
  assert(validateLocalPlannerCandidate(candidate, {
    currentFactId: "fact-1",
    memoryKeys: ["local_ai.expense.recent_30d"],
  }).ok, "memory candidate should validate with its bounded memory key");
  assert(!validateLocalPlannerCandidate({ ...candidate, number_facts: [{ value: 12.8, meaning: "amount", role: "measure", evidence: currentEvidence }] }, {
    currentFactId: "fact-1",
    memoryKeys: ["local_ai.expense.recent_30d"],
  }).ok, "memory candidate must not inherit current-fact number provenance");
});

Deno.test("unsupported evidence returns deterministic fallback reason", () => {
  const candidate = {
    candidate_id: "candidate-unsupported",
    semantic_key: "expense_current_record_context",
    canonical_text: "当前事实",
    dimension: "current_fact",
    claim_fingerprint: localClaimFingerprint("expense_current_record_context", "当前事实"),
    evidence: [evidenceReference("current_fact", "fact-other")],
    number_facts: [],
  };
  const result = validateLocalPlannerCandidate(candidate, { currentFactId: "fact-1" });
  assert(!result.ok && result.reason === "unsupported_evidence_reference", "unsupported evidence must be rejected");
});
