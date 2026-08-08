import {
  buildContextPacket,
  normalizeSemanticMemories,
  resolveExpressedSemanticKey,
  selectSemanticContext,
  type ContextPacketCandidate,
} from "./context-packet.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

function coverageCandidate(input: {
  semanticKey: string;
  dimension: string;
  fact: string;
  numberFacts?: ContextPacketCandidate["number_facts"];
}): ContextPacketCandidate {
  const numberFacts = input.numberFacts ?? [];
  return {
    candidate_id: `candidate:${input.semanticKey}`,
    semantic_key: input.semanticKey,
    kind: input.semanticKey,
    dimension: input.dimension,
    fact: input.fact,
    numbers: numberFacts.map((item) => item.value),
    count_numbers: numberFacts.filter((item) => item.role === "count").map((item) => item.value),
    number_facts: numberFacts,
    source: "expression_planner",
    source_surface: "record_detail",
    planner_version: "expression-shadow-auto-v0.6",
  };
}

Deno.test("semantic memory normalization keeps explicit meaning expressible", () => {
  const memories = normalizeSemanticMemories({
    long_term: [{
      id: "memory-1",
      key: "merchant_context:QLHazyCoder 数字中心",
      type: "merchant_pattern",
      content: "这是模型 API 中转站。",
      confidence: 1,
      weight: 5,
      evidence: {
        source: "user_explicit_feedback",
        merchant_aliases: ["QLHazyCoder数字中心"],
      },
    }],
  });

  assert(memories.length === 1, "one semantic memory should be normalized");
  assert(memories[0].origin === "user_explicit", "explicit source should be preserved");
  assert(memories[0].state === "confirmed", "explicit source should be confirmed");
  assert(memories[0].claimability === "expressible", "confirmed meaning should be expressible");
});

Deno.test("record-derived memory cannot enter expressible context", () => {
  const selected = selectSemanticContext({
    long_term: [{
      key: "merchant:示例餐厅",
      type: "merchant_pattern",
      content: "用户会在示例餐厅消费。",
      confidence: 0.75,
      weight: 1.2,
      evidence: { source_table: "transactions", source_record_id: "tx-1", merchant: "示例餐厅" },
    }],
  }, "expense", { merchant_name: "示例餐厅" });

  assert(selected.length === 0, "derived merchant pattern must not be expressible");
});

Deno.test("top-level source provenance marks legacy rows as derived", () => {
  const memories = normalizeSemanticMemories({
    long_term: [{
      id: "memory-derived",
      key: "reading:示例书",
      type: "reading_pattern",
      content: "用户最近在读示例书。",
      source_table: "data_records",
      source_id: "record-1",
      evidence: { book_name: "示例书" },
    }],
  });

  assert(memories[0].origin === "record_derived", "RPC source columns must be honored");
  assert(memories[0].sourceTable === "data_records", "source table must remain traceable");
  assert(memories[0].sourceId === "record-1", "source id must remain traceable");
});

Deno.test("nested domain entities can match an explicit memory", () => {
  const selected = selectSemanticContext({
    long_term: [{
      key: "reading:示例书",
      type: "reading_pattern",
      content: "这本书让用户想继续读。",
      evidence: { source: "user_explicit_feedback", book_name: "示例书" },
    }],
  }, "reading", { record_type: "reading", payload: { book_name: "示例书" } });

  assert(selected.length === 1, "reading memories must match payload entities");
  assert(selected[0].claimability === "expressible", "explicit memory must be expressible");
});

Deno.test("context packet contains selected candidates and bounded semantic context", () => {
  const packet = buildContextPacket({
    domainKey: "expense",
    recordFacts: { record_type: "expense", merchant_name: "示例餐厅", amount: 14.8 },
    signals: [{
      kind: "merchant_repeat",
      priority: 1,
      fact: "本自然周在示例餐厅已是第 4 次消费，含本笔",
      numbers: [4],
      countNumbers: [4],
    }],
    memory: {
      long_term: Array.from({ length: 5 }, (_, index) => ({
        key: `merchant_context:${index}`,
        type: "merchant_pattern",
        content: `语义 ${index}`,
        evidence: { source: "user_explicit_feedback", merchant: "示例餐厅" },
        weight: 5 - index,
      })),
    },
  });

  assert(packet.packet_version === "context-packet-v2", "packet version must be explicit");
  assert(packet.selected_candidates.length === 1, "packet must carry selected candidates");
  assert(packet.semantic_context.length <= 3, "semantic context must be bounded");
  assert(packet.trace.candidate_count === 1, "packet trace must include candidate count");
  assert(packet.trace.packet_created_at.length > 0, "packet trace must include creation time");
  assert(/^[0-9a-f]{8}$/.test(packet.trace.content_fingerprint), "packet trace must include a deterministic fingerprint");
  assert(packet.trace.memory_loaded_count === 5, "packet trace must include loaded memory count");
  assert(packet.trace.memory_filtered_count === 5, "nonmatching memories must be counted as filtered");
  assert(packet.selected_candidates[0].source === "domain_profile_signal", "candidate source must be explicit");
});

Deno.test("context packet preserves Planner provenance and numeric roles", () => {
  const packet = buildContextPacket({
    domainKey: "expense",
    recordFacts: { record_type: "expense", merchant_name: "青禾茶饮", amount: 6.28 },
    signals: [],
    selectedCandidates: [{
      candidate_id: "fact:expense:merchant-first-occurrence:preinsert-1",
      semantic_key: "expense_merchant_first_occurrence",
      kind: "expense_merchant_first_occurrence",
      dimension: "first_occurrence",
      fact: "第一次记录「青禾茶饮」",
      numbers: [1, 6.28],
      count_numbers: [1],
      number_facts: [
        { value: 1, meaning: "first_occurrence_count", role: "count" },
        { value: 6.28, meaning: "current_record_amount", role: "measure" },
      ],
      source: "expression_planner",
      source_surface: "record_detail",
      planner_version: "expression-shadow-auto-v0.6",
    }],
  });

  const candidate = packet.selected_candidates[0];
  assert(candidate.source === "expression_planner", "Planner source must survive packet assembly");
  assert(candidate.source_surface === "record_detail", "source surface must be explicit");
  assert(candidate.planner_version === "expression-shadow-auto-v0.6", "Planner version must be frozen");
  assert(candidate.count_numbers.length === 1 && candidate.count_numbers[0] === 1, "count role must remain strict");
  assert(candidate.number_facts[1].role === "measure", "amount must not become an occurrence count");
  assert(packet.trace.candidate_kinds[0] === "expense_merchant_first_occurrence", "trace must use semantic provenance");
});

Deno.test("first-occurrence coverage requires a grounded object and unscoped first-seen meaning", () => {
  const selectedCandidates = [coverageCandidate({
    semanticKey: "expense_merchant_first_occurrence",
    dimension: "first_occurrence",
    fact: "第一次记录「青禾茶饮」",
    numberFacts: [{ value: 1, meaning: "first_occurrence_count", role: "count" }],
  })];

  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: "expense_merchant_first_occurrence",
    companionMessage: "第一次记下青禾茶饮，熟悉的味道多了一个新坐标。",
    selectedCandidates,
    recordFacts: { record_type: "expense", merchant_name: "青禾茶饮", amount: 6.28 },
  }) === "expense_merchant_first_occurrence", "a natural first-seen expression with the actual merchant must be attributable");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: "expense_merchant_first_occurrence",
    companionMessage: "这笔记下了。",
    selectedCandidates,
  }) === null, "a generic sentence cannot hide a first-occurrence candidate");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: "expense_merchant_first_occurrence",
    companionMessage: "第一次记下另一家茶饮。",
    selectedCandidates,
  }) === null, "a first-occurrence statement about the wrong object must be rejected");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: "expense_merchant_first_occurrence",
    companionMessage: "这周第一次记下青禾茶饮。",
    selectedCandidates,
  }) === null, "a weekly first occurrence must not cover an all-history first occurrence");
  assert(resolveExpressedSemanticKey({
    companionMessage: "第一次记下青禾茶饮。",
    selectedCandidates,
  }) === null, "missing model attribution must fail open");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: "merchant_daily_count_total",
    companionMessage: "今天已经记下。",
    selectedCandidates,
  }) === null, "the model cannot claim an unselected semantic key");
});

Deno.test("record context needs a concrete record fact instead of a generic acknowledgement", () => {
  const candidate = coverageCandidate({
    semanticKey: "expense_current_record_context",
    dimension: "record_context",
    fact: "10:20 已记录一笔 6.28 元支出",
    numberFacts: [{ value: 6.28, meaning: "current_record_amount", role: "measure" }],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: "上午这笔 6.28 元支出已经记下。",
    selectedCandidates: [candidate],
  }) === candidate.semantic_key, "an accurate amount can ground record context");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: "这笔已经记下。",
    selectedCandidates: [candidate],
  }) === null, "a bare acknowledgement must not claim record context");
});

Deno.test("repeat interval and temporal rhythm require their exact time evidence", () => {
  const repeat = coverageCandidate({
    semanticKey: "expense_record_name_previous_gap",
    dimension: "repeat_interval",
    fact: "距离上一次同名记录已经过去 9 小时 41 分钟",
    numberFacts: [
      { value: 581, meaning: "same_record_name_elapsed_minutes", role: "measure" },
      { value: 9, meaning: "same_record_name_elapsed_hours_component", role: "measure" },
      { value: 41, meaning: "same_record_name_elapsed_minutes_component", role: "measure" },
    ],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: repeat.semantic_key,
    companionMessage: "距离上一次同名记录，已经过去 9 小时 41 分钟。",
    selectedCandidates: [repeat],
  }) === repeat.semantic_key, "the full previous-record duration must be attributable");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: repeat.semantic_key,
    companionMessage: "当天首笔到末笔相隔 9 小时 41 分钟。",
    selectedCandidates: [repeat],
  }) === null, "a daily first-to-last span is the wrong temporal meaning");

  const sleepTiming = coverageCandidate({
    semanticKey: "sleep_timing",
    dimension: "temporal_rhythm",
    fact: "入睡 23:40，醒来 07:05",
    numberFacts: [
      { value: 1420, meaning: "sleep_start_clock_minutes", role: "measure" },
      { value: 425, meaning: "wake_clock_minutes", role: "measure" },
    ],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: sleepTiming.semantic_key,
    companionMessage: "昨晚 23:40 入睡，今天 07:05 醒来。",
    selectedCandidates: [sleepTiming],
  }) === sleepTiming.semantic_key, "both exact clock endpoints must ground a sleep window");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: sleepTiming.semantic_key,
    companionMessage: "昨晚睡得不算晚，早上也醒得自然。",
    selectedCandidates: [sleepTiming],
  }) === null, "a vague rhythm sentence must not hide exact sleep times");
});

Deno.test("period comparison coverage requires the right periods and trusted numbers", () => {
  const candidate = coverageCandidate({
    semanticKey: "expense_category_week_to_date_vs_previous_week_same_period",
    dimension: "category_period_comparison",
    fact: "本周截至现在，生活 8 笔、64.99 元；上周同期 7 笔、97.65 元",
    numberFacts: [
      { value: 8, meaning: "current_week_to_date_count", role: "count" },
      { value: 64.99, meaning: "current_week_to_date_total", role: "measure" },
      { value: 7, meaning: "previous_week_same_period_count", role: "count" },
      { value: 97.65, meaning: "previous_week_same_period_total", role: "measure" },
    ],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: "这周生活类是 8 笔、64.99 元，上周同期是 7 笔、97.65 元。",
    selectedCandidates: [candidate],
  }) === candidate.semantic_key, "an accurate current-versus-previous period comparison must pass");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: "这周生活类是 11 笔，比上周更频繁。",
    selectedCandidates: [candidate],
  }) === null, "an invented period number must fail open");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: "这周生活类是 8 笔、64.99 元，比上周同期更克制。",
    selectedCandidates: [candidate],
  }) === null, "two current-period numbers cannot stand in for baseline evidence");
});

Deno.test("personal and meal baselines need both current and baseline evidence", () => {
  const personal = coverageCandidate({
    semanticKey: "sleep_vs_personal_median",
    dimension: "personal_baseline",
    fact: "本次睡眠 7.18 小时，历史中位数 6.73 小时",
    numberFacts: [
      { value: 7.18, meaning: "current_sleep_hours", role: "measure" },
      { value: 6.73, meaning: "historical_median_sleep_hours", role: "measure" },
    ],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: personal.semantic_key,
    companionMessage: "这次睡了 7.18 小时，比历史中位数 6.73 小时多一点。",
    selectedCandidates: [personal],
  }) === personal.semantic_key, "an exact personal baseline comparison must pass");

  const meal = coverageCandidate({
    semanticKey: "food_meal_vs_personal_median",
    dimension: "meal_baseline",
    fact: "这顿早餐约 33.3 千卡；历史同餐次中位数为 550 千卡",
    numberFacts: [
      { value: 33.3, meaning: "current_meal_calorie_kcal", role: "measure" },
      { value: 550, meaning: "historical_meal_median_calorie_kcal", role: "measure" },
      { value: 11, meaning: "meal_baseline_sample_count", role: "count" },
    ],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: meal.semantic_key,
    companionMessage: "这顿早餐约 33.3 千卡，历史同餐次中位数是 550 千卡。",
    selectedCandidates: [meal],
  }) === meal.semantic_key, "sample size omitted from the canonical fact must not be required");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: meal.semantic_key,
    companionMessage: "这顿早餐看起来挺轻巧。",
    selectedCandidates: [meal],
  }) === null, "a qualitative meal sentence must not claim a numeric baseline");
});

Deno.test("current facts require the exact current metric", () => {
  const candidate = coverageCandidate({
    semanticKey: "sleep_current_metric",
    dimension: "current_fact",
    fact: "本次睡眠为 7.18 小时",
    numberFacts: [{ value: 7.18, meaning: "current_sleep_hours", role: "measure" }],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: "这次睡了 7.18 小时，先把这一晚稳稳记下。",
    selectedCandidates: [candidate],
  }) === candidate.semantic_key, "an exact current metric must pass");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: "这次睡得不错。",
    selectedCandidates: [candidate],
  }) === null, "a qualitative sentence must not hide an exact current fact");
});

Deno.test("daily aggregation coverage binds day, merchant, count, and total", () => {
  const candidate = coverageCandidate({
    semanticKey: "merchant_daily_count_total",
    dimension: "daily_aggregation",
    fact: "2026-08-08 在「青禾茶饮」共 2 笔，累计 16.08 元",
    numberFacts: [
      { value: 2, meaning: "transaction_count", role: "count" },
      { value: 16.08, meaning: "daily_total_amount", role: "measure" },
    ],
  });
  const resolve = (message: string) => resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: message,
    selectedCandidates: [candidate],
    recordFacts: { merchant_name: "青禾茶饮" },
  });
  assert(resolve("今天在青禾茶饮共 2 笔，累计 16.08 元。") === candidate.semantic_key, "the exact daily aggregate must pass");
  assert(resolve("2026-08-07 在青禾茶饮共 2 笔，累计 16.08 元。") === null, "a different explicit day must fail");
  assert(resolve("今天在另一家茶饮共 2 笔，累计 16.08 元。") === null, "a different merchant must fail");
  assert(resolve("今天在青禾茶饮共 3 笔，累计 16.08 元。") === null, "a wrong count must fail");
  assert(resolve("今天在青禾茶饮花了 16.08 元。") === null, "an omitted count must fail open");
});

Deno.test("amount structure coverage requires the full distribution and exact maximum", () => {
  const candidate = coverageCandidate({
    semanticKey: "merchant_daily_amount_structure",
    dimension: "amount_structure",
    fact: "「青禾茶饮」的金额分布为 6.28 元、9.8 元，最高单笔 9.8 元",
    numberFacts: [
      { value: 6.28, meaning: "transaction_amount", role: "measure" },
      { value: 9.8, meaning: "transaction_amount", role: "measure" },
    ],
  });
  const resolve = (message: string) => resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: message,
    selectedCandidates: [candidate],
    recordFacts: { merchant_name: "青禾茶饮" },
  });
  assert(resolve("青禾茶饮这两笔分别是 6.28 元和 9.8 元，最高单笔 9.8 元。") === candidate.semantic_key, "the full amount structure must pass");
  assert(resolve("青禾茶饮的金额分布里，最高单笔是 9.8 元。") === null, "the maximum alone cannot hide the distribution");
  assert(resolve("青禾茶饮这两笔分别是 6.28 元和 9.8 元，最高单笔 6.28 元。") === null, "a wrong maximum must fail");
});

Deno.test("food composition coverage binds dishes and each macro to its own value", () => {
  const candidate = coverageCandidate({
    semanticKey: "food_composition",
    dimension: "record_composition",
    fact: "记录了2道菜：鸡腿饭、青菜；蛋白质 25 克，碳水 50 克，脂肪 18 克",
    numberFacts: [
      { value: 2, meaning: "recognized_dish_count", role: "count" },
      { value: 25, meaning: "protein_g", role: "measure" },
      { value: 50, meaning: "carb_g", role: "measure" },
      { value: 18, meaning: "fat_g", role: "measure" },
    ],
  });
  const recordFacts = { payload: { dishes: [{ name: "鸡腿饭" }, { name: "青菜" }] } };
  const resolve = (message: string) => resolveExpressedSemanticKey({
    declaredSemanticKey: candidate.semantic_key,
    companionMessage: message,
    selectedCandidates: [candidate],
    recordFacts,
  });
  assert(resolve("这顿有鸡腿饭和青菜，共 2 道菜；蛋白质 25 克、碳水 50 克、脂肪 18 克。") === candidate.semantic_key, "the complete composition must pass");
  assert(resolve("这顿有鸡腿饭，共 2 道菜；蛋白质 25 克、碳水 50 克、脂肪 18 克。") === null, "omitting a listed dish must fail open");
  assert(resolve("这顿有鸡腿饭和青菜，共 2 道菜；蛋白质 50 克、碳水 25 克、脂肪 18 克。") === null, "swapped macro values must fail");
  assert(resolve("这顿有鸡腿饭和青菜，共 2 道菜；蛋白质 25 千卡、碳水 50 克、脂肪 18 克。") === null, "a wrong macro unit must fail");
});

Deno.test("recurrence and income source patterns require their exact entity, period, and count", () => {
  const recurring = coverageCandidate({
    semanticKey: "food_recurring_dish",
    dimension: "recurrence",
    fact: "「鸡腿饭」在你的历史饮食中已出现 3 次",
    numberFacts: [{ value: 3, meaning: "prior_dish_occurrence_count", role: "count" }],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: recurring.semantic_key,
    companionMessage: "鸡腿饭在以前的饮食记录里已经出现 3 次。",
    selectedCandidates: [recurring],
  }) === recurring.semantic_key, "an exact recurring dish claim must pass");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: recurring.semantic_key,
    companionMessage: "又见鸡腿饭了。",
    selectedCandidates: [recurring],
  }) === null, "a qualitative recurrence must not hide the exact count");

  const source = coverageCandidate({
    semanticKey: "income_source_month_pattern",
    dimension: "source_pattern",
    fact: "2026-08 来自「稿费」的收入已出现 2 次",
    numberFacts: [{ value: 2, meaning: "current_month_source_occurrence_count", role: "count" }],
  });
  const resolveSource = (message: string) => resolveExpressedSemanticKey({
    declaredSemanticKey: source.semantic_key,
    companionMessage: message,
    selectedCandidates: [source],
    recordFacts: { source_name: "稿费" },
  });
  assert(resolveSource("2026 年 8 月来自稿费的收入已经出现 2 次。") === source.semantic_key, "an exact monthly source pattern must pass");
  assert(resolveSource("2026 年 7 月来自稿费的收入已经出现 2 次。") === null, "a different month must fail");
  assert(resolveSource("2026 年 8 月来自奖金的收入已经出现 2 次。") === null, "a different source must fail");
  assert(resolveSource("2026 年 8 月来自稿费的收入是 2 元。") === null, "an amount cannot stand in for an occurrence count");
});

Deno.test("sleep quality and stage coverage bind score and minutes to their labels", () => {
  const quality = coverageCandidate({
    semanticKey: "sleep_quality_current",
    dimension: "quality",
    fact: "设备睡眠评分 82，历史中位数 80",
    numberFacts: [
      { value: 82, meaning: "current_sleep_quality_score", role: "measure" },
      { value: 80, meaning: "historical_median_sleep_quality_score", role: "measure" },
      { value: 6, meaning: "sleep_quality_baseline_sample_count", role: "count" },
    ],
  });
  const resolveQuality = (message: string) => resolveExpressedSemanticKey({
    declaredSemanticKey: quality.semantic_key,
    companionMessage: message,
    selectedCandidates: [quality],
  });
  assert(resolveQuality("设备给这晚的睡眠评分是 82 分，历史中位数是 80 分。") === quality.semantic_key, "the exact device score comparison must pass");
  assert(resolveQuality("设备记录这晚睡了 82 分钟，历史中位数 80 分钟。") === null, "minutes cannot stand in for scores");
  assert(resolveQuality("设备给这晚的睡眠评分是 82 分。") === null, "omitting the baseline score must fail open");
  assert(resolveQuality("设备给这晚的睡眠评分是 80 分，历史中位数是 82 分。") === null, "swapped scores must fail");

  const stages = coverageCandidate({
    semanticKey: "sleep_stage_composition",
    dimension: "sleep_structure",
    fact: "睡眠阶段：深睡 90 分钟、浅睡 240 分钟、REM 75 分钟（设备估算）",
    numberFacts: [
      { value: 90, meaning: "deep_sleep_minutes", role: "measure" },
      { value: 240, meaning: "light_sleep_minutes", role: "measure" },
      { value: 75, meaning: "rem_sleep_minutes", role: "measure" },
    ],
  });
  const resolveStages = (message: string) => resolveExpressedSemanticKey({
    declaredSemanticKey: stages.semantic_key,
    companionMessage: message,
    selectedCandidates: [stages],
  });
  assert(resolveStages("设备估算这晚深睡 90 分钟、浅睡 240 分钟、REM 75 分钟。") === stages.semantic_key, "every known stage must pass when correctly bound");
  assert(resolveStages("设备估算这晚深睡 240 分钟、浅睡 90 分钟、REM 75 分钟。") === null, "swapped stage values must fail");
  assert(resolveStages("设备估算这晚深睡 90 分钟、浅睡 240 分钟。") === null, "omitting a known stage must fail open");
});

Deno.test("wallet state change coverage binds account, direction, delta, and current value", () => {
  const positive = coverageCandidate({
    semanticKey: "wallet_change_previous",
    dimension: "state_change",
    fact: "「示例账户」账户余额较上次变化 +50 元，当前 100 元",
    numberFacts: [
      { value: 50, meaning: "wallet_delta_amount", role: "measure" },
      { value: 100, meaning: "current_wallet_amount", role: "measure" },
      { value: 50, meaning: "previous_wallet_amount", role: "measure" },
    ],
  });
  const resolve = (message: string) => resolveExpressedSemanticKey({
    declaredSemanticKey: positive.semantic_key,
    companionMessage: message,
    selectedCandidates: [positive],
    recordFacts: { account_name: "示例账户" },
  });
  assert(resolve("示例账户余额比上次增加 50 元，现在是 100 元。") === positive.semantic_key, "an exact positive state change must pass");
  assert(resolve("示例账户余额比上次减少 50 元，现在是 100 元。") === null, "the wrong direction must fail");
  assert(resolve("另一账户余额比上次增加 50 元，现在是 100 元。") === null, "the wrong account must fail");
  assert(resolve("示例账户余额比上次增加 50 分钟，现在是 100 分钟。") === null, "minutes cannot stand in for money");

  const negative = coverageCandidate({
    semanticKey: "wallet_change_previous",
    dimension: "state_change",
    fact: "「示例待还」待还金额较上次变化 -20 元，当前 100 元",
    numberFacts: [
      { value: -20, meaning: "wallet_delta_amount", role: "measure" },
      { value: 100, meaning: "current_wallet_amount", role: "measure" },
      { value: 120, meaning: "previous_wallet_amount", role: "measure" },
    ],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: negative.semantic_key,
    companionMessage: "示例待还的待还金额比上次减少 20 元，目前是 100 元。",
    selectedCandidates: [negative],
    recordFacts: { account_name: "示例待还" },
  }) === negative.semantic_key, "a natural-language negative delta must pass");
});

Deno.test("timing deltas and unit roles remain directionally strict", () => {
  const timing = coverageCandidate({
    semanticKey: "sleep_timing_vs_typical",
    dimension: "timing_baseline",
    fact: "入睡20分钟晚，醒来10分钟早（相对你的典型作息）",
    numberFacts: [
      { value: 20, meaning: "sleep_start_delta_minutes", role: "measure" },
      { value: -10, meaning: "wake_delta_minutes", role: "measure" },
    ],
  });
  const resolveTiming = (message: string) => resolveExpressedSemanticKey({
    declaredSemanticKey: timing.semantic_key,
    companionMessage: message,
    selectedCandidates: [timing],
  });
  assert(resolveTiming("比典型作息入睡晚 20 分钟，醒来早 10 分钟。") === timing.semantic_key, "correctly directed timing deltas must pass");
  assert(resolveTiming("比典型作息入睡早 20 分钟，醒来晚 10 分钟。") === null, "reversed timing directions must fail");

  const streak = coverageCandidate({
    semanticKey: "example_streak",
    dimension: "current_fact",
    fact: "当前已连续 7 天",
    numberFacts: [{ value: 7, meaning: "consecutive_day_count", role: "count" }],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: streak.semantic_key,
    companionMessage: "当前已经连续 7 天。",
    selectedCandidates: [streak],
  }) === streak.semantic_key, "a day count must accept days");
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: streak.semantic_key,
    companionMessage: "当前已经连续 7 次。",
    selectedCandidates: [streak],
  }) === null, "a day count must reject occurrences");

  const amount = coverageCandidate({
    semanticKey: "expense_current_metric",
    dimension: "current_fact",
    fact: "本次支出为 1299 元",
    numberFacts: [{ value: 1299, meaning: "current_expense_amount", role: "measure" }],
  });
  assert(resolveExpressedSemanticKey({
    declaredSemanticKey: amount.semantic_key,
    companionMessage: "当前支出是 ￥1,299。",
    selectedCandidates: [amount],
  }) === amount.semantic_key, "currency symbols and grouped digits must remain grounded");
});
