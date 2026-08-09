import {
  type DomainSignal,
  extractDigitNumbers,
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

Deno.test("signal-backed tone may repeat the verified weekly count", () => {
  const signals: DomainSignal[] = [{
    kind: "merchant_repeat",
    priority: 1,
    fact: "本自然周在示例餐厅已是第 4 次消费，含本笔",
    numbers: [4],
    countNumbers: [4],
  }];
  const result = validateModelTone(
    ["这周第4次来示例餐厅，熟悉的味道又出现了。"],
    JSON.stringify({
      record_type: "expense",
      amount: 14.8,
      merchant_name: "示例餐厅",
    }),
    signals,
  );

  assert(result.ok, "the model may faithfully repeat a signal-backed weekly count");
});

Deno.test("baseline-backed qualitative sleep advice is retained", () => {
  const signals: DomainSignal[] = [{
    kind: "consecutive_short",
    priority: 1,
    fact: "本次睡眠 5.73 小时，比历史中位数 6.78 小时短些",
    numbers: [5.73, 6.78],
  }];
  const result = validateModelTone(
    ["睡了 5.73 小时，比平时短些。下午补个觉吧。"],
    JSON.stringify({ record_type: "sleep", sleep_hours: 5.73 }),
    signals,
  );
  assert(result.ok, "a grounded qualitative suggestion should survive tone validation");
});

Deno.test("statistical numbers stay bound to one candidate meaning unit and scope", () => {
  const signals: DomainSignal[] = [{
    kind: "merchant_repeat",
    priority: 1,
    fact: "本自然周在沙县小吃已是第 4 次消费；该店近90天平均单笔 9.54 元",
    numbers: [4, 9.54],
    countNumbers: [4],
    numberFacts: [{
      value: 4,
      meaning: "current_week_merchant_occurrence_count",
      role: "count",
      unit: "occurrence",
      scope: "week:current",
    }, {
      value: 9.54,
      meaning: "rolling_90d_merchant_average_amount",
      role: "measure",
      unit: "currency",
      scope: "rolling:90d",
    }],
  }];
  const recordFacts = JSON.stringify({
    record_type: "expense",
    amount: 11,
    merchant_name: "沙县小吃",
  });

  const accepted = [
    "本周第4次来沙县小吃，熟悉的味道又出现了。",
    "近90天在沙县小吃的平均单笔是9.54元。",
    "本笔11元，先把这一顿稳稳记下。",
  ];
  const rejected = [
    "近90天第4次来沙县小吃。",
    "本周已经消费90次。",
    "本周累计9.54元。",
  ];

  for (const text of accepted) {
    const result = validateVoiceNumbers([text], signals, recordFacts);
    assert(result.ok, `grounded claim must pass: ${text}; ${result.violations.join(" | ")}`);
  }
  for (const text of rejected) {
    const result = validateVoiceNumbers([text], signals, recordFacts);
    assert(!result.ok, `scope-swapped claim must fail: ${text}`);
    assert(result.badIndexes.includes(0), `rejected claim must identify its field: ${text}`);
  }
});

Deno.test("signal-backed tone cannot change the verified time window", () => {
  const signals: DomainSignal[] = [{
    kind: "merchant_repeat",
    priority: 1,
    fact: "本自然周在示例餐厅已是第 4 次消费，含本笔",
    numbers: [4],
    countNumbers: [4],
  }];
  const result = validateModelTone(
    ["近30天第4次来示例餐厅。"],
    JSON.stringify({
      record_type: "expense",
      amount: 14.8,
      merchant_name: "示例餐厅",
    }),
    signals,
  );

  assert(!result.ok, "a correct number with a wrong time window must be rejected");
});

Deno.test("signal-backed tone cannot swap one rolling window for another", () => {
  const signals: DomainSignal[] = [{
    kind: "merchant_repeat",
    priority: 1,
    fact: "本自然周在示例餐厅已是第 4 次消费；该店近90天平均单笔 9.54 元",
    numbers: [4, 9.54],
    countNumbers: [4],
  }];
  const result = validateModelTone(
    ["近30天第4次来示例餐厅，平均单笔9.54元。"],
    JSON.stringify({ record_type: "expense", merchant_name: "示例餐厅" }),
    signals,
  );

  assert(!result.ok, "near-90-day evidence must not authorize a near-30-day claim");
});

Deno.test("one candidate must support the whole statistical claim", () => {
  const signals: DomainSignal[] = [{
    kind: "merchant_repeat",
    priority: 1,
    fact: "本自然周在示例餐厅已是第 4 次消费",
    numbers: [4],
    countNumbers: [4],
  }, {
    kind: "unusual_amount",
    priority: 2,
    fact: "本笔14.8元高于近30天该类p90=12元",
    numbers: [14.8, 12, 30, 90],
  }];
  const result = validateModelTone(
    ["本周第4次来这里，平均单笔14.8元。"],
    JSON.stringify({ record_type: "expense", amount: 14.8, merchant_name: "示例餐厅" }),
    signals,
  );

  assert(!result.ok, "scopes from different candidates must not be merged into one claim");
});

Deno.test("unparseable Chinese counts never bypass the count whitelist", () => {
  const signals: DomainSignal[] = [{
    kind: "merchant_repeat",
    priority: 1,
    fact: "本自然周在示例餐厅已是第 4 次消费",
    numbers: [4],
    countNumbers: [4],
  }];
  const result = validateVoiceNumbers(
    ["这已经是第二十一次了。"],
    signals,
    JSON.stringify({ record_type: "expense", merchant_name: "示例餐厅" }),
  );

  assert(!result.ok, "a different multi-character Chinese count must be rejected");
});

Deno.test("content guard leaves verified statistics to the evidence validator", () => {
  assert(
    !hasUnsupportedFinanceCompanionClaim("这周第4次来示例餐厅。"),
    "content style guard must not preempt a signal-backed statistical claim",
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

Deno.test("grounded qualitative inference keeps record facts but rejects invented precision", () => {
  const recordFacts = JSON.stringify({
    record_type: "expense",
    amount: 6.28,
    merchant_name: "青禾茶饮",
    category: "food",
  });

  const grounded = validateModelTone(
    ["6.28 元看起来像碰上优惠。"],
    recordFacts,
  );
  const inventedDiscount = validateModelTone(
    ["这次优惠了 20 元。"],
    recordFacts,
  );
  const inventedFrequency = validateModelTone(
    ["这已经是本周第 3 次了。"],
    recordFacts,
  );

  assert(grounded.ok, "qualitative inference anchored to a current-record amount must survive");
  assert(!inventedDiscount.ok, "an unsupported precise discount amount must be rejected");
  assert(!inventedFrequency.ok, "an unsupported weekly count must be rejected");
});

Deno.test("Planner numeric roles allow first occurrence but do not turn a duration into a count", () => {
  const firstOccurrence = validateModelTone(
    ["第一次记录青禾茶饮，像是碰上了一个小惊喜。"],
    JSON.stringify({ record_type: "expense", amount: 6.28, merchant_name: "青禾茶饮" }),
    [{
      kind: "expense_merchant_first_occurrence",
      priority: 1,
      fact: "第一次记录「青禾茶饮」",
      numbers: [1, 6.28],
      countNumbers: [1],
    }],
  );
  const durationAsCount = validateModelTone(
    ["这已经是第 27 次了。"],
    JSON.stringify({ record_type: "expense", merchant_name: "示例商户" }),
    [{
      kind: "merchant_previous_transaction_gap",
      priority: 1,
      fact: "距离上一次同名记录已经过去 27 天",
      numbers: [27],
      countNumbers: [],
    }],
  );

  assert(firstOccurrence.ok, "a Planner count role must authorize the matching first-occurrence expression");
  assert(!durationAsCount.ok, "a measured day gap must not authorize an occurrence count");
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

Deno.test("EXP-003 noon alone cannot authorize meal or eating claims", () => {
  const result = validateModelTone(
    [
      "中午这笔支出已经记下。",
      "忙碌间隙好好吃饭，是对自己的犒劳。",
      "这顿午餐记得趁热吃。",
    ],
    JSON.stringify({
      record_type: "expense",
      image_type: "alipay_bill",
      amount: 6.8,
      merchant_name: "示例网络科技工作室",
      category: "life",
      platform: "支付宝",
      time_context: { event_daypart: "noon", event_local_time: "12:10:00" },
    }),
  );

  assert(!result.ok, "a compatible daypart must not become evidence that a meal happened");
  assert(!result.badIndexes.includes(0), "the grounded time-only field must survive");
  assert(result.badIndexes.includes(1), "unsupported eating language must be rejected by field");
  assert(result.badIndexes.includes(2), "unsupported meal and serving advice must be rejected by field");
});

Deno.test("EXP-003 independent food evidence allows natural meal language", () => {
  const categorizedExpense = validateModelTone(
    ["午餐稳稳记下了，记得趁热吃。"],
    JSON.stringify({
      record_type: "expense",
      image_type: "order_list",
      amount: 18.5,
      merchant_name: "示例饺子馆",
      category: "food",
      platform: "美团",
      time_context: { event_daypart: "noon", event_local_time: "12:10:00" },
    }),
  );
  const foodPhoto = validateModelTone(
    ["这顿午餐有饺子，趁热吃正好。"],
    JSON.stringify({
      record_type: "food",
      image_type: "food_photo",
      title: "饺子",
      payload: {
        meal_type: "lunch",
        dishes: [{ name: "饺子" }],
      },
    }),
  );

  assert(categorizedExpense.ok, "an explicit food category may support meal wording");
  assert(foodPhoto.ok, "structured dishes and meal type may support meal wording");
});

Deno.test("EXP-004 colloquial yuan-jiao forms normalize to the current amount", () => {
  const recordFacts = JSON.stringify({
    record_type: "expense",
    amount: 6.8,
    merchant_name: "示例商户",
  });
  const equivalentForms = ["6块8", "6块八", "6元8角", "六块八", "6.80元"];

  for (const amountText of equivalentForms) {
    const result = validateModelTone([`这笔 ${amountText} 记下了。`], recordFacts);
    assert(result.ok, `${amountText} must be treated as the verified 6.8 yuan amount: ${result.violations.join(" | ")}`);
  }
});

Deno.test("EXP-004 colloquial amount keeps its statistical meaning and scope", () => {
  const signals: DomainSignal[] = [{
    kind: "merchant_repeat",
    priority: 1,
    fact: "近90天平均单笔 6.8 元",
    numbers: [6.8],
    numberFacts: [{
      value: 6.8,
      meaning: "rolling_90d_merchant_average_amount",
      role: "measure",
      unit: "currency",
      scope: "rolling:90d",
    }],
  }];
  const result = validateModelTone(
    ["近90天平均单笔6块8。"],
    JSON.stringify({ record_type: "expense", amount: 9.2 }),
    signals,
  );

  assert(result.ok, `a colloquial statistical amount must retain its meaning and scope: ${result.violations.join(" | ")}`);
});

Deno.test("EXP-004 separate item quantities never become a decimal amount", () => {
  const parsed = extractDigitNumbers("6块商品、8份");
  const result = validateModelTone(
    ["一共6块商品、8份。"],
    JSON.stringify({ record_type: "expense", amount: 6.8 }),
  );

  assert(parsed.length === 2 && parsed[0] === 6 && parsed[1] === 8, "separate quantities must stay separate");
  assert(!result.ok, "separate quantities must not be authorized by a 6.8 yuan record amount");
});
