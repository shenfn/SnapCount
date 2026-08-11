import { buildFeedbackPrompt, buildPrompt, buildVoicePrompt } from "./prompts.ts";
import { buildContextPacket } from "./context-packet.ts";
import { buildTimeContext } from "./time.ts";

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
  assert(prompt.includes("上传时刻只写入 client_captured_at"), "recognition prompt must not promote capture time to event time");
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

  assert(voice.includes("context-packet-v2"), "voice prompt must include packet version");
  assert(feedback.includes("context-packet-v2"), "feedback prompt must include packet version");
  assert(!feedback.includes("【用户记忆】"), "feedback prompt must not dump raw memory");
  assert(!feedback.includes("不含历史统计；与 emotion_line 不重复"), "feedback rules must allow verified candidate facts");
  assert(feedback.includes("唯一上下文来源"), "feedback prompt must mark packet as the sole context source");
});

Deno.test("voice prompt permits grounded qualitative inference without yielding precise facts", () => {
  const prompt = buildVoicePrompt({
    domainKey: "expense",
    recordFacts: {
      record_type: "expense",
      merchant_name: "青禾茶饮",
      category: "food",
      amount: 6.28,
    },
    signals: [],
  });

  assert(prompt.includes("轻量定性推理"), "voice prompt must allow grounded qualitative inference");
  assert(
    prompt.includes("这个价格看起来像碰上优惠"),
    "voice prompt must include a non-copyable low-price qualitative example",
  );
  assert(
    prompt.includes("只有在记录或同一条已核实信号明确提供相同数字和口径时才能出现"),
    "voice prompt must keep precise claims grounded in a single verified source",
  );
  assert(
    prompt.includes("擅自补商品名、规格、金额、次数、优惠金额或历史统计"),
    "voice prompt must prohibit invented precise facts",
  );
  assert(
    prompt.includes("expressed_semantic_key"),
    "voice prompt must require explicit candidate-expression provenance",
  );
  assert(
    prompt.includes("companion_candidates") && prompt.includes("同一次调用"),
    "voice prompt must request bounded alternatives without adding another model call",
  );
});

Deno.test("voice prompt receives complete time context and prioritizes event time", () => {
  const timeContext = buildTimeContext({
    occurredAt: "2026-08-07T22:41:00Z",
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-08T06:45:00+08:00",
    requestReceivedAt: "2026-08-07T22:46:00Z",
  });
  const prompt = buildVoicePrompt({
    clientLocalTime: "2026-08-08 06:45",
    domainKey: "expense",
    recordFacts: { record_type: "expense", merchant_name: "星之柠", amount: 6.8 },
    signals: [],
    timeContext,
  });

  assert(prompt.includes("【代码计算的时间上下文】"), "voice prompt must identify the trusted time contract");
  assert(prompt.includes('"event_time":"2026-08-08T06:41:00+08:00"'), "voice prompt must include canonical event time");
  assert(prompt.includes('"event_daypart":"morning"'), "voice prompt must include the event daypart");
  assert(prompt.includes("发生时间是描述记录何时发生的唯一优先依据"), "voice prompt must prioritize event time");
  assert(prompt.includes("上传时间只用于判断实时记录或补录关系"), "voice prompt must limit capture-time semantics");
  assert(prompt.includes("禁止写成“凌晨”“深夜”或“夜里”"), "voice prompt must prohibit morning/night contradictions");
});

Deno.test("feedback prompt keeps time context when a frozen packet exists", () => {
  const packet = buildContextPacket({
    domainKey: "expense",
    recordFacts: { record_type: "expense", merchant_name: "星之柠", amount: 6.8 },
    signals: [],
  });
  const timeContext = buildTimeContext({
    occurredAt: "2026-08-08T06:41:00+08:00",
    orderFinishedAt: null,
    clientCapturedAt: "2026-08-08T06:45:00+08:00",
    requestReceivedAt: "2026-08-07T22:46:00Z",
  });
  const prompt = buildFeedbackPrompt({
    contextPacket: packet,
    timeContext,
  });

  assert(prompt.includes("【代码计算的时间上下文】"), "feedback prompt must not hide time context behind the packet");
  assert(prompt.includes('"event_daypart":"morning"'), "feedback prompt must receive the same time contract");
  assert(prompt.includes("发生时间是描述记录何时发生的唯一优先依据"), "feedback prompt must share event-time priority rules");
});
