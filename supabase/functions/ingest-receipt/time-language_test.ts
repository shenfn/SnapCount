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

Deno.test("morning event rewrites unsupported deep-night wording without dropping the sentence", () => {
  const timeContext = context(
    "2026-08-08T06:41:00+08:00",
    "2026-08-08T06:45:00+08:00",
  );

  assertEquals(
    sanitizeTextForTimeContext("深夜两点还在忙吗？", timeContext),
    "早上还在忙吗？",
    "an invented clock claim should be replaced by the verified event daypart",
  );
  assertEquals(
    sanitizeTextForTimeContext("星之柠这笔，深夜还在忙。", timeContext),
    "星之柠这笔，早上还在忙。",
    "the rest of a grounded sentence should survive",
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

Deno.test("unknown event time removes unsupported daypart claims", () => {
  const timeContext = buildTimeContext({
    occurredAt: null,
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-08T06:45:00+08:00",
    requestReceivedAt: "2026-08-08T06:46:00+08:00",
  });

  assertEquals(
    sanitizeTextForTimeContext("深夜这笔已经记下。", timeContext),
    "这笔已经记下。",
    "code must not preserve a daypart without an event-time fact",
  );
  assertEquals(
    sanitizeTextForTimeContext("凌晨两点还在忙吗？", timeContext),
    "还在忙吗？",
    "an unsupported exact clock must be removed with its daypart",
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

Deno.test("EXP-002 replaces an incompatible fuzzy or exact clock without dropping grounded copy", () => {
  const timeContext = context(
    "2026-08-09T17:13:00+08:00",
    "2026-08-09T17:14:00+08:00",
  );

  assertEquals(
    sanitizeTextForTimeContext("下午快四点啦，顺手记下这笔。", timeContext),
    "下午，顺手记下这笔。",
    "an invented fuzzy hour should degrade to the verified daypart",
  );
  assertEquals(
    sanitizeTextForTimeContext("下午四点，这笔已经完成。", timeContext),
    "下午，这笔已经完成。",
    "a wrong exact hour must not survive merely because its daypart matches",
  );
  assertEquals(
    sanitizeTextForTimeContext("将近4点，这笔已经完成。", timeContext),
    "下午，这笔已经完成。",
    "Arabic colloquial clocks should use the same semantic boundary",
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
