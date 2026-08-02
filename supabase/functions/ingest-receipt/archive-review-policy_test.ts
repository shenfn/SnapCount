import {
  builtinArchiveReviewReasons,
  looksLikeJieziAppScreenshot,
} from "./archive-review-policy.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("valid wallet evidence remains eligible for automatic archive", () => {
  const reasons = builtinArchiveReviewReasons({
    domainKey: "wallet",
    title: "支付宝余额",
    summary: "支付宝余额 320.50 元",
    payload: {
      account_name: "支付宝余额",
      account_type: "alipay",
      amount: 320.5,
      institution: "支付宝",
    },
  });

  assert(
    reasons.length === 0,
    "strong positive wallet evidence should not be blocked",
  );
});

Deno.test("non-positive wallet amount always requires review", () => {
  const reasons = builtinArchiveReviewReasons({
    domainKey: "wallet",
    title: "微信余额",
    payload: {
      account_name: "微信余额",
      account_type: "wechat",
      amount: 0,
    },
  });

  assert(
    reasons.some((reason) => reason.code === "wallet_non_positive_amount"),
    "zero-value wallet snapshots must not auto-archive",
  );
});

Deno.test("SnapCount home screenshots require review even with high-confidence wallet fields", () => {
  const reasons = builtinArchiveReviewReasons({
    domainKey: "wallet",
    title: "个人数据平台",
    summary: "今日支出 15 元，当前余额为 0",
    payload: {
      account_name: "个人数据平台",
      account_type: "other",
      amount: 0,
      institution: "个人数据平台",
    },
  });

  assert(
    reasons.some((reason) => reason.code === "wallet_generic_account"),
    "the app's own dashboard must be routed to review",
  );
  assert(
    reasons.some((reason) => reason.code === "wallet_weak_evidence"),
    "generic wallet records without financial evidence must be reviewed",
  );
});

Deno.test("other domains are unaffected by wallet review rules", () => {
  const reasons = builtinArchiveReviewReasons({
    domainKey: "sleep",
    title: "个人数据平台",
    payload: { amount: 0 },
  });

  assert(
    reasons.length === 0,
    "wallet-specific safeguards must not change other domains",
  );
});

Deno.test("Jiezi dashboard evidence is routed away from financial archive", () => {
  assert(
    looksLikeJieziAppScreenshot({
      title: "个人数据平台",
      summary: "今日支出 15 元，当前余额为 0",
    }),
    "the app dashboard should be identified from model text",
  );
  assert(
    !looksLikeJieziAppScreenshot({
      title: "微信余额",
      summary: "当前余额 320 元",
    }),
    "a real wallet screenshot should not be blocked by the app detector",
  );
});
