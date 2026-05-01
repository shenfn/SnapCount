// 随手账 · Edge Function: ingest-receipt
// 部署: supabase functions deploy ingest-receipt --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import jpeg from "https://esm.sh/jpeg-js@0.4.4";
import { decode as decodePng } from "https://esm.sh/fast-png@6.2.0";

const MOONSHOT_MODEL    = "moonshot-v1-8k-vision-preview";
const MOONSHOT_ENDPOINT = "https://api.moonshot.cn/v1/chat/completions";
const BUCKET_NAME       = "receipt-images";

// 歺加载：延迟到请求时获取 Secret，避免模块初始化就崩溃
function getEnv(key: string): string {
  const v = Deno.env.get(key);
  if (!v) throw new Error(`Missing required secret: ${key}`);
  return v;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function sha256(buf: ArrayBuffer): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function hammingDistanceHex(a: string | null, b: string | null): number | null {
  if (!a || !b || a.length !== b.length) return null;
  let distance = 0;
  for (let i = 0; i < a.length; i++) {
    const xor = parseInt(a[i], 16) ^ parseInt(b[i], 16);
    distance += xor.toString(2).replace(/0/g, "").length;
  }
  return distance;
}

function decodeImage(bytes: Uint8Array, mime: string): { data: Uint8Array; width: number; height: number } | null {
  try {
    if (mime.includes("png")) {
      const img = decodePng(bytes);
      return { data: img.data, width: img.width, height: img.height };
    }
    const img = jpeg.decode(bytes, { useTArray: true });
    return { data: img.data, width: img.width, height: img.height };
  } catch (e) {
    console.warn("Image decode for perceptual hash failed:", e);
    return null;
  }
}

function computePerceptualHash(bytes: Uint8Array, mime: string): string | null {
  const img = decodeImage(bytes, mime);
  if (!img || img.width <= 0 || img.height <= 0) return null;
  const samples: number[] = [];
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) {
      const srcX = Math.min(img.width - 1, Math.floor((x + 0.5) * img.width / 8));
      const srcY = Math.min(img.height - 1, Math.floor((y + 0.5) * img.height / 8));
      const idx = (srcY * img.width + srcX) * 4;
      const r = img.data[idx] ?? 0;
      const g = img.data[idx + 1] ?? 0;
      const b = img.data[idx + 2] ?? 0;
      samples.push(0.299 * r + 0.587 * g + 0.114 * b);
    }
  }
  const avg = samples.reduce((sum, v) => sum + v, 0) / samples.length;
  let bits = "";
  for (const v of samples) bits += v >= avg ? "1" : "0";
  let hex = "";
  for (let i = 0; i < bits.length; i += 4) {
    hex += parseInt(bits.slice(i, i + 4), 2).toString(16);
  }
  return hex;
}

const PROMPT = `你是个人数据平台的截图识别与路由助手。图片可能来自财务、运动、睡眠、阅读等生活数据域。请先判断图片类型和 record_type，再按对应数据域提取结构化字段。

【图片类型识别】
- payment_confirm：支付成功确认页（有“支付成功”“付款成功”等字样）
- income_confirm：收款成功/已收款确认页（有“你已收款”“收款成功”“资金已存入零钱”“到账成功”等字样）
- wechat_bill：微信账单详情页（有“记录时间”“来源”“备注”字段，灰色背景卡片风格）
- alipay_bill：支付宝账单详情页（有“交易时间”“交易状态”“商家订单号”等字段）
- bank_bill：银行账单/流水页（有银行标志、“账户余额”等）
- chat_transfer：聊天窗口内的转账/收款气泡（有聊天标题、左右气泡、“已收款”“已被接收”等）
- sport_detail：运动详情页，如华为健康/Keep/运动手表记录，标题可能是羽毛球、户外骑行、室内跑步、自由训练等
- sleep_detail：睡眠详情页，有“睡眠”“夜间睡眠”“睡眠评分”“入睡/醒来”“深睡/浅睡/快速眼动”等
- reading_progress：阅读首页/阅读进度页，有“继续阅读”“今日阅读进度”“图书·xx%”“之前读过”等
- order_list：订单列表页，同时出现多笔订单、多个商家、多个金额或“待付款/待收货/已完成”筛选
- other：其他

【record_type 路由规则】
- expense：单笔付款、支付成功、消费、扣款、转出；必须能明确提取一笔交易
- income：你已收款、收款成功、到账、已存入零钱、转入、退款到账、报销到账
- sport：运动详情截图
- sleep：睡眠详情截图
- reading：阅读记录/阅读进度截图
- uncertain：无法判断，或一张图内有多笔记录无法安全拆分
- 如果是 order_list 且页面包含多笔订单，不要自动挑选某一笔，record_type 返回 uncertain，image_type 返回 order_list，并在 summary 说明“多笔订单需人工确认”

【通用字段提取规则】

amount（金额）：
- 数字，不带货币符号，无法识别返回 null
- 若显示为负数（如 -16.00），取绝对值（返回 16.00）
- 若是支出页面，同时有“优惠”或“实付”，以实际支付金额为准
- 若是收入页面，以收款/到账/入账金额为准，不要把余额识别为本次收入

merchant_name（商家）：
- 优先从商家名称/收款方/收款账号字段提取
- 若备注/摘要格式为“扫二维码付款-给X”或“转账给X”或“付款给X”，则 X 为商家名
- 若备注格式为“转账-转给X”，则 X 为商家名
- 若备注含个人姓名（给张三、给李四），merchant_name 填写该姓名
- 无法识别返回 null（不要猜测）

platform（平台）：
从 [美团,微信,京东,拼多多,淘宝,抖音,支付宝,滴滴,饿了么,其他] 中选一个，识别规则（按优先级）：
* 页面含“先用后付”且订单号以 PO 开头 → 拼多多
* 页面含“先用后付”且订单号以 OD 开头 → 淘宝
* image_type 为 wechat_bill，或页面有微信特征（灰色圆角卡片、“记录时间”“来源:自动同步”）→ 微信
* image_type 为 alipay_bill，或页面有支付宝特征（蓝色主题、“交易快照”）→ 支付宝
* 无法判断 → null

category（消费类别）：
从 [food,shopping,transport,entertainment,life,health,education,other] 中选一个
- 微信账单详情页顶部有分类图标+文字，直接使用：
  * 餐饮/美食/餐厅 → food
  * 交通/出行/打车 → transport
  * 购物/网购 → shopping
  * 娱乐/休闲 → entertainment
  * 生活/日用/缴费 → life
  * 医疗/健康/药品 → health
  * 教育/学习 → education
  * 其余 → other
- 无分类图标时，根据商家名和平台推断

payment_method（支付方式）：
从 [微信支付,支付宝,花呗,京东白条,美团月付,拼多多先用后付,银行卡,其他] 中选一个
* 页面含“先用后付”且平台为拼多多 → 拼多多先用后付
* 页面含“先用后付”且平台为淘宝/天猫 → 花呗（花呗先用后付）
* image_type 为 wechat_bill 或平台为微信 → 微信支付
* image_type 为 alipay_bill 或平台为支付宝（且无花呗字样）→ 支付宝
* 页面含“花呗”字样 → 花呗
* 页面含“白条”字样 → 京东白条
* 无法识别 → null

confidence（置信度）：0-1 浮点数，识别整体置信度

record_type（流水类型）：
- expense：付款、支付成功、消费、扣款、转出
- income：你已收款、收款成功、到账、已存入零钱、转入、退款到账、报销到账
- sport：运动详情
- sleep：睡眠详情
- reading：阅读进度
- uncertain：无法判断

income_category（收入类别）：
当 record_type 为 income 时，从 [salary,bonus,freelance,investment,reimbursement,other] 中选一个。
- 工资/薪资/工资单 → salary
- 奖金/绩效/年终奖 → bonus
- 兼职/接单/劳务/服务费 → freelance
- 零钱通/理财收益/分红/利息 → investment
- 报销/退款/返款 → reimbursement
- 个人转账收款、普通收款、无法判断 → other

source_name（收入来源）：
当 record_type 为 income 时，提取付款方、转账方、备注中的来源名称；无法识别返回 null。
- 如果是聊天转账截图，优先使用聊天标题作为来源名称，例如标题为“老妈”，则 source_name 返回“老妈”。
- 左侧对方头像/气泡发来的“已被接收/转账”通常表示对方给我转账并被我接收，record_type 为 income。
- 右侧我方头像/气泡显示“已收款”通常也表示我已收到对方转账，source_name 仍优先使用聊天标题。
- 不要把视频号/广告卡片标题当作收入来源。

occurred_at（业务发生时间）：
- 优先提取支付时间、转账时间、交易时间、账单时间、收款时间、记录时间等字段。
- 微信账单详情页如出现“记录时间 2026年4月24日 13:13”，occurred_at 必须返回 2026-04-24T13:13:00+08:00。
- 返回 ISO 8601 字符串，无法识别返回 null。
- 这是判断真实重复消费的重要字段，同金额同商家但完成时间不同，仍可能是两笔真实交易。
- 如果页面只有“星期二 16:46”这类缺少年月日的聊天时间，不要根据星期几猜测日期，返回 null。

order_finished_at（订单完成时间）：
- 如果页面有明确的“完成时间”“支付完成时间”“收款时间”，返回该时间的 ISO 8601 字符串。
- 如果只有一个交易/转账/收款时间，可与 occurred_at 相同。
- 无法识别返回 null。
- 如果只有星期几或单独时间，没有完整年月日，返回 null。

【内置数据域 payload_jsonb 规则】

当 record_type 为 sport 时：
- domain_key 返回 "sport"
- title 优先返回运动类型，如“羽毛球”“户外骑行”“室内跑步”“自由训练”
- summary 用一句短语概括核心数据，如“运动 100 分钟，消耗 1399 千卡”
- payload_jsonb 至少包含：
  - sport_type：运动类型
  - duration_minutes：运动时长分钟数。例：01:40:14 返回 100.23，00:35:51 返回 35.85
  - calories：总消耗热量，单位千卡，无法识别返回 null
  - source_app：来源 App，无法判断可返回“健康”
- 若图片可见，还要提取 distance_km、avg_speed_kmh、avg_heart_rate、avg_pace、steps、avg_cadence、avg_stride_cm、ascent_m、descent_m、aerobic_training_effect、anaerobic_training_effect、recovery_hours。
- occurred_at 优先使用运动详情页顶部完整时间，例如 2026年4月18日 17:53 返回 2026-04-18T17:53:00+08:00。

当 record_type 为 sleep 时：
- domain_key 返回 "sleep"
- title 返回“夜间睡眠”或页面上的睡眠类型
- summary 用一句短语概括睡眠时长和评分，如“睡眠 5.35 小时，评分 73”
- payload_jsonb 至少包含：
  - sleep_hours：总睡眠小时数。例：5小时21分钟 返回 5.35，4小时39分钟 返回 4.65
  - quality_score：睡眠评分，无法识别返回 null
  - quality_level：>=80 为“优秀”，>=70 为“良好”，>=60 为“一般”，否则“较差”；没有评分时可根据页面描述返回 null
  - source_app：来源 App，无法判断可返回“健康”
- 若图片可见，还要提取 sleep_start_at、wake_at、deep_sleep_minutes、light_sleep_minutes、rem_minutes、awake_minutes。
- occurred_at 使用页面显示日期，若只有日期无具体时间，返回该日期 T12:00:00+08:00。

当 record_type 为 reading 时：
- domain_key 返回 "reading"
- title 优先返回当前正在阅读的书名
- summary 用一句短语概括阅读时间和进度，如“今日阅读 61 分钟，进度 14%”
- payload_jsonb 至少包含：
  - book_name：当前正在阅读的书名
  - reading_minutes：今日阅读时长分钟数。例：1:01 返回 61
  - progress_percent：进度百分比，无法识别返回 null
  - source_app：来源 App，无法判断可返回“阅读 App”
- 若图片可见，还要提取 author、book_type、previous_book_name、daily_goal_minutes。
- 阅读首页通常没有业务日期，occurred_at 无法看到完整日期时返回 null，由系统使用上传日期归档。

字段格式要求：
- domain_key：仅当 record_type 为 sport/sleep/reading 时填写对应 key；财务记录返回 null
- payload_jsonb：财务记录可返回 null；内置数据域必须返回对象
- title、summary：内置数据域尽量返回；财务记录可返回 null
- 看不清或不可见的字段返回 null，不要编造。

只返回如下结构的纯 JSON（不要 markdown 包裹）：
{"image_type":"other","record_type":"uncertain","domain_key":null,"title":null,"summary":null,"amount":null,"merchant_name":null,"platform":null,"category":null,"payment_method":null,"income_category":null,"source_name":null,"occurred_at":null,"order_finished_at":null,"payload_jsonb":null,"confidence":0}`;

type RecordType = "expense" | "income" | "sport" | "sleep" | "reading" | "uncertain";
type BuiltinDomainKey = "sport" | "sleep" | "reading";

interface AIResult {
  image_type: string;
  record_type?: RecordType;
  domain_key?: BuiltinDomainKey | null;
  title?: string | null;
  summary?: string | null;
  amount: number | null;
  merchant_name: string | null;
  platform: string | null;
  category: string | null;
  payment_method: string | null;
  income_category?: string | null;
  source_name?: string | null;
  occurred_at?: string | null;
  order_finished_at?: string | null;
  payload_jsonb?: Record<string, unknown> | null;
  confidence: number;
}

function normalizeAiDateTime(value: unknown): { date: string; time: string | null; iso: string } | null {
  if (typeof value !== "string" || !value.trim()) return null;
  let text = value.trim();
  const compact = text.match(/(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日?\s*(\d{1,2})?:?(\d{1,2})?/);
  if (compact) {
    const [, y, m, d, hh, mm] = compact;
    const date = `${y}-${m.padStart(2, "0")}-${d.padStart(2, "0")}`;
    const time = hh && mm ? `${hh.padStart(2, "0")}:${mm.padStart(2, "0")}:00` : null;
    return { date, time, iso: `${date}T${time ?? "00:00:00"}+08:00` };
  }

  text = text.replace("年", "-").replace("月", "-").replace("日", "");
  const normalized = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?(?:([+-]\d{2}:?\d{2}|Z))?$/);
  if (normalized) {
    const [, y, m, d, hh, mm, ss, zone] = normalized;
    const date = `${y}-${m.padStart(2, "0")}-${d.padStart(2, "0")}`;
    const time = hh && mm ? `${hh.padStart(2, "0")}:${mm.padStart(2, "0")}:${(ss ?? "00").padStart(2, "0")}` : null;
    const zoneText = zone ? (zone === "Z" ? "Z" : zone.includes(":") ? zone : `${zone.slice(0, 3)}:${zone.slice(3)}`) : "+08:00";
    return { date, time, iso: `${date}T${time ?? "00:00:00"}${zoneText}` };
  }

  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return null;
  return {
    date: parsed.toISOString().slice(0, 10),
    time: parsed.toISOString().slice(11, 19),
    iso: parsed.toISOString(),
  };
}

function normalizeAiDate(value: unknown): string | null {
  return normalizeAiDateTime(value)?.iso ?? null;
}

function isBuiltinDomain(recordType: string | undefined | null): recordType is BuiltinDomainKey {
  return recordType === "sport" || recordType === "sleep" || recordType === "reading";
}

function domainNameFromKey(key: string | null | undefined): string | null {
  if (key === "expense") return "消费记账";
  if (key === "income") return "收入记录";
  if (key === "sport") return "运动记录";
  if (key === "sleep") return "睡眠记录";
  if (key === "reading") return "阅读记录";
  return null;
}

function normalizeNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value * 100) / 100;
  if (typeof value === "string") {
    const parsed = Number(value.replace(/[^\d.\-]/g, ""));
    if (Number.isFinite(parsed)) return Math.round(parsed * 100) / 100;
  }
  return null;
}

function normalizeString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function parseDurationMinutes(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value * 100) / 100;
  if (typeof value !== "string") return null;
  const text = value.trim();
  const colon = text.match(/^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$/);
  if (colon) {
    const [, h, m, s] = colon;
    const minutes = Number(h) * 60 + Number(m) + Number(s ?? 0) / 60;
    return Math.round(minutes * 100) / 100;
  }
  const hm = text.match(/(?:(\d+(?:\.\d+)?)\s*小时)?\s*(?:(\d+(?:\.\d+)?)\s*分钟)?/);
  if (hm && (hm[1] || hm[2])) {
    const minutes = Number(hm[1] ?? 0) * 60 + Number(hm[2] ?? 0);
    return Math.round(minutes * 100) / 100;
  }
  return normalizeNumber(value);
}

function qualityLevelFromScore(score: number | null): string | null {
  if (score === null) return null;
  if (score >= 80) return "优秀";
  if (score >= 70) return "良好";
  if (score >= 60) return "一般";
  return "较差";
}

function cleanPayload(ai: AIResult): Record<string, unknown> {
  const payload = ai.payload_jsonb && typeof ai.payload_jsonb === "object" && !Array.isArray(ai.payload_jsonb)
    ? { ...ai.payload_jsonb }
    : {};
  for (const [key, value] of Object.entries(payload)) {
    if (value === undefined || value === "") payload[key] = null;
  }
  return payload;
}

function buildBuiltinPayload(ai: AIResult): {
  payload: Record<string, unknown>;
  title: string;
  summary: string;
  missingFields: string[];
} | null {
  const domainKey = isBuiltinDomain(ai.domain_key) ? ai.domain_key : isBuiltinDomain(ai.record_type) ? ai.record_type : null;
  if (!domainKey) return null;

  const payload = cleanPayload(ai);
  if (!payload.source_app) payload.source_app = "截图识别";
  const missingFields: string[] = [];
  let title = normalizeString(ai.title) ?? domainNameFromKey(domainKey) ?? "通用记录";
  let summary = normalizeString(ai.summary) ?? "截图识别记录";

  if (domainKey === "sport") {
    const sportType = normalizeString(payload.sport_type) ?? normalizeString(ai.title);
    const duration = parseDurationMinutes(payload.duration_minutes ?? payload.duration);
    const calories = normalizeNumber(payload.calories);
    const distance = normalizeNumber(payload.distance_km);
    const avgHeartRate = normalizeNumber(payload.avg_heart_rate ?? payload.heart_rate_avg);
    if (!sportType) missingFields.push("sport_type");
    if (duration === null) missingFields.push("duration_minutes");
    payload.sport_type = sportType;
    payload.duration_minutes = duration;
    payload.calories = calories;
    if (distance !== null) payload.distance_km = distance;
    if (avgHeartRate !== null) payload.avg_heart_rate = avgHeartRate;
    title = sportType ?? "运动记录";
    summary = [
      duration !== null ? `运动 ${Math.round(duration)} 分钟` : null,
      calories !== null ? `消耗 ${calories} 千卡` : null,
      distance !== null ? `${distance} 公里` : null,
    ].filter(Boolean).join("，") || summary;
  }

  if (domainKey === "sleep") {
    const sleepHours = normalizeNumber(payload.sleep_hours);
    const score = normalizeNumber(payload.quality_score);
    if (sleepHours === null) missingFields.push("sleep_hours");
    payload.sleep_hours = sleepHours;
    payload.quality_score = score;
    payload.quality_level = normalizeString(payload.quality_level) ?? qualityLevelFromScore(score);
    title = normalizeString(ai.title) ?? "夜间睡眠";
    summary = [
      sleepHours !== null ? `睡眠 ${sleepHours} 小时` : null,
      score !== null ? `评分 ${score}` : null,
    ].filter(Boolean).join("，") || summary;
  }

  if (domainKey === "reading") {
    const bookName = normalizeString(payload.book_name) ?? normalizeString(ai.title);
    const readingMinutes = parseDurationMinutes(payload.reading_minutes ?? payload.today_reading_time);
    const progress = normalizeNumber(payload.progress_percent);
    if (!bookName) missingFields.push("book_name");
    if (readingMinutes === null) missingFields.push("reading_minutes");
    payload.book_name = bookName;
    payload.reading_minutes = readingMinutes;
    payload.progress_percent = progress;
    title = bookName ?? "阅读记录";
    summary = [
      readingMinutes !== null ? `今日阅读 ${Math.round(readingMinutes)} 分钟` : null,
      progress !== null ? `进度 ${progress}%` : null,
    ].filter(Boolean).join("，") || summary;
  }

  return { payload, title, summary, missingFields };
}

async function getDomainByKey(
  supabase: ReturnType<typeof createClient>,
  key: BuiltinDomainKey,
): Promise<{ id: string; key: string; version?: string | null } | null> {
  const { data, error } = await supabase
    .from("data_domains")
    .select("id,key,version")
    .eq("key", key)
    .eq("status", "active")
    .limit(1)
    .maybeSingle();
  if (error) {
    console.error("Domain lookup failed:", error);
    return null;
  }
  return data;
}

async function writeAiLog(
  supabase: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
) {
  const { error } = await supabase.from("ai_recognition_logs").insert(payload);
  if (error) console.error("AI log insert failed:", error);
}

function normalizeAmount(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value) && value !== 0) {
    const abs = Math.abs(value);
    return Math.round(abs * 100) / 100;
  }
  if (typeof value === "string") {
    const cleaned = value.replace(/[^\d.\-]/g, "");
    const parsed = Number(cleaned);
    if (Number.isFinite(parsed) && parsed !== 0) {
      return Math.round(Math.abs(parsed) * 100) / 100;
    }
  }
  return null;
}

function normalizeName(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function isSameAmount(a: number | string | null | undefined, b: number | null): boolean {
  const left = normalizeAmount(a);
  return left !== null && b !== null && Math.abs(left - b) <= 0.01;
}

async function createStagingRecord(
  supabase: ReturnType<typeof createClient>,
  payload: {
    status: string;
    imagePath: string;
    imageHash: string;
    perceptualHash: string | null;
    ai: AIResult;
    occurredAt: string | null;
    orderFinishedAt: string | null;
    errorType?: string | null;
    errorMessage?: string | null;
  },
): Promise<{ id: string } | null> {
  const detectedDomainKey = isBuiltinDomain(payload.ai.domain_key)
    ? payload.ai.domain_key
    : payload.ai.record_type === "income" || payload.ai.record_type === "expense" || isBuiltinDomain(payload.ai.record_type)
      ? payload.ai.record_type
      : null;
  const detectedDomainName = domainNameFromKey(detectedDomainKey);
  const summaryParts = [
    payload.ai.record_type && payload.ai.record_type !== "uncertain" ? `疑似${detectedDomainName}` : "无法确定数据域",
    payload.ai.amount ? `金额 ${payload.ai.amount}` : null,
    payload.ai.merchant_name || payload.ai.source_name || payload.ai.title || null,
  ].filter(Boolean);

  const { data, error } = await supabase.from("staging_records").insert({
    status: payload.status,
    image_path: payload.imagePath,
    image_hash: payload.imageHash,
    perceptual_hash: payload.perceptualHash,
    image_type: payload.ai.image_type,
    record_type: payload.ai.record_type ?? "uncertain",
    occurred_at: payload.occurredAt,
    order_finished_at: payload.orderFinishedAt,
    detected_domain_key: detectedDomainKey,
    detected_domain_name: detectedDomainName,
    confidence: payload.ai.confidence ?? 0,
    ai_summary: summaryParts.join(" · ") || "截图已进入中转站，等待确认",
    extracted_json: payload.ai,
    routing_candidates: detectedDomainKey
      ? [{ key: detectedDomainKey, name: detectedDomainName, confidence: payload.ai.confidence ?? 0 }]
      : [],
    quality_report: {
      error_type: payload.errorType ?? null,
      missing_fields: [],
    },
    last_error_type: payload.errorType ?? null,
    last_error_message: payload.errorMessage ?? null,
    failure_reason: payload.errorMessage ?? null,
  }).select("id").single();

  if (error) {
    console.error("Staging insert failed:", error);
    const { data: existing } = await supabase
      .from("staging_records")
      .select("id")
      .eq("image_hash", payload.imageHash)
      .maybeSingle();
    if (existing) return existing;
    return null;
  }
  return data;
}

// 把 Uint8Array 转成 base64（避免大图时 String.fromCharCode 栈溢出）
function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

// 提取模型返回文本中的 JSON（防护 markdown 包裹）
function extractJson(text: string): string {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced) return fenced[1].trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) return text.slice(start, end + 1);
  return text;
}

async function callKimiVision(imageBytes: Uint8Array, mime: string, apiKey: string): Promise<AIResult> {
  const base64 = toBase64(imageBytes);
  const dataUrl = `data:${mime};base64,${base64}`;
  const body = {
    model: MOONSHOT_MODEL,
    messages: [{
      role: "user",
      content: [
        { type: "image_url", image_url: { url: dataUrl } },
        { type: "text", text: PROMPT },
      ],
    }],
    temperature: 0.1,
    response_format: { type: "json_object" },
  };
  const resp = await fetch(MOONSHOT_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`Moonshot API error ${resp.status}: ${txt}`);
  }
  const data = await resp.json();
  const text = data?.choices?.[0]?.message?.content ?? "{}";
  return JSON.parse(extractJson(text)) as AIResult;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // 在请求内层初始化客户端，避免启动崩溃
  let supabase: ReturnType<typeof createClient>;
  let moonshot_key: string;
  try {
    supabase = createClient(getEnv("SUPABASE_URL"), getEnv("SUPABASE_SERVICE_ROLE_KEY"));
    moonshot_key = getEnv("MOONSHOT_API_KEY");
  } catch (e) {
    return new Response(JSON.stringify({ error: `Secret config error: ${String(e)}` }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const startedAt = Date.now();
    // 1. 接收图片（multipart/form-data，字段名 image）
    const form = await req.formData();
    const file = form.get("image") as File | null;
    if (!file) {
      return new Response(JSON.stringify({ error: "Missing 'image' field" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const buf = await file.arrayBuffer();
    const bytes = new Uint8Array(buf);
    const mime = file.type || "image/jpeg";

    // 2. 计算 hash 去重
    const hash = await sha256(buf);
    const perceptualHash = computePerceptualHash(bytes, mime);
    let perceptualDistance: number | null = null;
    let perceptualDupRefId: string | null = null;
    if (perceptualHash) {
      const { data: recentLogs } = await supabase
        .from("ai_recognition_logs")
        .select("id,perceptual_hash")
        .not("perceptual_hash", "is", null)
        .order("created_at", { ascending: false })
        .limit(30);
      for (const item of recentLogs || []) {
        const distance = hammingDistanceHex(perceptualHash, item.perceptual_hash);
        if (distance !== null && distance <= 5) {
          perceptualDistance = distance;
          perceptualDupRefId = item.id;
          break;
        }
      }
    }
    const { data: txDup } = await supabase
      .from("transactions").select("id").eq("image_hash", hash).maybeSingle();
    if (txDup) {
      await writeAiLog(supabase, {
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: perceptualDistance,
        duplicate_kind: "exact_hash",
        status: "duplicate",
        record_type: "expense",
        target_table: "transactions",
        target_id: txDup.id,
        duration_ms: Date.now() - startedAt,
      });
      return new Response(JSON.stringify({ status: "duplicate", id: txDup.id, record_type: "expense", message: "该截图已记账" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { data: incDup } = await supabase
      .from("income_records").select("id").eq("image_hash", hash).maybeSingle();
    if (incDup) {
      await writeAiLog(supabase, {
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: perceptualDistance,
        duplicate_kind: "exact_hash",
        status: "duplicate",
        record_type: "income",
        target_table: "income_records",
        target_id: incDup.id,
        duration_ms: Date.now() - startedAt,
      });
      return new Response(JSON.stringify({ status: "duplicate", id: incDup.id, record_type: "income", message: "该收入截图已记录" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { data: dataDup } = await supabase
      .from("data_records").select("id,domain_key").eq("source_image_hash", hash).maybeSingle();
    if (dataDup) {
      await writeAiLog(supabase, {
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: perceptualDistance,
        duplicate_kind: "exact_hash",
        status: "duplicate",
        record_type: dataDup.domain_key,
        target_table: "data_records",
        target_id: dataDup.id,
        data_record_id: dataDup.id,
        duration_ms: Date.now() - startedAt,
        prompt_version: "platform-v3-builtins",
      });
      return new Response(JSON.stringify({ status: "duplicate", id: dataDup.id, record_type: dataDup.domain_key, message: "该截图已归档" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 3. 上传到 Storage
    const ext  = mime.includes("png") ? "png" : "jpg";
    const path = `${new Date().toISOString().slice(0,10)}/${hash.slice(0,12)}.${ext}`;
    let uploadedNewObject = false;
    const { error: upErr } = await supabase.storage.from(BUCKET_NAME)
      .upload(path, bytes, { contentType: mime, upsert: false });
    if (upErr && !upErr.message.includes("already exists")) {
      throw new Error(`Upload failed: ${upErr.message}`);
    }
    uploadedNewObject = !upErr;
    // 存储路径（非 signed URL），前端查询时动态生成 signed URL，避免过期问题

    // 4. 调用 Kimi Vision 识别
    let ai: AIResult;
    let aiOk = true;
    let aiErrorMessage: string | null = null;
    try {
      ai = await callKimiVision(bytes, mime, moonshot_key);
    } catch (e) {
      aiOk = false;
      aiErrorMessage = String(e);
      ai = { image_type: "other", record_type: "uncertain", domain_key: null, title: null, summary: null, amount: null, merchant_name: null, platform: null, category: null, payment_method: null, income_category: null, source_name: null, occurred_at: null, order_finished_at: null, payload_jsonb: null, confidence: 0 };
      console.error("Kimi Vision failed:", e);
    }

    const normalizedAmount = normalizeAmount(ai.amount);
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    const nowTime = now.toTimeString().slice(0, 8);
    const recordType: RecordType = ai.record_type ?? "expense";
    const builtinKey: BuiltinDomainKey | null = isBuiltinDomain(ai.domain_key)
      ? ai.domain_key
      : isBuiltinDomain(recordType)
        ? recordType
        : null;
    if (builtinKey) {
      ai.record_type = builtinKey;
      ai.domain_key = builtinKey;
    }
    const occurredDateTime = normalizeAiDateTime(ai.occurred_at) ?? normalizeAiDateTime(ai.order_finished_at);
    const orderFinishedDateTime = normalizeAiDateTime(ai.order_finished_at) ?? occurredDateTime;
    const occurredAt = occurredDateTime?.iso ?? null;
    const orderFinishedAt = orderFinishedDateTime?.iso ?? occurredAt;
    const recordDate = occurredDateTime?.date ?? today;
    const recordTime = occurredDateTime?.time ?? nowTime;
    let duplicateKind: string | null = perceptualDupRefId ? "perceptual_hash" : null;
    let duplicateRefTable: string | null = perceptualDupRefId ? "ai_recognition_logs" : null;
    let duplicateRefId: string | null = perceptualDupRefId;

    if (!aiOk || (!builtinKey && recordType === "uncertain") || (!builtinKey && (ai.confidence ?? 0) < 0.35 && normalizedAmount === null)) {
      const stagingStatus = !aiOk ? "ai_error" : "routing_failed";
      const staging = await createStagingRecord(supabase, {
        status: stagingStatus,
        imagePath: path,
        imageHash: hash,
        perceptualHash,
        ai,
        occurredAt,
        orderFinishedAt,
        errorType: !aiOk ? "AI_PROVIDER_ERROR" : "ROUTING_FAILED",
        errorMessage: aiErrorMessage,
      });
      await writeAiLog(supabase, {
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: perceptualDistance,
        image_url: path,
        image_type: ai.image_type,
        record_type: ai.record_type ?? "uncertain",
        occurred_at: occurredAt,
        order_finished_at: orderFinishedAt,
        duplicate_kind: duplicateKind,
        duplicate_ref_table: duplicateRefTable,
        duplicate_ref_id: duplicateRefId,
        target_table: "staging_records",
        target_id: staging?.id ?? null,
        staging_record_id: staging?.id ?? null,
        status: !aiOk ? "ai_error" : "pending",
        confidence: ai.confidence ?? 0,
        duration_ms: Date.now() - startedAt,
        ai_response: ai,
        error_message: aiErrorMessage,
        model_provider: "moonshot",
        model_name: MOONSHOT_MODEL,
        prompt_version: "platform-v3-builtins",
      });

      return new Response(JSON.stringify({
        status: "staging",
        staging_status: stagingStatus,
        id: staging?.id ?? null,
        ai_ok: aiOk,
        message: !aiOk ? "⚠ AI 识别失败，已进入待处理" : "⚠ 未确定数据域，已进入待处理",
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (builtinKey) {
      const built = buildBuiltinPayload(ai);
      const domain = await getDomainByKey(supabase, builtinKey);
      const fallbackOccurredAt = occurredAt ?? new Date().toISOString();
      const shouldAutoArchive = Boolean(domain && built && built.missingFields.length === 0 && (ai.confidence ?? 0) >= 0.75);

      if (!shouldAutoArchive || !domain || !built) {
        const missing = built?.missingFields ?? [];
        const staging = await createStagingRecord(supabase, {
          status: domain ? "pending_review" : "routing_failed",
          imagePath: path,
          imageHash: hash,
          perceptualHash,
          ai,
          occurredAt: fallbackOccurredAt,
          orderFinishedAt,
          errorType: domain ? "SCHEMA_REVIEW_REQUIRED" : "DOMAIN_NOT_FOUND",
          errorMessage: !domain
            ? `未找到内置数据域 ${builtinKey}，请确认 007 迁移已执行`
            : `缺少字段或置信度不足：${missing.join(", ") || "confidence"}`,
        });
        await writeAiLog(supabase, {
          image_hash: hash,
          perceptual_hash: perceptualHash,
          perceptual_distance: perceptualDistance,
          image_url: path,
          image_type: ai.image_type,
          record_type: builtinKey,
          occurred_at: fallbackOccurredAt,
          order_finished_at: orderFinishedAt,
          duplicate_kind: duplicateKind,
          duplicate_ref_table: duplicateRefTable,
          duplicate_ref_id: duplicateRefId,
          target_table: "staging_records",
          target_id: staging?.id ?? null,
          staging_record_id: staging?.id ?? null,
          domain_id: domain?.id ?? null,
          status: "pending",
          confidence: ai.confidence ?? 0,
          duration_ms: Date.now() - startedAt,
          ai_response: ai,
          error_message: !domain ? `data_domains.${builtinKey} 不存在` : null,
          model_provider: "moonshot",
          model_name: MOONSHOT_MODEL,
          prompt_version: "platform-v3-builtins",
        });

        return new Response(JSON.stringify({
          status: "staging",
          staging_status: domain ? "pending_review" : "routing_failed",
          id: staging?.id ?? null,
          record_type: builtinKey,
          ai_ok: aiOk,
          message: domain ? "⚠ 已识别为内置数据域，请确认后归档" : "⚠ 未找到对应数据域，已进入待处理",
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      const { data: row, error: dataErr } = await supabase.from("data_records").insert({
        domain_id: domain.id,
        domain_key: builtinKey,
        domain_version: domain.version ?? "1.0",
        occurred_at: fallbackOccurredAt,
        title: built.title,
        summary: built.summary,
        payload_jsonb: built.payload,
        source: "ai_scan",
        source_image_path: path,
        source_image_hash: hash,
      }).select().single();

      if (dataErr) {
        await writeAiLog(supabase, {
          image_hash: hash,
          perceptual_hash: perceptualHash,
          perceptual_distance: perceptualDistance,
          image_url: path,
          image_type: ai.image_type,
          record_type: builtinKey,
          occurred_at: fallbackOccurredAt,
          order_finished_at: orderFinishedAt,
          duplicate_kind: duplicateKind,
          duplicate_ref_table: duplicateRefTable,
          duplicate_ref_id: duplicateRefId,
          domain_id: domain.id,
          status: "db_error",
          confidence: ai.confidence ?? 0,
          duration_ms: Date.now() - startedAt,
          ai_response: ai,
          error_message: dataErr.message,
          model_provider: "moonshot",
          model_name: MOONSHOT_MODEL,
          prompt_version: "platform-v3-builtins",
        });
        if (uploadedNewObject) {
          const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
          if (removeErr) console.error("Cleanup uploaded data record image failed:", removeErr);
        }
        throw new Error(`Data record insert failed: ${dataErr.message}`);
      }

      await writeAiLog(supabase, {
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: perceptualDistance,
        image_url: path,
        image_type: ai.image_type,
        record_type: builtinKey,
        occurred_at: fallbackOccurredAt,
        order_finished_at: orderFinishedAt,
        duplicate_kind: duplicateKind,
        duplicate_ref_table: duplicateRefTable,
        duplicate_ref_id: duplicateRefId,
        target_table: "data_records",
        target_id: row.id,
        data_record_id: row.id,
        domain_id: domain.id,
        status: "success",
        confidence: ai.confidence ?? 0,
        duration_ms: Date.now() - startedAt,
        ai_response: ai,
        error_message: aiErrorMessage,
        model_provider: "moonshot",
        model_name: MOONSHOT_MODEL,
        prompt_version: "platform-v3-builtins",
      });

      return new Response(JSON.stringify({
        status: "done",
        id: row.id,
        record_type: builtinKey,
        ai_ok: aiOk,
        message: `✓ ${domainNameFromKey(builtinKey) ?? "记录"}已归档`,
        data: row,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (recordType === "income" && normalizedAmount !== null && (ai.confidence ?? 0) >= 0.7) {
      const incomeCategory = ["salary", "bonus", "freelance", "investment", "reimbursement", "other"].includes(ai.income_category ?? "")
        ? ai.income_category
        : "other";
      const sourceName = ai.source_name ?? ai.merchant_name ?? "截图识别收入";

      if (duplicateKind === "perceptual_hash" && duplicateRefId) {
        const { data: refLog } = await supabase
          .from("ai_recognition_logs")
          .select("id,target_table,target_id,record_type")
          .eq("id", duplicateRefId)
          .maybeSingle();

        if (refLog?.record_type === "income" && refLog.target_table === "income_records" && refLog.target_id) {
          const { data: refIncome } = await supabase
            .from("income_records")
            .select("id,amount,source_name")
            .eq("id", refLog.target_id)
            .maybeSingle();

          const currentSource = normalizeName(sourceName);
          const refSource = normalizeName(refIncome?.source_name);
          const sourceMatches = currentSource && refSource
            ? currentSource === refSource
            : currentSource === refSource || currentSource === "截图识别收入" || refSource === "截图识别收入";

          if (refIncome && isSameAmount(refIncome.amount, normalizedAmount) && sourceMatches) {
            await writeAiLog(supabase, {
              image_hash: hash,
              perceptual_hash: perceptualHash,
              perceptual_distance: perceptualDistance,
              image_url: path,
              image_type: ai.image_type,
              record_type: "income",
              occurred_at: occurredAt,
              order_finished_at: orderFinishedAt,
              duplicate_kind: duplicateKind,
              duplicate_ref_table: duplicateRefTable,
              duplicate_ref_id: duplicateRefId,
              target_table: "income_records",
              target_id: refIncome.id,
              status: "duplicate",
              confidence: ai.confidence ?? 0,
              duration_ms: Date.now() - startedAt,
              ai_response: ai,
              error_message: aiErrorMessage,
            });
            if (uploadedNewObject) {
              const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
              if (removeErr) console.error("Cleanup duplicate income image failed:", removeErr);
            }
            return new Response(JSON.stringify({
              status: "duplicate",
              id: refIncome.id,
              record_type: "income",
              ai_ok: aiOk,
              message: "该收入截图疑似已记录",
            }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
          }
        }
      }

      const { data: row, error: incErr } = await supabase.from("income_records").insert({
        amount: normalizedAmount,
        category: incomeCategory,
        source_name: sourceName,
        income_date: recordDate,
        image_url: path,
        image_hash: hash,
        source: "ai_scan",
        note: ai.platform ? `来自${ai.platform}截图识别` : "截图识别收入",
      }).select().single();

      if (incErr) {
        await writeAiLog(supabase, {
          image_hash: hash,
          perceptual_hash: perceptualHash,
          perceptual_distance: perceptualDistance,
          image_url: path,
          image_type: ai.image_type,
        record_type: "income",
        occurred_at: occurredAt,
        order_finished_at: orderFinishedAt,
        duplicate_kind: duplicateKind,
        duplicate_ref_table: duplicateRefTable,
        duplicate_ref_id: duplicateRefId,
        status: "db_error",
          confidence: ai.confidence ?? 0,
          duration_ms: Date.now() - startedAt,
          ai_response: ai,
          error_message: incErr.message,
        });
        if (uploadedNewObject) {
          const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
          if (removeErr) console.error("Cleanup uploaded income image failed:", removeErr);
        }
        throw new Error(`Income insert failed: ${incErr.message}`);
      }

      await writeAiLog(supabase, {
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: perceptualDistance,
        image_url: path,
        image_type: ai.image_type,
        record_type: "income",
        occurred_at: occurredAt,
        order_finished_at: orderFinishedAt,
        duplicate_kind: duplicateKind,
        duplicate_ref_table: duplicateRefTable,
        duplicate_ref_id: duplicateRefId,
        target_table: "income_records",
        target_id: row.id,
        status: "success",
        confidence: ai.confidence ?? 0,
        duration_ms: Date.now() - startedAt,
        ai_response: ai,
        error_message: aiErrorMessage,
      });

      return new Response(JSON.stringify({
        status: "done",
        id: row.id,
        record_type: "income",
        ai_ok: aiOk,
        message: "✓ 收入已记录",
        data: row,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // 5. 业务层疑似重复检测：3 分钟内同金额+同支付+同商家 → 标记 possible_duplicate
    //    不阻断入库，允许用户真实的重复消费，仅在响应中提示
    let possibleDuplicate = false;
    let dupRefId: string | null = null;
    if (aiOk && normalizedAmount !== null && ai.payment_method !== null) {
      const threeMinAgo = new Date(Date.now() - 3 * 60 * 1000).toISOString();
      const duplicateDate = recordDate;
      let dupQuery = supabase.from("transactions")
        .select("id,transaction_time")
        .eq("transaction_date", duplicateDate)
        .eq("payment_method", ai.payment_method)
        .gte("amount", (normalizedAmount - 0.01).toFixed(2))
        .lte("amount", (normalizedAmount + 0.01).toFixed(2));
      if (!occurredAt) {
        dupQuery = dupQuery.gte("created_at", threeMinAgo);
      }
      // 商家名已识别时额外过滤，减少误判；未识别时仅靠金额+支付方式兜底
      if (ai.merchant_name !== null) {
        dupQuery = dupQuery.eq("merchant_name", ai.merchant_name);
      }
      const { data: candidates } = await dupQuery.limit(5);
      const dup = (candidates || []).find((item) => {
        if (!occurredAt || !item.transaction_time) return true;
        const current = new Date(occurredAt);
        const existing = new Date(`${duplicateDate}T${item.transaction_time}`);
        return Math.abs(current.getTime() - existing.getTime()) <= 3 * 60 * 1000;
      });
      if (dup) {
        possibleDuplicate = true;
        dupRefId = dup.id;
        duplicateKind = "business_possible";
        duplicateRefTable = "transactions";
        duplicateRefId = dup.id;
      }
    }

    // 6. 判断是否完整
    const isComplete = normalizedAmount !== null && ai.platform !== null && ai.category !== null && ai.payment_method !== null;
    const status = isComplete && (ai.confidence ?? 0) >= 0.7 ? "done" : "pending";
    const isLargeTransport = ai.category === "transport" && (normalizedAmount ?? 0) >= 200;

    // 6. 写入数据库
    const { data: row, error: insErr } = await supabase.from("transactions").insert({
      type: "expense",
      amount: normalizedAmount ?? 0.01,     // 金额识别失败或非法时占位 0.01，由用户改
      merchant_name: ai.merchant_name,
      platform: ai.platform,
      category: ai.category,
      payment_method: ai.payment_method,
      status: normalizedAmount === null ? "pending" : status,
      image_url: path,
      image_hash: hash,
      is_large_transport: isLargeTransport,
      transaction_date: recordDate,
      transaction_time: recordTime,
      source: "ai_scan",
    }).select().single();

    if (insErr) {
      await writeAiLog(supabase, {
          image_hash: hash,
          perceptual_hash: perceptualHash,
          perceptual_distance: perceptualDistance,
          image_url: path,
        image_type: ai.image_type,
        record_type: "expense",
        occurred_at: occurredAt,
        order_finished_at: orderFinishedAt,
        duplicate_kind: duplicateKind,
        duplicate_ref_table: duplicateRefTable,
        duplicate_ref_id: duplicateRefId,
        status: "db_error",
        confidence: ai.confidence ?? 0,
        duration_ms: Date.now() - startedAt,
        ai_response: ai,
        error_message: insErr.message,
      });
      if (uploadedNewObject) {
        const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
        if (removeErr) console.error("Cleanup uploaded image failed:", removeErr);
      }
      throw new Error(`DB insert failed: ${insErr.message}`);
    }

    await writeAiLog(supabase, {
      image_hash: hash,
      perceptual_hash: perceptualHash,
      perceptual_distance: perceptualDistance,
      image_url: path,
      image_type: ai.image_type,
      record_type: "expense",
      occurred_at: occurredAt,
      order_finished_at: orderFinishedAt,
      duplicate_kind: duplicateKind,
      duplicate_ref_table: duplicateRefTable,
      duplicate_ref_id: duplicateRefId,
      target_table: "transactions",
      target_id: row.id,
      status: aiOk ? row.status : "ai_error",
      confidence: ai.confidence ?? 0,
      duration_ms: Date.now() - startedAt,
      ai_response: ai,
      error_message: aiErrorMessage,
    });

    return new Response(JSON.stringify({
      status: row.status,
      id: row.id,
      ai_ok: aiOk,
      possible_duplicate: possibleDuplicate,
      dup_ref_id: dupRefId,
      message: possibleDuplicate
        ? `✓ 已记账（⚠ 3 分钟内有相同消费，请确认是否重复，参考 id: ${dupRefId}）`
        : row.status === "done" ? "✓ 已记账" : "⚠ 信息不全，请打开 PWA 补全",
      data: row,
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
