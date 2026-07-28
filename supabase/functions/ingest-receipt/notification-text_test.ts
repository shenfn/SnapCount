import { mergePlannerNotification, uniqueNotificationLines } from "./notification-text.ts";

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

  assertEquals(notification.split("\n"), [
    "✨ 温和提醒",
    "留意到今天在这里有两次记录",
    "当天同名记录共 2 笔、21 元",
    "💸 -¥10.00 · 示例商户",
    "今日已花 ¥21.00（2 笔）",
  ], "companion copy should remain the first visible layer without duplication");
});
