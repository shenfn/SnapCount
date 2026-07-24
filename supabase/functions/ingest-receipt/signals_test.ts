import {
  type DomainSignal,
  hasModelOwnedStatisticalClaim,
  hasUnsupportedFinanceCompanionClaim,
  selectSignals,
  validateModelTone,
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

Deno.test("model tone cannot relabel a rolling count as a weekly count", () => {
  const result = validateModelTone(
    ["这已经是本周第50次给数字中心充值了。"],
    JSON.stringify({
      record_type: "expense",
      amount: 10,
      merchant_name: "QLHazyCoder 数字中心",
    }),
  );

  assert(!result.ok, "weekly count claims must be owned by the rule layer");
  assert(result.badIndexes.includes(0), "the relabeled weekly claim must be rejected");
});

Deno.test("model tone cannot hide a count behind the current amount", () => {
  const result = validateModelTone(
    ["这已经50次了，调用费是真刚需。"],
    JSON.stringify({
      record_type: "expense",
      amount: 50,
      merchant_name: "QLHazyCoder 数字中心",
    }),
  );

  assert(!result.ok, "a current amount must never authorize a historical count with the same number");
});

Deno.test("model tone cannot make nonnumeric historical comparisons", () => {
  const result = validateModelTone(
    ["最近总是来这里充值，频率比平时高。"],
    JSON.stringify({
      record_type: "expense",
      amount: 10,
      merchant_name: "QLHazyCoder 数字中心",
    }),
  );

  assert(!result.ok, "historical comparisons without numbers must still be rule-owned");
  assert(
    hasModelOwnedStatisticalClaim("最近总是来这里充值，频率比平时高。"),
    "qualitative historical claims must be detected",
  );
});

Deno.test("model tone may use current record facts without history", () => {
  const result = validateModelTone(
    ["这 10 元花得很干脆，模型调用费确实刚需。"],
    JSON.stringify({
      record_type: "expense",
      amount: 10,
      merchant_name: "QLHazyCoder 数字中心",
    }),
  );

  assert(result.ok, "current-record numbers may remain in tone after validation");
});

Deno.test("model tone may stay qualitative while code renders the count", () => {
  const result = validateModelTone(
    ["模型调用费交得挺勤快。"],
    JSON.stringify({
      record_type: "expense",
      amount: 10,
      merchant_name: "QLHazyCoder 数字中心",
    }),
  );

  assert(result.ok, "pure tone must survive while the rule layer renders exact evidence");
});

Deno.test("new accounts still receive a deterministic current-record signal", () => {
  const signals = selectSignals("expense", {}, {
    amount: 10,
    merchant: "QLHazyCoder 数字中心",
    category: "other",
  });

  assert(signals.length === 1, "missing profiles must not remove the current-record fallback");
  assert(signals[0].kind === "record_acknowledge", "fallback must acknowledge only the current record");
  assert(signals[0].fact.includes("10 元"), "fallback fact must be rendered by code");
});

Deno.test("merchant statistics merge harmless spacing variants", () => {
  const signals = selectSignals("expense", {
    expense: {
      source_count: 55,
      profile: {
        merchant_stats: {
          "QLHazyCoder 数字中心": {
            week_count: 4,
            month_count: 50,
            count_90d: 50,
            avg_amount: 11.69,
          },
          "QLHazyCoder数字中心": {
            week_count: 1,
            month_count: 4,
            count_90d: 5,
            avg_amount: 10.2,
          },
        },
      },
    },
  }, {
    amount: 10,
    merchant: "QLHazyCoder 数字中心",
    category: "other",
  });

  assert(signals[0].kind === "merchant_repeat", "merged aliases must still produce the merchant signal");
  assert(signals[0].fact.includes("第 6 次"), "weekly counts from normalized aliases must be summed");
});
