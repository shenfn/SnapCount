import type { TimeContext, TimeDaypart } from "./time.ts";

const DAYPART_LABELS: Record<Exclude<TimeDaypart, "unknown">, string> = {
  late_night: "凌晨",
  morning: "早上",
  noon: "中午",
  afternoon: "下午",
  evening: "晚上",
  night: "深夜",
};

const DAYPART_COMPATIBILITY: Record<Exclude<TimeDaypart, "unknown">, Set<string>> = {
  late_night: new Set(["凌晨", "深夜", "夜里", "夜间"]),
  morning: new Set(["早上", "早晨", "清晨", "上午"]),
  noon: new Set(["中午"]),
  afternoon: new Set(["下午", "午后"]),
  evening: new Set(["傍晚", "晚上"]),
  night: new Set(["晚上", "深夜", "夜里", "夜间"]),
};

const DAYPART_TOKEN = /(凌晨|深夜|夜里|夜间|早上|早晨|清晨|上午|中午|下午|午后|傍晚|晚上)/g;
const DAYPART_WITH_CLOCK = /(凌晨|深夜|夜里|夜间|早上|早晨|清晨|上午|中午|下午|午后|傍晚|晚上)\s*(?:[0-2]?\d|[零〇一二两三四五六七八九十]{1,3})\s*(?:点|时)(?:\s*(?:半|[零〇一二两三四五六七八九十\d]{1,3}\s*分))?/g;
const CAPTURE_RELATION_CUE = /(补录|上传|截图|录入|记下|记录时|现在才|今天才)/;

function isCompatible(daypart: TimeDaypart, token: string): boolean {
  if (daypart === "unknown") return true;
  return DAYPART_COMPATIBILITY[daypart].has(token);
}

function mayDescribeCaptureTime(
  text: string,
  index: number,
  tokenLength: number,
  timeContext: TimeContext,
): boolean {
  if (!timeContext.is_backfill || timeContext.client_daypart === "unknown") return false;
  const start = Math.max(0, index - 8);
  const end = Math.min(text.length, index + tokenLength + 10);
  const nearby = text.slice(start, end);
  return CAPTURE_RELATION_CUE.test(nearby)
    && isCompatible(timeContext.client_daypart, text.slice(index, index + tokenLength));
}

/**
 * Keep model tone while making code-owned event-time semantics authoritative.
 * Capture-time wording remains allowed only when it is explicitly tied to a
 * backfill/upload action.
 */
export function sanitizeTextForTimeContext(
  value: string | null | undefined,
  timeContext: TimeContext | null | undefined,
): string | null {
  if (!value) return null;
  const text = value.trim();
  if (!text || !timeContext) return text || null;
  if (timeContext.event_daypart === "unknown") {
    const withoutUnsupportedClock = text
      .replace(DAYPART_WITH_CLOCK, "")
      .replace(DAYPART_TOKEN, "")
      .replace(/\s{2,}/g, " ")
      .replace(/([，。！？、])\1+/g, "$1")
      .replace(/^[，。！？、\s]+|[，、\s]+$/g, "")
      .trim();
    return withoutUnsupportedClock || null;
  }

  const expected = DAYPART_LABELS[timeContext.event_daypart];
  let result = text.replace(
    DAYPART_WITH_CLOCK,
    (match: string, token: string, offset: number) => {
      if (isCompatible(timeContext.event_daypart, token)) return match;
      if (mayDescribeCaptureTime(text, offset, token.length, timeContext)) return match;
      return expected;
    },
  );

  result = result.replace(
    DAYPART_TOKEN,
    (token: string, offset: number) => {
      if (isCompatible(timeContext.event_daypart, token)) return token;
      if (mayDescribeCaptureTime(result, offset, token.length, timeContext)) return token;
      return expected;
    },
  );

  return result.replace(new RegExp(`${expected}(?:\\s*${expected})+`, "g"), expected).trim() || null;
}
