import {
  composeNotificationSlots,
  mergePlannerNotification,
  uniqueNotificationLines,
} from "./notification-text.ts";

const assertEquals = <T>(actual: T, expected: T, message: string) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: expected ${JSON.stringify(expected)}, got ${
        JSON.stringify(actual)
      }`,
    );
  }
};

Deno.test("notification assembly removes an exactly repeated record fact", () => {
  const lines = uniqueNotificationLines([
    "💸 本周复现",
    "这周再次记录了示例商品。",
    "💸 -¥10.00 · 示例商户 · 示例商品 · other",
    "💸 -¥10.00 · 示例商户 · 示例商品 · other",
    "今日已花 ¥30.00（3 笔）",
  ]);

  assertEquals(lines, [
    "💸 本周复现",
    "这周再次记录了示例商品。",
    "💸 -¥10.00 · 示例商户 · 示例商品 · other",
    "今日已花 ¥30.00（3 笔）",
  ], "the current-record fact should appear once");
});

Deno.test("notification assembly preserves distinct facts", () => {
  const lines = uniqueNotificationLines([
    "  本笔支出 10 元  ",
    "本笔支出   10 元",
    "今日已花 30 元",
  ]);

  assertEquals(lines, [
    "本笔支出 10 元",
    "今日已花 30 元",
  ], "whitespace variants should be removed without dropping another fact");
});

Deno.test("planner message is delivered once before stable shortcut facts", () => {
  const notification = mergePlannerNotification(
    "当天同名记录共 3 笔、30 元",
    "💸 -¥10.00 · 示例商户\n今日已花 ¥30.00（3 笔）\n当天同名记录共 3 笔、30 元",
  );

  assertEquals(notification.split("\n"), [
    "当天同名记录共 3 笔、30 元",
    "💸 -¥10.00 · 示例商户",
    "今日已花 ¥30.00（3 笔）",
  ], "planner message should lead without duplicating a fact");
});

Deno.test("companion copy stays before planner and stable shortcut facts", () => {
  const notification = mergePlannerNotification(
    "当天同名记录共 2 笔、21 元",
    "留意到今天在这里有两次记录\n💸 -¥10.00 · 示例商户\n今日已花 ¥21.00（2 笔）",
    "✨ 温和提醒\n留意到今天在这里有两次记录",
  );

  assertEquals(
    notification.split("\n"),
    [
      "✨ 温和提醒",
      "留意到今天在这里有两次记录",
      "当天同名记录共 2 笔、21 元",
      "💸 -¥10.00 · 示例商户",
      "今日已花 ¥21.00（2 笔）",
    ],
    "companion copy should remain the first visible layer without duplication",
  );
});

Deno.test("same claim with different wording is rendered once", () => {
  const notification = mergePlannerNotification(
    "本周在沙县小吃已经记录 4 次",
    "💸 -¥9.18 · 沙县小吃\n今日已花 ¥30.00（3 笔）",
    "这周第 4 次点沙县，熟悉的味道又出现了。",
    {
      companion_claim: {
        semantic_key: "merchant_weekly_recurrence",
        claim_fingerprint: "claim-repeat-4",
      },
      planner_claim: {
        semantic_key: "merchant_weekly_recurrence",
        claim_fingerprint: "claim-repeat-4",
      },
    },
  );

  assertEquals(notification.split("\n"), [
    "这周第 4 次点沙县，熟悉的味道又出现了。",
    "💸 -¥9.18 · 沙县小吃",
    "今日已花 ¥30.00（3 笔）",
  ], "the earlier Voice rendering should own a correctly covered claim");
});

Deno.test("same number from different claims remains visible", () => {
  const lines = composeNotificationSlots([
    {
      slot: "expression_claim",
      text: "本周在该商户记录了 4 次",
      claim: {
        semantic_key: "merchant_weekly_recurrence",
        claim_fingerprint: "merchant-repeat-4",
      },
    },
    {
      slot: "expression_claim",
      text: "本周餐饮分类共有 4 笔",
      claim: {
        semantic_key: "category_weekly_count",
        claim_fingerprint: "category-count-4",
      },
    },
  ]);

  assertEquals(lines, [
    "本周在该商户记录了 4 次",
    "本周餐饮分类共有 4 笔",
  ], "matching numbers must not be treated as matching claims");
});

Deno.test("wrong claim fingerprint cannot suppress the Planner fact", () => {
  const notification = mergePlannerNotification(
    "本周在沙县小吃已经记录 4 次",
    "💸 -¥9.18 · 沙县小吃",
    "这周第 11 次点沙县，看来这家确实合你胃口。",
    {
      companion_claim: {
        semantic_key: "merchant_weekly_recurrence",
        claim_fingerprint: "wrong-repeat-11",
      },
      planner_claim: {
        semantic_key: "merchant_weekly_recurrence",
        claim_fingerprint: "correct-repeat-4",
      },
    },
  );

  assertEquals(notification.split("\n"), [
    "这周第 11 次点沙县，看来这家确实合你胃口。",
    "本周在沙县小吃已经记录 4 次",
    "💸 -¥9.18 · 沙县小吃",
  ], "a mismatched fingerprint must fail closed instead of hiding Planner");
});

Deno.test("missing claim fingerprint cannot suppress the Planner fact", () => {
  const notification = mergePlannerNotification(
    "本周在沙县小吃已经记录 4 次",
    "💸 -¥9.18 · 沙县小吃",
    "这周又去了一次沙县。",
    {
      companion_claim: {
        semantic_key: "merchant_weekly_recurrence",
        claim_fingerprint: null,
      },
      planner_claim: {
        semantic_key: "merchant_weekly_recurrence",
        claim_fingerprint: "correct-repeat-4",
      },
    },
  );

  assertEquals(notification.split("\n"), [
    "这周又去了一次沙县。",
    "本周在沙县小吃已经记录 4 次",
    "💸 -¥9.18 · 沙县小吃",
  ], "missing coverage evidence must preserve the deterministic Planner line");
});

Deno.test("fixed receipt result stays independent from an expression claim", () => {
  const lines = composeNotificationSlots([
    {
      slot: "expression_claim",
      text: "本笔支出 9.18 元，来自沙县小吃",
      claim: {
        semantic_key: "expense_current_amount",
        claim_fingerprint: "expense-9.18",
      },
    },
    {
      slot: "fixed_receipt_result",
      text: "💸 -¥9.18 · 沙县小吃",
      claim: {
        semantic_key: "expense_current_amount",
        claim_fingerprint: "expense-9.18",
      },
    },
  ]);

  assertEquals(lines, [
    "本笔支出 9.18 元，来自沙县小吃",
    "💸 -¥9.18 · 沙县小吃",
  ], "the receipt result must not compete for the expression slot");
});

Deno.test("exact visible text is de-duplicated after claim composition", () => {
  const lines = composeNotificationSlots([
    {
      slot: "expression_claim",
      text: "本周记录 4 次",
      claim: {
        semantic_key: "merchant_weekly_recurrence",
        claim_fingerprint: "merchant-repeat-4",
      },
    },
    {
      slot: "stable_shortcut_fact",
      text: "本周记录   4 次",
      claim: {
        semantic_key: "category_weekly_count",
        claim_fingerprint: "category-count-4",
      },
    },
  ]);

  assertEquals(lines, [
    "本周记录 4 次",
  ], "exact whitespace-normalized text should still appear only once");
});
