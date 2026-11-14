/** Cross-client contract for local Companion context and Planner candidates.
 *
 * Keep this module dependency-free. Swift mirrors the canonicalization and
 * fingerprint rules so Hosted and BYOK can validate the same candidate.
 */

export type PlannerEvidenceKind = "current_fact" | "recent_fact" | "local_memory";
export type PlannerEvidenceSource = "local_record" | "local_memory";
export type PlannerNumberRole = "count" | "measure";

export interface PlannerEvidenceReference {
  kind: PlannerEvidenceKind;
  source: PlannerEvidenceSource;
  reference: string;
  field: string | null;
}

export interface PlannerNumberProvenance {
  value: number;
  meaning: string | null;
  role: PlannerNumberRole;
  evidence: PlannerEvidenceReference[];
}

export interface LocalPlannerCandidateContract {
  candidate_id: string;
  semantic_key: string;
  canonical_text: string;
  dimension: string;
  claim_fingerprint: string;
  evidence: PlannerEvidenceReference[];
  number_facts: PlannerNumberProvenance[];
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.entries(value as Record<string, unknown>)
      .filter(([, item]) => item !== undefined)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${canonical(item)}`)
      .join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

/** Stable, non-secret audit fingerprint. */
export function localExpressionFingerprint(value: unknown): string {
  const bytes = new TextEncoder().encode(canonical(value));
  let hash = 0xcbf29ce484222325n;
  for (const byte of bytes) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return `fnv1a64:${hash.toString(16).padStart(16, "0")}`;
}

export function localClaimFingerprint(semanticKey: string, canonicalText: string): string {
  return localExpressionFingerprint({
    semantic_key: semanticKey.trim(),
    canonical_text: canonicalText.trim(),
  });
}

function isEvidenceReference(value: unknown): value is PlannerEvidenceReference {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const item = value as Record<string, unknown>;
  return ["current_fact", "recent_fact", "local_memory"].includes(String(item.kind))
    && ["local_record", "local_memory"].includes(String(item.source))
    && typeof item.reference === "string"
    && item.reference.trim().length > 0
    && (item.field === null || typeof item.field === "string");
}

function sanitizeEvidenceReference(value: unknown): PlannerEvidenceReference | null {
  if (!isEvidenceReference(value)) return null;
  const item = value as Record<string, unknown>;
  return {
    kind: item.kind as PlannerEvidenceKind,
    source: item.source as PlannerEvidenceSource,
    reference: (item.reference as string).trim(),
    field: item.field === null ? null : (item.field as string).trim() || null,
  };
}

function numericValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function numberArray(value: unknown): { present: boolean; values: number[]; valid: boolean } {
  if (value === undefined) return { present: false, values: [], valid: true };
  if (!Array.isArray(value)) return { present: true, values: [], valid: false };
  const values = value.map((item) => item && typeof item === "object" && !Array.isArray(item)
    ? numericValue((item as Record<string, unknown>).value)
    : numericValue(item));
  return {
    present: true,
    values: values.filter((item): item is number => item !== null),
    valid: values.every((item): item is number => item !== null),
  };
}

function numericFieldValue(value: unknown, field: string | null): number | null {
  if (field && value && typeof value === "object" && !Array.isArray(value)) {
    const item = value as Record<string, unknown>;
    const direct = numericValue(item[field]);
    if (direct !== null) return direct;
    const payload = item.payload_json && typeof item.payload_json === "object"
      ? item.payload_json as Record<string, unknown>
      : item.payload && typeof item.payload === "object"
      ? item.payload as Record<string, unknown>
      : null;
    return payload ? numericValue(payload[field]) : null;
  }
  return numericValue(value);
}

function evidenceValue(
  evidence: PlannerEvidenceReference,
  options: {
    currentFact?: Record<string, unknown>;
    recentFacts?: Record<string, unknown>[];
    memoryFacts?: Record<string, unknown>[];
  },
): number | null {
  if (evidence.kind === "current_fact" && evidence.source === "local_record") {
    return numericFieldValue(options.currentFact, evidence.field);
  }
  if (evidence.kind === "recent_fact" && evidence.source === "local_record") {
    const fact = (options.recentFacts ?? []).find((item) => item.id === evidence.reference);
    return numericFieldValue(fact, evidence.field);
  }
  if (evidence.kind === "local_memory" && evidence.source === "local_memory") {
    const memory = (options.memoryFacts ?? []).find((item) => item.key === evidence.reference);
    return numericFieldValue(memory, evidence.field);
  }
  return null;
}

/**
 * Validates a candidate without trusting its prose. An unsupported candidate
 * returns a reason so callers can use deterministic fallback.
 */
export function validateLocalPlannerCandidate(
  candidate: Partial<LocalPlannerCandidateContract> & Record<string, unknown>,
  options: {
    currentFactId: string;
    currentFact?: Record<string, unknown>;
    recentFactIds?: string[];
    recentFacts?: Record<string, unknown>[];
    memoryKeys?: string[];
    memoryFacts?: Record<string, unknown>[];
  },
): { ok: true; candidate: LocalPlannerCandidateContract } | { ok: false; reason: string } {
  const candidateId = typeof candidate.candidate_id === "string" ? candidate.candidate_id.trim() : "";
  const semanticKey = typeof candidate.semantic_key === "string" ? candidate.semantic_key.trim() : "";
  const canonicalText = typeof candidate.canonical_text === "string" ? candidate.canonical_text.trim() : "";
  const dimension = typeof candidate.dimension === "string" ? candidate.dimension.trim() : "";
  const claimFingerprint = typeof candidate.claim_fingerprint === "string" ? candidate.claim_fingerprint.trim() : "";
  if (!candidateId || !semanticKey || !canonicalText || !dimension) return { ok: false, reason: "missing_candidate_identity" };
  if (!claimFingerprint || claimFingerprint !== localClaimFingerprint(semanticKey, canonicalText)) {
    return { ok: false, reason: "claim_fingerprint_mismatch" };
  }
  const rawEvidence = Array.isArray(candidate.evidence) ? candidate.evidence : [];
  const evidence = rawEvidence.flatMap((item) => {
    const sanitized = sanitizeEvidenceReference(item);
    return sanitized ? [sanitized] : [];
  });
  if (evidence.length === 0) return { ok: false, reason: "missing_evidence" };
  if (evidence.length !== rawEvidence.length) return { ok: false, reason: "invalid_evidence_reference" };
  if (evidence.some((item) => item.kind === "current_fact")
    && (!options.currentFactId || options.currentFactId.trim() === "" || options.currentFactId === "current_fact")) {
    return { ok: false, reason: "missing_current_fact_identity" };
  }
  const recentIds = new Set(options.recentFactIds ?? []);
  const memoryKeys = new Set(options.memoryKeys ?? []);
  const supported = evidence.every((item) => {
    if (item.kind === "local_memory") return item.source === "local_memory" && memoryKeys.has(item.reference);
    if (item.source !== "local_record") return false;
    if (item.kind === "current_fact") return item.reference === options.currentFactId;
    return recentIds.has(item.reference);
  });
  if (!supported) return { ok: false, reason: "unsupported_evidence_reference" };
  const rawNumberFacts = candidate.number_facts;
  if (rawNumberFacts !== undefined && !Array.isArray(rawNumberFacts)) {
    return { ok: false, reason: "invalid_number_facts" };
  }
  const numbers = numberArray(candidate.numbers);
  const countNumbers = numberArray(candidate.count_numbers);
  if (!numbers.valid || !countNumbers.valid) return { ok: false, reason: "invalid_number_array" };
  const numberFacts = Array.isArray(rawNumberFacts)
    ? rawNumberFacts.flatMap((raw) => {
      if (!raw || typeof raw !== "object") return [];
      const item = raw as Record<string, unknown>;
      const value = typeof item.value === "number" && Number.isFinite(item.value) ? item.value : null;
      if (value === null || !["count", "measure"].includes(String(item.role))) return [];
      const rawNumberEvidence = Array.isArray(item.evidence) ? item.evidence : [];
      const numberEvidence = rawNumberEvidence.flatMap((reference) => {
        const sanitized = sanitizeEvidenceReference(reference);
        return sanitized ? [sanitized] : [];
      });
      if (numberEvidence.length === 0) return [];
      if (numberEvidence.length !== rawNumberEvidence.length) return [];
      return [{
        value,
        meaning: typeof item.meaning === "string" ? item.meaning.trim() || null : null,
        role: item.role as PlannerNumberRole,
        evidence: numberEvidence,
      }];
    })
    : [];
  if (Array.isArray(rawNumberFacts) && numberFacts.length !== rawNumberFacts.length) {
    return { ok: false, reason: "invalid_number_facts" };
  }
  if ((numbers.present || countNumbers.present) && !Array.isArray(rawNumberFacts)) {
    return { ok: false, reason: "missing_number_facts" };
  }
  if (numbers.present && numbers.values.some((value) => !numberFacts.some((fact) => Math.abs(fact.value - value) < 1e-9))) {
    return { ok: false, reason: "number_without_provenance" };
  }
  if (countNumbers.present && countNumbers.values.some((value) => !numberFacts.some((fact) =>
    fact.role === "count" && Math.abs(fact.value - value) < 1e-9
  ))) return { ok: false, reason: "count_without_provenance" };
  if (numberFacts.some((item) => !item.evidence.every((reference) => evidence.some((candidateReference) =>
    reference.kind === candidateReference.kind
      && reference.source === candidateReference.source
      && reference.reference === candidateReference.reference
      && reference.field === candidateReference.field
  )))) return { ok: false, reason: "number_evidence_not_in_candidate" };
  for (const item of numberFacts) {
    for (const reference of item.evidence) {
      const actual = evidenceValue(reference, options);
      if (actual === null || Math.abs(actual - item.value) >= 1e-9) {
        return { ok: false, reason: "number_value_mismatch" };
      }
    }
  }
  return {
    ok: true,
    candidate: {
      candidate_id: candidateId,
      semantic_key: semanticKey,
      canonical_text: canonicalText,
      dimension,
      claim_fingerprint: claimFingerprint,
      evidence,
      number_facts: numberFacts,
    },
  };
}

export function evidenceReference(
  kind: PlannerEvidenceKind,
  reference: string,
  field: string | null = null,
): PlannerEvidenceReference {
  return {
    kind,
    source: kind === "local_memory" ? "local_memory" : "local_record",
    reference,
    field,
  };
}
