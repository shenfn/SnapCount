export interface NotificationClaimIdentity {
  semantic_key: string | null | undefined;
  claim_fingerprint: string | null | undefined;
}

export interface NotificationSlotGroup {
  /**
   * Groups may only suppress one another inside the same presentation slot.
   * The fixed receipt result therefore remains independent from an insight.
   */
  slot: string;
  text: string | null | undefined;
  claim?: NotificationClaimIdentity | null;
}

export interface MergePlannerNotificationOptions {
  companion_claim?: NotificationClaimIdentity | null;
  planner_claim?: NotificationClaimIdentity | null;
}

const EXPRESSION_CLAIM_SLOT = "expression_claim";
const FIXED_RECEIPT_SLOT = "fixed_receipt_result";
const STABLE_FACT_SLOT = "stable_shortcut_fact";

function normalizedTextLines(value: string | null | undefined): string[] {
  return String(value ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

function claimCompositionKey(group: NotificationSlotGroup): string | null {
  const slot = group.slot.trim();
  const semanticKey = group.claim?.semantic_key?.trim();
  const claimFingerprint = group.claim?.claim_fingerprint?.trim();
  if (!slot || !semanticKey || !claimFingerprint) return null;
  return JSON.stringify([slot, semanticKey, claimFingerprint]);
}

export function uniqueNotificationLines(
  lines: Array<string | null | undefined>,
): string[] {
  const seen = new Set<string>();
  const unique: string[] = [];

  for (const value of lines) {
    const line = value?.trim();
    if (!line) continue;

    const key = line.replace(/\s+/g, " ");
    if (seen.has(key)) continue;

    seen.add(key);
    unique.push(line);
  }

  return unique;
}

/**
 * Compose notification groups in display order.
 *
 * Claim-level de-duplication is deliberately fail-closed: a group is removed
 * only when its slot, semantic key, and claim fingerprint all match an earlier
 * group. Missing or mismatched fingerprints must not hide a deterministic
 * Planner fact. Exact visible-line de-duplication is applied only after the
 * claim composition step.
 */
export function composeNotificationSlots(
  groups: NotificationSlotGroup[],
): string[] {
  const seenClaims = new Set<string>();
  const selectedGroups: NotificationSlotGroup[] = [];

  for (const group of groups) {
    if (normalizedTextLines(group.text).length === 0) continue;

    const claimKey = claimCompositionKey(group);
    if (claimKey && seenClaims.has(claimKey)) continue;
    if (claimKey) seenClaims.add(claimKey);
    selectedGroups.push(group);
  }

  return uniqueNotificationLines(
    selectedGroups.flatMap((group) => normalizedTextLines(group.text)),
  );
}

export function mergePlannerNotification(
  plannerMessage: string | null | undefined,
  fallbackNotification: string,
  companionMessage?: string | null,
  options: MergePlannerNotificationOptions = {},
): string {
  const fallbackLines = normalizedTextLines(fallbackNotification);
  return composeNotificationSlots([
    {
      slot: EXPRESSION_CLAIM_SLOT,
      text: companionMessage,
      claim: options.companion_claim,
    },
    {
      slot: EXPRESSION_CLAIM_SLOT,
      text: plannerMessage,
      claim: options.planner_claim,
    },
    {
      slot: FIXED_RECEIPT_SLOT,
      text: fallbackLines[0],
    },
    ...fallbackLines.slice(1).map((line) => ({
      slot: STABLE_FACT_SLOT,
      text: line,
    })),
  ]).join("\n");
}
