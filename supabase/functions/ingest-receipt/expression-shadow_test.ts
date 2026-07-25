import {
  buildExpressionShadowBaselinePayload,
  minimizeExpressionShadowPlan,
  shouldCaptureExpressionShadow,
} from "./expression-shadow.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("Expression Shadow requires explicit improvement consent", () => {
  assert(!shouldCaptureExpressionShadow(false, "shadow"), "opt-out must disable Shadow capture");
  assert(!shouldCaptureExpressionShadow(true, "off"), "server off mode must disable Shadow capture");
  assert(shouldCaptureExpressionShadow(true, "shadow"), "opt-in and shadow mode should enable capture");
});

Deno.test("Expression Shadow baseline excludes user-visible and business text", () => {
  const baseline = buildExpressionShadowBaselinePayload({
    status: "done",
    record_type: "expense",
    id: "record-id",
    notification: "Private notification text",
    message: "Private message text",
    possible_duplicate: false,
    ai_ok: true,
    ai_feedback: {
      badge: "Private badge",
      emotion_line: "Private emotion",
      utility_line: "Private utility",
      confidence: 0.82,
    },
  });
  const serialized = JSON.stringify(baseline);
  for (const forbidden of ["record-id", "Private notification", "Private message", "Private badge", "Private emotion", "Private utility"]) {
    assert(!serialized.includes(forbidden), `baseline leaked ${forbidden}`);
  }
  assert(serialized.includes('"confidence":0.82'), "feedback confidence should remain available");
});

Deno.test("Expression Shadow plan keeps scores but removes business values", () => {
  const minimized = minimizeExpressionShadowPlan({
    status: "auto_planned",
    planner_version: "test-v1",
    domain_key: "expense",
    current_record: { merchant_name: "Private Merchant", amount: 123.45 },
    candidate_count: 1,
    candidates: [{
      candidate_id: "candidate-1",
      claim_type: "comparison",
      dimension: "frequency",
      claim: { semantic_key: "merchant_week_count", amount: 123.45, merchant_name: "Private Merchant" },
      quality: { importance: 0.8, amount: 987.65, private_note: "do not keep" },
      eligibility: {
        eligible: true,
        blocked_reasons: [],
        surface_eligibility: { shortcut_notification: { eligible: true, private_note: "do not keep" } },
      },
      scoring: {
        surfaces: { shortcut_notification: { eligible: true, score: 72, passes_threshold: true, private_note: "do not keep" } },
      },
    }],
    plan_summary: {
      shortcut_notification: {
        capacity: 1,
        selected_count: 1,
        selected: [{ candidate_id: "candidate-1", semantic_key: "merchant_week_count", score: 72, selection_mode: "primary" }],
        fallback_used: false,
        silent: false,
      },
    },
    eligibility_summary: { total_candidates: 1, private_note: "do not keep" },
  });
  const serialized = JSON.stringify(minimized);
  for (const forbidden of ["Private Merchant", "123.45", "987.65", "private_note", "do not keep", "current_record", "candidate-1"]) {
    assert(!serialized.includes(forbidden), `minimized plan leaked ${forbidden}`);
  }
  assert(serialized.includes("merchant_week_count"), "semantic key should remain available");
  assert(serialized.includes('"score":72'), "deterministic score should remain available");
});
