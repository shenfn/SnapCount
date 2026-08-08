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
