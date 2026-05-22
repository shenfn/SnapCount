export interface NormalizedAiDateTime {
  date: string;
  time: string | null;
  iso: string;
}

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
  event_time_source: "ai_occurred_at" | "ai_order_finished_at" | "fallback" | "unknown";
  client_captured_at: string | null;
  request_received_at: string;
  reference_time: string;
  reference_time_source: "client_captured_at" | "request_received_at";
  delta_minutes: number | null;
  time_relation: TimeRelation;
  is_backfill: boolean;
  confidence: number;
}

export function normalizeAiDateTime(value: unknown): NormalizedAiDateTime | null {
  if (typeof value !== "string" || !value.trim()) return null;
  let text = value.trim();
  const compact = text.match(/(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日?\s*(\d{1,2})?:?(\d{1,2})?/);
  if (compact) {
    const [, y, m, d, hh, mm] = compact;
    const date = `${y}-${m.padStart(2, "0")}-${d.padStart(2, "0")}`;
    const time = hh && mm ? `${hh.padStart(2, "0")}:${mm.padStart(2, "0")}:00` : null;
    return { date, time, iso: `${date}T${time ?? "00:00:00"}+08:00` };
  }

  text = text.replace("年", "-").replace("月", "-").replace("日", "");
  const normalized = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?(?:([+-]\d{2}:?\d{2}|Z))?$/);
  if (normalized) {
    const [, y, m, d, hh, mm, ss, zone] = normalized;
    const date = `${y}-${m.padStart(2, "0")}-${d.padStart(2, "0")}`;
    const time = hh && mm ? `${hh.padStart(2, "0")}:${mm.padStart(2, "0")}:${(ss ?? "00").padStart(2, "0")}` : null;
    const zoneText = zone ? (zone === "Z" ? "Z" : zone.includes(":") ? zone : `${zone.slice(0, 3)}:${zone.slice(3)}`) : "+08:00";
    return { date, time, iso: `${date}T${time ?? "00:00:00"}${zoneText}` };
  }

  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return null;
  return {
    date: parsed.toISOString().slice(0, 10),
    time: parsed.toISOString().slice(11, 19),
    iso: parsed.toISOString(),
  };
}

export function normalizeAiDate(value: unknown): string | null {
  return normalizeAiDateTime(value)?.iso ?? null;
}

export function classifyTimeRelation(eventIso: string | null, referenceIso: string): Pick<TimeContext, "delta_minutes" | "time_relation" | "is_backfill" | "confidence"> {
  if (!eventIso) {
    return { delta_minutes: null, time_relation: "unknown", is_backfill: false, confidence: 0.35 };
  }

  const eventTime = new Date(eventIso);
  const referenceTime = new Date(referenceIso);
  if (Number.isNaN(eventTime.getTime()) || Number.isNaN(referenceTime.getTime())) {
    return { delta_minutes: null, time_relation: "unknown", is_backfill: false, confidence: 0.25 };
  }

  const deltaMinutes = Math.round((referenceTime.getTime() - eventTime.getTime()) / 60000);
  if (deltaMinutes < -10) {
    return { delta_minutes: deltaMinutes, time_relation: "future_event", is_backfill: false, confidence: 0.55 };
  }
  if (deltaMinutes <= 30) {
    return { delta_minutes: deltaMinutes, time_relation: "realtime", is_backfill: false, confidence: 0.9 };
  }
  if (deltaMinutes <= 120) {
    return { delta_minutes: deltaMinutes, time_relation: "near_realtime", is_backfill: false, confidence: 0.82 };
  }

  const sameLocalDate = eventIso.slice(0, 10) === referenceIso.slice(0, 10);
  if (sameLocalDate) {
    return { delta_minutes: deltaMinutes, time_relation: "backfill_same_day", is_backfill: true, confidence: 0.82 };
  }
  if (deltaMinutes <= 7 * 24 * 60) {
    return { delta_minutes: deltaMinutes, time_relation: "backfill_cross_day", is_backfill: true, confidence: 0.78 };
  }
  return { delta_minutes: deltaMinutes, time_relation: "historical_record", is_backfill: true, confidence: 0.72 };
}

export function buildTimeContext(input: {
  occurredAt: string | null;
  orderFinishedAt: string | null;
  clientCapturedAt: unknown;
  requestReceivedAt: string;
  fallbackEventTime?: string | null;
}): TimeContext {
  const clientCaptured = normalizeAiDateTime(input.clientCapturedAt);
  const referenceTime = clientCaptured?.iso ?? input.requestReceivedAt;
  const eventTime = input.occurredAt ?? input.orderFinishedAt ?? input.fallbackEventTime ?? null;
  const eventSource: TimeContext["event_time_source"] = input.occurredAt
    ? "ai_occurred_at"
    : input.orderFinishedAt
      ? "ai_order_finished_at"
      : input.fallbackEventTime
        ? "fallback"
        : "unknown";
  const relation = classifyTimeRelation(eventTime, referenceTime);
  return {
    event_time: eventTime,
    event_time_source: eventSource,
    client_captured_at: clientCaptured?.iso ?? null,
    request_received_at: input.requestReceivedAt,
    reference_time: referenceTime,
    reference_time_source: clientCaptured ? "client_captured_at" : "request_received_at",
    ...relation,
  };
}
