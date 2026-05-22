// ════════════════════════════════════════════════════════════════════
// generate-insights Edge Function
// ────────────────────────────────────────────────────────────────────
// 输入：{ days?: 7 | 14 | 30, force?: boolean }
// 流程：
//   1. 鉴权（取 user_id；单用户阶段 user_id 可能为 null）
//   2. 查询 daily_domain_summary
//   3. 计算 maturity + data_hash
//   4. 若 force=false 且最近 cache（30 分钟内）的 data_hash 命中，直接返回
//   5. 否则调 Moonshot v1-32k 文本模型生成洞察
//   6. 写入 ai_insights 缓存并返回
// ════════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { MODE_GUIDES, SAFETY_RULES, WRITING_RULES, buildDomainHeuristics } from "./prompts.ts";

const MOONSHOT_TEXT_ENDPOINT = "https://api.moonshot.cn/v1/chat/completions";
const MOONSHOT_TEXT_MODEL    = "moonshot-v1-32k";
const RELAY_TEXT_ENDPOINT    = "http://47.76.157.150:8317/v1/chat/completions";
const RELAY_TEXT_MODEL       = "gpt-5.4";
const PROMPT_VERSION         = "insights-v3-freeform-advisor";
const CACHE_TTL_MS           = 30 * 60 * 1000; // 30 分钟内同 hash 不重复调用
const DEFAULT_QUESTION       = "请综合分析我最近的生活状态，重点指出最值得关注的变化和接下来 7 天的行动建议。";

// ───────────── 成熟度档位（与前端 utils/maturity.js 保持一致） ─────────────
const MATURITY_STAGES = [
  { key: "seed",    label: "萌芽", minDays: 0,  nextTarget: 3,  tone: "陪伴" },
  { key: "sprout",  label: "抽芽", minDays: 3,  nextTarget: 7,  tone: "观察" },
  { key: "growing", label: "成长", minDays: 7,  nextTarget: 14, tone: "描述" },
  { key: "mature",  label: "成熟", minDays: 14, nextTarget: 30, tone: "关联" },
  { key: "rich",    label: "丰盈", minDays: 30, nextTarget: null, tone: "基准" },
];

function getMaturity(daysWithData: number) {
  const n = Math.max(0, Math.floor(daysWithData || 0));
  let stage = MATURITY_STAGES[0];
  for (const s of MATURITY_STAGES) {
    if (n >= s.minDays) stage = s;
    else break;
  }
  return { ...stage, days: n };
}

// ───────────── CORS ─────────────
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getEnv(key: string): string {
  const v = Deno.env.get(key);
  if (!v) throw new Error(`Missing env: ${key}`);
  return v;
}

function getOptionalEnv(key: string, fallback: string): string {
  return Deno.env.get(key) || fallback;
}

type InsightProviderName = "auto" | "moonshot" | "relay";

interface TextProviderConfig {
  provider: Exclude<InsightProviderName, "auto">;
  apiKey: string;
  endpoint: string;
  model: string;
}

function getMoonshotTextProvider(): TextProviderConfig {
  return {
    provider: "moonshot",
    apiKey: Deno.env.get("AI_ANALYSIS_API_KEY") || getEnv("MOONSHOT_API_KEY"),
    endpoint: getOptionalEnv("AI_ANALYSIS_ENDPOINT", MOONSHOT_TEXT_ENDPOINT),
    model: getOptionalEnv("AI_ANALYSIS_MODEL", getOptionalEnv("AI_MODEL", MOONSHOT_TEXT_MODEL)),
  };
}

function getRelayTextProvider(): TextProviderConfig {
  return {
    provider: "relay",
    apiKey: getEnv("RELAY_API_KEY"),
    endpoint: getOptionalEnv("RELAY_ENDPOINT", RELAY_TEXT_ENDPOINT),
    model: getOptionalEnv("RELAY_MODEL", RELAY_TEXT_MODEL),
  };
}

function getAnalysisProviderByPreference(pref: string | null | undefined): TextProviderConfig {
  if (pref === "relay") return getRelayTextProvider();
  return getMoonshotTextProvider();
}

// ───────────── 数据指纹（用于缓存命中） ─────────────
async function hashString(s: string): Promise<string> {
  const data = new TextEncoder().encode(s);
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

// ───────────── Prompt 构造 ─────────────
function compactPayload(payload: any) {
  if (!payload || typeof payload !== "object") return {};
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(payload).slice(0, 12)) {
    if (value == null) continue;
    if (["string", "number", "boolean"].includes(typeof value)) out[key] = value;
    else if (Array.isArray(value)) out[key] = value.slice(0, 5);
  }
  return out;
}

function buildDailyRows(rows: any[]) {
  return rows.filter(r => r.has_any_data).map(r => ({
    date: r.date,
    expense: Number(r.expense_total) || 0,
    income: Number(r.income_total) || 0,
    sleepMin: Number(r.sleep_minutes) || 0,
    sleepScore: r.sleep_score_avg != null ? Number(r.sleep_score_avg) : null,
    sportMin: Number(r.sport_minutes) || 0,
    foodCal: Number(r.food_calories) || 0,
    foodMeals: Number(r.food_meals) || 0,
    readingMin: Number(r.reading_minutes) || 0,
  }));
}

function buildDetailRows(transactions: any[], incomes: any[], records: any[]) {
  const walletRecords = records
    .filter(r => r.domain_key === "wallet")
    .map(r => {
      const payload = r.payload_jsonb || {};
      return {
        date: r.occurred_at ? String(r.occurred_at).slice(0, 10) : null,
        title: r.title,
        summary: r.summary,
        recordKind: payload.record_kind,
        accountName: payload.account_name,
        accountType: payload.account_type,
        amount: Number(payload.amount) || 0,
        dueDate: payload.due_date,
        billDay: payload.bill_day,
        minimumPayment: payload.minimum_payment,
        status: payload.status,
      };
    });
  return {
    expenses: transactions.map(r => ({
      date: r.transaction_date,
      time: r.transaction_time,
      amount: Number(r.amount) || 0,
      merchant: r.merchant_name,
      platform: r.platform,
      category: r.category,
      note: r.note,
    })),
    incomes: incomes.map(r => ({
      date: r.income_date,
      amount: Number(r.amount) || 0,
      category: r.category,
      source: r.source_name,
      recurringDay: r.recurring_day,
      note: r.note,
    })),
    lifeRecords: records.map(r => ({
      date: r.occurred_at ? String(r.occurred_at).slice(0, 10) : null,
      domain: r.domain_key,
      title: r.title,
      summary: r.summary,
      payload: compactPayload(r.payload_jsonb),
    })),
    walletRecords,
  };
}

function getShanghaiDateParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date).reduce((acc: any, p) => {
    if (p.type !== "literal") acc[p.type] = p.value;
    return acc;
  }, {});
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    iso: `${parts.year}-${parts.month}-${parts.day}`,
  };
}

function daysBetweenShanghai(fromIso: string, toIso: string) {
  const from = new Date(`${fromIso}T00:00:00+08:00`).getTime();
  const to = new Date(`${toIso}T00:00:00+08:00`).getTime();
  return Math.max(0, Math.ceil((to - from) / 86400000));
}

function nextMonthlyDate(dayOfMonth: number, base = getShanghaiDateParts()) {
  const day = Math.min(Math.max(Math.floor(dayOfMonth || 15), 1), 28);
  let y = base.year;
  let m = base.month;
  if (base.day >= day) {
    m += 1;
    if (m > 12) {
      y += 1;
      m = 1;
    }
  }
  return `${y}-${String(m).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function extractMonthlyDay(question: string, keywords: string[], fallback: number) {
  for (const keyword of keywords) {
    const m = question.match(new RegExp(`${keyword}[^\\d]{0,8}(\\d{1,2})\\s*号`));
    if (m) return Number(m[1]);
  }
  const general = question.match(/每月\s*(\d{1,2})\s*号.*?(发工资|工资|房租|交租|租金)/);
  if (general) return Number(general[1]);
  return fallback;
}

function extractDailyWage(question: string) {
  const m = question.match(/(?:一天|每天|日薪)[^\d]{0,8}(\d+(?:\.\d+)?)\s*元/);
  return m ? Number(m[1]) : null;
}

function extractCurrentCash(question: string) {
  const m = question.match(/(?:身上|余额|现金|银行卡|目前有|现在有|手里)[^\d]{0,10}(\d+(?:\.\d+)?)\s*元/);
  return m ? Number(m[1]) : null;
}

function includesAny(text: string, words: string[]) {
  return words.some(w => text.includes(w));
}

function nextDueDateFromBillDay(dayOfMonth: number, base = getShanghaiDateParts()) {
  return nextMonthlyDate(dayOfMonth, base);
}

function summarizeWallet(details: any, today = getShanghaiDateParts(), nextPayday?: string) {
  const latestByAccount = new Map<string, any>();
  for (const row of details.walletRecords || []) {
    const key = `${row.recordKind || ""}:${row.accountName || ""}:${row.accountType || ""}`;
    const prev = latestByAccount.get(key);
    if (!prev || String(row.date || "") >= String(prev.date || "")) latestByAccount.set(key, row);
  }
  const snapshots = Array.from(latestByAccount.values());
  const cashAccounts = snapshots.filter((r: any) => r.recordKind === "cash_snapshot" && Number(r.amount) > 0);
  const liabilities = snapshots.filter((r: any) => r.recordKind === "liability_snapshot" && Number(r.amount) > 0 && r.status !== "paid");
  const liabilitiesWithDue = liabilities.map((r: any) => {
    const dueDate = r.dueDate || (r.billDay ? nextDueDateFromBillDay(Number(r.billDay), today) : null);
    return { ...r, computedDueDate: dueDate };
  });
  const shortTermLiabilities = nextPayday
    ? liabilitiesWithDue.filter((r: any) => !r.computedDueDate || r.computedDueDate <= nextPayday)
    : liabilitiesWithDue;
  const availableCash = cashAccounts.reduce((s: number, r: any) => s + (Number(r.amount) || 0), 0);
  const shortTermLiabilityTotal = shortTermLiabilities.reduce((s: number, r: any) => s + (Number(r.amount) || 0), 0);
  return {
    available_cash_total: Math.round(availableCash),
    short_term_liability_total: Math.round(shortTermLiabilityTotal),
    cash_accounts: cashAccounts,
    liabilities: liabilitiesWithDue,
    short_term_liabilities: shortTermLiabilities,
    has_wallet_snapshot: snapshots.length > 0,
  };
}

function buildFinanceProjection(stats: any, details: any, question: string) {
  const today = getShanghaiDateParts();
  const paydayDay = extractMonthlyDay(question, ["发工资", "工资", "薪"], 15);
  const rentDay = extractMonthlyDay(question, ["房租", "交租", "租金"], paydayDay);
  const nextPayday = nextMonthlyDate(paydayDay, today);
  const daysUntilNextPayday = daysBetweenShanghai(today.iso, nextPayday);
  const dailyWage = extractDailyWage(question);
  const explicitCurrentCash = extractCurrentCash(question);
  const rentCandidates = details.expenses.filter((r: any) => includesAny(`${r.category || ""}${r.merchant || ""}${r.note || ""}`, ["房租", "租金", "租房", "交租"]));
  const salaryCandidates = details.incomes.filter((r: any) => includesAny(`${r.category || ""}${r.source || ""}${r.note || ""}`, ["工资", "薪资", "薪水", "实习", "劳务"]));
  const recordedNet = stats.incomeTotal - stats.expenseTotal;
  const rentTotal = rentCandidates.reduce((s: number, r: any) => s + (Number(r.amount) || 0), 0);
  const expenseWithoutRent = Math.max(0, stats.expenseTotal - rentTotal);
  const dayBase = Math.max(1, stats.expenseDays);
  const dailyExpenseAvg = stats.expenseTotal / dayBase;
  const dailyExpenseWithoutRentAvg = expenseWithoutRent / dayBase;
  const wallet = summarizeWallet(details, today, nextPayday);
  const walletCash = wallet.has_wallet_snapshot ? wallet.available_cash_total : null;
  const proxyCash = explicitCurrentCash ?? walletCash ?? recordedNet;
  const cashAfterShortTermLiabilities = proxyCash - wallet.short_term_liability_total;
  const safeDailyBudgetByRecordedNet = daysUntilNextPayday > 0 ? proxyCash / daysUntilNextPayday : proxyCash;
  const safeDailyBudgetAfterLiabilities = daysUntilNextPayday > 0 ? cashAfterShortTermLiabilities / daysUntilNextPayday : cashAfterShortTermLiabilities;
  const projectedDailyNeed = dailyExpenseWithoutRentAvg * daysUntilNextPayday;
  return {
    today: today.iso,
    payday_day: paydayDay,
    rent_day: rentDay,
    next_payday: nextPayday,
    days_until_next_payday: daysUntilNextPayday,
    daily_wage_from_user: dailyWage,
    explicit_current_cash: explicitCurrentCash,
    wallet,
    current_cash_known: explicitCurrentCash != null || walletCash != null,
    current_cash_source: explicitCurrentCash != null ? "user_question" : walletCash != null ? "wallet_snapshot" : "recorded_net_proxy",
    recorded_net_balance_proxy: Math.round(recordedNet),
    recorded_income_total: Math.round(stats.incomeTotal),
    recorded_expense_total: Math.round(stats.expenseTotal),
    rent_candidates: rentCandidates,
    salary_candidates: salaryCandidates,
    rent_total_in_records: Math.round(rentTotal),
    daily_expense_avg: Math.round(dailyExpenseAvg),
    daily_expense_without_rent_avg: Math.round(dailyExpenseWithoutRentAvg),
    safe_daily_budget_by_available_proxy: Math.round(safeDailyBudgetByRecordedNet),
    safe_daily_budget_after_short_term_liabilities: Math.round(safeDailyBudgetAfterLiabilities),
    projected_daily_need_until_payday: Math.round(projectedDailyNeed),
    projected_gap_by_proxy: Math.round(cashAfterShortTermLiabilities - projectedDailyNeed),
  };
}

function buildRouterPrompt(days: number, maturity: any, question: string, stats: any) {
  return `你是 SnapCount 的意图路由器，只负责判断用户要分析什么，不做正式回答。

【用户问题】
${question}

【可用数据概况】
- 范围：最近 ${days} 天
- 活跃记录：${stats.activeDays} 天，成熟度：${maturity.label}
- 财务：消费 ${stats.expenseDays} 天 ¥${stats.expenseTotal.toFixed(0)}，收入 ${stats.incomeDays} 天 ¥${stats.incomeTotal.toFixed(0)}
- 睡眠：${stats.sleepDays} 天${stats.sleepScoreAvg ? `，平均评分 ${stats.sleepScoreAvg.toFixed(1)}` : ""}
- 运动：${stats.sportDays} 天，累计 ${stats.sportTotalMin.toFixed(0)} 分钟
- 饮食：${stats.foodDays} 天，累计 ${stats.foodCaloriesTotal.toFixed(0)} 千卡，${stats.foodMealsTotal} 餐
- 阅读：${stats.readingDays} 天

【可选模式】
finance_cashflow：钱够不够花、每日预算、月底结余、工资/房租/固定支出
finance_spending_pattern：哪里花多了、消费规律、周期性支出
sleep_quality：睡眠变差、睡眠质量、睡眠与其他域关联
diet_pattern：饮食结构、非热量维度、零食/补给/饮品、饮食与状态关联
exercise_pattern：运动频率、运动与睡眠/饮食关联
cross_domain_life_review：整体状态、多域联动、接下来 7 天优先级
unknown：当前数据无法支持或问题不清楚

【输出要求】
严格输出 JSON，不要任何前后缀：
{
  "primary_mode": "finance_cashflow",
  "mode_label": "财务现金流",
  "secondary_modes": ["diet_pattern"],
  "user_goal": "用户真实想解决的问题",
  "time_horizon": "current_month|recent_days|next_7_days|unknown",
  "required_context": ["daily_summary", "detail_records"],
  "analysis_plan": ["步骤1", "步骤2", "步骤3"],
  "confidence": 0.9,
  "clarifying_question": null
}`;
}

function buildExpertPrompt(days: number, maturity: { key: string; label: string; tone: string }, rows: any[], stats: any, question: string, route: any, details: any) {
  const stageDirective = {
    seed:    "用户记录刚开始。你的角色是温柔的陪伴者。只描述他记下了什么、鼓励继续，绝对不下结论、不做关联、不给建议。",
    sprout:  "数据量很少。你只能指出极值（最高/最低），但要明确说'样本少不能下结论'。",
    growing: "可以描述模式（周末高低、平均水平），但不要做跨域关联推断。",
    mature:  "可以做跨域'观察'，比如'有运动的天睡得更长'，但要标注样本数。可以给 1-2 条具体行动建议。",
    rich:    "可以给出基于个人基准线的具体观察和可执行建议。建议必须是具体动作，不能是'多注意休息'这类废话。",
  }[maturity.key];

  const financeProjection = buildFinanceProjection(stats, details, question);
  const domainHeuristics = buildDomainHeuristics(route);

  return `你是 SnapCount 的个人生活数据顾问。用户已经记录了 ${stats.activeDays}/${days} 天的多域生活数据，当前处于「${maturity.label}」阶段。

【你的角色定位】
${stageDirective}
${MODE_GUIDES[route.primary_mode] || MODE_GUIDES.cross_domain_life_review}

【用户这次真正想问】
${question}

【第一次路由结果】
${JSON.stringify(route, null, 0)}

${SAFETY_RULES}

${WRITING_RULES}

${domainHeuristics}

【本期数据】
- 范围：最近 ${days} 天
- 活跃记录：${stats.activeDays} 天
- 消费：${stats.expenseDays} 天有记录，累计 ¥${stats.expenseTotal.toFixed(0)}
- 收入：${stats.incomeDays} 天有记录，累计 ¥${stats.incomeTotal.toFixed(0)}
- 睡眠：${stats.sleepDays} 天有记录${stats.sleepDays ? `，平均 ${(stats.sleepTotalMin / stats.sleepDays / 60).toFixed(1)} 小时` : ""}${stats.sleepScoreAvg ? `，平均评分 ${stats.sleepScoreAvg.toFixed(1)}` : ""}
- 运动：${stats.sportDays} 天有记录${stats.sportDays ? `，累计 ${stats.sportTotalMin.toFixed(0)} 分钟` : ""}
- 饮食：${stats.foodDays} 天有记录${stats.foodDays ? `，累计 ${stats.foodCaloriesTotal.toFixed(0)} 千卡（${stats.foodMealsTotal} 餐）` : ""}
- 阅读：${stats.readingDays} 天有记录${stats.readingDays ? `，累计 ${stats.readingTotalMin.toFixed(0)} 分钟` : ""}

【每日明细 JSON】（仅有数据的天）
${JSON.stringify(buildDailyRows(rows), null, 0)}

【原始明细 JSON】（供识别商户、备注、周期性规律；如果字段为空就不要推断）
${JSON.stringify(details, null, 0)}

【财务现金流推演辅助 JSON】（仅当用户问钱够不够、能否撑到某日期、每日预算、工资/房租时重点使用）
${JSON.stringify(financeProjection, null, 0)}

【输出要求】
严格按如下 JSON 格式输出，不要任何前后缀文字。除 mode/mode_label/headline/confidence/followup_questions 外，正式回答全部写进 content_md：
{
  "headline": "一句概括这 ${days} 天的核心观察，不超过 25 字",
  "mode": "${route.primary_mode || "cross_domain_life_review"}",
  "mode_label": "${route.mode_label || "全域生活分析"}",
  "content_md": "自由 Markdown 正文。必须先给结论，再按结论 → 关键证据 → 口径说明 → 不确定性 → 行动建议的顺序组织。不要套死板固定栏目，全文控制在 500-900 字。",
  "confidence": 0.72,
  "followup_questions": ["如果缺少关键数据，可以问 1-2 个追问；没有就空数组"]
}

注意：
- content_md 可以使用 Markdown 标题、列表和加粗，但不要超过 900 字
- 如果是 finance_cashflow，content_md 必须包含：结论、推算口径、每日安全预算、关键不确定项
- 如果涉及睡眠、饮食、运动或情绪风险，必须使用生活方式观察表达，不能输出医学诊断或疾病判断
- 如果有钱包快照，要说明使用了钱包快照；如果没有钱包快照，必须说明"记录期净额只能近似代表可用钱，不能等同于真实余额"
- 全文中文`;
}

function formatMarkdown(payload: any): string {
  if (payload.content_md) return String(payload.content_md);
  const parts: string[] = [];
  if (payload.headline) parts.push(`**${payload.headline}**\n`);
  if (payload.answer) parts.push(`${payload.answer}\n`);
  if (payload.observations?.length) {
    parts.push("### 观察");
    payload.observations.forEach((o: string) => parts.push(`- ${o}`));
    parts.push("");
  }
  if (payload.patterns?.length) {
    parts.push("### 规律");
    payload.patterns.forEach((o: string) => parts.push(`- ${o}`));
    parts.push("");
  }
  if (payload.risks?.length) {
    parts.push("### 风险");
    payload.risks.forEach((o: string) => parts.push(`- ${o}`));
    parts.push("");
  }
  if (payload.suggestions?.length) {
    parts.push("### 建议");
    payload.suggestions.forEach((s: string) => parts.push(`- ${s}`));
    parts.push("");
  }
  if (payload.action_plan?.length) {
    parts.push("### 接下来 7 天");
    payload.action_plan.forEach((s: string) => parts.push(`- ${s}`));
    parts.push("");
  }
  if (payload.uncertainty?.length) {
    parts.push("### 还不确定");
    payload.uncertainty.forEach((s: string) => parts.push(`- ${s}`));
    parts.push("");
  }
  if (payload.encouragement) parts.push(payload.encouragement);
  return parts.join("\n");
}

async function callChatJson(apiKey: string, endpoint: string, model: string, prompt: string, maxTokens: number, temperature: number) {
  const resp = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: prompt }],
      temperature,
      max_tokens: maxTokens,
      response_format: { type: "json_object" },
    }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error("AI 服务返回错误：" + errText.slice(0, 200));
  }

  const json = await resp.json();
  const content = json.choices?.[0]?.message?.content || "";
  return { payload: extractJson(content), usage: json.usage || null, model };
}

function extractJson(text: string): any {
  // 优先：直接 JSON.parse
  try { return JSON.parse(text); } catch {}
  // 兜底：抽 ```json ... ``` 块
  const m = text.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (m) { try { return JSON.parse(m[1]); } catch {} }
  // 再兜底：找第一个 { 到最后一个 }
  const a = text.indexOf("{"), b = text.lastIndexOf("}");
  if (a >= 0 && b > a) {
    try { return JSON.parse(text.slice(a, b + 1)); } catch {}
  }
  throw new Error("AI 返回不是合法 JSON：" + text.slice(0, 200));
}

// ───────────── 主流程 ─────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    // 1. 鉴权 - 用 user 自己的 token 创建 client，借用 RLS
    const supabaseUrl = getEnv("SUPABASE_URL");
    const anonKey     = getEnv("SUPABASE_ANON_KEY");
    const authHeader  = req.headers.get("Authorization") || "";
    if (!authHeader) return jsonResponse({ error: "Missing Authorization" }, 401);

    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData } = await supabase.auth.getUser();
    const userId = userData?.user?.id || null;
    let insightProviderPref: InsightProviderName = "auto";
    if (userId) {
      const { data: cfg } = await supabase
        .from("user_configs")
        .select("ai_insight_provider")
        .eq("user_id", userId)
        .maybeSingle();
      if (cfg?.ai_insight_provider === "moonshot" || cfg?.ai_insight_provider === "relay") {
        insightProviderPref = cfg.ai_insight_provider;
      }
    }

    // 2. 解析请求
    const body = await req.json().catch(() => ({}));
    const days = [7, 14, 30].includes(body.days) ? body.days : 14;
    const force = !!body.force;
    const question = String(body.question || DEFAULT_QUESTION).trim().slice(0, 800) || DEFAULT_QUESTION;

    // 3. 拉数据
    const sinceDate = new Date();
    sinceDate.setDate(sinceDate.getDate() - days);
    const sinceStr = sinceDate.toISOString().slice(0, 10);

    const { data: rows, error: queryErr } = await supabase
      .from("daily_domain_summary")
      .select("*")
      .gte("date", sinceStr)
      .order("date", { ascending: true });

    if (queryErr) {
      return jsonResponse({ error: "查询数据失败：" + queryErr.message }, 500);
    }

    if (!rows || rows.length === 0) {
      return jsonResponse({ error: "暂无数据可分析。先去录入一些记录吧。", code: "no_data" }, 400);
    }

    const [
      { data: txRows, error: txErr },
      { data: incomeRows, error: incomeErr },
      { data: lifeRows, error: lifeErr },
    ] = await Promise.all([
      supabase
        .from("transactions")
        .select("transaction_date,transaction_time,amount,merchant_name,platform,category,note")
        .eq("status", "done")
        .eq("type", "expense")
        .gte("transaction_date", sinceStr)
        .order("transaction_date", { ascending: true })
        .limit(120),
      supabase
        .from("income_records")
        .select("income_date,amount,category,source_name,recurring_day,note")
        .gte("income_date", sinceStr)
        .order("income_date", { ascending: true })
        .limit(60),
      supabase
        .from("data_records")
        .select("occurred_at,domain_key,title,summary,payload_jsonb")
        .gte("occurred_at", `${sinceStr}T00:00:00+08:00`)
        .order("occurred_at", { ascending: true, nullsFirst: false })
        .limit(120),
    ]);

    if (txErr) console.warn("查询支出明细失败:", txErr.message);
    if (incomeErr) console.warn("查询收入明细失败:", incomeErr.message);
    if (lifeErr) console.warn("查询生活明细失败:", lifeErr.message);
    const details = buildDetailRows(txRows || [], incomeRows || [], lifeRows || []);

    // 4. 计算 stats + maturity + hash
    const stats = rows.reduce((acc: any, r: any) => {
      acc.expenseTotal += Number(r.expense_total) || 0;
      acc.expenseDays += (Number(r.expense_count) || 0) > 0 ? 1 : 0;
      acc.incomeTotal += Number(r.income_total) || 0;
      acc.incomeDays += (Number(r.income_count) || 0) > 0 ? 1 : 0;
      acc.sleepTotalMin += Number(r.sleep_minutes) || 0;
      acc.sleepDays += (Number(r.sleep_count) || 0) > 0 ? 1 : 0;
      if (r.sleep_score_avg != null) {
        acc.sleepScoreSum += Number(r.sleep_score_avg);
        acc.sleepScoreCnt += 1;
      }
      acc.sportTotalMin += Number(r.sport_minutes) || 0;
      acc.sportDays += (Number(r.sport_count) || 0) > 0 ? 1 : 0;
      acc.readingTotalMin += Number(r.reading_minutes) || 0;
      acc.readingDays += (Number(r.reading_count) || 0) > 0 ? 1 : 0;
      acc.foodCaloriesTotal += Number(r.food_calories) || 0;
      acc.foodMealsTotal += Number(r.food_meals) || 0;
      acc.foodDays += (Number(r.food_meals) || 0) > 0 ? 1 : 0;
      acc.activeDays += r.has_any_data ? 1 : 0;
      return acc;
    }, {
      expenseTotal: 0, expenseDays: 0, incomeTotal: 0, incomeDays: 0,
      sleepTotalMin: 0, sleepDays: 0, sleepScoreSum: 0, sleepScoreCnt: 0,
      sportTotalMin: 0, sportDays: 0,
      readingTotalMin: 0, readingDays: 0,
      foodCaloriesTotal: 0, foodMealsTotal: 0, foodDays: 0,
      activeDays: 0,
    });
    stats.sleepScoreAvg = stats.sleepScoreCnt > 0 ? stats.sleepScoreSum / stats.sleepScoreCnt : null;

    const maturity = getMaturity(stats.activeDays);

    // hash：覆盖范围 + 关键聚合值（粗粒度，避免每条小改动都触发重新生成）
    const hashInput = JSON.stringify({
      days, activeDays: stats.activeDays,
      e: Math.round(stats.expenseTotal),
      i: Math.round(stats.incomeTotal),
      s: Math.round(stats.sleepTotalMin),
      sp: Math.round(stats.sportTotalMin),
      f: Math.round(stats.foodCaloriesTotal),
      r: Math.round(stats.readingTotalMin),
      ed: stats.expenseDays, sd: stats.sleepDays, fd: stats.foodDays,
      q: question,
      tx: details.expenses.length,
      inc: details.incomes.length,
      life: details.lifeRecords.length,
      details,
    });
    const dataHash = await hashString(hashInput);

    // 5. 命中缓存？
    if (!force) {
      const { data: cached } = await supabase
        .from("ai_insights")
        .select("*")
        .eq("data_hash", dataHash)
        .eq("days_range", days)
        .eq("status", "success")
        .order("generated_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (cached) {
        const age = Date.now() - new Date(cached.generated_at).getTime();
        if (age < CACHE_TTL_MS) {
          return jsonResponse({
            cached: true,
            insight: cached,
            maturity,
            stats,
          });
        }
      }
    }

    // 6. 调用 AI
    const routerApiKey = Deno.env.get("AI_ROUTER_API_KEY") || getEnv("MOONSHOT_API_KEY");
    const routerEndpoint = getOptionalEnv("AI_ROUTER_ENDPOINT", MOONSHOT_TEXT_ENDPOINT);
    const routerModel = getOptionalEnv("AI_ROUTER_MODEL", getOptionalEnv("AI_MODEL", MOONSHOT_TEXT_MODEL));
    const analysisProvider = getAnalysisProviderByPreference(insightProviderPref);
    const analysisApiKey = analysisProvider.apiKey;
    const analysisEndpoint = analysisProvider.endpoint;
    const analysisModel = analysisProvider.model;

    let route: any;
    let routerUsage: any = null;
    try {
      const routerResult = await callChatJson(
        routerApiKey,
        routerEndpoint,
        routerModel,
        buildRouterPrompt(days, maturity, question, stats),
        700,
        0.1,
      );
      route = routerResult.payload;
      routerUsage = routerResult.usage;
    } catch (e) {
      console.warn("AI 路由失败，降级为全域分析:", String(e));
      route = {
        primary_mode: "cross_domain_life_review",
        mode_label: "全域生活分析",
        secondary_modes: [],
        user_goal: question,
        time_horizon: "recent_days",
        required_context: ["daily_summary", "detail_records"],
        analysis_plan: ["综合查看多域数据", "识别最值得关注的变化", "给出接下来 7 天行动建议"],
        confidence: 0.4,
        clarifying_question: null,
      };
    }

    let payload: any;
    let analysisUsage: any = null;
    try {
      const analysisResult = await callChatJson(
        analysisApiKey,
        analysisEndpoint,
        analysisModel,
        buildExpertPrompt(days, maturity, rows, stats, question, route, details),
        1800,
        0.35,
      );
      payload = analysisResult.payload;
      analysisUsage = analysisResult.usage;
    } catch (e) {
      return jsonResponse({ error: String(e) }, 500);
    }

    payload.question = question;
    payload.route = route;

    const contentMd = formatMarkdown(payload);

    // 7. 写缓存
    const { data: inserted, error: insertErr } = await supabase
      .from("ai_insights")
      .insert({
        user_id: userId,
        days_range: days,
        maturity_stage: maturity.key,
        active_days: stats.activeDays,
        data_hash: dataHash,
        content_md: contentMd,
        payload_jsonb: payload,
        model: analysisModel,
        prompt_version: PROMPT_VERSION,
        token_usage: { router: routerUsage, analysis: analysisUsage, analysis_provider: analysisProvider.provider, analysis_preference: insightProviderPref },
        status: "success",
      })
      .select()
      .single();

    if (insertErr) {
      console.error("写入 ai_insights 失败:", insertErr.message);
      // 不阻断返回结果给前端
    }

    return jsonResponse({
      cached: false,
      insight: inserted || { content_md: contentMd, payload_jsonb: payload, generated_at: new Date().toISOString() },
      maturity,
      stats,
    });
  } catch (e: any) {
    console.error("[generate-insights] 异常:", e);
    return jsonResponse({ error: String(e?.message || e) }, 500);
  }
});
