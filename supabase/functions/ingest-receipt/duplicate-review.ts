export type FinancialRecordType = "expense" | "income";

export type FinancialReferenceTable = "transactions" | "income_records" | "staging_records";

export type TimePrecision = "datetime" | "date" | "none";

export interface FinancialPerceptualCandidate {
  id: string;
  perceptualHash: string | null;
  recordType: FinancialRecordType;
  referenceTable: FinancialReferenceTable;
  referenceId: string;
  amount: number | null;
  merchantOrSource: string | null;
  platform?: string | null;
  paymentMethod?: string | null;
  occurredAt?: string | null;
  occurredDate?: string | null;
  timePrecision?: TimePrecision;
  createdAt?: string | null;
}

export interface CurrentFinancialFacts {
  recordType: FinancialRecordType;
  amount: number | null;
  merchantOrSource: string | null;
  platform?: string | null;
  paymentMethod?: string | null;
  occurredAt?: string | null;
  occurredDate?: string | null;
  timePrecision?: TimePrecision;
}

export interface RankedPerceptualCandidate extends FinancialPerceptualCandidate {
  distance: number;
}

const GENERIC_INCOME_NAMES = new Set(["income", "截图识别收入", "收入", "收入记录"]);

export function hammingDistanceHex(a: string | null, b: string | null): number | null {
  if (!a || !b || a.length !== b.length || !/^[0-9a-f]+$/i.test(a) || !/^[0-9a-f]+$/i.test(b)) {
    return null;
  }

  let distance = 0;
  for (let index = 0; index < a.length; index += 1) {
    const xor = Number.parseInt(a[index], 16) ^ Number.parseInt(b[index], 16);
    distance += xor.toString(2).replace(/0/g, "").length;
  }
  return distance;
}

function normalizedLabel(value: string | null | undefined): string {
  return String(value ?? "").trim().replace(/\s+/g, " ").toLocaleLowerCase();
}

function sameAmount(a: number | null, b: number | null): boolean {
  return a !== null && b !== null && Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) <= 0.01;
}

function dateKey(value: string | null | undefined): string | null {
  const match = String(value ?? "").match(/^(\d{4}-\d{2}-\d{2})/);
  return match?.[1] ?? null;
}

function sameOccurrence(
  current: CurrentFinancialFacts,
  reference: FinancialPerceptualCandidate,
  windowMs: number,
): boolean {
  const currentPrecision = current.timePrecision ?? (current.occurredAt ? "datetime" : current.occurredDate ? "date" : "none");
  const referencePrecision = reference.timePrecision ?? (reference.occurredAt ? "datetime" : reference.occurredDate ? "date" : "none");

  if (currentPrecision === "datetime" && referencePrecision === "datetime") {
    const currentTime = Date.parse(String(current.occurredAt));
    const referenceTime = Date.parse(String(reference.occurredAt));
    if (Number.isFinite(currentTime) && Number.isFinite(referenceTime)) {
      return Math.abs(currentTime - referenceTime) <= windowMs;
    }
  }

  const currentDate = dateKey(current.occurredDate ?? current.occurredAt);
  const referenceDate = dateKey(reference.occurredDate ?? reference.occurredAt);
  if (currentDate && referenceDate) return currentDate === referenceDate;

  return true;
}

function sameIdentity(current: CurrentFinancialFacts, reference: FinancialPerceptualCandidate): boolean {
  const currentName = normalizedLabel(current.merchantOrSource);
  const referenceName = normalizedLabel(reference.merchantOrSource);

  if (current.recordType === "income") {
    if (currentName && referenceName && currentName === referenceName) return true;
    return GENERIC_INCOME_NAMES.has(currentName) && GENERIC_INCOME_NAMES.has(referenceName);
  }

  if (currentName && referenceName) return currentName === referenceName;

  const currentPlatform = normalizedLabel(current.platform);
  const referencePlatform = normalizedLabel(reference.platform);
  const currentPayment = normalizedLabel(current.paymentMethod);
  const referencePayment = normalizedLabel(reference.paymentMethod);
  return Boolean(
    currentPlatform && referencePlatform && currentPlatform === referencePlatform
    && currentPayment && referencePayment && currentPayment === referencePayment
  );
}

function sourcePriority(candidate: FinancialPerceptualCandidate): number {
  return candidate.referenceTable === "staging_records" ? 1 : 0;
}

export function rankPerceptualCandidates(
  perceptualHash: string | null,
  candidates: FinancialPerceptualCandidate[],
  maxDistance = 5,
): RankedPerceptualCandidate[] {
  return candidates
    .map((candidate) => ({
      ...candidate,
      distance: hammingDistanceHex(perceptualHash, candidate.perceptualHash),
    }))
    .filter((candidate): candidate is RankedPerceptualCandidate => (
      candidate.distance !== null
      && candidate.distance <= maxDistance
      && Boolean(candidate.referenceId)
    ))
    .sort((left, right) => {
      if (left.distance !== right.distance) return left.distance - right.distance;
      const priorityDelta = sourcePriority(left) - sourcePriority(right);
      if (priorityDelta !== 0) return priorityDelta;
      return Date.parse(right.createdAt ?? "") - Date.parse(left.createdAt ?? "");
    });
}

export function findLikelyFinancialDuplicate(
  perceptualHash: string | null,
  current: CurrentFinancialFacts,
  candidates: FinancialPerceptualCandidate[],
  options: { maxDistance?: number; timeWindowMs?: number } = {},
): RankedPerceptualCandidate | null {
  const maxDistance = options.maxDistance ?? 5;
  const timeWindowMs = options.timeWindowMs ?? 10 * 60 * 1000;

  for (const candidate of rankPerceptualCandidates(perceptualHash, candidates, maxDistance)) {
    if (candidate.recordType !== current.recordType) continue;
    if (!sameAmount(current.amount, candidate.amount)) continue;
    if (!sameIdentity(current, candidate)) continue;
    if (!sameOccurrence(current, candidate, timeWindowMs)) continue;
    return candidate;
  }

  return null;
}
