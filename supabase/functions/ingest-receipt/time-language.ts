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

const DAYPART_TOKEN = /(?:凌晨|深夜|夜里|夜间|早上|早晨|清晨|上午|中午|下午|午后|傍晚|晚上)/g;
const DAYPART_WITH_CLOCK = /(凌晨|深夜|夜里|夜间|早上|早晨|清晨|上午|中午|下午|午后|傍晚|晚上)\s*(?:[0-2]?\d|[零〇一二两三四五六七八九十]{1,3})\s*(?:点|时)(?:\s*(?:半|[零〇一二两三四五六七八九十\d]{1,3}\s*分))?/g;
const CLOCK_NUMBER_PATTERN = "(?:[0-2]?\\d|[零〇一二两三四五六七八九十]{1,3})";
const NATURAL_CLOCK_PHRASE = new RegExp(
  `(?:(凌晨|深夜|夜里|夜间|早上|早晨|清晨|上午|中午|下午|午后|傍晚|晚上)\\s*)?`
    + `(快|将近|刚过|差不多)?\\s*(${CLOCK_NUMBER_PATTERN})\\s*(?:点|时)`
    + `(?:\\s*(?:(半)|(多)|(${CLOCK_NUMBER_PATTERN})\\s*分))?`
    + `\\s*(左右|前后)?\\s*(了|啦)?`,
  "g",
);
const CAPTURE_RELATION_CUE = /(补录|上传|截图|录入|记下|记录时|现在才|今天才)/;

const CHINESE_DIGIT: Record<string, number> = {
  零: 0,
  〇: 0,
  一: 1,
  二: 2,
  两: 2,
  三: 3,
  四: 4,
  五: 5,
  六: 6,
  七: 7,
  八: 8,
  九: 9,
};
const NEAR_HOUR_WINDOW_MINUTES = 20;
const AROUND_CLOCK_TOLERANCE_MINUTES = 10;
const EXACT_CLOCK_TOLERANCE_MINUTES = 5;

function parseClockNumber(value: string | undefined): number | null {
  if (!value) return null;
  if (/^\d+$/.test(value)) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  if (!value.includes("十")) return value.length === 1 ? CHINESE_DIGIT[value] ?? null : null;
  const [tensText, onesText] = value.split("十", 2);
  const tens = tensText ? CHINESE_DIGIT[tensText] : 1;
  const ones = onesText ? CHINESE_DIGIT[onesText] : 0;
  if (tens === undefined || ones === undefined) return null;
  return tens * 10 + ones;
}

function localMinuteOfDay(value: string | null | undefined): number | null {
  const match = value?.match(/^(\d{1,2}):(\d{2})/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isInteger(hour) || hour < 0 || hour > 23 || !Number.isInteger(minute) || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

function candidateClockHours(hour: number): number[] {
  if (!Number.isInteger(hour) || hour < 0 || hour > 24) return [];
  if (hour === 24 || hour === 0) return [0];
  if (hour > 12) return [hour];
  if (hour === 12) return [0, 12];
  return [hour, hour + 12];
}

function circularForwardMinutes(from: number, to: number): number {
  return (to - from + 1440) % 1440;
}

function clockPhraseContainsMinute(input: {
  actualMinute: number;
  targetHour: number;
  modifier?: string;
  half?: string;
  more?: string;
  minuteText?: string;
  around?: string;
}): boolean {
  const target = input.targetHour * 60;
  const forward = circularForwardMinutes(target, input.actualMinute);
  const backward = circularForwardMinutes(input.actualMinute, target);
  if (input.modifier === "快" || input.modifier === "将近") {
    return backward >= 1 && backward <= NEAR_HOUR_WINDOW_MINUTES;
  }
  if (input.modifier === "刚过") return forward <= NEAR_HOUR_WINDOW_MINUTES;

  const explicitMinute = input.half ? 30 : parseClockNumber(input.minuteText);
  if (explicitMinute !== null) {
    if (explicitMinute < 0 || explicitMinute > 59) return false;
    const expected = (target + explicitMinute) % 1440;
    const distance = Math.min(
      circularForwardMinutes(expected, input.actualMinute),
      circularForwardMinutes(input.actualMinute, expected),
    );
    return distance <= (input.half || input.around
      ? AROUND_CLOCK_TOLERANCE_MINUTES
      : EXACT_CLOCK_TOLERANCE_MINUTES);
  }
  if (input.more) return forward <= 59;
  if (input.modifier === "差不多" || input.around) {
    return Math.min(forward, backward) <= AROUND_CLOCK_TOLERANCE_MINUTES;
  }
  return forward <= 59;
}

function nearbyCaptureCue(text: string, index: number, length: number): boolean {
  const start = Math.max(0, index - 8);
  const end = Math.min(text.length, index + length + 10);
  return CAPTURE_RELATION_CUE.test(text.slice(start, end));
}

function sanitizeNaturalClockPhrases(text: string, timeContext: TimeContext): string {
  return text.replace(
    NATURAL_CLOCK_PHRASE,
    (
      match: string,
      daypart: string | undefined,
      modifier: string | undefined,
      hourText: string,
      half: string | undefined,
      more: string | undefined,
      minuteText: string | undefined,
      around: string | undefined,
      particle: string | undefined,
      offset: number,
    ) => {
      const hour = parseClockNumber(hourText);
      if (hour === null) return match;
      const hasExplicitClockCue = Boolean(daypart || modifier || half || more || minuteText || around || particle);
      if (!hasExplicitClockCue) return match;

      const describesCapture = timeContext.is_backfill
        && nearbyCaptureCue(text, offset, match.length)
        && (!daypart || isCompatible(timeContext.client_daypart, daypart));
      const actualMinute = describesCapture
        ? localMinuteOfDay(timeContext.client_local_time)
        : localMinuteOfDay(timeContext.event_local_time);
      const valid = actualMinute !== null && candidateClockHours(hour).some(targetHour =>
        clockPhraseContainsMinute({ actualMinute, targetHour, modifier, half, more, minuteText, around })
      );
      if (valid) return match;

      const referenceDaypart = describesCapture ? timeContext.client_daypart : timeContext.event_daypart;
      return referenceDaypart === "unknown" ? "" : DAYPART_LABELS[referenceDaypart];
    },
  );
}

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
  const clockSanitizedText = sanitizeNaturalClockPhrases(text, timeContext);
  if (timeContext.event_daypart === "unknown") {
    const withoutUnsupportedClock = clockSanitizedText
      .replace(DAYPART_WITH_CLOCK, "")
      .replace(DAYPART_TOKEN, "")
      .replace(/\s{2,}/g, " ")
      .replace(/([，。！？、])\1+/g, "$1")
      .replace(/^[，。！？、\s]+|[，、\s]+$/g, "")
      .trim();
    return withoutUnsupportedClock || null;
  }

  const expected = DAYPART_LABELS[timeContext.event_daypart];
  let result = clockSanitizedText.replace(
    DAYPART_WITH_CLOCK,
    (match: string, token: string, offset: number) => {
      if (isCompatible(timeContext.event_daypart, token)) return match;
      if (mayDescribeCaptureTime(clockSanitizedText, offset, token.length, timeContext)) return match;
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
