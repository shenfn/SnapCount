import { buildLocalExpenseVoiceBrief, plannerVoiceBriefFromPlan } from "./expression-delivery.ts";
import { buildExpressionShadowPlan } from "./expression-shadow-planner.ts";

const current = {
  id: "current", domain_key: "expense", merchant_name: "示例商户",
  record_date: "2026-11-17", occurred_at: "2026-11-17T12:05:00+08:00",
  amount: 2, category: "life",
};
const earlier = {
  id: "earlier", merchant_name: "示例商户", transaction_date: "2026-11-17",
  occurred_at: "2026-11-17T10:00:00+08:00", created_at: "2026-11-17T10:01:00+08:00",
  amount: 5,
};
const known = "2026-11-17T12:06:00+08:00";

Deno.test("LOCAL-AI-EXPENSE-01: Hosted uses the same record-detail aggregate as PWA", () => {
  const pwa = plannerVoiceBriefFromPlan(buildExpressionShadowPlan({
    currentRecordId: current.id,
    transactions: [
      { ...earlier, status: "done", category: "life" },
      {
        ...current, transaction_date: current.record_date, created_at: known, status: "done",
      },
    ],
  }) as Record<string, unknown>);
  const local = buildLocalExpenseVoiceBrief(current, {
    current_known_at: known, day_complete: true, history: [earlier],
  });
  if (!local || !pwa || local.semantic_key !== "merchant_daily_count_total" ||
      local.canonical_text !== pwa.canonical_text || local.numbers.join() !== "2,7") {
    throw new Error("Hosted and PWA did not select the same 2 records / 7 yuan observation");
  }
});

Deno.test("LOCAL-AI-EXPENSE-02: incomplete day is not reported as a full day", () => {
  const brief = buildLocalExpenseVoiceBrief(current, {
    current_known_at: known, day_complete: false, history: [earlier],
  });
  if (brief?.semantic_key === "merchant_daily_count_total") {
    throw new Error("An incomplete local window must not become a full-day total");
  }
});

Deno.test("LOCAL-AI-EXPENSE-03: only the prior known same-name date can supply a date-only interval", () => {
  const brief = buildLocalExpenseVoiceBrief({ ...current, occurred_at: null }, {
    current_known_at: known, day_complete: true, history: [
      { ...earlier, transaction_date: "2026-11-16", occurred_at: null },
      { ...earlier, id: "backfill", occurred_at: null, created_at: "2026-11-18T10:00:00+08:00" },
    ],
  });
  if (brief?.semantic_key !== "expense_record_name_previous_gap" ||
      brief.numbers.join() !== "1" || !brief.canonical_text.includes("约 1 天")) {
    throw new Error("Expected the one-day difference between the two date-only records");
  }
});

Deno.test("LOCAL-AI-EXPENSE-04: duplicate IDs and history beyond the Hosted window are rejected", () => {
  for (const history of [[earlier, earlier], [{ ...earlier, transaction_date: "2026-09-01", occurred_at: null }]]) {
    if (buildLocalExpenseVoiceBrief(current, { current_known_at: known, day_complete: true, history }) !== null) {
      throw new Error("Invalid evidence must not reach the Voice prompt");
    }
  }
});
