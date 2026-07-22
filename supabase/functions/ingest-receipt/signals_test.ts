import {
  type DomainSignal,
  hasUnsupportedFinanceCompanionClaim,
  validateVoiceNumbers,
} from "./signals.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

Deno.test("new account rejects unsupported merchant frequency", () => {
  const result = validateVoiceNumbers(
    ["这周第三次在示例餐厅点餐，14.8元的小确幸。"],
    [],
    JSON.stringify({
      record_type: "expense",
      amount: 14.8,
      merchant_name: "示例餐厅",
    }),
  );

  assert(!result.ok, "frequency without a profile signal must be rejected");
  assert(
    result.badIndexes.includes(0),
    "the companion line must be marked invalid",
  );
  assert(
    hasUnsupportedFinanceCompanionClaim("14.8元的小确幸。"),
    "unsupported finance phrasing must be rejected",
  );
});

Deno.test("current transaction amount remains valid without history", () => {
  const result = validateVoiceNumbers(
    ["示例餐厅 14.8 元已记录。"],
    [],
    JSON.stringify({
      record_type: "expense",
      amount: 14.8,
      merchant_name: "示例餐厅",
    }),
  );

  assert(result.ok, "numbers copied from the current record must remain valid");
});

Deno.test("verified merchant frequency accepts the declared count", () => {
  const signals: DomainSignal[] = [{
    kind: "merchant_repeat",
    priority: 1,
    fact: "本自然周在示例餐厅已是第 3 次消费，含本笔",
    numbers: [3, 14.8],
    countNumbers: [3],
  }];
  const result = validateVoiceNumbers(
    ["这周第三次在示例餐厅点餐，本笔 14.8 元。"],
    signals,
    JSON.stringify({
      record_type: "expense",
      amount: 14.8,
      merchant_name: "示例餐厅",
    }),
  );

  assert(
    result.ok,
    "frequency backed by an explicit count signal must be accepted",
  );
});
