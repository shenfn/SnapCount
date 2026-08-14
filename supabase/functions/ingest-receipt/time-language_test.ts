import { sanitizeTextForTimeContext } from "./time-language.ts";
import { buildTimeContext } from "./time.ts";

const assertEquals = <T>(actual: T, expected: T, message: string) => {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${String(expected)}, got ${String(actual)}`);
  }
};

function context(event: string, captured: string) {
  return buildTimeContext({
    occurredAt: event,
    orderFinishedAt: null,
    clientCapturedAt: captured,
    requestReceivedAt: captured,
  });
}

Deno.test("morning event rejects unsupported deep-night wording without rewriting the sentence", () => {
  const timeContext = context(
    "2026-08-08T06:41:00+08:00",
    "2026-08-08T06:45:00+08:00",
  );

  assertEquals(
    sanitizeTextForTimeContext("深夜两点还在忙吗？", timeContext),
    null,
    "an invented clock claim should reject the whole candidate",
  );
  assertEquals(
    sanitizeTextForTimeContext("星之柠这笔，深夜还在忙。", timeContext),
    null,
    "an incompatible daypart should reject the whole candidate",
  );
});

Deno.test("backfill wording may mention capture time when the relationship is explicit", () => {
  const timeContext = context(
    "2026-08-07T22:30:00+08:00",
    "2026-08-08T06:45:00+08:00",
  );
  const text = "早上才补录，昨晚这笔也算安稳收好了。";

  assertEquals(
    sanitizeTextForTimeContext(text, timeContext),
    text,
    "explicit capture-time wording should remain available for backfill context",
  );
});

Deno.test("TIME-REF-001 uses upload time when event time is unknown", () => {
  const timeContext = buildTimeContext({
    occurredAt: null,
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-08T06:45:00+08:00",
    requestReceivedAt: "2026-08-08T06:46:00+08:00",
  });

  assertEquals(
    sanitizeTextForTimeContext("早上这笔已经记下。", timeContext),
    "早上这笔已经记下。",
    "upload daypart is valid when event time is missing",
  );
  assertEquals(
    sanitizeTextForTimeContext("刚过八点，广清这笔小额支出先记下啦。", timeContext),
    null,
    "an incompatible upload clock must reject the whole candidate instead of leaving a fragment",
  );
  assertEquals(
    sanitizeTextForTimeContext("深夜这笔已经记下。", timeContext),
    null,
    "an incompatible upload daypart must reject the whole candidate",
  );
});

Deno.test("TIME-REF-001 accepts upload clock wording when event time is absent", () => {
  const timeContext = buildTimeContext({
    occurredAt: null,
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-14T08:24:00+08:00",
    requestReceivedAt: "2026-08-14T08:24:03+08:00",
  });

  assertEquals(
    sanitizeTextForTimeContext("八点多，把广清这笔小额支出记下啦。", timeContext),
    "八点多，把广清这笔小额支出记下啦。",
    "upload time should support natural wording when event time is unavailable",
  );
});

Deno.test("EXP-002 keeps natural fuzzy clock phrases whose semantic interval contains the event time", () => {
  const nearSix = context(
    "2026-08-09T17:43:00+08:00",
    "2026-08-09T17:44:00+08:00",
  );
  const justAfterFive = context(
    "2026-08-09T17:08:00+08:00",
    "2026-08-09T17:09:00+08:00",
  );
  const aroundHalfPastFive = context(
    "2026-08-09T17:30:00+08:00",
    "2026-08-09T17:31:00+08:00",
  );

  assertEquals(
    sanitizeTextForTimeContext("快六点了，这笔也记下了。", nearSix),
    "快六点了，这笔也记下了。",
    "a natural near-hour phrase should remain available",
  );
  assertEquals(
    sanitizeTextForTimeContext("刚过五点，顺手收好这笔。", justAfterFive),
    "刚过五点，顺手收好这笔。",
    "a just-after phrase should remain available",
  );
  assertEquals(
    sanitizeTextForTimeContext("五点半左右，这笔已经完成。", aroundHalfPastFive),
    "五点半左右，这笔已经完成。",
    "a half-hour approximation should remain available",
  );
});

Deno.test("EXP-002 rejects an incompatible fuzzy or exact clock as a whole candidate", () => {
  const timeContext = context(
    "2026-08-09T17:13:00+08:00",
    "2026-08-09T17:14:00+08:00",
  );

  assertEquals(
    sanitizeTextForTimeContext("下午快四点啦，顺手记下这笔。", timeContext),
    null,
    "an invented fuzzy hour should reject the whole candidate",
  );
  assertEquals(
    sanitizeTextForTimeContext("下午四点，这笔已经完成。", timeContext),
    null,
    "a wrong exact hour must reject the whole candidate even when its daypart matches",
  );
  assertEquals(
    sanitizeTextForTimeContext("将近4点，这笔已经完成。", timeContext),
    null,
    "Arabic colloquial clocks should reject the whole candidate when incompatible",
  );
});

Deno.test("TIME-REF-001 allows both event and upload time when each claim is explicit", () => {
  const timeContext = context(
    "2026-08-14T17:12:00+08:00",
    "2026-08-14T20:31:00+08:00",
  );
  const text = "下午五点多发生，晚上八点半才上传。";

  assertEquals(
    sanitizeTextForTimeContext(text, timeContext),
    text,
    "event and upload wording should coexist when each is tied to its source",
  );
});

Deno.test("EXP-002 validates fuzzy clock phrases across midnight", () => {
  const timeContext = context(
    "2026-08-09T23:50:00+08:00",
    "2026-08-09T23:51:00+08:00",
  );

  assertEquals(
    sanitizeTextForTimeContext("晚上快十二点了，这笔也完成了。", timeContext),
    "晚上快十二点了，这笔也完成了。",
    "near-midnight wording should use a circular 24-hour interval",
  );
});

Deno.test("EXP-002 validates an explicit backfill capture clock against capture time", () => {
  const timeContext = context(
    "2026-08-08T22:30:00+08:00",
    "2026-08-09T06:45:00+08:00",
  );
  const text = "早上快七点才补录，昨晚这笔也收好了。";

  assertEquals(
    sanitizeTextForTimeContext(text, timeContext),
    text,
    "an explicit capture clock should remain when it matches client capture time",
  );
});

Deno.test("EXP-002 keeps non-time point counts outside the clock grammar", () => {
  const timeContext = context(
    "2026-08-09T17:13:00+08:00",
    "2026-08-09T17:14:00+08:00",
  );
  const text = "这里有3点建议，可以慢慢看。";

  assertEquals(
    sanitizeTextForTimeContext(text, timeContext),
    text,
    "a bare point count without clock cues must not be rewritten as time",
  );
});
