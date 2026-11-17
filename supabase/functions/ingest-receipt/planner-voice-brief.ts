import { EXPRESSION_PLANNER_VERSION, plannerClaimFingerprint } from "./expression-shadow-planner.ts";
import type { ContextPacketCandidate } from "./context-packet.ts";
import type { PlannerEvidenceReference } from "./local-expression-contract.ts";

export interface PlannerVoiceBrief {
  candidate_id: string;
  semantic_key: string;
  dimension: string;
  canonical_text: string;
  source_surface: "record_detail";
  planner_version: string;
  numbers: number[];
  count_numbers: number[];
  number_facts: Array<{
    value: number;
    meaning: string | null;
    role: "count" | "measure";
    evidence: PlannerEvidenceReference[];
  }>;
  evidence: PlannerEvidenceReference[];
  claim_fingerprint: string;
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function text(value: unknown, max = 500): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function finiteNumber(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function plannerNumberFacts(candidate: Record<string, unknown>): PlannerVoiceBrief["number_facts"] {
  const numbers = Array.isArray(candidate.numbers) ? candidate.numbers : [];
  return numbers.flatMap((rawNumber) => {
    const descriptor = object(rawNumber);
    const value = finiteNumber(Object.keys(descriptor).length > 0 ? descriptor.value : rawNumber);
    if (value === null) return [];
    const meaning = text(descriptor.meaning, 120) || null;
    const explicitRole = text(descriptor.role, 40);
    const role: "count" | "measure" = explicitRole === "count"
      || /(?:count|occurrence|session|streak|consecutive)/i.test(meaning ?? "")
      ? "count"
      : "measure";
    const evidence = Array.isArray(descriptor.evidence)
      ? descriptor.evidence.filter((item): item is PlannerEvidenceReference => !!item && typeof item === "object")
      : [];
    return [{ value, meaning, role, evidence }];
  });
}

export function plannerVoiceBriefFromPlan(plan: Record<string, unknown>): PlannerVoiceBrief | null {
  if (plan.status !== "auto_planned") return null;
  const renderPlan = object(object(plan.render_plans).record_detail);
  const selected = Array.isArray(renderPlan.selected) ? renderPlan.selected : [];
  const selection = selected.find((item) => text(object(item).selection_mode, 80) === "threshold");
  if (!selection) return null;
  const selectedItem = object(selection);
  const candidateId = text(selectedItem.candidate_id, 200);
  const candidates = Array.isArray(plan.candidates) ? plan.candidates : [];
  const candidate = candidates.map(object).find((item) => text(item.candidate_id, 200) === candidateId);
  if (!candidate) return null;
  const claim = object(candidate.claim);
  const semanticKey = text(claim.semantic_key, 200);
  const canonicalText = text(selectedItem.canonical_text ?? claim.canonical_text, 1000);
  if (!candidateId || !semanticKey || !canonicalText) return null;
  const numberFacts = plannerNumberFacts(candidate);
  const evidence = Array.isArray(candidate.evidence)
    ? candidate.evidence.filter((item): item is PlannerEvidenceReference => !!item && typeof item === "object")
    : [];
  if (evidence.length === 0 || numberFacts.some((item) => item.evidence.length === 0)) return null;
  return {
    candidate_id: candidateId,
    semantic_key: semanticKey,
    dimension: text(candidate.dimension, 100),
    canonical_text: canonicalText,
    source_surface: "record_detail",
    planner_version: text(plan.planner_version, 100) || EXPRESSION_PLANNER_VERSION,
    numbers: numberFacts.map((item) => item.value),
    count_numbers: numberFacts.filter((item) => item.role === "count").map((item) => item.value),
    number_facts: numberFacts,
    evidence,
    claim_fingerprint: plannerClaimFingerprint(semanticKey, canonicalText),
  };
}

export function plannerBriefContextCandidate(brief: PlannerVoiceBrief): ContextPacketCandidate {
  return {
    candidate_id: brief.candidate_id,
    semantic_key: brief.semantic_key,
    kind: brief.semantic_key,
    dimension: brief.dimension,
    fact: brief.canonical_text,
    numbers: brief.numbers,
    count_numbers: brief.count_numbers,
    number_facts: brief.number_facts,
    evidence: brief.evidence,
    source: "expression_planner",
    source_surface: brief.source_surface,
    planner_version: brief.planner_version,
    claim_fingerprint: brief.claim_fingerprint,
  };
}
