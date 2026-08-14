import type { TimeContext, TimeDaypart } from "./time.ts";

const DAYPART_COMPATIBILITY: Record<Exclude<TimeDaypart, "unknown">, Set<string>> = {
  late_night: new Set(["凌晨", "深夜", "夜里", "夜间"]),
  morning: new Set(["早上", "早晨", "清晨", "上午"]),
  noon: new Set(["中午"]),
  afternoon: new Set(["下午", "午后"]),
  evening: new Set(["傍晚", "晚上"]),
  night: new Set(["晚上", "深夜", "夜里", "夜间"]),
};

const DAYPART_TOKEN = /(?:凌晨|深夜|夜里|夜间|早上|早晨|清晨|上午|中午|下午|午后|傍晚|晚上)/g;
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

function isCompatible(daypart: TimeDaypart, token: string): boolean {
  if (daypart === "unknown") return false;
  return DAYPART_COMPATIBILITY[daypart].has(token);
}

function referenceForClaim(
  text: string,
  index: number,
  length: number,
  timeContext: TimeContext,
): { localTime: string | null; daypart: TimeDaypart } {
  if (timeContext.client_local_time && nearbyCaptureCue(text, index, length)) {
    return {
      localTime: timeContext.client_local_time,
      daypart: timeContext.client_daypart,
    };
  }
  return {
    localTime: timeContext.reference_local_time,
    daypart: timeContext.reference_daypart,
  };
}

function clockClaimIsSupported(
  match: RegExpMatchArray,
  text: string,
  timeContext: TimeContext,
): boolean {
  const [full, daypart, modifier, hourText, half, more, minuteText, around, particle] = match;
  const hasExplicitClockCue = Boolean(daypart || modifier || half || more || minuteText || around || particle);
  if (!hasExplicitClockCue) return true;
  const hour = parseClockNumber(hourText);
  if (hour === null) return false;
  const reference = referenceForClaim(text, match.index ?? 0, full.length, timeContext);
  if (daypart && !isCompatible(reference.daypart, daypart)) return false;
  const actualMinute = localMinuteOfDay(reference.localTime);
  return actualMinute !== null && candidateClockHours(hour).some((targetHour) =>
    clockPhraseContainsMinute({
      actualMinute,
      targetHour,
      modifier,
      half,
      more,
      minuteText,
      around,
    })
  );
}

function daypartClaimIsSupported(
  match: RegExpMatchArray,
  text: string,
  timeContext: TimeContext,
): boolean {
  const token = match[0];
  const reference = referenceForClaim(text, match.index ?? 0, token.length, timeContext);
  return isCompatible(reference.daypart, token);
}

/**
 * Keep model prose intact. A time claim is either supported by the selected
 * reference or the whole field is rejected; this function never edits words
 * out of generated language.
 */
export function sanitizeTextForTimeContext(
  value: string | null | undefined,
  timeContext: TimeContext | null | undefined,
): string | null {
  if (!value) return null;
  const text = value.trim();
  if (!text || !timeContext) return text || null;
  for (const match of text.matchAll(NATURAL_CLOCK_PHRASE)) {
    if (!clockClaimIsSupported(match, text, timeContext)) return null;
  }
  for (const match of text.matchAll(DAYPART_TOKEN)) {
    if (!daypartClaimIsSupported(match, text, timeContext)) return null;
  }
  return text;
}
