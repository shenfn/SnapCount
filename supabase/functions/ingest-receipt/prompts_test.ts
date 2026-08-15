import { buildFeedbackPrompt, buildPrompt, buildVoicePrompt } from "./prompts.ts";
import { buildContextPacket } from "./context-packet.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

Deno.test("recognition prompt does not receive raw companion memory", () => {
  const prompt = buildPrompt({
    clientLocalTime: "2026-08-06 12:00",
    companionEnabled: true,
    memoryEnabled: true,
    persona: "observer",
  });

  assert(!prompt.includes("frequent_merchants_30d"), "recognition prompt must not receive short-term statistics");
  assert(prompt.includes("识别阶段上下文边界"), "recognition prompt must declare its context boundary");
  assert(!prompt.includes("陪伴文案 companion_message"), "recognition prompt must not own the final companion copy");
});

Deno.test("feedback and voice prompts consume a frozen packet", () => {
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
  });
  const voice = buildVoicePrompt({
    domainKey: "expense",
    recordFacts: packet.record_facts,
    signals: packet.selected_candidates.map((candidate) => ({ kind: candidate.kind, fact: candidate.fact })),
    contextPacket: packet,
  });
  const feedback = buildFeedbackPrompt({
    recognizedFields: packet.record_facts,
    contextPacket: packet,
  });

  assert(voice.includes("context-packet-v1"), "voice prompt must include packet version");
  assert(feedback.includes("context-packet-v1"), "feedback prompt must include packet version");
  assert(!feedback.includes("【用户记忆】"), "feedback prompt must not dump raw memory");
  assert(!feedback.includes("不含历史统计；与 emotion_line 不重复"), "feedback rules must allow verified candidate facts");
  assert(feedback.includes("唯一上下文来源"), "feedback prompt must mark packet as the sole context source");
});
