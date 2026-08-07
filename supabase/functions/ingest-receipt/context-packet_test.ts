import {
  buildContextPacket,
  normalizeSemanticMemories,
  selectSemanticContext,
} from "./context-packet.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

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

  assert(packet.packet_version === "context-packet-v1", "packet version must be explicit");
  assert(packet.selected_candidates.length === 1, "packet must carry selected candidates");
  assert(packet.semantic_context.length <= 3, "semantic context must be bounded");
  assert(packet.trace.candidate_count === 1, "packet trace must include candidate count");
  assert(packet.trace.packet_created_at.length > 0, "packet trace must include creation time");
  assert(/^[0-9a-f]{8}$/.test(packet.trace.content_fingerprint), "packet trace must include a deterministic fingerprint");
  assert(packet.trace.memory_loaded_count === 5, "packet trace must include loaded memory count");
  assert(packet.trace.memory_filtered_count === 5, "nonmatching memories must be counted as filtered");
  assert(packet.selected_candidates[0].source === "domain_profile_signal", "candidate source must be explicit");
});
