import {
  buildCrossRecordSourceRecord,
  buildDataPlannerSourceRecord,
  buildExpressionShadowPlan,
  buildGenericExpressionShadowPlan,
  buildIncomePlannerSourceRecord,
} from "./expression-shadow-planner.ts";
import type { ShadowExpenseTransaction } from "./expression-shadow-planner.ts";
import { plannerVoiceBriefFromPlan } from "./planner-voice-brief.ts";
// @ts-ignore Shared JavaScript candidate module.
import { clockMinutes } from "../_shared/expression-core/sleep-candidates.mjs";

type RecordFields = Record<string, unknown>;

interface LocalPlannerInput {
  current: RecordFields;
  history?: RecordFields[];
  includeRelatedRecords?: boolean;
}

function payload(record: RecordFields): RecordFields {
  return (record.payload_jsonb ?? {}) as RecordFields;
}

function sleepProfile(current: RecordFields, history: RecordFields[]): RecordFields {
  const day = typeof current.record_date === "string" ? Date.parse(current.record_date) : NaN;
  if (!Number.isFinite(day)) return {};
  const earliest = day - 30 * 24 * 60 * 60 * 1000;
  const nights = new Map<string, RecordFields>();
  for (const row of [...history].sort((a, b) => Date.parse(String(b.occurred_at)) - Date.parse(String(a.occurred_at)))) {
    if (typeof row.record_date !== "string" || Date.parse(row.record_date) < earliest ||
      Date.parse(row.record_date) >= day || nights.has(row.record_date)) continue;
    nights.set(row.record_date, row);
  }
  const start: number[] = [];
  const wake: number[] = [];
  for (const row of nights.values()) {
    const fields = payload(row);
    const startMinute = clockMinutes(fields.sleep_start_at);
    const wakeMinute = clockMinutes(fields.wake_at);
    if (startMinute !== null) start.push(startMinute);
    if (wakeMinute !== null) wake.push(wakeMinute);
  }
  function averageClock(samples: number[]): string | null {
    if (samples.length < 3) return null;
    const shifted = samples.map((minute) => (minute + 720) % 1440);
    const minute = (Math.floor(shifted.reduce((sum, value) => sum + value, 0) / shifted.length) + 720) % 1440;
    return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
  }
  return {
    chronotype: { typical_sleep_start: averageClock(start), typical_wake: averageClock(wake) },
    chronotype_source_ids: [...nights.values()].filter(row =>
      clockMinutes(payload(row).sleep_start_at) !== null || clockMinutes(payload(row).wake_at) !== null
    ).map(row => row.id),
  };
}

function foodProfile(current: RecordFields, history: RecordFields[]): RecordFields {
  const meal = payload(current).meal_type;
  if (typeof meal !== "string" || !meal.trim()) return {};
  const recordedAt = Date.parse(String(current.occurred_at)) || Date.parse(String(current.record_date));
  if (!Number.isFinite(recordedAt)) return {};
  const cutoff = recordedAt - 30 * 24 * 60 * 60 * 1000;
  const samples = history.flatMap(row => {
    const values = payload(row);
    const at = Date.parse(String(row.occurred_at));
    const kcal = values.total_calorie_kcal;
    return at >= cutoff && at <= recordedAt && values.meal_type === meal &&
      typeof kcal === "number" && Number.isFinite(kcal) ? [kcal] : [];
  }).sort((a, b) => a - b);
  if (samples.length < 5) return {};
  const mid = Math.floor(samples.length / 2);
  const median = samples.length % 2 ? samples[mid] : (samples[mid - 1] + samples[mid]) / 2;
  return { meal_baseline: { [meal]: { n: samples.length, median_kcal: Math.round(median) } } };
}

export function buildLocalSharedPlan(input: LocalPlannerInput): RecordFields | null {
  const current = input.current;
  const id = current.id;
  const domain = current.domain_key;
  if (typeof id !== "string" || typeof domain !== "string") return null;
  const knownAt = Date.parse(String(current.created_at));
  const eventAt = Date.parse(String(current.occurred_at));
  const history = (input.history ?? []).filter((row) =>
    row.id !== id && Date.parse(String(row.created_at)) < knownAt);
  const relatedRecords = input.includeRelatedRecords === false ? [] : history.filter((row) => {
    const gap = eventAt - Date.parse(String(row.occurred_at));
    return gap >= 0 && gap <= 180 * 60 * 1000;
  }).map((row) => buildCrossRecordSourceRecord(
    row, row.domain_key === "expense" ? "transactions" : row.domain_key === "income" ? "income_records" : "data_records",
  ));
  const sameDomain = history.filter((row) =>
    row.domain_key === domain && String(row.record_date) <= String(current.record_date) &&
    (domain === "expense" || !Number.isFinite(eventAt) ||
      !Number.isFinite(Date.parse(String(row.occurred_at))) || Date.parse(String(row.occurred_at)) <= eventAt));
  const records = [current, ...sameDomain];
  if (domain === "expense") {
    return buildExpressionShadowPlan({
      currentRecordId: id,
      transactions: records as unknown as ShadowExpenseTransaction[],
      relatedRecords,
      currentOnly: input.history === undefined || !Number.isFinite(knownAt),
      requirePreciseRelatedTime: true,
    });
  }
  return buildGenericExpressionShadowPlan({
    domainKey: domain,
    currentOnly: input.history === undefined || !Number.isFinite(knownAt),
    currentRecordId: id,
    records: records.map(domain === "income" ? buildIncomePlannerSourceRecord : buildDataPlannerSourceRecord),
    domainProfile: domain === "sleep" ? sleepProfile(current, sameDomain)
      : domain === "food" ? foodProfile(current, sameDomain) : {},
    relatedRecords,
  });
}

export function buildLocalSharedVoiceBrief(input: LocalPlannerInput) {
  const plan = buildLocalSharedPlan(input);
  const brief = plan ? plannerVoiceBriefFromPlan(plan) : null;
  if (!brief) return null;
  // The plan uses all local evidence for its calculation. Keep only a bounded
  // set of opaque references in the packet, with the primary record first.
  const refs = [...new Set(brief.evidence.map(ref => ref.reference))];
  const allowed = new Set([String(input.current.id), ...refs.filter(id => id !== input.current.id).slice(0, 7)]);
  return {
    ...brief,
    evidence: brief.evidence.filter(ref => allowed.has(ref.reference)),
    number_facts: brief.number_facts.map(fact => ({
      ...fact, evidence: fact.evidence.filter(ref => allowed.has(ref.reference)),
    })),
  };
}
