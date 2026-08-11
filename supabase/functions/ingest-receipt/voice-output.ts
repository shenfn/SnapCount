export interface VoiceCandidateSelectionInput {
  candidates: string[];
  recentExpressions?: string[];
  isAllowed?: (candidate: string) => boolean;
}

export interface VoiceCandidateSelection {
  text: string | null;
  rejected: Array<{ text: string; reason: string }>;
}

export function collectVoiceCandidateTexts(parsed: Record<string, unknown>): string[] {
  const raw = [
    parsed.companion_message,
    ...(Array.isArray(parsed.companion_candidates) ? parsed.companion_candidates : []),
  ];
  const seen = new Set<string>();
  return raw
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.replace(/[\r\n]+/g, " ").trim())
    .filter((item) => item !== "" && !seen.has(item) && Boolean(seen.add(item)))
    .slice(0, 3);
}

export function isStructurallyCompleteVoiceText(value: string): boolean {
  const text = value.trim();
  if (!text || /^[，。！？、；：,.!?;:]/u.test(text)) return false;
  // Keep this deliberately conservative: "的确" is a valid opening, while
  // "的3元" and "的这点甜" are high-confidence missing-subject fragments.
  return !/^的(?:这|那|几|点|份|笔|次|元|块|口|顿|餐|一|两|二|三|四|五|六|七|八|九|十|\d)/u.test(text);
}

function expressionShape(value: string): string {
  return value
    .normalize("NFKC")
    .toLocaleLowerCase()
    .replace(/[\s，。！？、；：,.!?;:“”「」『』（）()]/gu, "")
    .replace(/[一二两三四五六七八九十百千万\d.]+(?:元|块钱|块|角|毛|分)?/gu, "#");
}

function grams(value: string, width: number): string[] {
  if (value.length <= width) return value ? [value] : [];
  return Array.from({ length: value.length - width + 1 }, (_, index) => value.slice(index, index + width));
}

export function voiceExpressionSimilarity(left: string, right: string): number {
  const leftShape = expressionShape(left);
  const rightShape = expressionShape(right);
  if (!leftShape || !rightShape) return 0;
  if (leftShape === rightShape) return 1;
  const width = Math.min(leftShape.length, rightShape.length) >= 6 ? 3 : 2;
  const leftGrams = grams(leftShape, width);
  const rightGrams = grams(rightShape, width);
  const remaining = new Map<string, number>();
  for (const gram of leftGrams) remaining.set(gram, (remaining.get(gram) ?? 0) + 1);
  let overlap = 0;
  for (const gram of rightGrams) {
    const count = remaining.get(gram) ?? 0;
    if (count <= 0) continue;
    overlap += 1;
    remaining.set(gram, count - 1);
  }
  const denominator = Math.min(leftGrams.length, rightGrams.length);
  return denominator > 0 ? overlap / denominator : 0;
}

export function selectVoiceCandidate(input: VoiceCandidateSelectionInput): VoiceCandidateSelection {
  const rejected: VoiceCandidateSelection["rejected"] = [];
  const recent = (input.recentExpressions ?? []).filter((item) => item.trim());
  const seen = new Set<string>();
  for (const raw of input.candidates) {
    const text = raw.trim();
    if (!text || seen.has(text)) continue;
    seen.add(text);
    if (!isStructurallyCompleteVoiceText(text)) {
      rejected.push({ text, reason: "incomplete" });
      continue;
    }
    if (recent.some((item) => voiceExpressionSimilarity(text, item) >= 0.64)) {
      rejected.push({ text, reason: "recently_repeated" });
      continue;
    }
    if (input.isAllowed && !input.isAllowed(text)) {
      rejected.push({ text, reason: "not_allowed" });
      continue;
    }
    return { text, rejected };
  }
  return { text: null, rejected };
}
