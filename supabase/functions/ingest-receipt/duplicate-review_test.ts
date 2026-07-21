import {
  findLikelyFinancialDuplicate,
  hammingDistanceHex,
  rankPerceptualCandidates,
  type FinancialPerceptualCandidate,
} from "./duplicate-review.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const baseExpense: FinancialPerceptualCandidate = {
  id: "expense-1",
  perceptualHash: "0000000000000001",
  recordType: "expense",
  referenceTable: "transactions",
  referenceId: "expense-1",
  amount: 70.89,
  merchantOrSource: "无燎鲜货火锅自助",
  platform: "美团",
  paymentMethod: "微信支付",
  occurredAt: "2026-07-21T17:40:00+08:00",
  occurredDate: "2026-07-21",
  timePrecision: "datetime",
  createdAt: "2026-07-21T17:41:00+08:00",
};

Deno.test("hamming distance validates and compares hexadecimal hashes", () => {
  assert(hammingDistanceHex("0000", "0001") === 1, "one changed bit should have distance 1");
  assert(hammingDistanceHex("0000", "ffff") === 16, "four hexadecimal digits should contain 16 changed bits");
  assert(hammingDistanceHex("invalid", "0000000") === null, "invalid hexadecimal values must be ignored");
});

Deno.test("candidate ranking chooses the closest valid image instead of the newest row", () => {
  const ranked = rankPerceptualCandidates("0000000000000000", [
    { ...baseExpense, id: "newer", referenceId: "newer", perceptualHash: "000000000000000f", createdAt: "2026-07-21T18:00:00+08:00" },
    { ...baseExpense, id: "closer", referenceId: "closer", perceptualHash: "0000000000000001", createdAt: "2026-07-21T17:00:00+08:00" },
  ]);
  assert(ranked[0]?.referenceId === "closer", "the lowest Hamming distance should win");
});

Deno.test("matching expense facts route a perceptually similar image to review", () => {
  const match = findLikelyFinancialDuplicate("0000000000000000", {
    recordType: "expense",
    amount: 70.89,
    merchantOrSource: "无燎鲜货火锅自助",
    platform: "美团",
    paymentMethod: "微信支付",
    occurredAt: "2026-07-21T17:45:00+08:00",
    occurredDate: "2026-07-21",
    timePrecision: "datetime",
  }, [baseExpense]);
  assert(match?.referenceId === "expense-1", "matching financial evidence should produce a review candidate");
});

Deno.test("different facts or distant times do not become duplicate reviews", () => {
  const differentMerchant = findLikelyFinancialDuplicate("0000000000000000", {
    recordType: "expense",
    amount: 70.89,
    merchantOrSource: "另一家店",
    occurredAt: "2026-07-21T17:45:00+08:00",
    timePrecision: "datetime",
  }, [baseExpense]);
  assert(differentMerchant === null, "similar layouts must not override different merchants");

  const distantTime = findLikelyFinancialDuplicate("0000000000000000", {
    recordType: "expense",
    amount: 70.89,
    merchantOrSource: "无燎鲜货火锅自助",
    occurredAt: "2026-07-21T18:30:00+08:00",
    timePrecision: "datetime",
  }, [baseExpense]);
  assert(distantTime === null, "transactions outside the time window must remain independent");
});

Deno.test("income records use their business date when no transaction time exists", () => {
  const income: FinancialPerceptualCandidate = {
    id: "income-1",
    perceptualHash: "1000000000000000",
    recordType: "income",
    referenceTable: "income_records",
    referenceId: "income-1",
    amount: 500,
    merchantOrSource: "报销",
    occurredDate: "2026-07-21",
    timePrecision: "date",
    createdAt: "2026-07-21T12:00:00+08:00",
  };

  const sameDay = findLikelyFinancialDuplicate("0000000000000000", {
    recordType: "income",
    amount: 500,
    merchantOrSource: "报销",
    occurredDate: "2026-07-21",
    timePrecision: "date",
  }, [income]);
  assert(sameDay?.referenceId === "income-1", "same-day income evidence should be reviewed");

  const nextDay = findLikelyFinancialDuplicate("0000000000000000", {
    recordType: "income",
    amount: 500,
    merchantOrSource: "报销",
    occurredDate: "2026-07-22",
    timePrecision: "date",
  }, [income]);
  assert(nextDay === null, "income on another date should not be treated as the same record");
});
