import { uniqueNotificationLines } from "./notification-text.ts";

const assertEquals = <T>(actual: T, expected: T, message: string) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
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
