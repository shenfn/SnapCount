import {
  collectVoiceCandidateTexts,
  isStructurallyCompleteVoiceText,
  selectVoiceCandidate,
  voiceExpressionSimilarity,
} from "./voice-output.ts";
import { resolveExpressedSemanticKey, type ContextPacketCandidate } from "./context-packet.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

Deno.test("EXP-009 rejects a dangling possessive fragment before persistence", () => {
  assert(
    !isStructurallyCompleteVoiceText("的3元，像是给忙碌生活留了个小口。"),
    "a sentence starting with a dangling possessive particle must be rejected",
  );
  assert(
    isStructurallyCompleteVoiceText("杭州深度求索这笔3元支出，轻轻记下了。"),
    "a natural complete sentence must remain eligible",
  );
});

Deno.test("EXP-010 detects a repeated expression skeleton after record variables change", () => {
  const score = voiceExpressionSimilarity(
    "杭州深度求索的3元，像是给忙碌生活留了个小口。",
    "广清的九块钱，像是给忙碌留了个小口。",
  );
  assert(score >= 0.64, `the repeated expression skeleton must be detected, got ${score}`);
  assert(
    voiceExpressionSimilarity("今天这笔支出轻轻记下。", "昨晚睡得有点短，下午慢一点。") < 0.64,
    "unrelated expressions must not be treated as duplicates",
  );
});

Deno.test("EXP-010 accepts multiple alternatives from one Voice response", () => {
  const candidates = collectVoiceCandidateTexts({
    companion_message: "第一条表达",
    companion_candidates: ["第二条表达", "第三条表达", "第二条表达"],
  });
  assert(
    candidates.join("|") === "第一条表达|第二条表达|第三条表达",
    `one response should expose unique alternatives in order: ${candidates.join("|")}`,
  );
});

Deno.test("EXP-009 to EXP-011 select the first complete distinct grounded alternative", () => {
  const grounded = "距离上一次同名记录约1天，这次又记下了。";
  const selection = selectVoiceCandidate({
    candidates: [
      "的3元，像是给忙碌生活留了个小口。",
      "这点花费，是对忙碌生活温柔的回应。",
      "杭州深度求索这笔3元支出，轻轻记下了。",
      grounded,
    ],
    recentExpressions: [
      "广清的九块钱，像是给忙碌留了个小口。",
      "的这点甜，是对忙碌生活温柔的回应。",
    ],
    isAllowed: (candidate) => candidate === grounded,
  });

  assert(selection.text === grounded, `the grounded alternative must win, got ${selection.text}`);
  assert(selection.rejected.some((item) => item.reason === "incomplete"), "the fragment rejection must be observable");
  assert(selection.rejected.some((item) => item.reason === "recently_repeated"), "the repetition rejection must be observable");
  assert(selection.rejected.some((item) => item.reason === "not_allowed"), "the Planner alignment rejection must be observable");
});

Deno.test("EXP-011 generic prose cannot bypass a selected Planner repeat interval", () => {
  const selectedCandidate: ContextPacketCandidate = {
    candidate_id: "fact:record-name:previous-gap:example",
    semantic_key: "expense_record_name_previous_gap",
    kind: "expense_record_name_previous_gap",
    dimension: "repeat_interval",
    fact: "距离上一次同名记录已经过去约1天",
    numbers: [1],
    count_numbers: [],
    number_facts: [{
      value: 1,
      meaning: "elapsed_calendar_days",
      role: "measure",
    }],
    source: "expression_planner",
    source_surface: "record_detail",
    planner_version: "expression-shadow-auto-v0.6",
  };
  const generic = "这点花费，给忙碌生活留了个小口。";
  const grounded = "距离上一次同名记录约1天，这次又记下了。";
  const selection = selectVoiceCandidate({
    candidates: [generic, grounded],
    isAllowed: (candidate) => resolveExpressedSemanticKey({
      declaredSemanticKey: selectedCandidate.semantic_key,
      companionMessage: candidate,
      selectedCandidates: [selectedCandidate],
      recordFacts: { merchant_name: "示例商户", amount: 3 },
    }) === selectedCandidate.semantic_key,
  });

  assert(selection.text === grounded, "the selected Planner fact must constrain the visible main expression");
});
