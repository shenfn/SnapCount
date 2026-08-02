export type BuiltinArchiveReviewReasonCode =
  | "wallet_non_positive_amount"
  | "wallet_generic_account"
  | "wallet_weak_evidence";

export interface BuiltinArchiveReviewReason {
  code: BuiltinArchiveReviewReasonCode;
  message: string;
}

export interface BuiltinArchiveReviewInput {
  domainKey: string;
  title?: string | null;
  summary?: string | null;
  payload?: Record<string, unknown> | null;
}

export interface AppScreenshotEvidenceInput {
  title?: string | null;
  summary?: string | null;
  accountName?: string | null;
}

const GENERIC_ACCOUNT_MARKERS = [
  "个人数据平台",
  "芥子",
  "snapcount",
  "snapflow",
  "数据看板",
  "财务状态",
  "中转站",
  "隐私与留存",
];

const FINANCIAL_ACCOUNT_MARKERS = [
  "银行",
  "信用卡",
  "储蓄卡",
  "微信",
  "零钱",
  "支付宝",
  "余额宝",
  "花呗",
  "白条",
  "月付",
  "现金",
];

const APP_NAVIGATION_MARKERS = ["今日", "收件箱", "记录", "分析", "设置"];

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function number(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string" || value.trim() === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function hasValue(value: unknown): boolean {
  if (value === null || value === undefined) return false;
  if (typeof value === "string") return value.trim() !== "";
  if (typeof value === "number") return Number.isFinite(value);
  return true;
}

export function looksLikeJieziAppScreenshot(
  input: AppScreenshotEvidenceInput,
): boolean {
  const combined = [input.title, input.summary, input.accountName]
    .map(text)
    .join(" ")
    .toLocaleLowerCase();
  if (!combined) return false;

  if (
    ["个人数据平台", "芥子", "snapcount", "snapflow", "中转站", "隐私与留存"]
      .some((marker) => combined.includes(marker.toLocaleLowerCase()))
  ) {
    return true;
  }

  const navigationHits = APP_NAVIGATION_MARKERS.filter((marker) =>
    combined.includes(marker)
  );
  return navigationHits.length >= 3 &&
    combined.includes("今日支出") &&
    combined.includes("当前余额");
}

export function builtinArchiveReviewReasons(
  input: BuiltinArchiveReviewInput,
): BuiltinArchiveReviewReason[] {
  if (input.domainKey !== "wallet") return [];

  const payload = input.payload ?? {};
  const accountName = text(payload.account_name) || text(input.title);
  const combinedLabel = `${accountName} ${text(input.title)} ${
    text(input.summary)
  }`.toLocaleLowerCase();
  const amount = number(payload.amount ?? payload.snapshot_balance);
  const accountType = text(payload.account_type).toLocaleLowerCase();
  const institution = text(payload.institution);
  const reasons: BuiltinArchiveReviewReason[] = [];

  if (amount !== null && amount <= 0) {
    reasons.push({
      code: "wallet_non_positive_amount",
      message: "账户金额不大于 0，需要确认这是否真的是余额或待还截图",
    });
  }

  if (
    GENERIC_ACCOUNT_MARKERS.some((marker) =>
      combinedLabel.includes(marker.toLocaleLowerCase())
    )
  ) {
    reasons.push({
      code: "wallet_generic_account",
      message: "截图看起来像芥子应用页面，需要确认数据类型",
    });
  }

  const hasFinancialName = FINANCIAL_ACCOUNT_MARKERS.some((marker) => (
    accountName.includes(marker) || institution.includes(marker)
  ));
  const hasAccountMetadata = /^\d{4}$/.test(text(payload.last4)) ||
    hasValue(payload.due_date) ||
    hasValue(payload.payment_due_day) ||
    hasValue(payload.statement_start_date) ||
    hasValue(payload.statement_end_date) ||
    hasValue(payload.bill_day);

  if (accountType === "other" && !hasFinancialName && !hasAccountMetadata) {
    reasons.push({
      code: "wallet_weak_evidence",
      message: "缺少账户机构、尾号或账单日期等金融证据，需要人工确认",
    });
  }

  return reasons;
}
