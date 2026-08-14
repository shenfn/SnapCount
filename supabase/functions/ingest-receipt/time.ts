export interface NormalizedAiDateTime {
  date: string;
  time: string | null;
  iso: string;
  hasExactTime: boolean;
}

export type TimeDaypart =
  | "late_night"
  | "morning"
  | "noon"
  | "afternoon"
  | "evening"
  | "night"
  | "unknown";

export type TimeRelation =
  | "realtime"
  | "near_realtime"
  | "backfill_same_day"
  | "backfill_cross_day"
  | "historical_record"
  | "future_event"
  | "unknown";

export interface TimeContext {
  event_time: string | null;
  event_time_source:
    | "ai_occurred_at"
    | "ai_order_finished_at"
    | "fallback"
    | "unknown";
  event_local_date: string | null;
  event_local_time: string | null;
  event_daypart: TimeDaypart;
  client_captured_at: string | null;
  client_local_date: string | null;
  client_local_time: string | null;
  client_daypart: TimeDaypart;
  client_captured_at_raw?: string | null;
  client_captured_at_invalid_reason?:
    | "too_old"
    | "too_future"
    | "unparsable"
    | null;
  request_received_at: string;
  reference_time: string;
  reference_time_source:
    | "event_time"
    | "client_captured_at"
    | "request_received_at";
  reference_local_date: string | null;
  reference_local_time: string | null;
  reference_daypart: TimeDaypart;
  delta_minutes: number | null;
  time_relation: TimeRelation;
  is_backfill: boolean;
  confidence: number;
}

const MIN_VALID_CAPTURE_MS = Date.UTC(2010, 0, 1);
const MAX_FUTURE_OFFSET_MS = 365 * 24 * 60 * 60 * 1000;
const SHANGHAI_OFFSET = "+08:00";
const SHANGHAI_OFFSET_MS = 8 * 60 * 60 * 1000;

function pad2(value: number | string): string {
  return String(value).padStart(2, "0");
}

function validWallDateTime(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
): boolean {
  if (
    hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 ||
    second > 59
  ) return false;
  const value = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  return value.getUTCFullYear() === year &&
    value.getUTCMonth() === month - 1 &&
    value.getUTCDate() === day &&
    value.getUTCHours() === hour &&
    value.getUTCMinutes() === minute &&
    value.getUTCSeconds() === second;
}

function shanghaiDateTimeFromInstant(ms: number): NormalizedAiDateTime | null {
  if (!Number.isFinite(ms)) return null;
  const local = new Date(ms + SHANGHAI_OFFSET_MS);
  const date = `${local.getUTCFullYear()}-${pad2(local.getUTCMonth() + 1)}-${
    pad2(local.getUTCDate())
  }`;
  const time = `${pad2(local.getUTCHours())}:${pad2(local.getUTCMinutes())}:${
    pad2(local.getUTCSeconds())
  }`;
  return {
    date,
    time,
    iso: `${date}T${time}${SHANGHAI_OFFSET}`,
    hasExactTime: true,
  };
}

function wallDateTime(
  yearText: string,
  monthText: string,
  dayText: string,
  hourText?: string,
  minuteText?: string,
  secondText?: string,
): NormalizedAiDateTime | null {
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hasTime = hourText !== undefined && minuteText !== undefined;
  const hour = hasTime ? Number(hourText) : 0;
  const minute = hasTime ? Number(minuteText) : 0;
  const second = hasTime ? Number(secondText ?? 0) : 0;
  if (!validWallDateTime(year, month, day, hour, minute, second)) return null;
  const date = `${yearText.padStart(4, "0")}-${pad2(month)}-${pad2(day)}`;
  const time = hasTime ? `${pad2(hour)}:${pad2(minute)}:${pad2(second)}` : null;
  return {
    date,
    time,
    iso: `${date}T${time ?? "00:00:00"}${SHANGHAI_OFFSET}`,
    hasExactTime: hasTime,
  };
}

export function normalizeAiDateTime(
  value: unknown,
): NormalizedAiDateTime | null {
  if (typeof value !== "string" || !value.trim()) return null;
  let text = value.trim();
  const compact = text.match(
    /(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日?\s*(\d{1,2})?:?(\d{1,2})?/,
  );
  if (compact) {
    const [, y, m, d, hh, mm] = compact;
    return wallDateTime(y, m, d, hh, mm);
  }

  text = text.replace("年", "-").replace("月", "-").replace("日", "")
    .replaceAll("/", "-");
  const normalized = text.match(
    /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.\d{1,9})?)?)?(?:([+-]\d{2}:?\d{2}|Z))?$/i,
  );
  if (normalized) {
    const [, y, m, d, hh, mm, ss, zone] = normalized;
    const wall = wallDateTime(y, m, d, hh, mm, ss);
    if (!wall) return null;
    if (!zone) return wall;
    const zoneText = zone.toUpperCase() === "Z"
      ? "Z"
      : zone.includes(":")
      ? zone
      : `${zone.slice(0, 3)}:${zone.slice(3)}`;
    const parsedMs = Date.parse(
      `${wall.date}T${wall.time ?? "00:00:00"}${zoneText}`,
    );
    return shanghaiDateTimeFromInstant(parsedMs);
  }

  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return null;
  return shanghaiDateTimeFromInstant(parsed.getTime());
}

export function normalizeAiDate(value: unknown): string | null {
  return normalizeAiDateTime(value)?.iso ?? null;
}

export function classifyDaypart(value: unknown): TimeDaypart {
  let time: string | null = null;
  if (typeof value === "string") {
    const clock = value.trim().match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
    time = clock
      ? `${pad2(clock[1])}:${clock[2]}:00`
      : normalizeAiDateTime(value)?.time ?? null;
  }
  if (!time) return "unknown";
  const hour = Number(time.slice(0, 2));
  if (!Number.isFinite(hour) || hour < 0 || hour > 23) return "unknown";
  if (hour < 5) return "late_night";
  if (hour < 11) return "morning";
  if (hour < 14) return "noon";
  if (hour < 18) return "afternoon";
  if (hour < 22) return "evening";
  return "night";
}

export function classifyTimeRelation(
  eventIso: string | null,
  referenceIso: string,
): Pick<
  TimeContext,
  "delta_minutes" | "time_relation" | "is_backfill" | "confidence"
> {
  if (!eventIso) {
    return {
      delta_minutes: null,
      time_relation: "unknown",
      is_backfill: false,
      confidence: 0.35,
    };
  }

  const eventTime = normalizeAiDateTime(eventIso);
  const referenceTime = normalizeAiDateTime(referenceIso);
  if (!eventTime || !referenceTime) {
    return {
      delta_minutes: null,
      time_relation: "unknown",
      is_backfill: false,
      confidence: 0.25,
    };
  }

  const deltaMinutes = Math.round(
    (Date.parse(referenceTime.iso) - Date.parse(eventTime.iso)) / 60000,
  );
  if (deltaMinutes < -10) {
    return {
      delta_minutes: deltaMinutes,
      time_relation: "future_event",
      is_backfill: false,
      confidence: 0.55,
    };
  }
  if (deltaMinutes <= 30) {
    return {
      delta_minutes: deltaMinutes,
      time_relation: "realtime",
      is_backfill: false,
      confidence: 0.9,
    };
  }
  if (deltaMinutes <= 120) {
    return {
      delta_minutes: deltaMinutes,
      time_relation: "near_realtime",
      is_backfill: false,
      confidence: 0.82,
    };
  }

  const sameLocalDate = eventTime.date === referenceTime.date;
  if (sameLocalDate) {
    return {
      delta_minutes: deltaMinutes,
      time_relation: "backfill_same_day",
      is_backfill: true,
      confidence: 0.82,
    };
  }
  if (deltaMinutes <= 7 * 24 * 60) {
    return {
      delta_minutes: deltaMinutes,
      time_relation: "backfill_cross_day",
      is_backfill: true,
      confidence: 0.78,
    };
  }
  return {
    delta_minutes: deltaMinutes,
    time_relation: "historical_record",
    is_backfill: true,
    confidence: 0.72,
  };
}

export function buildTimeContext(input: {
  occurredAt: string | null;
  orderFinishedAt: string | null;
  clientCapturedAt: unknown;
  requestReceivedAt: string;
  fallbackEventTime?: string | null;
}): TimeContext {
  const rawClient = typeof input.clientCapturedAt === "string"
    ? input.clientCapturedAt.trim() || null
    : null;
  const clientCaptured = normalizeAiDateTime(input.clientCapturedAt);
  const requestReceived = normalizeAiDateTime(input.requestReceivedAt);
  const requestReceivedIso = requestReceived?.iso ?? input.requestReceivedAt;
  const requestMs = Date.parse(requestReceivedIso);
  let clientIso: string | null = clientCaptured?.hasExactTime
    ? clientCaptured.iso
    : null;
  let invalidReason: TimeContext["client_captured_at_invalid_reason"] = null;
  if (rawClient && (!clientCaptured || !clientCaptured.hasExactTime)) {
    invalidReason = "unparsable";
  } else if (clientCaptured) {
    const ms = Date.parse(clientCaptured.iso);
    if (Number.isNaN(ms)) {
      invalidReason = "unparsable";
      clientIso = null;
    } else if (ms < MIN_VALID_CAPTURE_MS) {
      invalidReason = "too_old";
      clientIso = null;
    } else if (
      !Number.isNaN(requestMs) && ms - requestMs > MAX_FUTURE_OFFSET_MS
    ) {
      invalidReason = "too_future";
      clientIso = null;
    }
  }

  const occurredAt = normalizeAiDateTime(input.occurredAt);
  const orderFinishedAt = normalizeAiDateTime(input.orderFinishedAt);
  const fallbackEventTime = normalizeAiDateTime(input.fallbackEventTime);
  let event: NormalizedAiDateTime | null = null;
  let eventSource: TimeContext["event_time_source"] = "unknown";
  if (occurredAt?.hasExactTime) {
    event = occurredAt;
    eventSource = "ai_occurred_at";
  } else if (orderFinishedAt?.hasExactTime) {
    event = orderFinishedAt;
    eventSource = "ai_order_finished_at";
  } else if (fallbackEventTime?.hasExactTime) {
    event = fallbackEventTime;
    eventSource = "fallback";
  } else if (occurredAt) {
    event = occurredAt;
    eventSource = "ai_occurred_at";
  } else if (orderFinishedAt) {
    event = orderFinishedAt;
    eventSource = "ai_order_finished_at";
  } else if (fallbackEventTime) {
    event = fallbackEventTime;
    eventSource = "fallback";
  }
  const captureReferenceTime = clientIso ?? requestReceivedIso;
  const eventTime = event?.hasExactTime ? event.iso : null;
  const relation = classifyTimeRelation(eventTime, captureReferenceTime);
  const reference = eventTime
    ? event
    : clientIso
    ? clientCaptured
    : requestReceived;
  const referenceTime = reference?.iso ?? captureReferenceTime;
  const referenceSource: TimeContext["reference_time_source"] = eventTime
    ? "event_time"
    : clientIso
    ? "client_captured_at"
    : "request_received_at";
  return {
    event_time: eventTime,
    event_time_source: eventSource,
    event_local_date: event?.date ?? null,
    event_local_time: event?.hasExactTime ? event.time : null,
    event_daypart: classifyDaypart(eventTime),
    client_captured_at: clientIso,
    client_local_date: clientIso ? clientCaptured?.date ?? null : null,
    client_local_time: clientIso ? clientCaptured?.time ?? null : null,
    client_daypart: classifyDaypart(clientIso),
    client_captured_at_raw: rawClient,
    client_captured_at_invalid_reason: invalidReason,
    request_received_at: requestReceivedIso,
    reference_time: referenceTime,
    reference_time_source: referenceSource,
    reference_local_date: reference?.date ?? null,
    reference_local_time: reference?.hasExactTime ? reference.time : null,
    reference_daypart: classifyDaypart(referenceTime),
    ...relation,
  };
}
