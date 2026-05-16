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
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const MOONSHOT_TEXT_ENDPOINT = "https://api.moonshot.cn/v1/chat/completions";
const MOONSHOT_TEXT_MODEL    = "moonshot-v1-32k";
const PROMPT_VERSION         = "insights-v1";
const CACHE_TTL_MS           = 30 * 60 * 1000; // 30 分钟内同 hash 不重复调用

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

// ───────────── 数据指纹（用于缓存命中） ─────────────
async function hashString(s: string): Promise<string> {
  const data = new TextEncoder().encode(s);
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

// ───────────── Prompt 构造 ─────────────
function buildPrompt(days: number, maturity: { key: string; label: string; tone: string }, rows: any[], stats: any) {
  const stageDirective = {
    seed:    "用户记录刚开始。你的角色是温柔的陪伴者。只描述他记下了什么、鼓励继续，绝对不下结论、不做关联、不给建议。",
    sprout:  "数据量很少。你只能指出极值（最高/最低），但要明确说'样本少不能下结论'。",
    growing: "可以描述模式（周末高低、平均水平），但不要做跨域关联推断。",
    mature:  "可以做跨域'观察'，比如'有运动的天睡得更长'，但要标注样本数。可以给 1-2 条具体行动建议。",
    rich:    "可以给出基于个人基准线的具体观察和可执行建议。建议必须是具体动作，不能是'多注意休息'这类废话。",
  }[maturity.key];

  return `你是一位温柔但克制的个人数据分析师。用户已经记录了 ${stats.activeDays}/${days} 天的多域生活数据，当前处于「${maturity.label}」阶段。

【你的角色定位】
${stageDirective}

【硬性规则】
1. 只说数据能支撑的话，永远不要编造数字或事实
2. 建议必须具体到行动，不要"多注意休息""保持平衡"这类废话
3. 样本不足的关联必须明确标注"样本仅 N 天，仅供参考"
4. 不要刻意找问题，如果数据看起来正常就肯定它
5. 用第二人称"你"称呼用户，口吻像朋友而非医生

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
${JSON.stringify(rows.filter(r => r.has_any_data).map(r => ({
  date: r.date,
  expense: Number(r.expense_total) || 0,
  income: Number(r.income_total) || 0,
  sleepMin: Number(r.sleep_minutes) || 0,
  sleepScore: r.sleep_score_avg != null ? Number(r.sleep_score_avg) : null,
  sportMin: Number(r.sport_minutes) || 0,
  foodCal: Number(r.food_calories) || 0,
  foodMeals: Number(r.food_meals) || 0,
  readingMin: Number(r.reading_minutes) || 0,
})), null, 0)}

【输出要求】
严格按如下 JSON 格式输出，不要任何前后缀文字：
{
  "headline": "一句概括这 ${days} 天的核心观察，不超过 25 字",
  "observations": ["观察 1（一句话，含具体数字）", "观察 2", "..."],
  "suggestions": ["具体行动建议 1", "..."],
  "encouragement": "一段温和的鼓励或下一阶段引导，1-2 句话"
}

注意：
- ${maturity.key === "seed" ? "observations 和 suggestions 都可以为空数组 []" : "observations 至少 1 条"}
- ${maturity.key === "seed" || maturity.key === "sprout" ? "suggestions 留空数组，现阶段不给建议" : "suggestions 1-3 条"}
- 全文中文`;
}

function formatMarkdown(payload: any): string {
  const parts: string[] = [];
  if (payload.headline) parts.push(`**${payload.headline}**\n`);
  if (payload.observations?.length) {
    parts.push("### 观察");
    payload.observations.forEach((o: string) => parts.push(`- ${o}`));
    parts.push("");
  }
  if (payload.suggestions?.length) {
    parts.push("### 建议");
    payload.suggestions.forEach((s: string) => parts.push(`- ${s}`));
    parts.push("");
  }
  if (payload.encouragement) parts.push(payload.encouragement);
  return parts.join("\n");
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

    // 2. 解析请求
    const body = await req.json().catch(() => ({}));
    const days = [7, 14, 30].includes(body.days) ? body.days : 14;
    const force = !!body.force;

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
    const apiKey = getEnv("MOONSHOT_API_KEY");
    const prompt = buildPrompt(days, maturity, rows, stats);

    const aiResp = await fetch(MOONSHOT_TEXT_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${apiKey}` },
      body: JSON.stringify({
        model: MOONSHOT_TEXT_MODEL,
        messages: [{ role: "user", content: prompt }],
        temperature: 0.4,
        max_tokens: 1024,
        response_format: { type: "json_object" },
      }),
    });

    if (!aiResp.ok) {
      const errText = await aiResp.text();
      return jsonResponse({ error: "AI 服务返回错误：" + errText.slice(0, 200) }, 502);
    }

    const aiJson = await aiResp.json();
    const aiContent = aiJson.choices?.[0]?.message?.content || "";
    const tokenUsage = aiJson.usage || null;

    let payload: any;
    try {
      payload = extractJson(aiContent);
    } catch (e) {
      return jsonResponse({ error: String(e), raw: aiContent.slice(0, 500) }, 500);
    }

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
        model: MOONSHOT_TEXT_MODEL,
        prompt_version: PROMPT_VERSION,
        token_usage: tokenUsage,
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
