import {
  buildTimeContext,
  classifyDaypart,
  classifyTimeRelation,
  normalizeAiDateTime,
} from "./time.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

const assertEquals = <T>(actual: T, expected: T, message: string) => {
  if (actual !== expected) {
    throw new Error(
      `${message}: expected ${String(expected)}, got ${String(actual)}`,
    );
  }
};

Deno.test("timezone-bearing timestamps normalize to the same Shanghai wall time", () => {
  const fromUtc = normalizeAiDateTime("2026-08-07T22:41:00Z");
  const fromShanghai = normalizeAiDateTime("2026-08-08T06:41:00+08:00");

  assert(fromUtc !== null, "UTC timestamp should normalize");
  assert(fromShanghai !== null, "Shanghai timestamp should normalize");
  assertEquals(
    fromUtc?.date,
    "2026-08-08",
    "UTC timestamp should use the Shanghai calendar date",
  );
  assertEquals(
    fromUtc?.time,
    "06:41:00",
    "UTC timestamp should use the Shanghai clock time",
  );
  assertEquals(
    fromUtc?.iso,
    "2026-08-08T06:41:00+08:00",
    "UTC timestamp should use canonical Shanghai ISO",
  );
  assertEquals(
    fromShanghai?.iso,
    fromUtc?.iso,
    "equivalent instants should share one canonical ISO",
  );
  assertEquals(fromUtc?.hasExactTime, true, "timezone timestamp is exact");
});

Deno.test("timezone-less timestamps are treated as Shanghai wall time", () => {
  const normalized = normalizeAiDateTime("2026-08-08 06:41");

  assertEquals(normalized?.date, "2026-08-08", "wall date should be preserved");
  assertEquals(normalized?.time, "06:41:00", "wall time should be preserved");
  assertEquals(
    normalized?.iso,
    "2026-08-08T06:41:00+08:00",
    "wall time should receive the Shanghai offset",
  );
  assertEquals(normalized?.hasExactTime, true, "wall clock is exact");
});

Deno.test("date-only evidence keeps the date but does not invent an event instant", () => {
  const normalized = normalizeAiDateTime("2026-08-08");
  assertEquals(normalized?.date, "2026-08-08", "date evidence should survive");
  assertEquals(normalized?.time, null, "date-only evidence has no clock");
  assertEquals(normalized?.hasExactTime, false, "date-only evidence is not exact");

  const context = buildTimeContext({
    occurredAt: "2026-08-08",
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-08T06:45:00+08:00",
    requestReceivedAt: "2026-08-07T22:46:00Z",
  });
  assertEquals(context.event_time, null, "date-only evidence must not become midnight");
  assertEquals(context.event_local_date, "2026-08-08", "known event date remains available");
  assertEquals(context.event_local_time, null, "unknown event clock remains unknown");
  assertEquals(context.event_daypart, "unknown", "unknown clock has no daypart");
  assertEquals(context.time_relation, "unknown", "date-only evidence cannot claim a precise delta");
});

Deno.test("missing event evidence keeps its source unknown", () => {
  const context = buildTimeContext({
    occurredAt: null,
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-08T06:45:00+08:00",
    requestReceivedAt: "2026-08-07T22:46:00Z",
  });

  assertEquals(context.event_time, null, "missing evidence has no event instant");
  assertEquals(context.event_local_date, null, "missing evidence has no event date");
  assertEquals(context.event_time_source, "unknown", "null values must not compare as an AI source");
});

Deno.test("TIME-REF-001 uses upload time as the expression reference when event time is missing", () => {
  const context = buildTimeContext({
    occurredAt: null,
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-14T08:24:00+08:00",
    requestReceivedAt: "2026-08-14T08:24:03+08:00",
  });
  assertEquals(context.reference_time, "2026-08-14T08:24:00+08:00", "upload time should become the reference instant");
  assertEquals(context.reference_time_source, "client_captured_at", "reference source should identify upload time");
  assertEquals(context.reference_local_date, "2026-08-14", "reference date should be available to the prompt");
  assertEquals(context.reference_local_time, "08:24:00", "reference clock should be available to the prompt");
  assertEquals(context.reference_daypart, "morning", "reference daypart should use upload time when event time is absent");
});

Deno.test("TIME-REF-001 keeps event time as the expression reference when both times exist", () => {
  const context = buildTimeContext({
    occurredAt: "2026-08-14T17:12:00+08:00",
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-14T17:31:00+08:00",
    requestReceivedAt: "2026-08-14T17:31:03+08:00",
  });
  assertEquals(context.reference_time, "2026-08-14T17:12:00+08:00", "event time should remain the primary reference");
  assertEquals(context.reference_time_source, "event_time", "reference source should identify event time");
  assertEquals(context.reference_local_time, "17:12:00", "event clock should drive ordinary time wording");
  assertEquals(context.delta_minutes, 19, "capture delta should remain available separately");
  assertEquals(context.time_relation, "realtime", "event and upload relation should remain realtime");
});

Deno.test("time relation compares Shanghai local calendar dates", () => {
  const sameDay = classifyTimeRelation(
    "2026-08-07T22:00:00Z",
    "2026-08-08T09:00:00+08:00",
  );
  assertEquals(sameDay.delta_minutes, 180, "delta should compare instants");
  assertEquals(
    sameDay.time_relation,
    "backfill_same_day",
    "06:00 and 09:00 Shanghai time are the same local day",
  );

  const crossDay = classifyTimeRelation(
    "2026-08-08T12:00:00Z",
    "2026-08-09T08:00:00+08:00",
  );
  assertEquals(
    crossDay.delta_minutes,
    720,
    "cross-day delta should compare instants",
  );
  assertEquals(
    crossDay.time_relation,
    "backfill_cross_day",
    "20:00 and next-day 08:00 cross the Shanghai calendar day",
  );
});

Deno.test("daypart classifies 06:41 as morning", () => {
  assertEquals(
    classifyDaypart("06:41:00"),
    "morning",
    "06:41 must not be classified as late night",
  );
  assertEquals(
    classifyDaypart("2026-08-07T22:41:00Z"),
    "morning",
    "timezone-bearing input should use Shanghai clock time",
  );
});

Deno.test("time context exposes canonical event and capture fields", () => {
  const context = buildTimeContext({
    occurredAt: "2026-08-07T22:41:00Z",
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-08T06:45:00+08:00",
    requestReceivedAt: "2026-08-07T22:46:00Z",
  });

  assertEquals(
    context.event_time,
    "2026-08-08T06:41:00+08:00",
    "event time should be canonical Shanghai ISO",
  );
  assertEquals(
    context.event_local_date,
    "2026-08-08",
    "event local date should be explicit",
  );
  assertEquals(
    context.event_local_time,
    "06:41:00",
    "event local clock should be explicit",
  );
  assertEquals(
    context.event_daypart,
    "morning",
    "event daypart should be explicit",
  );
  assertEquals(
    context.client_captured_at,
    "2026-08-08T06:45:00+08:00",
    "capture time should be canonical Shanghai ISO",
  );
  assertEquals(
    context.client_local_time,
    "06:45:00",
    "capture local clock should be explicit",
  );
  assertEquals(
    context.client_daypart,
    "morning",
    "capture daypart should be explicit",
  );
  assertEquals(
    context.request_received_at,
    "2026-08-08T06:46:00+08:00",
    "request time should use the same canonical zone",
  );
  assertEquals(
    context.delta_minutes,
    4,
    "event-to-capture delta should remain instant-based",
  );
  assertEquals(
    context.time_relation,
    "realtime",
    "four minutes should be realtime",
  );
});
