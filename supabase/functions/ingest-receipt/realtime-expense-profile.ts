// @ts-ignore Shared experiment module is framework-neutral and bundled with the Edge Function.
import { normalizeEntityText } from "../../../tools/ai-validation/expression-planner/lib/entity-normalizer.mjs";

export interface ExpenseMerchantHistoryRow {
  merchant_name?: string | null;
  amount?: number | string | null;
  transaction_date?: string | null;
}

interface CurrentExpenseFact {
  merchant: string;
  amount: number;
  transactionDate: string;
}

export function normalizeMerchantIdentity(value: unknown): string {
  return normalizeEntityText(value);
}

function dateAtUtc(localDate: string): Date {
  return new Date(`${localDate}T00:00:00Z`);
}

function addDays(localDate: string, days: number): string {
  const date = dateAtUtc(localDate);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function startOfWeek(localDate: string): string {
  const date = dateAtUtc(localDate);
  return addDays(localDate, -((date.getUTCDay() + 6) % 7));
}

export function buildRealtimeMerchantStats(
  rows: ExpenseMerchantHistoryRow[],
  current: CurrentExpenseFact,
) {
  const identity = normalizeMerchantIdentity(current.merchant);
  if (!identity || !Number.isFinite(current.amount)) return null;
  const ninetyDayStart = addDays(current.transactionDate, -89);
  const monthStart = addDays(current.transactionDate, -29);
  const weekStart = startOfWeek(current.transactionDate);
  const matched = rows
    .filter((row) => normalizeMerchantIdentity(row.merchant_name) === identity)
    .filter((row) => row.transaction_date && row.transaction_date >= ninetyDayStart && row.transaction_date <= current.transactionDate)
    .map((row) => ({ amount: Number(row.amount), transactionDate: row.transaction_date as string }))
    .filter((row) => Number.isFinite(row.amount));
  matched.push({ amount: current.amount, transactionDate: current.transactionDate });
  const total = matched.reduce((sum, row) => sum + row.amount, 0);
  return {
    week_count: matched.filter((row) => row.transactionDate >= weekStart).length,
    month_count: matched.filter((row) => row.transactionDate >= monthStart).length,
    count_90d: matched.length,
    last_visit: current.transactionDate,
    avg_amount: Math.round((total / matched.length) * 100) / 100,
    source: "raw_transactions_realtime",
    aliases_collapsed: [...new Set(rows
      .filter((row) => normalizeMerchantIdentity(row.merchant_name) === identity)
      .map((row) => String(row.merchant_name ?? "").trim())
      .filter(Boolean))],
  };
}
