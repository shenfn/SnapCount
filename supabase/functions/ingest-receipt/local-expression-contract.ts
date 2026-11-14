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

function evidenceForNumber(value: number, provenance: PlannerNumberProvenance[]): PlannerEvidenceReference[] {
  return provenance
    .filter((item) => Number.isFinite(item.value) && Math.abs(item.value - value) < 1e-9)
    .flatMap((item) => item.evidence)
    .filter(isEvidenceReference);
}

/**
 * Validates a candidate without trusting its prose. An unsupported candidate
 * returns a reason so callers can use deterministic fallback.
 */
export function validateLocalPlannerCandidate(
  candidate: Partial<LocalPlannerCandidateContract> & Record<string, unknown>,
  options: { currentFactId: string; recentFactIds?: string[]; memoryKeys?: string[] },
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
  const evidence = rawEvidence.filter(isEvidenceReference);
  if (evidence.length === 0) return { ok: false, reason: "missing_evidence" };
  if (evidence.length !== rawEvidence.length) return { ok: false, reason: "invalid_evidence_reference" };
  const recentIds = new Set(options.recentFactIds ?? []);
  const memoryKeys = new Set(options.memoryKeys ?? []);
  const supported = evidence.every((item) => {
    if (item.kind === "local_memory") return item.source === "local_memory" && memoryKeys.has(item.reference);
    if (item.source !== "local_record") return false;
    if (item.kind === "current_fact") return item.reference === options.currentFactId;
    return recentIds.has(item.reference);
  });
  if (!supported) return { ok: false, reason: "unsupported_evidence_reference" };
  const numberFacts = Array.isArray(candidate.number_facts)
    ? candidate.number_facts.flatMap((raw) => {
      if (!raw || typeof raw !== "object") return [];
      const item = raw as Record<string, unknown>;
      const value = typeof item.value === "number" ? item.value : Number(item.value);
      if (!Number.isFinite(value) || !["count", "measure"].includes(String(item.role))) return [];
      const rawNumberEvidence = Array.isArray(item.evidence) ? item.evidence : [];
      const numberEvidence = rawNumberEvidence.filter(isEvidenceReference);
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
  if (numberFacts.some((item) => !item.evidence.every((reference) => evidence.some((candidateReference) =>
    reference.kind === candidateReference.kind
      && reference.source === candidateReference.source
      && reference.reference === candidateReference.reference
      && reference.field === candidateReference.field
  )))) return { ok: false, reason: "number_evidence_not_in_candidate" };
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
