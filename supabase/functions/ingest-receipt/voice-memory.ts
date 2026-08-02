// @ts-ignore Shared experiment module is framework-neutral and bundled with the Edge Function.
import { normalizeEntityText } from "../../../tools/ai-validation/expression-planner/lib/entity-normalizer.mjs";

type UnknownRecord = Record<string, unknown>;

function asRecord(value: unknown): UnknownRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as UnknownRecord
    : null;
}

function asText(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export function normalizeVoiceComparableText(value: unknown): string {
  return asText(value) ? normalizeEntityText(value) : "";
}

function memoryMatchesMerchant(item: UnknownRecord, merchantComparable: string): boolean {
  const evidence = asRecord(item.evidence) ?? {};
  const aliases = Array.isArray(evidence.merchant_aliases) ? evidence.merchant_aliases : [];
  const candidates = [item.key, item.content, evidence.merchant, ...aliases];
  return candidates.some((candidate) => {
    const comparable = normalizeVoiceComparableText(candidate);
    return comparable.length > 0 && (
      comparable.includes(merchantComparable) || merchantComparable.includes(comparable)
    );
  });
}

export function selectRelevantVoiceMemories(
  memory: UnknownRecord | null | undefined,
  merchant: unknown,
  limit = 3,
): string[] {
  const merchantComparable = normalizeVoiceComparableText(merchant);
  if (!memory || !merchantComparable) return [];
  const longTerm = Array.isArray(memory.long_term) ? memory.long_term : [];
  const selected: string[] = [];
  for (const rawItem of longTerm) {
    const item = asRecord(rawItem);
    const content = item ? asText(item.content) : null;
    if (!item || !content || !memoryMatchesMerchant(item, merchantComparable)) continue;
    if (!selected.includes(content)) selected.push(content);
    if (selected.length >= limit) break;
  }
  return selected;
}

const MERCHANT_REPEAT_JUDGMENT = /(生活惯性|审视必要性|浪费|上瘾|成瘾|依赖|不必要|应该少|少花|控制消费|建议.{0,8}(减少|审视|控制|停止)|又充钱|又花钱)/i;

export function validateVoiceSemantics(
  signalKinds: string[],
  texts: Array<string | null | undefined>,
): { ok: boolean; violations: string[] } {
  if (!signalKinds.includes("merchant_repeat")) return { ok: true, violations: [] };
  const violations = texts
    .filter((text): text is string => typeof text === "string" && text.length > 0)
    .filter((text) => MERCHANT_REPEAT_JUDGMENT.test(text))
    .map((text) => `merchant_repeat_overinterpretation:${text}`);
  return { ok: violations.length === 0, violations };
}
