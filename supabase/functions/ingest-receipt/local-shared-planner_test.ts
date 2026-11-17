import { buildLocalSharedPlan, buildLocalSharedVoiceBrief } from "./local-shared-planner.ts";
import { normalizeLocalSharedBrief } from "./local-shared-brief.ts";
import { normalizeLocalExpressionAction } from "./local-expression-action.ts";
import { buildExpressionShadowPlan, buildGenericExpressionShadowPlan, buildDataPlannerSourceRecord } from "./expression-shadow-planner.ts";
import type { ShadowExpenseTransaction } from "./expression-shadow-planner.ts";
import { buildContextPacket } from "./context-packet.ts";
import { buildVoicePrompt } from "./prompts.ts";
import { plannerVoiceBriefFromPlan, plannerBriefContextCandidate } from "./planner-voice-brief.ts";

function record(id: string, domain: string, day: number, payload: Record<string, unknown>) {
  return {
    id, domain_key: domain, title: domain,
    record_date: `2026-11-${day}`,
    occurred_at: `2026-11-${day}T07:10:00+08:00`,
    created_at: `2026-11-${day}T09:10:00+08:00`,
    payload_jsonb: payload,
  };
}

Deno.test("LOCAL-AI-003-PARITY-LIFE: shared Planner finds a reading baseline with three prior records", () => {
  const rows = [15, 16, 17, 18].map((day) =>
    record(`r${day}`, "reading", day, { reading_minutes: day === 18 ? 40 : 20 }));
  const plan = buildLocalSharedPlan({ current: rows[3], history: rows.slice(0, 3) });
  const candidates = plan?.candidates as { claim: { semantic_key: string; structured_value: { median: number } } }[];
  if (!candidates?.some(({ claim }) =>
    claim.semantic_key === "reading_vs_personal_median" && claim.structured_value.median === 20)) {
    throw new Error("Reading baseline was not available");
  }
  const pwa = plannerVoiceBriefFromPlan(buildGenericExpressionShadowPlan({
    domainKey: "reading", records: rows.map(buildDataPlannerSourceRecord), currentRecordId: rows[3].id,
  }));
  if (acceptedBrief({ current: rows[3], history: rows.slice(0, 3) }).claim_fingerprint !== pwa?.claim_fingerprint) {
    throw new Error("iOS and PWA selected different reading observations");
  }
});


type PlannerInput = Parameters<typeof buildLocalSharedPlan>[0];

function acceptedBrief(input: PlannerInput) {
  const brief = buildLocalSharedVoiceBrief(input);
  const accepted = normalizeLocalSharedBrief(brief, input.current);
  if (!accepted) throw new Error(`Hosted dropped the selected ${input.current.domain_key} brief: ${JSON.stringify(brief)}`);
  return accepted;
}

function candidateKeys(input: PlannerInput): string[] {
  const plan = buildLocalSharedPlan(input);
  return ((plan?.candidates ?? []) as { claim: { semantic_key: string } }[])
    .map(({ claim }) => claim.semantic_key);
}

function requireKeys(keys: string[], expected: string[]) {
  for (const key of expected) if (!keys.includes(key)) throw new Error(`Expected ${key}, got ${keys.join(",")}`);
}

Deno.test("LOCAL-AI-003-PARITY-LIFE: sleep stage, timing, and typical schedule; food and sport baselines", () => {
  const sleep = [15, 16, 17, 18].map((day) => ({
    ...record(`s${day}`, "sleep", day, {
      sleep_start_at: `2026-11-${day - 1}T${day === 18 ? "23:50" : "23:20"}:00+08:00`,
      wake_at: `2026-11-${day}T07:10:00+08:00`, sleep_minutes: 440,
      deep_sleep_minutes: 90, light_sleep_minutes: 240, rem_minutes: 110, quality_score: 85,
    }),
  }));
  requireKeys(candidateKeys({ current: sleep[3], history: sleep.slice(0, 3) }),
    ["sleep_timing", "sleep_timing_vs_typical", "sleep_stage_composition", "sleep_quality_current"]);
  const received = normalizeLocalExpressionAction({
    currentFact: { ...sleep[3], payload_json: sleep[3].payload_jsonb },
    plannerCandidate: null, localMemoryContext: null, requestReceivedAt: "2026-11-18T09:00:00Z",
  });
  acceptedBrief({ current: sleep[3], history: sleep.slice(0, 3) });
  const fields = received.currentFact.payload_json as Record<string, unknown>;
  if (fields.sleep_start_at !== "2026-11-17T23:50:00+08:00" || fields.rem_minutes !== 110) {
    throw new Error("Hosted stripped structured sleep evidence");
  }
  const meals = [15, 16, 17, 18].map((day) => record(`f${day}`, "food", day, {
    meal_type: "dinner", total_calorie_kcal: day === 18 ? 560 : 680, dishes: [{ name: "番茄牛腩" }],
  }));
  requireKeys(candidateKeys({ current: meals[3], history: meals.slice(0, 3) }),
    ["food_meal_vs_personal_median", "food_recurring_dish"]);
  acceptedBrief({ current: meals[3], history: meals.slice(0, 3) });
  const sports = [15, 16, 17, 18].map((day) =>
    record(`a${day}`, "sport", day, { duration_minutes: day === 18 ? 40 : 25 }));
  requireKeys(candidateKeys({ current: sports[3], history: sports.slice(0, 3) }), ["sport_vs_personal_median"]);
  acceptedBrief({ current: sports[3], history: sports.slice(0, 3) });
});

Deno.test("LOCAL-AI-003-PARITY-FINANCE: expense and income produce quantified context", () => {
  const expense = (id: string, hour: number, amount: number) => ({
    ...record(id, "expense", 18, {}), amount, merchant_name: "示例便利店", category: "food",
    transaction_date: "2026-11-18", occurred_at: `2026-11-18T1${hour}:01:00+08:00`,
    created_at: `2026-11-18T1${hour}:05:00+08:00`, status: "done", type: "expense",
  });
  const input = { current: expense("expense-now", 2, 2), history: [expense("expense-before", 1, 5)] };
  requireKeys(candidateKeys(input), ["merchant_daily_count_total", "expense_record_name_previous_gap"]);
  const plan = buildLocalSharedPlan(input);
  const claims = (plan?.candidates as { claim: { semantic_key: string; structured_value: { count: number; total_amount: number } } }[])
    .map(({ claim }) => claim);
  const daily = claims.find(claim => claim.semantic_key === "merchant_daily_count_total");
  if (daily?.structured_value.count !== 2 || daily.structured_value.total_amount !== 7) {
    throw new Error("Expected 2 purchases totalling 7 yuan");
  }
  const pwa = plannerVoiceBriefFromPlan(buildExpressionShadowPlan({
    transactions: [input.current, ...input.history] as ShadowExpenseTransaction[],
    currentRecordId: input.current.id,
  }));
  if (acceptedBrief(input).claim_fingerprint !== pwa?.claim_fingerprint) {
    throw new Error("iOS and PWA selected different expense observations");
  }
  const income = [16, 18].map((day) => ({
    ...record(`i${day}`, "income", day, {}), amount: day, source_name: "示例来源", income_date: `2026-11-${day}`,
  }));
  requireKeys(candidateKeys({ current: income[1], history: [income[0]] }),
    ["income_month_total_count", "income_source_month_pattern"]);
  acceptedBrief({ current: income[1], history: [income[0]] });
});

Deno.test("LOCAL-AI-003-PARITY-WALLET: compares only the same account and snapshot kind", () => {
  const snapshot = (id: string, day: number, account: string, kind: string, amount: number) => ({
    ...record(id, "wallet", day, { account_name: "示例卡" }),
    linked_account_id: account, account_snapshot_kind: kind, snapshot_balance: amount,
  });
  const current = snapshot("wallet-now", 18, "a", "asset", 500);
  const previous = snapshot("wallet-before", 17, "a", "asset", 550);
  requireKeys(candidateKeys({ current, history: [previous] }), ["wallet_change_previous"]);
  acceptedBrief({ current, history: [previous] });
  const wrong = snapshot("wallet-other", 17, "b", "liability", 550);
  if (candidateKeys({ current, history: [wrong] }).includes("wallet_change_previous")) {
    throw new Error("Compared an unrelated wallet snapshot");
  }
});

Deno.test("LOCAL-AI-003-PARITY-RELATION: close matching records permit only a hypothesis", () => {
  const current = { ...record("related-meal", "food", 18, { dishes: [{ name: "番茄牛腩" }] }), title: "番茄牛腩" };
  const previous = { ...record("related-expense", "expense", 18, {}),
    merchant_name: "番茄牛腩", occurred_at: "2026-11-18T06:50:00+08:00", created_at: "2026-11-18T06:55:00+08:00",
  };
  requireKeys(candidateKeys({ current, history: [previous] }), ["cross_record_possible_life_chain"]);
  if (candidateKeys({ current, history: [previous], includeRelatedRecords: false }).includes("cross_record_possible_life_chain")) {
    throw new Error("Used related history when no history was authorized");
  }
});

Deno.test("LOCAL-AI-003-PARITY-TRANSPORT: sends one claim and bounded references; Hosted accepts exactly that claim", () => {
  const history = Array.from({ length: 12 }, (_, index) =>
    record(`r-${index}`, "reading", index + 10, { reading_minutes: 20, book_name: "历史字段不进入请求" }));
  const current = record("reading-now", "reading", 22, { reading_minutes: 40 });
  const brief = buildLocalSharedVoiceBrief({ current, history });
  if (!brief || JSON.stringify(brief).includes("历史字段不进入请求") || brief.evidence.length > 8) {
    throw new Error("Wrong scope for selected observation packet");
  }
  const fact = { id: current.id, domain_key: current.domain_key };
  const normalized = normalizeLocalSharedBrief(brief, fact);
  if (!normalized || normalized.claim_fingerprint !== brief.claim_fingerprint ||
    normalized.canonical_text !== brief.canonical_text) throw new Error("Voice lost the selected observation");
  const contextPacket = buildContextPacket({
    domainKey: "reading",
    recordFacts: { reading_minutes: 40 },
    signals: [],
    selectedCandidates: [plannerBriefContextCandidate(normalized)],
  });
  const prompt = buildVoicePrompt({
    domainKey: "reading", recordFacts: contextPacket.record_facts, signals: [], contextPacket,
    clientLocalTime: null, weekday: null,
  });
  if (contextPacket.selected_candidates[0]?.semantic_key !== brief.semantic_key ||
    !prompt.includes(brief.canonical_text) || prompt.includes("历史字段不进入请求")) {
    throw new Error("The model input lost the selected observation or leaked history");
  }
  if (normalizeLocalSharedBrief({ ...brief, canonical_text: "未经授权的文字" }, fact) ||
    normalizeLocalSharedBrief(brief, { ...fact, id: "different-record" })) {
    throw new Error("Accepted a mismatching observation");
  }
});


Deno.test("LOCAL-AI-003-PARITY-LIFE: ISO UTC sleep times use the same local clock as written output", () => {
  const input = {
    current: record("sleep-now", "sleep", 18, {
      sleep_start_at: "2026-11-17T15:45:00Z", wake_at: "2026-11-17T23:05:00Z", sleep_minutes: 440,
    }),
  };
  const planned = buildLocalSharedPlan(input);
  const timing = (planned?.candidates as {
    claim: { semantic_key: string; canonical_text: string };
    numbers: { value: number }[];
  }[]).find(candidate => candidate.claim.semantic_key === "sleep_timing");
  if (!timing?.claim.canonical_text.includes("23:45") ||
    timing.numbers[0]?.value !== 1425 || timing.numbers[1]?.value !== 425) {
    throw new Error("Sleep interpreted UTC as the user's local time");
  }
});

Deno.test("LOCAL-AI-003-PARITY-FINANCE: income period follows its business date around month boundaries", () => {
  const current = { ...record("income-now", "income", 18, {}), income_date: "2026-12-01",
    record_date: "2026-12-01", occurred_at: "2026-11-30T16:05:00Z", created_at: "2026-11-30T16:15:00Z", amount: 30 };
  const prior = { ...current, id: "income-last-month", income_date: "2026-11-30",
    record_date: "2026-11-30", occurred_at: "2026-11-30T15:30:00Z", created_at: "2026-11-30T15:35:00Z" };
  const plan = buildLocalSharedPlan({ current, history: [prior] });
  const monthly = (plan?.candidates as { claim: { semantic_key: string; structured_value: { count: number; month: string } } }[])
    .find(({ claim }) => claim.semantic_key === "income_month_total_count");
  if (monthly?.claim.structured_value.month !== "2026-12" || monthly.claim.structured_value.count !== 1) {
    throw new Error("Income was counted in the wrong month");
  }
});
