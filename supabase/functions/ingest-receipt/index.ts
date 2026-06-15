// 随手账 · Edge Function: ingest-receipt
// 部署: supabase functions deploy ingest-receipt --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2.45.0";
import jpeg from "npm:jpeg-js@0.4.4";
import { decode as decodePng } from "npm:fast-png@6.2.0";
import { PROMPT, buildPrompt } from "./prompts.ts";
import { buildTimeContext, normalizeAiDate, normalizeAiDateTime } from "./time.ts";
import type { TimeContext } from "./time.ts";

const MOONSHOT_MODEL    = "moonshot-v1-8k-vision-preview";
const MOONSHOT_ENDPOINT = "https://api.moonshot.cn/v1/chat/completions";
// MiMo 默认值（可被环境变量 MIMO_ENDPOINT / MIMO_MODEL 覆盖）
// 申请到 MiMo Vision 额度后，至少需要在 Supabase secrets 中设置 MIMO_API_KEY 才会启用 fallback
// MiMo 默认值对应 xiaomimimo.com 套餐（OpenAI 兼容协议）
// mimo-v2-omni 是多模态版；图像识别仅 mimo-v2.5 / mimo-v2-omni 支持
const MIMO_DEFAULT_ENDPOINT = "https://api.xiaomimimo.com/v1/chat/completions";
const MIMO_DEFAULT_MODEL    = "mimo-v2-omni";

// 阿里云百炼 Qwen Vision（OpenAI 兼容协议）
// qwen3.6-flash 是「混合思考」模型，默认会生成 reasoning_content 大幅拖慢，
// 必须在请求体传 enable_thinking=false 关闭推理才能达到 2-4s 响应
const QWEN_DEFAULT_ENDPOINT = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";
const QWEN_DEFAULT_MODEL    = "qwen3.6-flash";

// 自建 OpenAI 兼容中转站（支持视觉模型时可直接复用）
const RELAY_DEFAULT_ENDPOINT = "http://47.76.157.150:8317/v1/chat/completions";
const RELAY_DEFAULT_MODEL    = "gpt-5.4";
const BUCKET_NAME       = "receipt-images";

// Vision Provider 抽象：用于多 Provider 优雅降级（Moonshot 主 → MiMo 备）
type ProviderName = "moonshot" | "mimo" | "qwen" | "relay";

interface ProviderConfig {
  name: ProviderName;
  model: string;
  endpoint: string;
  apiKey: string;
}

interface VisionAttempt {
  provider: ProviderName;
  model: string;
  duration_ms: number;
  error?: string;
}

interface VisionCallResult {
  ai: AIResult;
  provider: ProviderName;
  model: string;
  attempts: VisionAttempt[];
}

// 歺加载：延迟到请求时获取 Secret，避免模块初始化就崩溃
function getEnv(key: string): string {
  const v = Deno.env.get(key);
  if (!v) throw new Error(`Missing required secret: ${key}`);
  return v;
}

// 可选 secret：缺失时返回 null 而不抛错（用于 MiMo 这类 fallback provider）
function getEnvOptional(key: string): string | null {
  const v = Deno.env.get(key);
  return v && v.length > 0 ? v : null;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ---- Timings: 链路分段耗时埋点 ----
// 每个 mark(label) 记录"自上次 mark 以来"的耗时（毫秒），最终通过 snapshot() 输出 dict
// 最终落盘到 ai_recognition_logs.raw_response.timings，便于在 Dashboard 排查慢请求
interface Timings {
  mark(label: string): void;
  snapshot(): Record<string, number>;
  total(): number;
}

function makeTimings(): Timings {
  const startedAt = Date.now();
  let last = startedAt;
  const data: Record<string, number> = {};
  return {
    mark(label: string) {
      const now = Date.now();
      // 累加同名 label，避免循环/分支重复 mark 时数据丢失
      data[label] = (data[label] ?? 0) + (now - last);
      last = now;
    },
    snapshot() {
      return { ...data, total: Date.now() - startedAt };
    },
    total() {
      return Date.now() - startedAt;
    },
  };
}

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

function getImageFeatures(bytes: Uint8Array, mime: string): ImageFeatures {
  const img = decodeImage(bytes, mime);
  if (!img || img.width <= 0 || img.height <= 0) {
    return {
      width: null,
      height: null,
      aspect_ratio: null,
      megapixels: null,
      decode_ok: false,
      is_tall_screenshot: false,
      is_wide_screenshot: false,
      is_tiny_image: false,
      likely_phone_screenshot: false,
      mime,
    };
  }
  const ratio = Math.round((img.height / img.width) * 100) / 100;
  const megapixels = Math.round((img.width * img.height / 1_000_000) * 100) / 100;
  return {
    width: img.width,
    height: img.height,
    aspect_ratio: ratio,
    megapixels,
    decode_ok: true,
    is_tall_screenshot: ratio >= 1.6,
    is_wide_screenshot: img.width > img.height * 1.25,
    is_tiny_image: img.width < 320 || img.height < 320,
    likely_phone_screenshot: img.height >= 1000 && img.width >= 600 && ratio >= 1.5 && ratio <= 2.4,
    mime,
  };
}

type RecordType = "expense" | "income" | "sport" | "sleep" | "reading" | "food" | "wallet" | "uncertain";
type BuiltinDomainKey = "sport" | "sleep" | "reading" | "food" | "wallet";

interface ImageFeatures {
  width: number | null;
  height: number | null;
  aspect_ratio: number | null;
  megapixels: number | null;
  decode_ok: boolean;
  is_tall_screenshot: boolean;
  is_wide_screenshot: boolean;
  is_tiny_image: boolean;
  likely_phone_screenshot: boolean;
  mime: string;
}

interface DispatcherCandidate {
  key: string;
  name: string;
  confidence: number;
  reason: string;
  matched_keywords: string[];
  matched_apps: string[];
}

interface DispatcherResult {
  raw_text: string | null;
  source_app: string | null;
  image_features: ImageFeatures;
  candidate_domains: DispatcherCandidate[];
  selected_domain_key: string | null;
  route_confidence: number;
  route_reason: string;
  should_call_vision: boolean;
  skip_reason: string | null;
}

const BUILTIN_ROUTE_RULES: Record<string, { keywords: string[]; apps: string[]; threshold: number }> = {
  expense: {
    keywords: ["支付成功", "付款成功", "交易成功", "订单已送达", "实付", "支付方式", "商家", "收款方", "账单详情"],
    apps: ["微信", "支付宝", "美团", "饿了么", "京东", "淘宝", "拼多多"],
    threshold: 0.72,
  },
  income: {
    keywords: ["你已收款", "收款成功", "到账", "已存入零钱", "转入", "退款到账", "报销"],
    apps: ["微信", "支付宝", "银行"],
    threshold: 0.72,
  },
  sport: {
    keywords: ["运动时间", "总消耗热量", "平均心率", "公里", "配速", "步频", "羽毛球", "户外骑行", "室内跑步", "自由训练"],
    apps: ["华为运动健康", "Keep", "健康", "Fitness"],
    threshold: 0.75,
  },
  sleep: {
    keywords: ["睡眠", "夜间睡眠", "睡眠评分", "入睡", "醒来", "深睡", "浅睡", "快速眼动"],
    apps: ["华为运动健康", "健康", "Sleep"],
    threshold: 0.75,
  },
  reading: {
    keywords: ["继续阅读", "今日阅读", "阅读进度", "图书", "之前读过", "书库", "书名"],
    apps: ["微信读书", "Kindle", "阅读"],
    threshold: 0.75,
  },
  // 食物拍照通常无 OCR 文本，dispatcher 主要靠 Vision 判定；关键词仅在罕见的菜单/标签照片中触发
  food: {
    keywords: ["千卡", "kcal", "营养", "蛋白质", "碳水", "脂肪", "热量"],
    apps: ["薄荷健康", "MyFitnessPal", "下厨房"],
    threshold: 0.8,
  },
  wallet: {
    keywords: ["花呗", "白条", "京东白条", "抖音月付", "月付", "待还", "应还", "还款日", "本月应还", "剩余应还", "账户余额", "可用余额", "银行卡余额", "零钱", "余额宝"],
    apps: ["支付宝", "京东", "抖音", "微信", "银行"],
    threshold: 0.74,
  },
};

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
  funding_source?: {
    raw_text?: string | null;
    type?: string | null;
    institution?: string | null;
    last4?: string | null;
    confidence?: number | null;
    evidence?: string | null;
  } | null;
  receiving_account?: {
    raw_text?: string | null;
    type?: string | null;
    institution?: string | null;
    last4?: string | null;
    confidence?: number | null;
    evidence?: string | null;
  } | null;
  income_category?: string | null;
  source_name?: string | null;
  occurred_at?: string | null;
  order_finished_at?: string | null;
  payload_jsonb?: Record<string, unknown> | null;
  confidence: number;
  companion_message?: string | null;
}

interface AIFeedback {
  version: "feedback-v1";
  domain_key: string;
  badge: string;
  icon: string;
  band: "positive" | "neutral" | "watch" | "recover" | "ritual";
  tone: string;
  emotion_line: string;
  utility_line?: string | null;
  detail_reason?: string | null;
  internal_score?: number | null;
  confidence: number;
  source: "rule" | "hybrid";
  timing_signal?: {
    key: string;
    label: string;
  } | null;
}

interface AccountRow {
  id: string;
  user_id: string;
  name: string;
  type: string;
  institution: string | null;
  last4: string | null;
  is_archived: boolean;
}

interface AccountHint {
  raw_text: string | null;
  type: string | null;
  institution: string | null;
  last4: string | null;
  confidence: number;
  evidence: string | null;
}

interface AccountCandidate {
  id: string;
  score: number;
  name: string;
  type: string;
  institution: string | null;
  last4: string | null;
  reasons: string[];
}

function normalizeText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.replace(/\s+/g, " ").trim();
  return text ? text.slice(0, 4000) : null;
}

function arrayFromUnknown(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => typeof item === "string" ? item.trim() : "")
    .filter(Boolean);
}

function includesAny(text: string, words: string[]): string[] {
  const lowerText = text.toLowerCase();
  return words.filter((word) => lowerText.includes(word.toLowerCase()));
}

function isBuiltinDomain(recordType: string | undefined | null): recordType is BuiltinDomainKey {
  return recordType === "sport" || recordType === "sleep" || recordType === "reading" || recordType === "food" || recordType === "wallet";
}

function domainNameFromKey(key: string | null | undefined): string | null {
  if (key === "expense") return "消费记账";
  if (key === "income") return "收入记录";
  if (key === "sport") return "运动记录";
  if (key === "sleep") return "睡眠记录";
  if (key === "food") return "饮食记录";
  if (key === "reading") return "阅读记录";
  if (key === "wallet") return "钱包与待还";
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

function normalizeAccountTypeValue(value: unknown): string | null {
  const text = normalizeString(value)?.toLowerCase() ?? null;
  if (!text) return null;
  if (["cash", "wallet_balance", "debit_card", "credit_card", "credit_line", "other"].includes(text)) return text;
  if (["wechat", "alipay", "balance"].includes(text)) return "wallet_balance";
  if (["bank_card", "bank", "debit"].includes(text)) return "debit_card";
  if (["huabei", "jd_baitiao", "douyin_monthly"].includes(text)) return "credit_line";
  return text;
}

function normalizeLast4(value: unknown): string | null {
  const text = normalizeString(value)?.replace(/[^\d]/g, "") ?? null;
  return text && /^\d{4}$/.test(text) ? text : null;
}

function normalizeComparableText(value: unknown): string {
  return normalizeString(value)?.toLowerCase().replace(/\s+/g, "") ?? "";
}

function buildAccountHint(ai: AIResult, recordType: RecordType): AccountHint | null {
  const source = recordType === "income"
    ? (ai.receiving_account ?? ai.funding_source ?? null)
    : (ai.funding_source ?? null);
  const rawText = normalizeString(source?.raw_text);
  const type = normalizeAccountTypeValue(source?.type);
  const institution = normalizeString(source?.institution);
  const last4 = normalizeLast4(source?.last4);
  const confidence = normalizeNumber(source?.confidence) ?? 0;
  const evidence = normalizeString(source?.evidence);

  if (rawText || type || institution || last4) {
    return { raw_text: rawText, type, institution, last4, confidence, evidence };
  }

  const paymentMethod = normalizeString(ai.payment_method);
  if (paymentMethod === "花呗") {
    return { raw_text: paymentMethod, type: "credit_line", institution: "花呗", last4: null, confidence: 0.92, evidence: "payment_method=花呗" };
  }
  if (paymentMethod === "京东白条") {
    return { raw_text: paymentMethod, type: "credit_line", institution: "京东白条", last4: null, confidence: 0.92, evidence: "payment_method=京东白条" };
  }
  if (paymentMethod === "美团月付") {
    return { raw_text: paymentMethod, type: "credit_line", institution: "美团月付", last4: null, confidence: 0.9, evidence: "payment_method=美团月付" };
  }
  if (paymentMethod === "微信支付") {
    return { raw_text: paymentMethod, type: "wallet_balance", institution: "微信", last4: null, confidence: 0.78, evidence: "payment_method=微信支付" };
  }
  if (paymentMethod === "支付宝") {
    return { raw_text: paymentMethod, type: "wallet_balance", institution: "支付宝", last4: null, confidence: 0.78, evidence: "payment_method=支付宝" };
  }
  if (paymentMethod === "银行卡") {
    return { raw_text: paymentMethod, type: "debit_card", institution: "银行卡", last4: null, confidence: 0.72, evidence: "payment_method=银行卡" };
  }
  return null;
}

async function loadUserAccounts(
  supabase: ReturnType<typeof createClient>,
  userId: string | null,
): Promise<AccountRow[]> {
  if (!userId) return [];
  const { data, error } = await supabase
    .from("accounts")
    .select("id,user_id,name,type,institution,last4,is_archived")
    .eq("user_id", userId)
    .eq("is_archived", false)
    .order("created_at", { ascending: true });
  if (error) {
    console.error("Account lookup failed:", error);
    return [];
  }
  return (data || []) as AccountRow[];
}

function rankAccountCandidates(accounts: AccountRow[], hint: AccountHint | null): AccountCandidate[] {
  if (!hint) return [];
  const hintText = [hint.raw_text, hint.institution].filter(Boolean).join(" ");
  const hintComparable = normalizeComparableText(hintText);
  const activeDebitCardCount = accounts.filter((account) => normalizeAccountTypeValue(account.type) === "debit_card").length;
  return accounts.map((account) => {
    let score = 0;
    const reasons: string[] = [];
    const accountType = normalizeAccountTypeValue(account.type);
    const accountName = normalizeComparableText(account.name);
    const institution = normalizeComparableText(account.institution);

    if (hint.type && accountType === hint.type) {
      score += 0.34;
      reasons.push("type");
    }
    if (hint.last4 && account.last4 === hint.last4) {
      score += 0.42;
      reasons.push("last4");
    }
    if (hintComparable) {
      if (accountName && hintComparable.includes(accountName)) {
        score += 0.2;
        reasons.push("name");
      }
      if (institution && hintComparable.includes(institution)) {
        score += 0.2;
        reasons.push("institution");
      }
      if (accountName && accountName.includes(hintComparable) && hintComparable.length >= 2) {
        score += 0.12;
        reasons.push("name_reverse");
      }
      if (institution && institution.includes(hintComparable) && hintComparable.length >= 2) {
        score += 0.12;
        reasons.push("institution_reverse");
      }
      if (hintComparable.includes("花呗") && accountType === "credit_line" && (accountName.includes("花呗") || institution.includes("花呗"))) {
        score += 0.42;
        reasons.push("huabei_exact");
      }
      if (hintComparable.includes("白条") && accountType === "credit_line" && (accountName.includes("白条") || institution.includes("白条") || accountName.includes("京东") || institution.includes("京东"))) {
        score += 0.42;
        reasons.push("baitiao_exact");
      }
      if (hintComparable.includes("月付") && accountType === "credit_line" && (accountName.includes("月付") || institution.includes("月付"))) {
        score += 0.42;
        reasons.push("monthly_credit_exact");
      }
      if (hintComparable.includes("微信") && accountType === "wallet_balance" && (accountName.includes("微信") || institution.includes("微信"))) {
        score += 0.42;
        reasons.push("wechat_exact");
      }
      if (hintComparable.includes("支付宝") && accountType === "wallet_balance" && (accountName.includes("支付宝") || institution.includes("支付宝"))) {
        score += 0.42;
        reasons.push("alipay_exact");
      }
      if ((hintComparable.includes("银行卡") || hintComparable.includes("银行")) && accountType === "debit_card") {
        score += activeDebitCardCount === 1 ? 0.5 : 0.16;
        reasons.push(activeDebitCardCount === 1 ? "single_debit_card" : "debit_card_type");
      }
    }
    if (hint.confidence >= 0.8) score += 0.04;
    return {
      id: account.id,
      score: Math.round(Math.min(score, 0.99) * 100) / 100,
      name: account.name,
      type: account.type,
      institution: account.institution,
      last4: account.last4,
      reasons,
    };
  })
  .filter((item) => item.score > 0)
  .sort((a, b) => b.score - a.score);
}

function chooseAutoBindAccount(candidates: AccountCandidate[]): AccountCandidate | null {
  if (!candidates.length) return null;
  const first = candidates[0];
  const second = candidates[1];
  if (first.score < 0.84) return null;
  if (second && first.score - second.score < 0.08) return null;
  return first;
}

function resolveEntryDirectionForAccountType(accountType: string | null, recordType: "expense" | "income"): "in" | "out" {
  if (recordType === "income") return "in";
  return accountType === "credit_card" || accountType === "credit_line" ? "in" : "out";
}

async function createAutoAccountEntry(
  supabase: ReturnType<typeof createClient>,
  payload: {
    userId: string | null;
    accountId: string;
    accountType: string | null;
    recordType: "expense" | "income";
    amount: number;
    sourceId: string;
    occurredAt: string | null;
  },
): Promise<void> {
  if (!payload.userId) return;
  const direction = resolveEntryDirectionForAccountType(payload.accountType, payload.recordType);
  const occurredAt = payload.occurredAt ?? new Date().toISOString();
  const { error } = await supabase.from("account_entries").insert({
    user_id: payload.userId,
    account_id: payload.accountId,
    direction,
    amount: payload.amount,
    entry_type: payload.recordType,
    source_table: payload.recordType === "income" ? "income_records" : "transactions",
    source_id: payload.sourceId,
    occurred_at: occurredAt,
    note: payload.recordType === "income" ? "截图识别自动绑定账户" : "截图识别自动绑定出资账户",
  });
  if (error) throw new Error(`Account entry insert failed: ${error.message}`);
}

const SMALL_PACK_FOOD_KEYWORDS = [
  "西梅", "梅干", "果脯", "话梅", "坚果", "葡萄干", "肉干", "海苔", "饼干", "薯片",
  "辣条", "巧克力", "糖", "果冻", "零食", "独立包装", "小包", "迷你", "单包", "随手包",
];

const SMALL_PACK_HINT_KEYWORDS = [
  "小包", "独立包装", "迷你", "单包", "一包", "两包", "三包", "四包", "五包",
  "1包", "2包", "3包", "4包", "5包", "一袋", "两袋", "三袋", "1袋", "2袋", "3袋",
];

function extractVisiblePackCount(text: string): number | null {
  const normalized = text.replace(/\s+/g, "");
  const directMatch = normalized.match(/([1-9]\d?)\s*(?:包|袋|颗|粒|枚)/);
  if (directMatch) return Number(directMatch[1]);

  const cnMap: Record<string, number> = {
    "一": 1,
    "两": 2,
    "二": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
    "十": 10,
  };
  const cnMatch = normalized.match(/([一二两三四五六七八九十])(?:包|袋|颗|粒|枚)/);
  return cnMatch ? (cnMap[cnMatch[1]] ?? null) : null;
}

function scaleNutritionValue(value: number | null | undefined, scale: number): number | null {
  if (value == null || !Number.isFinite(value)) return null;
  return Math.round(value * scale * 10) / 10;
}

function applyCompactPackHeuristic(
  dishes: Array<{
    name: string;
    estimated_grams: number | null;
    calorie_kcal: number | null;
    protein_g: number | null;
    carb_g: number | null;
    fat_g: number | null;
  }>,
  payload: Record<string, unknown>,
  ai: AIResult,
): { dishes: typeof dishes; note: string | null } {
  if (dishes.length === 0) return { dishes, note: null };

  const contextText = [
    normalizeString(ai.title),
    normalizeString(ai.summary),
    normalizeString(payload.confidence_note),
    ...dishes.map((dish) => dish.name),
  ].filter(Boolean).join(" ");

  if (!contextText) return { dishes, note: null };

  const isSmallPackSnack = includesAny(contextText, SMALL_PACK_FOOD_KEYWORDS).length > 0;
  const hasPackHint = includesAny(contextText, SMALL_PACK_HINT_KEYWORDS).length > 0;
  if (!isSmallPackSnack || (!hasPackHint && dishes.length > 2)) {
    return { dishes, note: null };
  }

  const visiblePackCount = Math.max(1, extractVisiblePackCount(contextText) ?? 1);
  const maxTotalGrams = visiblePackCount * 20;
  const adjustedDishes = dishes.map((dish) => {
    if (dish.estimated_grams == null || dish.estimated_grams <= maxTotalGrams || dish.estimated_grams > 300) {
      return dish;
    }

    const scale = maxTotalGrams / dish.estimated_grams;
    return {
      ...dish,
      estimated_grams: maxTotalGrams,
      calorie_kcal: scaleNutritionValue(dish.calorie_kcal, scale),
      protein_g: scaleNutritionValue(dish.protein_g, scale),
      carb_g: scaleNutritionValue(dish.carb_g, scale),
      fat_g: scaleNutritionValue(dish.fat_g, scale),
    };
  });

  const adjusted = adjustedDishes.some((dish, index) => dish.estimated_grams !== dishes[index]?.estimated_grams);
  if (!adjusted) return { dishes, note: null };

  return {
    dishes: adjustedDishes,
    note: `按小包装零食保守估算：按画面可见约 ${visiblePackCount} 份独立小包计，每包最多按 20g 估算。`,
  };
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

function normalizeDateOnlyValue(value: unknown): string | null {
  const dt = normalizeAiDateTime(value);
  return dt?.date ?? null;
}

function normalizeMonthKeyValue(value: unknown): string | null {
  const text = normalizeString(value);
  const match = text?.match(/^(\d{4})[-/年](\d{1,2})/);
  if (!match) return null;
  const month = Number(match[2]);
  if (!Number.isFinite(month) || month < 1 || month > 12) return null;
  return `${match[1]}-${String(month).padStart(2, "0")}`;
}

function correctWalletDueDateYear(dueDate: string | null, referenceDate: string | null): string | null {
  if (!dueDate || !referenceDate) return dueDate;
  const dueMatch = dueDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const refMatch = referenceDate.match(/^(\d{4})-\d{2}-\d{2}$/);
  if (!dueMatch || !refMatch) return dueDate;
  const dueYear = Number(dueMatch[1]);
  const refYear = Number(refMatch[1]);
  if (!Number.isFinite(dueYear) || !Number.isFinite(refYear)) return dueDate;
  if (Math.abs(dueYear - refYear) <= 1) return dueDate;
  return `${refYear}-${dueMatch[2]}-${dueMatch[3]}`;
}

function correctWalletStatementDateYear(statementDate: string | null, dueDate: string | null, referenceDate: string | null): string | null {
  if (!statementDate) return null;
  const statementMatch = statementDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!statementMatch) return statementDate;
  const anchor = dueDate ?? referenceDate;
  const anchorMatch = anchor?.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!anchorMatch) return statementDate;
  const statementYear = Number(statementMatch[1]);
  const anchorYear = Number(anchorMatch[1]);
  if (!Number.isFinite(statementYear) || !Number.isFinite(anchorYear)) return statementDate;
  if (Math.abs(statementYear - anchorYear) <= 1) return statementDate;
  return `${anchorYear}-${statementMatch[2]}-${statementMatch[3]}`;
}

function normalizeSleepClockTime(value: unknown, dateHint: string | null): string | null {
  const normalized = normalizeAiDateTime(value);
  if (normalized) return normalized.iso;
  if (typeof value !== "string" || !dateHint) return null;
  const text = value.trim();
  const clock = text.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!clock) return null;
  const [, hh, mm, ss] = clock;
  return `${dateHint}T${hh.padStart(2, "0")}:${mm}:${(ss ?? "00").padStart(2, "0")}+08:00`;
}

function normalizeSleepStartAt(startAt: string | null, wakeAt: string | null): string | null {
  if (!startAt || !wakeAt) return startAt;
  const startMs = Date.parse(startAt);
  const wakeMs = Date.parse(wakeAt);
  if (Number.isNaN(startMs) || Number.isNaN(wakeMs) || startMs <= wakeMs) return startAt;
  return new Date(startMs - 24 * 60 * 60 * 1000).toISOString();
}

function normalizeRecordKind(value: unknown): "cash_snapshot" | "liability_snapshot" | null {
  const text = normalizeString(value);
  if (text === "cash_snapshot" || text === "liability_snapshot") return text;
  if (!text) return null;
  if (includesAny(text, ["待还", "应还", "账单", "还款", "欠款"]).length) return "liability_snapshot";
  if (includesAny(text, ["余额", "现金", "零钱", "银行卡", "账户"]).length) return "cash_snapshot";
  return null;
}

function normalizeAccountType(value: unknown, accountName: string | null, recordKind: string | null): string {
  const text = `${normalizeString(value) ?? ""} ${accountName ?? ""}`.toLowerCase();
  if (text.includes("花呗")) return "credit_line";
  if (text.includes("白条") || text.includes("jd")) return "credit_line";
  if (text.includes("抖音") || text.includes("douyin")) return "credit_line";
  if (text.includes("信用卡")) return "credit_card";
  if (text.includes("微信") || text.includes("零钱")) return "wallet_balance";
  if (text.includes("支付宝") || text.includes("余额宝")) return "wallet_balance";
  if (text.includes("银行") || text.includes("卡")) return "debit_card";
  if (text.includes("现金")) return "cash";
  return recordKind === "liability_snapshot" ? "credit_line" : "other";
}

function normalizeWalletStatus(value: unknown, recordKind: string | null): string {
  const text = normalizeString(value);
  if (text === "unpaid" || text === "paid" || text === "available" || text === "unknown") return text;
  if (!text) return recordKind === "cash_snapshot" ? "available" : "unpaid";
  if (includesAny(text, ["已还", "已结清", "paid"]).length) return "paid";
  if (includesAny(text, ["待还", "应还", "未还", "unpaid"]).length) return "unpaid";
  if (includesAny(text, ["余额", "可用"]).length) return "available";
  return "unknown";
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
    const sleepMinutes = parseDurationMinutes(payload.sleep_minutes);
    const score = normalizeNumber(payload.quality_score);
    const occurredDate = normalizeDateOnlyValue(ai.occurred_at) ?? normalizeDateOnlyValue(payload.wake_at) ?? normalizeDateOnlyValue(payload.sleep_start_at);
    const wakeAt = normalizeSleepClockTime(payload.wake_at, occurredDate);
    const sleepStartAt = normalizeSleepStartAt(normalizeSleepClockTime(payload.sleep_start_at, occurredDate), wakeAt);
    const normalizedSleepHours = sleepHours ?? (sleepMinutes !== null ? Math.round((sleepMinutes / 60) * 100) / 100 : null);
    const normalizedSleepMinutes = sleepMinutes ?? (normalizedSleepHours !== null ? Math.round(normalizedSleepHours * 60) : null);
    if (normalizedSleepMinutes === null) missingFields.push("sleep_minutes");
    payload.sleep_hours = normalizedSleepHours;
    payload.sleep_minutes = normalizedSleepMinutes;
    if (wakeAt) payload.wake_at = wakeAt;
    if (sleepStartAt) payload.sleep_start_at = sleepStartAt;
    payload.quality_score = score;
    payload.quality_level = normalizeString(payload.quality_level) ?? qualityLevelFromScore(score);
    title = normalizeString(ai.title) ?? "夜间睡眠";
    summary = [
      normalizedSleepHours !== null ? `睡眠 ${normalizedSleepHours} 小时` : null,
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

  if (domainKey === "food") {
    // 标准化 dishes 数组：每项至少含 name；其它字段允许为 null
    const rawDishes = Array.isArray(payload.dishes) ? payload.dishes : [];
    let dishes = rawDishes.map((d: unknown) => {
      if (!d || typeof d !== "object") return null;
      const item = d as Record<string, unknown>;
      const name = normalizeString(item.name);
      if (!name) return null;
      return {
        name,
        estimated_grams: normalizeNumber(item.estimated_grams),
        calorie_kcal: normalizeNumber(item.calorie_kcal),
        protein_g: normalizeNumber(item.protein_g),
        carb_g: normalizeNumber(item.carb_g),
        fat_g: normalizeNumber(item.fat_g),
      };
    }).filter((d): d is NonNullable<typeof d> => d !== null);

    const compactPackAdjustment = applyCompactPackHeuristic(dishes, payload, ai);
    dishes = compactPackAdjustment.dishes;

    // 总热量：优先用 AI 给的，回落到 dishes 累加
    const dishCalorieSum = dishes.reduce((acc, d) => acc + (d.calorie_kcal ?? 0), 0);
    let totalCalorie = normalizeNumber(payload.total_calorie_kcal);
    if (compactPackAdjustment.note && dishCalorieSum > 0) {
      totalCalorie = Math.round(dishCalorieSum * 10) / 10;
    } else if (totalCalorie === null && dishes.length > 0) {
      totalCalorie = dishCalorieSum > 0 ? Math.round(dishCalorieSum * 10) / 10 : null;
    }

    // meal_type：AI 没给则按当前北京时间推断
    const allowedMealTypes = ["breakfast", "lunch", "dinner", "snack"];
    let mealType = normalizeString(payload.meal_type);
    if (!mealType || !allowedMealTypes.includes(mealType)) {
      // 北京时间小时（UTC+8）
      const nowBjHour = new Date(Date.now() + 8 * 60 * 60 * 1000).getUTCHours();
      if (nowBjHour >= 6 && nowBjHour < 10) mealType = "breakfast";
      else if (nowBjHour >= 10 && nowBjHour < 14) mealType = "lunch";
      else if (nowBjHour >= 17 && nowBjHour < 21) mealType = "dinner";
      else mealType = "snack";
    }

    if (dishes.length === 0) missingFields.push("dishes");
    if (totalCalorie === null) missingFields.push("total_calorie_kcal");

    payload.dishes = dishes;
    payload.total_calorie_kcal = totalCalorie;
    payload.meal_type = mealType;
    const confidenceNote = normalizeString(payload.confidence_note);
    payload.confidence_note = [confidenceNote, compactPackAdjustment.note].filter(Boolean).join(" ") || null;
    // 标记为估算值，前端可据此显示提醒
    payload.is_estimated = true;

    title = normalizeString(ai.title) ?? dishes[0]?.name ?? "饮食记录";
    const mealLabel = mealType === "breakfast" ? "早餐"
      : mealType === "lunch" ? "午餐"
      : mealType === "dinner" ? "晚餐" : "加餐";
    const dishesPart = dishes.length > 0
      ? dishes.slice(0, 3).map((d) => d.name).join("+") + (dishes.length > 3 ? "等" : "")
      : null;
    summary = [
      mealLabel,
      dishesPart,
      totalCalorie !== null ? `约 ${Math.round(totalCalorie)} 千卡` : null,
    ].filter(Boolean).join("·") || summary;
  }

  if (domainKey === "wallet") {
    const accountName = normalizeString(payload.account_name) ?? normalizeString(ai.title);
    const recordKind = normalizeRecordKind(payload.record_kind)
      ?? normalizeRecordKind(ai.image_type)
      ?? normalizeRecordKind(ai.summary)
      ?? (includesAny(`${accountName ?? ""}${ai.summary ?? ""}`, ["花呗", "白条", "月付", "信用卡", "待还", "应还"]).length ? "liability_snapshot" : "cash_snapshot");
    const amount = normalizeNumber(payload.amount ?? ai.amount);
    const referenceDate = normalizeDateOnlyValue(ai.occurred_at);
    const dueDate = correctWalletDueDateYear(normalizeDateOnlyValue(payload.due_date), referenceDate);
    const statementStartDate = correctWalletStatementDateYear(normalizeDateOnlyValue(payload.statement_start_date), dueDate, referenceDate);
    const statementEndDate = correctWalletStatementDateYear(normalizeDateOnlyValue(payload.statement_end_date), dueDate, referenceDate);
    const paymentDueDay = normalizeNumber(payload.payment_due_day ?? payload.due_day ?? payload.repayment_day);
    const billDay = normalizeNumber(payload.bill_day)
      ?? (statementEndDate ? Number(statementEndDate.slice(-2)) : null);
    const cycleMonth = normalizeMonthKeyValue(payload.cycle_month)
      ?? normalizeMonthKeyValue(payload.statement_month)
      ?? normalizeMonthKeyValue(payload.bill_month)
      ?? normalizeMonthKeyValue(dueDate)
      ?? normalizeMonthKeyValue(statementEndDate)
      ?? normalizeMonthKeyValue(referenceDate);
    const minimumPayment = normalizeNumber(payload.minimum_payment);
    if (!accountName) missingFields.push("account_name");
    if (!recordKind) missingFields.push("record_kind");
    if (amount === null) missingFields.push("amount");
    payload.record_kind = recordKind;
    payload.account_name = accountName;
    payload.account_type = normalizeAccountType(payload.account_type, accountName, recordKind);
    payload.amount = amount;
    payload.snapshot_balance = amount;
    payload.account_snapshot_kind = recordKind === "liability_snapshot" ? "liability" : "asset";
    payload.institution = normalizeString(payload.institution) ?? accountName;
    {
      const last4 = normalizeString(payload.last4);
      payload.last4 = last4 && /^\d{4}$/.test(last4) ? last4 : null;
    }
    payload.due_date = dueDate;
    payload.payment_due_day = paymentDueDay ?? (dueDate ? Number(dueDate.slice(-2)) : null);
    payload.statement_start_date = statementStartDate;
    payload.statement_end_date = statementEndDate;
    payload.bill_day = billDay;
    payload.cycle_month = cycleMonth;
    payload.minimum_payment = minimumPayment;
    payload.status = normalizeWalletStatus(payload.status, recordKind);
    payload.source_app = normalizeString(payload.source_app) ?? "截图识别";
    title = normalizeString(ai.title)
      ?? (recordKind === "liability_snapshot" ? `${accountName ?? "待还款"}待还` : `${accountName ?? "账户"}余额`);
    summary = [
      accountName,
      recordKind === "liability_snapshot" ? "待还" : "余额",
      amount !== null ? `${amount} 元` : null,
      dueDate ? `${dueDate} 还` : billDay ? `每月 ${billDay} 号还` : null,
    ].filter(Boolean).join("，") || summary;
  }

  return { payload, title, summary, missingFields };
}

function resolveBuiltinOccurredAt(domainKey: BuiltinDomainKey, occurredAt: string | null, payload: Record<string, unknown>): string {
  if (domainKey === "sleep") {
    const wakeAt = normalizeAiDate(payload.wake_at);
    const sleepStartAt = normalizeAiDate(payload.sleep_start_at);
    return wakeAt ?? sleepStartAt ?? occurredAt ?? new Date().toISOString();
  }
  return occurredAt ?? new Date().toISOString();
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

async function runLowCostDispatcher(
  supabase: ReturnType<typeof createClient>,
  params: {
    rawText: string | null;
    sourceApp: string | null;
    imageFeatures: ImageFeatures;
  },
): Promise<DispatcherResult> {
  const text = [params.rawText, params.sourceApp].filter(Boolean).join(" ");
  const { data: domains, error } = await supabase
    .from("data_domains")
    .select("key,name,routing_json,status")
    .eq("status", "active");

  if (error) console.error("Dispatcher domain load failed:", error);

  const candidates: DispatcherCandidate[] = [];
  const seenKeys = new Set<string>();
  for (const domain of domains || []) {
    const routing = domain.routing_json && typeof domain.routing_json === "object" && !Array.isArray(domain.routing_json)
      ? domain.routing_json as Record<string, unknown>
      : {};
    const fallback = BUILTIN_ROUTE_RULES[domain.key] ?? { keywords: [], apps: [], threshold: 0.7 };
    const keywords = [...new Set([...arrayFromUnknown(routing.keywords ?? routing.trigger_keywords), ...fallback.keywords])];
    const apps = [...new Set([...arrayFromUnknown(routing.trigger_apps), ...fallback.apps])];
    const threshold = normalizeNumber(routing.confidence_threshold) ?? fallback.threshold;
    const matchedKeywords = text ? includesAny(text, keywords) : [];
    const matchedApps = params.sourceApp ? includesAny(params.sourceApp, apps) : [];
    if (matchedKeywords.length === 0 && matchedApps.length === 0) continue;
    seenKeys.add(domain.key);
    const confidence = Math.min(0.95, Math.max(threshold, 0.45 + matchedKeywords.length * 0.12 + matchedApps.length * 0.2));
    candidates.push({
      key: domain.key,
      name: domain.name,
      confidence: Math.round(confidence * 100) / 100,
      reason: `命中 ${[...matchedKeywords, ...matchedApps].join(" / ")}`,
      matched_keywords: matchedKeywords,
      matched_apps: matchedApps,
    });
  }
  for (const [key, rule] of Object.entries(BUILTIN_ROUTE_RULES)) {
    if (seenKeys.has(key)) continue;
    const matchedKeywords = text ? includesAny(text, rule.keywords) : [];
    const matchedApps = params.sourceApp ? includesAny(params.sourceApp, rule.apps) : [];
    if (matchedKeywords.length === 0 && matchedApps.length === 0) continue;
    const confidence = Math.min(0.95, Math.max(rule.threshold, 0.45 + matchedKeywords.length * 0.12 + matchedApps.length * 0.2));
    candidates.push({
      key,
      name: domainNameFromKey(key) ?? key,
      confidence: Math.round(confidence * 100) / 100,
      reason: `命中内置规则 ${[...matchedKeywords, ...matchedApps].join(" / ")}`,
      matched_keywords: matchedKeywords,
      matched_apps: matchedApps,
    });
  }

  candidates.sort((a, b) => b.confidence - a.confidence);
  const selected = candidates[0] ?? null;
  const hasTextButNoCandidate = Boolean(text) && !selected;
  const looksMeaningless = !params.imageFeatures.likely_phone_screenshot
    && !params.imageFeatures.is_tall_screenshot
    && !text
    && (params.imageFeatures.is_tiny_image || params.imageFeatures.is_wide_screenshot);

  return {
    raw_text: params.rawText,
    source_app: params.sourceApp,
    image_features: params.imageFeatures,
    candidate_domains: candidates,
    selected_domain_key: selected?.key ?? null,
    route_confidence: selected?.confidence ?? 0,
    route_reason: selected?.reason ?? (hasTextButNoCandidate ? "OCR 文本未命中任何模板规则" : looksMeaningless ? "图片基础特征疑似非手机业务截图" : "未命中低成本路由规则"),
    should_call_vision: !looksMeaningless && !hasTextButNoCandidate,
    skip_reason: hasTextButNoCandidate ? "NO_TRIGGER_RULE_MATCH" : looksMeaningless ? "LOW_VALUE_IMAGE_FEATURES" : null,
  };
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

// 通知摘要相关 helpers ─────────────────────────────────────────
function fmtYuan(n: number | null | undefined): string {
  const v = Number(n ?? 0);
  return `¥${v.toFixed(2)}`;
}

function chinaTodayStr(): string {
  return new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

async function summarizeTodaySpend(
  supabase: ReturnType<typeof createClient>,
  userId: string | null,
): Promise<{ total: number; count: number }> {
  if (!userId) return { total: 0, count: 0 };
  const today = chinaTodayStr();
  const { data } = await supabase
    .from("transactions")
    .select("amount")
    .eq("user_id", userId)
    .eq("type", "expense")
    .eq("transaction_date", today);
  if (!data) return { total: 0, count: 0 };
  const total = data.reduce((s: number, r: any) => s + Number(r.amount || 0), 0);
  return { total: Math.round(total * 100) / 100, count: data.length };
}

async function summarizeMonthIncome(
  supabase: ReturnType<typeof createClient>,
  userId: string | null,
): Promise<{ total: number }> {
  if (!userId) return { total: 0 };
  const monthStart = chinaTodayStr().slice(0, 7) + "-01";
  const { data } = await supabase
    .from("income_records")
    .select("amount")
    .eq("user_id", userId)
    .gte("income_date", monthStart);
  if (!data) return { total: 0 };
  const total = data.reduce((s: number, r: any) => s + Number(r.amount || 0), 0);
  return { total: Math.round(total * 100) / 100 };
}

function todaySpendLine(s: { total: number; count: number }): string {
  if (s.count === 0) return "今日尚无支出记录";
  return `今日已花 ${fmtYuan(s.total)}（${s.count} 笔）`;
}

function monthIncomeLine(s: { total: number }): string {
  return `本月已入 ${fmtYuan(s.total)}`;
}

interface CompanionSettings {
  enabled: boolean;
  memoryEnabled: boolean;
  persona: string;
  memoryStrength: string;
  expressionStyle: string;
  customNote: string | null;
}

const DEFAULT_COMPANION_SETTINGS: CompanionSettings = {
  enabled: true,
  memoryEnabled: true,
  persona: "observer",
  memoryStrength: "balanced",
  expressionStyle: "plain",
  customNote: null,
};

async function loadCompanionContext(
  supabase: ReturnType<typeof createClient>,
  userId: string | null,
): Promise<{ settings: CompanionSettings; memory: Record<string, unknown> | null }> {
  if (!userId) return { settings: DEFAULT_COMPANION_SETTINGS, memory: null };
  const { data, error } = await supabase.rpc("get_companion_context", { p_user_id: userId });
  if (error) {
    console.warn("Companion context fetch failed:", error.message);
    return { settings: DEFAULT_COMPANION_SETTINGS, memory: null };
  }
  const raw = (data || {}) as Record<string, unknown>;
  const settingsRaw = (raw.settings || {}) as Record<string, unknown>;
  const settings: CompanionSettings = {
    enabled: settingsRaw.enabled !== false,
    memoryEnabled: settingsRaw.memory_enabled !== false,
    persona: typeof settingsRaw.persona === "string" ? settingsRaw.persona : "observer",
    memoryStrength: typeof settingsRaw.memory_strength === "string" ? settingsRaw.memory_strength : "balanced",
    expressionStyle: typeof settingsRaw.expression_style === "string" ? settingsRaw.expression_style : "plain",
    customNote: typeof settingsRaw.custom_note === "string" ? settingsRaw.custom_note : null,
  };
  return { settings, memory: settings.memoryEnabled ? raw : null };
}

function firstNonEmpty(...values: Array<string | null | undefined>): string | null {
  for (const value of values) {
    const normalized = normalizeString(value);
    if (normalized) return normalized;
  }
  return null;
}

function memoryText(value: string, max = 80): string {
  return value.length > max ? value.slice(0, max) : value;
}

function formatChinaMonthDay(value: string | null | undefined): string | null {
  if (!value) return null;
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) return null;
  const chinaDate = new Date(ms + 8 * 60 * 60 * 1000);
  return `${chinaDate.getUTCMonth() + 1}月${chinaDate.getUTCDate()}日`;
}

function sanitizeCompanionMessageForTime(
  message: string | null,
  ai: AIResult,
  timeContext: ReturnType<typeof buildTimeContext>,
): string | null {
  if (!message) return null;
  const recordType = ai.domain_key ?? ai.record_type;
  if (recordType !== "sleep" || !timeContext.is_backfill) return message;
  if (!/(昨晚|昨天|昨日)/.test(message)) return message;

  const eventLabel = formatChinaMonthDay(timeContext.event_time);
  if (!eventLabel) return message;
  return message
    .replace(/昨晚/g, `${eventLabel}这晚`)
    .replace(/昨天|昨日/g, eventLabel)
    .slice(0, 60);
}

const COMPANION_FORBIDDEN_PATTERNS = [
  /刚吃完.+又来/,
  /这周.*吃过.*今天换成/,
  /第\s*N\s*顿/i,
  /第几笔/,
  /看来.*(熬夜|胃口不错|吃饱了|凑个单)/,
  /(记得|别忘了|要按时|注意身体|合理饮食|少吃|控制)/,
  /(超标|放纵|罪恶|买个安心|生活还在继续)/,
];

const FOOD_MERCHANT_HINTS = [
  "外婆家",
  "老婆大人",
  "杨掌勺",
  "鱼羊鲜",
  "沈氏牛肉汤",
  "甬上嫂子",
  "RightCode",
  "乔稚",
];

function collectCompanionAllowedText(ai: AIResult): string {
  const payload = ai.payload_jsonb && typeof ai.payload_jsonb === "object" && !Array.isArray(ai.payload_jsonb)
    ? ai.payload_jsonb
    : {};
  const dishes = Array.isArray(payload.dishes)
    ? payload.dishes
      .map((item) => item && typeof item === "object" ? normalizeString((item as Record<string, unknown>).name) : null)
      .filter(Boolean)
    : [];
  return [
    ai.title,
    ai.summary,
    ai.merchant_name,
    ai.source_name,
    ai.category,
    ai.payment_method,
    payload.confidence_note,
    payload.meal_type,
    ...dishes,
  ].map((value) => normalizeString(value)).filter(Boolean).join(" ");
}

function sanitizeCompanionMessageForContent(message: string | null, ai: AIResult): string | null {
  if (!message) return null;
  const text = message.trim();
  if (!text) return null;
  if (COMPANION_FORBIDDEN_PATTERNS.some((pattern) => pattern.test(text))) return null;

  const recordType = ai.domain_key ?? ai.record_type;
  const allowedText = collectCompanionAllowedText(ai);
  if (recordType === "food" && ai.image_type === "food_photo") {
    const unrelatedMerchant = FOOD_MERCHANT_HINTS.find((hint) => text.includes(hint) && !allowedText.includes(hint));
    if (unrelatedMerchant) return null;
  }

  return text.slice(0, 60);
}

function buildSportCompanionFallback(payload: Record<string, unknown>, title: string): string | null {
  const sportType = normalizeString(payload.sport_type) ?? normalizeString(title) ?? "这次运动";
  const duration = normalizeNumber(payload.duration_minutes);
  const distance = normalizeNumber(payload.distance_km);
  const calories = normalizeNumber(payload.calories);
  const avgHeartRate = normalizeNumber(payload.avg_heart_rate);
  const label = sportType === "运动记录" ? "这次运动" : sportType;

  if (distance !== null && duration !== null) {
    return `${label} ${distance} 公里，${Math.round(duration)} 分钟很完整。`;
  }
  if (duration !== null && calories !== null) {
    return `${label} ${Math.round(duration)} 分钟，消耗 ${Math.round(calories)} 千卡。`;
  }
  if (duration !== null && avgHeartRate !== null) {
    return `${label} ${Math.round(duration)} 分钟，心率 ${Math.round(avgHeartRate)}。`;
  }
  if (duration !== null) {
    return `${label} ${Math.round(duration)} 分钟，记录得很清楚。`;
  }
  return null;
}

function buildBuiltinCompanionFallback(
  domainKey: BuiltinDomainKey,
  built: { payload: Record<string, unknown>; title: string; summary: string },
): string | null {
  if (domainKey === "sport") return buildSportCompanionFallback(built.payload, built.title);
  return null;
}

function compactFeedbackText(value: string | null | undefined, max = 42): string | null {
  const text = normalizeString(value)?.replace(/[\r\n]+/g, " ").trim();
  if (!text) return null;
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

function feedbackNotification(
  feedback: AIFeedback | null,
  fallback: string,
  options: { preserveFallbackTail?: boolean; preserveFallbackAll?: boolean } = {},
): string {
  if (!feedback || feedback.confidence < 0.5) return fallback;
  const fallbackLines = fallback.split("\n").map((line) => line.trim()).filter(Boolean);
  const fallbackTail = options.preserveFallbackAll
    ? fallbackLines
    : options.preserveFallbackTail
      ? fallbackLines.slice(1)
      : [];
  const lines = [
    `${feedback.icon} ${feedback.badge}`,
    compactFeedbackText(feedback.emotion_line, 34),
    compactFeedbackText(feedback.utility_line, 34) ?? fallbackLines[0],
    ...fallbackTail,
  ].filter(Boolean);
  return lines.join("\n");
}

function timingSignalFor(domainKey: string, timeContext: TimeContext | null): AIFeedback["timing_signal"] {
  if (!timeContext || timeContext.delta_minutes === null || timeContext.delta_minutes < 0) return null;
  const delta = timeContext.delta_minutes;
  if (domainKey === "sleep" && delta <= 15) return { key: "morning_check", label: "晨起记录" };
  if (domainKey === "sport" && delta <= 30) return { key: "post_sport_check", label: "运动后记录" };
  if (domainKey === "expense" && delta <= 10) return { key: "realtime_accounting", label: "即时记账" };
  if (timeContext.is_backfill) return { key: "backfill", label: "补录完成" };
  return null;
}

function financeCompanionLine(ai: AIResult): string | null {
  const text = compactFeedbackText(ai.companion_message, 34);
  if (!text) return null;
  const financeText = `${ai.merchant_name ?? ""} ${ai.source_name ?? ""} ${ai.category ?? ""} ${ai.platform ?? ""}`;
  const leaksOtherDomain = /(运动|骑行|跑步|睡眠|饮食记录|热量|蛋白|碳水|外婆家|老婆大人)/.test(text)
    && !/(餐饮|food|美食|饭|餐|外卖)/i.test(financeText);
  if (leaksOtherDomain) return null;
  if (/(第几笔|凑个单|小确幸|给生活充个值|看来是|应该不错|确实地道)/.test(text)) return null;
  return text;
}

function buildBuiltinAIFeedback(
  domainKey: BuiltinDomainKey,
  built: { payload: Record<string, unknown>; title: string; summary: string },
  timeContext: TimeContext,
  companionLine: string | null = null,
): AIFeedback | null {
  const timingSignal = timingSignalFor(domainKey, timeContext);
  const aiEmotion = compactFeedbackText(companionLine, 34);
  const payload = built.payload || {};

  if (domainKey === "sport") {
    const sportType = normalizeString(payload.sport_type) ?? "运动";
    const duration = normalizeNumber(payload.duration_minutes);
    const distance = normalizeNumber(payload.distance_km);
    const calories = normalizeNumber(payload.calories);
    const avgHeartRate = normalizeNumber(payload.avg_heart_rate);
    if (timingSignal?.key === "post_sport_check") {
      return {
        version: "feedback-v1",
        domain_key: "sport",
        badge: "即时记录",
        icon: "🏃",
        band: "ritual",
        tone: "ritual_seen",
        emotion_line: `刚${sportType}完就记录，身体状态还新鲜。`,
        utility_line: duration !== null ? `这次运动 ${Math.round(duration)} 分钟，后面看恢复更有意义。` : "这条记录留下了运动后的第一手状态。",
        detail_reason: `截图时间与运动时间相隔约 ${timeContext.delta_minutes} 分钟，属于运动后即时记录。`,
        internal_score: 82,
        confidence: 0.82,
        source: "rule",
        timing_signal: timingSignal,
      };
    }
    if (duration !== null && duration >= 30 && (distance !== null || calories !== null)) {
      return {
        version: "feedback-v1",
        domain_key: "sport",
        badge: "有效有氧",
        icon: "🏃",
        band: "positive",
        tone: "specific_recognition",
        emotion_line: aiEmotion ?? (distance !== null
          ? `${Math.round(duration)} 分钟 ${distance} 公里，不是随便活动一下。`
          : `${Math.round(duration)} 分钟运动，身体被认真调动起来了。`),
        utility_line: avgHeartRate !== null ? `平均心率 ${Math.round(avgHeartRate)}，详情里可以看强度。` : "这类完整记录，最适合后面看连续性。",
        detail_reason: `时长达到 30 分钟以上${distance !== null ? `，距离 ${distance} 公里` : ""}${calories !== null ? `，消耗约 ${Math.round(calories)} 千卡` : ""}。`,
        internal_score: 78,
        confidence: 0.78,
        source: aiEmotion ? "hybrid" : "rule",
        timing_signal: timingSignal,
      };
    }
    if (duration !== null) {
      return {
        version: "feedback-v1",
        domain_key: "sport",
        badge: "轻量唤醒",
        icon: "🏃",
        band: "neutral",
        tone: "light_observation",
        emotion_line: aiEmotion ?? `${sportType} ${Math.round(duration)} 分钟，今天身体被叫醒了。`,
        utility_line: "量不一定大，但这条记录能接上运动节奏。",
        detail_reason: "本次运动时长较短或缺少距离/热量信息，先按轻量运动记录处理。",
        internal_score: 62,
        confidence: 0.68,
        source: aiEmotion ? "hybrid" : "rule",
        timing_signal: timingSignal,
      };
    }
  }

  if (domainKey === "sleep") {
    const sleepHours = normalizeNumber(payload.sleep_hours);
    const sleepMinutes = normalizeNumber(payload.sleep_minutes);
    const hours = sleepHours ?? (sleepMinutes !== null ? sleepMinutes / 60 : null);
    if (timingSignal?.key === "morning_check") {
      return {
        version: "feedback-v1",
        domain_key: "sleep",
        badge: "晨起记录",
        icon: "🌙",
        band: "ritual",
        tone: "ritual_seen",
        emotion_line: `醒后 ${timeContext.delta_minutes} 分钟就截图，像是晨间小仪式。`,
        utility_line: hours !== null ? `这晚约 ${Math.round(hours * 10) / 10} 小时，状态还很新鲜。` : "刚醒就记录，睡眠感受还没有被白天冲淡。",
        detail_reason: "截图时间与醒来时间非常接近，记录时机本身具有习惯信号。",
        internal_score: 84,
        confidence: 0.84,
        source: "rule",
        timing_signal: timingSignal,
      };
    }
    if (timeContext.is_backfill) {
      return {
        version: "feedback-v1",
        domain_key: "sleep",
        badge: "补录完成",
        icon: "🌙",
        band: "neutral",
        tone: "archive_first",
        emotion_line: "这是补录，先把睡眠拼图补上就有价值。",
        utility_line: hours !== null ? `这晚约 ${Math.round(hours * 10) / 10} 小时，后面再看趋势。` : "补齐记录，比空着一晚更有用。",
        detail_reason: "记录发生时间早于截图时间，系统按补录处理，不强行评价当天状态。",
        internal_score: 60,
        confidence: 0.72,
        source: "rule",
        timing_signal: timingSignal,
      };
    }
    if (hours !== null && hours >= 7) {
      return {
        version: "feedback-v1",
        domain_key: "sleep",
        badge: "睡够一晚",
        icon: "🌙",
        band: "positive",
        tone: "specific_recognition",
        emotion_line: aiEmotion ?? `这晚睡了 ${Math.round(hours * 10) / 10} 小时，底子比较厚。`,
        utility_line: "今天别急着把电量一次性花完。",
        detail_reason: "睡眠时长达到 7 小时以上，先按相对充足的一晚处理。",
        internal_score: 76,
        confidence: 0.76,
        source: aiEmotion ? "hybrid" : "rule",
        timing_signal: timingSignal,
      };
    }
    if (hours !== null) {
      return {
        version: "feedback-v1",
        domain_key: "sleep",
        badge: "轻缺觉",
        icon: "🌙",
        band: "watch",
        tone: "soft_watch",
        emotion_line: aiEmotion ?? `这晚约 ${Math.round(hours * 10) / 10} 小时，有点薄。`,
        utility_line: "今天少给自己加码一点，就算补回来了。",
        detail_reason: "睡眠时长低于 7 小时，但单晚记录只提示状态，不评价用户。",
        internal_score: 52,
        confidence: 0.7,
        source: aiEmotion ? "hybrid" : "rule",
        timing_signal: timingSignal,
      };
    }
  }

  if (domainKey === "food") {
    const mealType = normalizeString(payload.meal_type);
    const calories = normalizeNumber(payload.total_calorie_kcal);
    const dishes = Array.isArray(payload.dishes) ? payload.dishes : [];
    const dishText = dishes
      .map((item) => item && typeof item === "object" ? normalizeString((item as Record<string, unknown>).name) : null)
      .filter(Boolean)
      .join(" ");
    const isSweetOrFried = includesAny(`${built.title} ${built.summary} ${dishText}`, ["奶茶", "可乐", "炸", "薯条", "甜", "蛋糕", "汉堡"]).length > 0;
    if (isSweetOrFried || (calories !== null && calories >= 800)) {
      return {
        version: "feedback-v1",
        domain_key: "food",
        badge: "偏放松",
        icon: "🍱",
        band: "recover",
        tone: "soft_recovery",
        emotion_line: aiEmotion ?? "偶尔吃得快乐一点很正常，快乐也是刚需。",
        utility_line: "轻补救：今晚散步 15 分钟，或者下一餐清一点。",
        detail_reason: calories !== null
          ? `这顿估算约 ${Math.round(calories)} 千卡，且可能包含甜口或油炸元素。`
          : "这顿可能包含甜口或油炸元素，按轻量兜底处理。",
        internal_score: 48,
        confidence: 0.72,
        source: aiEmotion ? "hybrid" : "rule",
        timing_signal: timingSignal,
      };
    }
    if (mealType && mealType !== "snack") {
      return {
        version: "feedback-v1",
        domain_key: "food",
        badge: "结构扎实",
        icon: "🍱",
        band: "positive",
        tone: "specific_recognition",
        emotion_line: aiEmotion ?? "这顿像是认真吃饭，不是随便糊弄一口。",
        utility_line: calories !== null ? `估算约 ${Math.round(calories)} 千卡，适合和当天总量一起看。` : "后面补齐几次，饮食节奏会更清楚。",
        detail_reason: "当前记录被识别为正餐，且没有明显高糖/油炸信号。",
        internal_score: 72,
        confidence: 0.7,
        source: aiEmotion ? "hybrid" : "rule",
        timing_signal: timingSignal,
      };
    }
    return {
      version: "feedback-v1",
      domain_key: "food",
      badge: "轻加餐",
      icon: "🍱",
      band: "neutral",
      tone: "light_observation",
      emotion_line: aiEmotion ?? "这更像一次加餐，不用把它当成正餐压力。",
      utility_line: "下一顿正常吃，节奏就不会被它带跑。",
      detail_reason: "当前记录更接近零食或加餐，单次记录不做强评价。",
      internal_score: 60,
      confidence: 0.66,
      source: aiEmotion ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }

  if (domainKey === "reading") {
    const minutes = normalizeNumber(payload.reading_minutes);
    return {
      version: "feedback-v1",
      domain_key: "reading",
      badge: minutes !== null && minutes >= 20 ? "连续推进" : "碎片续航",
      icon: "📚",
      band: "positive",
      tone: "steady_progress",
      emotion_line: aiEmotion ?? (minutes !== null && minutes >= 20 ? "今天不是只翻两页，进度往前挪了一格。" : "碎片阅读最怕断，不怕慢。"),
      utility_line: minutes !== null ? `这次 ${Math.round(minutes)} 分钟，后面看连续性更有意义。` : "先把阅读这件事接住了。",
      detail_reason: "阅读记录更重视连续性和主题沉淀，不按单次数量评价。",
      internal_score: minutes !== null && minutes >= 20 ? 74 : 66,
      confidence: 0.68,
      source: aiEmotion ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }

  if (domainKey === "wallet") {
    const recordKind = normalizeString(payload.record_kind);
    const amount = normalizeNumber(payload.amount);
    return {
      version: "feedback-v1",
      domain_key: "wallet",
      badge: recordKind === "liability_snapshot" ? "现金流提醒" : "账户快照",
      icon: "💳",
      band: recordKind === "liability_snapshot" ? "watch" : "neutral",
      tone: "finance_observation",
      emotion_line: aiEmotion ?? (recordKind === "liability_snapshot" ? "这条重点不是金额，是后面的还款节奏。" : "这次留的是账户状态，不只是单笔流水。"),
      utility_line: amount !== null ? `金额 ${fmtYuan(amount)}，后面适合看余额变化。` : "先把快照留住，后面才看得出变化。",
      detail_reason: recordKind === "liability_snapshot" ? "识别为待还/账单类快照，优先提醒还款节奏。" : "识别为余额类快照，适合作为账户变化参照。",
      internal_score: 62,
      confidence: 0.68,
      source: aiEmotion ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }

  return null;
}

function buildExpenseAIFeedback(
  ai: AIResult,
  amount: number | null,
  timeContext: TimeContext,
  possibleDuplicate: boolean,
): AIFeedback | null {
  if (amount === null || (ai.confidence ?? 0) < 0.7) return null;
  const timingSignal = timingSignalFor("expense", timeContext);
  const category = normalizeString(ai.category);
  const merchant = normalizeString(ai.merchant_name);
  const aiLine = financeCompanionLine(ai);
  const financeText = `${merchant ?? ""} ${category ?? ""} ${ai.platform ?? ""} ${ai.payment_method ?? ""}`;
  const isRepayment = includesAny(financeText, ["还款", "待还", "信贷", "花呗", "白条", "月付", "信用卡"]).length > 0;
  const isRentLike = includesAny(financeText, ["房租", "租房", "公寓", "房东", "滨江叔叔"]).length > 0
    || (amount >= 1000 && category !== null && includesAny(category, ["life", "生活", "housing", "rent"]).length > 0);
  if (possibleDuplicate) {
    return {
      version: "feedback-v1",
      domain_key: "expense",
      badge: "疑似重复",
      icon: "💸",
      band: "watch",
      tone: "verify_gently",
      emotion_line: aiLine ?? "这笔和刚才的消费很像，先别急着算两次。",
      utility_line: "轻确认：点进 App 看一眼是不是重复记账。",
      detail_reason: "3 分钟内存在同金额、同支付方式且商家相近的支出。",
      internal_score: 50,
      confidence: 0.82,
      source: aiLine ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }
  if (isRepayment) {
    return {
      version: "feedback-v1",
      domain_key: "expense",
      badge: "还款节奏",
      icon: "💸",
      band: "watch",
      tone: "finance_observation",
      emotion_line: aiLine && /(还|待还|账单|信贷|花呗|白条|信用卡)/.test(aiLine)
        ? aiLine
        : "这笔重点不是花掉了，而是待还节奏被记录住了。",
      utility_line: `金额 ${fmtYuan(amount)}，适合和本月还款一起看。`,
      detail_reason: "商家、分类或支付信息包含还款/信贷信号，按现金流节奏处理。",
      internal_score: 60,
      confidence: 0.76,
      source: aiLine ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }
  if (isRentLike) {
    return {
      version: "feedback-v1",
      domain_key: "expense",
      badge: "固定支出",
      icon: "💸",
      band: "neutral",
      tone: "finance_observation",
      emotion_line: aiLine && /(房|租|住|居住|公寓)/.test(aiLine)
        ? aiLine
        : "这类房租/居住成本，重点是周期，不是冲动消费。",
      utility_line: `金额 ${fmtYuan(amount)}，应该单独看固定支出占比。`,
      detail_reason: "本笔金额较高且分类偏生活/居住，按固定生活成本处理。",
      internal_score: 64,
      confidence: 0.74,
      source: aiLine ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }
  if (amount <= 20) {
    return {
      version: "feedback-v1",
      domain_key: "expense",
      badge: "小额渗漏",
      icon: "💸",
      band: "watch",
      tone: "soft_watch",
      emotion_line: aiLine ?? "金额不大，但小额最容易在月底失踪。",
      utility_line: category ? `先把${category}归好类，后面看频率。` : "先看见它，就已经少漏一笔。",
      detail_reason: `本笔支出 ${fmtYuan(amount)}，属于小额消费，价值在于频率追踪。`,
      internal_score: 58,
      confidence: 0.68,
      source: aiLine ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }
  if (category && includesAny(category, ["交通", "transport", "缴费", "生活"]).length) {
    return {
      version: "feedback-v1",
      domain_key: "expense",
      badge: "必要支出",
      icon: "💸",
      band: "neutral",
      tone: "finance_observation",
      emotion_line: aiLine ?? "这笔更像必要支出，不用和冲动消费混着看。",
      utility_line: `金额 ${fmtYuan(amount)}，重点放在周期和总量。`,
      detail_reason: "当前分类偏生活必要支出，适合与周期预算一起看。",
      internal_score: 64,
      confidence: 0.66,
      source: aiLine ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }
  if (timingSignal?.key === "realtime_accounting") {
    return {
      version: "feedback-v1",
      domain_key: "expense",
      badge: "即时记账",
      icon: "💸",
      band: "ritual",
      tone: "ritual_seen",
      emotion_line: aiLine ?? "这笔刚发生就记下来了，记录很及时。",
      utility_line: merchant ? `${merchant} 这笔已收进今天账本。` : "这种即时记录，最能防止月底对不上。",
      detail_reason: `截图时间与交易时间相隔约 ${timeContext.delta_minutes} 分钟，属于即时记账。`,
      internal_score: 82,
      confidence: 0.78,
      source: aiLine ? "hybrid" : "rule",
      timing_signal: timingSignal,
    };
  }
  return {
    version: "feedback-v1",
    domain_key: "expense",
    badge: "清楚入账",
    icon: "💸",
    band: "neutral",
    tone: "finance_observation",
    emotion_line: aiLine ?? (merchant ? `${merchant} 这笔已经归位，今天账面更清楚。` : "这笔已经归位，今天账面更清楚。"),
    utility_line: `金额 ${fmtYuan(amount)}，后面更适合看当天总量。`,
    detail_reason: "支出识别完整并已入账，本次反馈优先强调记录完整性。",
    internal_score: 66,
    confidence: 0.64,
    source: aiLine ? "hybrid" : "rule",
    timing_signal: timingSignal,
  };
}

function buildIncomeAIFeedback(ai: AIResult, amount: number | null, timeContext: TimeContext): AIFeedback | null {
  if (amount === null || (ai.confidence ?? 0) < 0.7) return null;
  const aiLine = financeCompanionLine(ai);
  const sourceName = normalizeString(ai.source_name ?? ai.merchant_name);
  const category = normalizeString(ai.income_category);
  const isSalary = category === "salary" || includesAny(`${sourceName ?? ""} ${category ?? ""}`, ["工资", "薪资", "薪水"]).length > 0;
  return {
    version: "feedback-v1",
    domain_key: "income",
    badge: isSalary ? "工资到账" : "收入入账",
    icon: "💰",
    band: "positive",
    tone: "cashflow_positive",
    emotion_line: aiLine ?? (isSalary ? "工资到账，今天的现金流多了一块确定性。" : "这笔收入已入账，现金流被补了一口气。"),
    utility_line: sourceName ? `${sourceName} · ${fmtYuan(amount)}` : `金额 ${fmtYuan(amount)}，适合和本月收入一起看。`,
    detail_reason: isSalary ? "识别为工资/薪资类收入，优先作为本月现金流基准。" : "识别为收入记录，优先纳入本月收入累计。",
    internal_score: 76,
    confidence: aiLine ? 0.76 : 0.68,
    source: aiLine ? "hybrid" : "rule",
    timing_signal: timingSignalFor("income", timeContext),
  };
}

async function upsertCompanionMemory(
  supabase: ReturnType<typeof createClient>,
  payload: {
    userId: string | null;
    memoryKey: string;
    memoryType: string;
    content: string;
    evidence: Record<string, unknown>;
    confidence?: number;
    weight?: number;
    expiresAt?: string | null;
    sourceTable?: string | null;
    sourceId?: string | null;
  },
): Promise<void> {
  if (!payload.userId) return;
  const { error } = await supabase.from("user_companion_memories").upsert({
    user_id: payload.userId,
    memory_key: payload.memoryKey,
    memory_type: payload.memoryType,
    content: memoryText(payload.content),
    evidence_jsonb: payload.evidence,
    confidence: payload.confidence ?? 0.65,
    weight: payload.weight ?? 1,
    last_seen_at: new Date().toISOString(),
    expires_at: payload.expiresAt ?? null,
    source_table: payload.sourceTable ?? null,
    source_id: payload.sourceId ?? null,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id,memory_key" });
  if (error) console.warn("Companion memory upsert failed:", error.message);
}

async function rememberCompanionSignals(
  supabase: ReturnType<typeof createClient>,
  params: {
    userId: string | null;
    ai: AIResult;
    recordType: RecordType;
    recordId: string | null;
    recordTable: string | null;
    amount: number | null;
    occurredAt: string | null;
  },
): Promise<void> {
  if (!params.userId || !params.recordId || !params.recordTable) return;
  const expiresSoon = new Date(Date.now() + 21 * 24 * 3600 * 1000).toISOString();
  const expiresLater = new Date(Date.now() + 60 * 24 * 3600 * 1000).toISOString();
  const writes: Promise<void>[] = [];

  if (params.recordType === "expense") {
    const merchant = firstNonEmpty(params.ai.merchant_name);
    const category = firstNonEmpty(params.ai.category);
    if (merchant) {
      writes.push(upsertCompanionMemory(supabase, {
        userId: params.userId,
        memoryKey: `merchant:${merchant}`,
        memoryType: "merchant_pattern",
        content: `用户会在「${merchant}」消费。`,
        evidence: { merchant, category, amount: params.amount, occurred_at: params.occurredAt },
        confidence: 0.75,
        weight: category === "food" ? 1.5 : 1.2,
        expiresAt: expiresLater,
        sourceTable: params.recordTable,
        sourceId: params.recordId,
      }));
    }
    if (category) {
      writes.push(upsertCompanionMemory(supabase, {
        userId: params.userId,
        memoryKey: `expense_category:${category}`,
        memoryType: "spending_pattern",
        content: `用户最近有「${category}」类支出。`,
        evidence: { category, merchant, amount: params.amount, occurred_at: params.occurredAt },
        confidence: 0.65,
        weight: category === "food" ? 1.3 : 1,
        expiresAt: expiresSoon,
        sourceTable: params.recordTable,
        sourceId: params.recordId,
      }));
    }
  } else if (params.recordType === "income") {
    const source = firstNonEmpty(params.ai.source_name, params.ai.merchant_name);
    if (source) {
      writes.push(upsertCompanionMemory(supabase, {
        userId: params.userId,
        memoryKey: `income_source:${source}`,
        memoryType: "income_pattern",
        content: `用户有来自「${source}」的收入记录。`,
        evidence: { source, income_category: params.ai.income_category, amount: params.amount, occurred_at: params.occurredAt },
        confidence: 0.7,
        weight: 1.1,
        expiresAt: expiresLater,
        sourceTable: params.recordTable,
        sourceId: params.recordId,
      }));
    }
  } else if (params.recordType === "sleep") {
    const payload = params.ai.payload_jsonb || {};
    const sleepHours = normalizeNumber(payload.sleep_hours);
    const sleepMinutes = normalizeNumber(payload.sleep_minutes);
    if (sleepHours !== null || sleepMinutes !== null) {
      const label = sleepHours !== null
        ? `${sleepHours} 小时`
        : `${sleepMinutes} 分钟`;
      writes.push(upsertCompanionMemory(supabase, {
        userId: params.userId,
        memoryKey: "sleep:last_pattern",
        memoryType: "sleep_pattern",
        content: `用户最近一次睡眠约 ${label}。`,
        evidence: { sleep_hours: payload.sleep_hours, sleep_minutes: payload.sleep_minutes, score: payload.quality_score, occurred_at: params.occurredAt },
        confidence: 0.75,
        weight: 1.4,
        expiresAt: expiresSoon,
        sourceTable: params.recordTable,
        sourceId: params.recordId,
      }));
    }
  } else if (params.recordType === "sport") {
    const payload = params.ai.payload_jsonb || {};
    const sportType = firstNonEmpty(String(payload.sport_type ?? ""), params.ai.title);
    writes.push(upsertCompanionMemory(supabase, {
      userId: params.userId,
      memoryKey: `sport:${sportType ?? "recent"}`,
      memoryType: "sport_pattern",
      content: sportType ? `用户最近做过「${sportType}」。` : "用户最近有运动记录。",
      evidence: { sport_type: sportType, duration_minutes: payload.duration_minutes, calories: payload.calories, occurred_at: params.occurredAt },
      confidence: 0.7,
      weight: 1.3,
      expiresAt: expiresSoon,
      sourceTable: params.recordTable,
      sourceId: params.recordId,
    }));
  } else if (params.recordType === "food") {
    const payload = params.ai.payload_jsonb || {};
    const mealType = normalizeString(payload.meal_type);
    const mealLabel = mealType === "breakfast" ? "早餐"
      : mealType === "lunch" ? "午餐"
      : mealType === "dinner" ? "晚餐"
      : mealType === "snack" ? "加餐"
      : "饮食";
    const title = firstNonEmpty(params.ai.title, params.ai.summary);
    const calories = normalizeNumber(payload.total_calorie_kcal);
    writes.push(upsertCompanionMemory(supabase, {
      userId: params.userId,
      memoryKey: `food:${payload.meal_type ?? "recent"}`,
      memoryType: "food_pattern",
      content: title
        ? `用户最近记录过${mealLabel}：${title}${calories !== null ? `，约 ${Math.round(calories)} 千卡` : ""}。`
        : `用户最近记录过${mealLabel}。`,
      evidence: { meal_type: payload.meal_type, calories: payload.total_calorie_kcal, title: params.ai.title, occurred_at: params.occurredAt },
      confidence: 0.65,
      weight: 1.1,
      expiresAt: expiresSoon,
      sourceTable: params.recordTable,
      sourceId: params.recordId,
    }));
  } else if (params.recordType === "reading") {
    const payload = params.ai.payload_jsonb || {};
    const book = firstNonEmpty(String(payload.book_name ?? ""), params.ai.title);
    if (book) {
      writes.push(upsertCompanionMemory(supabase, {
        userId: params.userId,
        memoryKey: `reading:${book}`,
        memoryType: "reading_pattern",
        content: `用户最近在读「${book}」。`,
        evidence: { book_name: book, reading_minutes: payload.reading_minutes, progress_percent: payload.progress_percent, occurred_at: params.occurredAt },
        confidence: 0.7,
        weight: 1.1,
        expiresAt: expiresLater,
        sourceTable: params.recordTable,
        sourceId: params.recordId,
      }));
    }
  }

  await Promise.all(writes);
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
    dispatcher?: DispatcherResult | null;
    userId?: string | null;
    timeContext?: unknown;
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
    user_id: payload.userId || null,
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
    extracted_json: { ...payload.ai, time_context: payload.timeContext ?? null },
    companion_message: payload.ai.companion_message ?? null,
    raw_text: payload.dispatcher?.raw_text ?? null,
    routing_candidates: payload.dispatcher?.candidate_domains?.length
      ? payload.dispatcher.candidate_domains
      : detectedDomainKey
        ? [{ key: detectedDomainKey, name: detectedDomainName, confidence: payload.ai.confidence ?? 0 }]
        : [],
    quality_report: {
      error_type: payload.errorType ?? null,
      time_context: payload.timeContext ?? null,
      missing_fields: [],
      dispatcher: payload.dispatcher ? {
        source_app: payload.dispatcher.source_app,
        image_features: payload.dispatcher.image_features,
        route_reason: payload.dispatcher.route_reason,
        route_confidence: payload.dispatcher.route_confidence,
        skip_reason: payload.dispatcher.skip_reason,
      } : null,
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

// 通用 OpenAI-compatible Vision 调用（Moonshot / MiMo 都走这个）
async function callOpenAICompatibleVision(
  imageBytes: Uint8Array,
  mime: string,
  config: ProviderConfig,
  promptText: string = PROMPT,
): Promise<AIResult> {
  const base64 = toBase64(imageBytes);
  const dataUrl = `data:${mime};base64,${base64}`;
  const body: Record<string, unknown> = {
    model: config.model,
    messages: [{
      role: "user",
      content: [
        { type: "image_url", image_url: { url: dataUrl } },
        { type: "text", text: promptText },
      ],
    }],
    temperature: 0.1,
    // 限制输出长度，防止思考模式生成过长 reasoning_content 拖慢响应
    // JSON 实际只需 ~500 token，1024 留足余量
    max_completion_tokens: 1024,
  };
  // response_format 是 OpenAI 扩展，部分兼容服务不支持会 400
  // 仅 Moonshot 已验证支持；其它 provider 依赖 extractJson 兜底从 markdown / 文本中抽 JSON
  if (config.name === "moonshot") {
    body.response_format = { type: "json_object" };
  }
  // 关闭「思考/推理模式」：MiMo v2.5/omni、Qwen3.6 以及部分 OpenAI-compatible 中转模型
  // 默认为混合思考，若不关闭会生成较长 reasoning_content，明显拉高耗时
  // 默认会生成大段 reasoning_content（实测 28s 级），关掉后预期降到 3-8s
  if (config.name === "mimo" || config.name === "qwen" || config.name === "relay") {
    body.enable_thinking = false;
  }
  // 同时附带 Authorization Bearer 与 api-key header：
  // - Moonshot 只认 Authorization Bearer
  // - xiaomimimo.com 文档 curl 示例用 api-key，Python SDK 实测 Authorization 也通
  // 两个 header 并存对双方均无副作用
  const resp = await fetch(config.endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${config.apiKey}`,
      "api-key": config.apiKey,
    },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`${config.name} API error ${resp.status}: ${txt}`);
  }
  const data = await resp.json();
  const text = data?.choices?.[0]?.message?.content ?? "{}";
  return JSON.parse(extractJson(text)) as AIResult;
}

// 多 Provider 优雅降级：按顺序尝试，第一个成功即返回；全部失败则抛聚合错误
// 错误码语义：429 / 5xx / 网络错误 = 服务端临时问题，应快速降级到下一个 provider
async function callVisionWithFallback(
  imageBytes: Uint8Array,
  mime: string,
  providers: ProviderConfig[],
  promptText: string = PROMPT,
): Promise<VisionCallResult> {
  if (providers.length === 0) {
    throw new Error("No vision providers configured");
  }
  const attempts: VisionAttempt[] = [];
  for (const cfg of providers) {
    const startedAt = Date.now();
    try {
      const ai = await callOpenAICompatibleVision(imageBytes, mime, cfg, promptText);
      attempts.push({ provider: cfg.name, model: cfg.model, duration_ms: Date.now() - startedAt });
      if (attempts.length > 1) {
        console.warn(`[vision] succeeded on fallback provider=${cfg.name} after ${attempts.length - 1} failure(s)`);
      }
      return { ai, provider: cfg.name, model: cfg.model, attempts };
    } catch (e) {
      const errMsg = String(e);
      attempts.push({ provider: cfg.name, model: cfg.model, duration_ms: Date.now() - startedAt, error: errMsg });
      console.warn(`[vision-fallback] provider=${cfg.name} failed: ${errMsg}`);
      // 继续尝试下一个 provider
    }
  }
  // 全部失败：抛带聚合信息的错误
  const summary = attempts.map(a => `${a.provider}: ${a.error}`).join(" | ");
  const err = new Error(`All vision providers failed → ${summary}`);
  // 把 attempts 挂到 error 上，外层可以读取写入日志
  (err as Error & { attempts?: VisionAttempt[] }).attempts = attempts;
  throw err;
}

// 兼容保留：现有代码仍可调用 callKimiVision（内部走通用接口）
async function callKimiVision(imageBytes: Uint8Array, mime: string, apiKey: string): Promise<AIResult> {
  return callOpenAICompatibleVision(imageBytes, mime, {
    name: "moonshot",
    model: MOONSHOT_MODEL,
    endpoint: MOONSHOT_ENDPOINT,
    apiKey,
  });
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
  let visionProviders: ProviderConfig[] = [];
  try {
    supabase = createClient(getEnv("SUPABASE_URL"), getEnv("SUPABASE_SERVICE_ROLE_KEY"));

    // 准备所有可用 provider
    const moonshotKey = getEnv("MOONSHOT_API_KEY");
    const moonshotProvider: ProviderConfig = {
      name: "moonshot",
      model: MOONSHOT_MODEL,
      endpoint: MOONSHOT_ENDPOINT,
      apiKey: moonshotKey,
    };

    const mimoKey = getEnvOptional("MIMO_API_KEY");
    const mimoProvider: ProviderConfig | null = mimoKey ? {
      name: "mimo",
      model: getEnvOptional("MIMO_MODEL") ?? MIMO_DEFAULT_MODEL,
      endpoint: getEnvOptional("MIMO_ENDPOINT") ?? MIMO_DEFAULT_ENDPOINT,
      apiKey: mimoKey,
    } : null;

    const qwenKey = getEnvOptional("QWEN_API_KEY");
    const qwenProvider: ProviderConfig | null = qwenKey ? {
      name: "qwen",
      model: getEnvOptional("QWEN_MODEL") ?? QWEN_DEFAULT_MODEL,
      endpoint: getEnvOptional("QWEN_ENDPOINT") ?? QWEN_DEFAULT_ENDPOINT,
      apiKey: qwenKey,
    } : null;

    const relayKey = getEnvOptional("RELAY_API_KEY");
    const relayProvider: ProviderConfig | null = relayKey ? {
      name: "relay",
      model: getEnvOptional("RELAY_MODEL") ?? RELAY_DEFAULT_MODEL,
      endpoint: getEnvOptional("RELAY_ENDPOINT") ?? RELAY_DEFAULT_ENDPOINT,
      apiKey: relayKey,
    } : null;

    // 主备顺序：通过 VISION_PRIMARY env 决定首选 provider，其它 provider 按固定后备顺序拼接
    // 取值: moonshot (默认) | qwen | mimo | relay
    const primary = (getEnvOptional("VISION_PRIMARY") ?? "moonshot").toLowerCase();
    const allProviders: ProviderConfig[] = [moonshotProvider];
    if (qwenProvider) allProviders.push(qwenProvider);
    if (mimoProvider) allProviders.push(mimoProvider);
    if (relayProvider) allProviders.push(relayProvider);
    // 把 primary 对应的 provider 移到首位（如果存在）
    const primaryIdx = allProviders.findIndex((p) => p.name === primary);
    if (primaryIdx > 0) {
      const [picked] = allProviders.splice(primaryIdx, 1);
      allProviders.unshift(picked);
    }
    visionProviders = allProviders;
  } catch (e) {
    return new Response(JSON.stringify({ error: `Secret config error: ${String(e)}` }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const startedAt = Date.now();
    const timings = makeTimings();
    // 1. 接收图片（multipart/form-data，字段名 image）
    const form = await req.formData();
    timings.mark("form_parse");
    // 用户身份：优先 user_id，其次 upload_token 查表
    let userId = normalizeString(form.get("user_id"));
    const uploadToken = normalizeString(form.get("upload_token"));
    if (!userId && uploadToken) {
      const { data: cfg } = await supabase.from("user_configs")
        .select("user_id")
        .eq("upload_token", uploadToken)
        .eq("is_active", true)
        .maybeSingle();
      if (cfg) userId = cfg.user_id;
    }

    let companionSettings: CompanionSettings = DEFAULT_COMPANION_SETTINGS;
    let companionContextPromise: Promise<{ settings: CompanionSettings; memory: Record<string, unknown> | null }> = Promise.resolve({
      settings: DEFAULT_COMPANION_SETTINGS,
      memory: null,
    });

    // 用户级 AI 引擎偏好：覆盖 VISION_PRIMARY env
    // 取值 auto 表示跟随平台默认；其它强制指定 provider 优先
    if (userId) {
      const { data: prefRow } = await supabase.from("user_configs")
        .select("vision_primary, companion_enabled, companion_memory_enabled, companion_persona, companion_memory_strength, companion_expression_style, companion_custom_note")
        .eq("user_id", userId)
        .maybeSingle();
      const userPref = prefRow?.vision_primary;
      companionSettings = {
        enabled: prefRow?.companion_enabled ?? true,
        memoryEnabled: prefRow?.companion_memory_enabled ?? true,
        persona: prefRow?.companion_persona ?? "observer",
        memoryStrength: prefRow?.companion_memory_strength ?? "balanced",
        expressionStyle: prefRow?.companion_expression_style ?? "plain",
        customNote: prefRow?.companion_custom_note ?? null,
      };
      if (userPref && userPref !== "auto") {
        const idx = visionProviders.findIndex((p) => p.name === userPref);
        if (idx > 0) {
          const [picked] = visionProviders.splice(idx, 1);
          visionProviders.unshift(picked);
        }
      }
      companionContextPromise = loadCompanionContext(supabase, userId);
    }

    const stagingRetryId = normalizeString(form.get("staging_record_id"));
    let file = form.get("image") as File | null;
    let retryImageBytes: Uint8Array | null = null;
    let retryImageMime = "image/jpeg";
    let retryImagePath: string | null = null;
    let retryImageHash: string | null = null;
    if (stagingRetryId && !file) {
      const { data: stagingRow } = await supabase.from("staging_records")
        .select("id,image_path,image_hash,retry_count")
        .eq("id", stagingRetryId)
        .maybeSingle();
      if (!stagingRow || !stagingRow.image_path) {
        return new Response(JSON.stringify({ error: "Staging record not found or missing image" }), {
          status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if ((stagingRow.retry_count || 0) >= 3) {
        return new Response(JSON.stringify({ error: "Retry limit exceeded (max 3)" }), {
          status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const { data: imgData, error: imgErr } = await supabase.storage.from(BUCKET_NAME).download(stagingRow.image_path);
      if (imgErr || !imgData) {
        return new Response(JSON.stringify({ error: "Failed to download image: " + (imgErr?.message || 'not found') }), {
          status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      retryImageBytes = new Uint8Array(await imgData.arrayBuffer());
      if (stagingRow.image_path.endsWith(".png")) retryImageMime = "image/png";
      retryImagePath = stagingRow.image_path;
      retryImageHash = stagingRow.image_hash;
    }
    if (!file && !retryImageBytes) {
      return new Response(JSON.stringify({ error: "Missing 'image' field" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    let bytes: Uint8Array;
    let buf: ArrayBuffer;
    let mime: string;
    if (retryImageBytes) {
      bytes = retryImageBytes;
      buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      mime = retryImageMime;
    } else {
      buf = await file!.arrayBuffer();
      bytes = new Uint8Array(buf);
      mime = file!.type || "image/jpeg";
    }
    const isRetry = !!stagingRetryId;
    const rawText = normalizeText(form.get("ocr_text") ?? form.get("text") ?? form.get("raw_text"));
    const sourceApp = normalizeText(form.get("source_app") ?? form.get("app_name"));
    const clientCapturedAt = form.get("client_captured_at") ?? form.get("client_upload_at") ?? form.get("shortcut_time") ?? form.get("captured_at");
    const imageFeatures = getImageFeatures(bytes, mime);

    // 时间锚点：以请求接收时间为基准，附带北京时区换算；陪伴文案 prompt 需要本地时间感
    const now = new Date();
    const requestReceivedAt = now.toISOString();
    // Deno 运行在 UTC 环境，显式换算为 UTC+8 时间
    const chinaNow = new Date(now.getTime() + 8 * 60 * 60 * 1000);
    const today = chinaNow.toISOString().slice(0, 10);
    const nowTime = `${String(chinaNow.getUTCHours()).padStart(2, '0')}:${String(chinaNow.getUTCMinutes()).padStart(2, '0')}:00`;
    // 优先用客户端截图时间（已校验），否则退化到服务端北京时间
    const clientCapturedIso = normalizeAiDate(clientCapturedAt);
    const referenceLocal = clientCapturedIso
      ? new Date(new Date(clientCapturedIso).getTime() + 8 * 60 * 60 * 1000)
      : chinaNow;
    const _weekdayCN = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][referenceLocal.getUTCDay()];
    const clientLocalTime = `${referenceLocal.toISOString().slice(0, 10)} ${String(referenceLocal.getUTCHours()).padStart(2, '0')}:${String(referenceLocal.getUTCMinutes()).padStart(2, '0')}`;
    const companionContext = await companionContextPromise;
    companionSettings = companionContext.settings;
    timings.mark("companion_context");
    const visionPrompt = buildPrompt({
      clientLocalTime,
      weekday: _weekdayCN,
      companionEnabled: companionSettings.enabled,
      memoryEnabled: companionSettings.memoryEnabled,
      memoryStrength: companionSettings.memoryStrength,
      expressionStyle: companionSettings.expressionStyle,
      persona: companionSettings.persona,
      customNote: companionSettings.customNote,
      memory: companionContext.memory,
    });

    // 2. 计算 hash 去重
    const hash = retryImageHash || await sha256(buf);
    const perceptualHash = computePerceptualHash(bytes, mime);
    timings.mark("hash");
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
    timings.mark("perceptual_lookup");
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
      const _spendSum = await summarizeTodaySpend(supabase, userId);
      return new Response(JSON.stringify({
        status: "duplicate", id: txDup.id, record_type: "expense",
        message: "该截图已记账",
        notification: `🔁 该截图已记账过\n${todaySpendLine(_spendSum)}`,
      }), {
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
      const _incSum = await summarizeMonthIncome(supabase, userId);
      return new Response(JSON.stringify({
        status: "duplicate", id: incDup.id, record_type: "income",
        message: "该收入截图已记录",
        notification: `🔁 该收入截图已记录过\n${monthIncomeLine(_incSum)}`,
      }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { data: dataDup } = await supabase
      .from("data_records").select("id,domain_key").eq("source_image_hash", hash).maybeSingle();
    timings.mark("dup_check");
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
      return new Response(JSON.stringify({
        status: "duplicate", id: dataDup.id, record_type: dataDup.domain_key,
        message: "该截图已归档",
        notification: `🔁 该截图已归档过 · ${domainNameFromKey(dataDup.domain_key) ?? dataDup.domain_key}`,
      }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const dispatcher = await runLowCostDispatcher(supabase, { rawText, sourceApp, imageFeatures });
    timings.mark("dispatcher");
    let duplicateKind: string | null = perceptualDupRefId ? "perceptual_hash" : null;
    let duplicateRefTable: string | null = perceptualDupRefId ? "ai_recognition_logs" : null;
    let duplicateRefId: string | null = perceptualDupRefId;

    // 3. 上传到 Storage（重试模式跳过，图片已存在）
    const path = isRetry ? (retryImagePath!) : `${new Date().toISOString().slice(0,10)}/${hash.slice(0,12)}.${mime.includes("png") ? "png" : "jpg"}`;
    let uploadedNewObject = false;
    if (!isRetry) {
      const { error: upErr } = await supabase.storage.from(BUCKET_NAME)
        .upload(path, bytes, { contentType: mime, upsert: false });
      if (upErr && !upErr.message.includes("already exists")) {
        throw new Error(`Upload failed: ${upErr.message}`);
      }
      uploadedNewObject = !upErr;
    }
    timings.mark("storage_upload");

    // 4. 调用 Vision 识别（多 Provider 优雅降级：Moonshot 主 → MiMo 备）
    //    始终调用，不因低成本路由无匹配而跳过
    let ai: AIResult;
    let aiOk = true;
    let aiErrorMessage: string | null = null;
    let aiProvider: ProviderName = "moonshot";
    let aiModel: string = MOONSHOT_MODEL;
    let visionAttempts: VisionAttempt[] = [];
    try {
      const visionResult = await callVisionWithFallback(bytes, mime, visionProviders, visionPrompt);
      ai = visionResult.ai;
      aiProvider = visionResult.provider;
      aiModel = visionResult.model;
      visionAttempts = visionResult.attempts;
    } catch (e) {
      aiOk = false;
      aiErrorMessage = String(e);
      // 从聚合错误中读出 attempts（如果有）
      const attempts = (e as Error & { attempts?: VisionAttempt[] }).attempts;
      if (attempts) visionAttempts = attempts;
      // 标注最终归属：使用最后一次尝试的 provider，便于排查
      const lastAttempt = visionAttempts[visionAttempts.length - 1];
      if (lastAttempt) {
        aiProvider = lastAttempt.provider;
        aiModel = lastAttempt.model;
      }
      ai = { image_type: "other", record_type: "uncertain", domain_key: null, title: null, summary: null, amount: null, merchant_name: null, platform: null, category: null, payment_method: null, income_category: null, source_name: null, occurred_at: null, order_finished_at: null, payload_jsonb: null, confidence: 0 };
      console.error("All vision providers failed:", e);
    }
    timings.mark("vision_total");
    // 慢请求采样：vision 阶段 > 5s 时打印 warn，方便从函数日志直接搜
    const _visionMs = timings.snapshot().vision_total ?? 0;
    if (_visionMs > 5000) {
      console.warn(`[slow] vision_total=${_visionMs}ms provider=${aiProvider} attempts=${visionAttempts.length}`);
    }

    const normalizedAmount = normalizeAmount(ai.amount);
    // 归一化陪伴文案：去前后空白和引号、压缩换行、截断到 60 字符（约 30 个汉字裕量）
    if (typeof ai.companion_message === "string") {
      const trimmed = ai.companion_message.replace(/[\r\n]+/g, " ").trim().replace(/^["'""''「『]+|["'""''」』]+$/g, "");
      ai.companion_message = trimmed ? trimmed.slice(0, 60) : null;
    } else {
      ai.companion_message = null;
    }
    if (!companionSettings.enabled) ai.companion_message = null;
    ai.companion_message = sanitizeCompanionMessageForContent(ai.companion_message, ai);
    let companionMessage: string | null = ai.companion_message;
    let aiFeedback: AIFeedback | null = null;
    const withCompanion = (text: string) => companionMessage ? `${companionMessage}\n${text}` : text;
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
    const accountHint = !builtinKey ? buildAccountHint(ai, recordType) : null;
    const userAccounts = !builtinKey ? await loadUserAccounts(supabase, userId) : [];
    const accountCandidates = !builtinKey ? rankAccountCandidates(userAccounts, accountHint) : [];
    const autoBoundAccount = !builtinKey ? chooseAutoBindAccount(accountCandidates) : null;

    // 重试模式：处理结果后直接返回
    if (isRetry && stagingRetryId) {
      const retryResult = aiOk && (recordType !== "uncertain") && (ai.confidence ?? 0) >= 0.5;
      const retryCount = (await supabase.from("staging_records").select("retry_count").eq("id", stagingRetryId).maybeSingle())?.data?.retry_count ?? 0;
      const retryOccurredDateTime = normalizeAiDateTime(ai.occurred_at) ?? normalizeAiDateTime(ai.order_finished_at);
      const retryOccurredAt = retryOccurredDateTime?.iso ?? null;
      const retryTimeContext = buildTimeContext({
        occurredAt: retryOccurredAt,
        orderFinishedAt: retryOccurredAt,
        clientCapturedAt,
        requestReceivedAt,
      });
      companionMessage = sanitizeCompanionMessageForTime(companionMessage, ai, retryTimeContext);
      companionMessage = sanitizeCompanionMessageForContent(companionMessage, ai);
      ai.companion_message = companionMessage;
      const retryAiWithTimeContext = { ...ai, time_context: retryTimeContext };

      if (retryResult) {
        // 重试成功：按 recordType 归档
        let archivedTo: string | null = null;
        let archivedId: string | null = null;
        const occurredDateTime = normalizeAiDateTime(ai.occurred_at) ?? normalizeAiDateTime(ai.order_finished_at);
        const occurredAt = occurredDateTime?.iso ?? new Date().toISOString();
        const timeContext = buildTimeContext({
          occurredAt,
          orderFinishedAt: occurredAt,
          clientCapturedAt,
          requestReceivedAt,
        });
        companionMessage = sanitizeCompanionMessageForTime(companionMessage, ai, timeContext);
        companionMessage = sanitizeCompanionMessageForContent(companionMessage, ai);
        ai.companion_message = companionMessage;
        let aiWithTimeContext: Record<string, unknown> = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
        const recordDate = occurredDateTime?.date ?? today;
        const recordTime = occurredDateTime?.time ?? nowTime;

        if (recordType === "income") {
          const incomeCat = ["salary","bonus","freelance","investment","reimbursement","other"].includes(ai.income_category ?? "") ? ai.income_category! : "other";
          const { data: incRow } = await supabase.from("income_records").insert({
            amount: normalizedAmount ?? 0.01, category: incomeCat,
            source_name: ai.source_name ?? ai.merchant_name ?? "截图识别收入",
            income_date: recordDate, image_url: path, image_hash: hash, user_id: userId || null, source: "ai_scan",
            account_id: autoBoundAccount?.id ?? null,
            companion_message: companionMessage,
          }).select("id").single();
          if (incRow) {
            if (autoBoundAccount && normalizedAmount !== null) {
              try {
                await createAutoAccountEntry(supabase, {
                  userId,
                  accountId: autoBoundAccount.id,
                  accountType: autoBoundAccount.type,
                  recordType: "income",
                  amount: normalizedAmount,
                  sourceId: incRow.id,
                  occurredAt,
                });
              } catch (entryError) {
                await supabase.from("income_records").delete().eq("id", incRow.id);
                throw entryError;
              }
            }
            archivedTo = "income_records";
            archivedId = incRow.id;
          }
        } else if (builtinKey) {
          const built = buildBuiltinPayload(ai);
          const domain = await getDomainByKey(supabase, builtinKey);
          if (domain && built) {
            const retryFeedback = built.missingFields.length === 0 && (ai.confidence ?? 0) >= 0.75 && companionSettings.enabled
              ? buildBuiltinAIFeedback(builtinKey, built, timeContext, companionMessage)
              : null;
            if (retryFeedback) {
              aiFeedback = retryFeedback;
              companionMessage = retryFeedback.emotion_line;
              ai.companion_message = companionMessage;
              aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
            }
            const { data: drRow } = await supabase.from("data_records").insert({
              domain_id: domain.id, domain_key: builtinKey, domain_version: domain.version ?? "1.0",
              occurred_at: occurredAt, title: built.title, summary: built.summary,
              payload_jsonb: { ...built.payload, time_context: timeContext, companion_message: companionMessage, ai_feedback: aiFeedback }, user_id: userId || null, source: "ai_scan", source_image_path: path, source_image_hash: hash,
            }).select("id").single();
            if (drRow) { archivedTo = "data_records"; archivedId = drRow.id; }
          }
        } else {
          // expense
          const isComplete = normalizedAmount !== null && ai.platform !== null && ai.category !== null && ai.payment_method !== null;
          const { data: txRow } = await supabase.from("transactions").insert({
            type: "expense", amount: normalizedAmount ?? 0.01,
            merchant_name: ai.merchant_name, platform: ai.platform, category: ai.category,
            payment_method: ai.payment_method, status: isComplete ? "done" : "pending",
            image_url: path, image_hash: hash,
            transaction_date: recordDate, transaction_time: recordTime, user_id: userId || null, source: "ai_scan",
            account_id: autoBoundAccount?.id ?? null,
            companion_message: companionMessage,
          }).select("id").single();
          if (txRow) {
            if (autoBoundAccount && normalizedAmount !== null) {
              try {
                await createAutoAccountEntry(supabase, {
                  userId,
                  accountId: autoBoundAccount.id,
                  accountType: autoBoundAccount.type,
                  recordType: "expense",
                  amount: normalizedAmount,
                  sourceId: txRow.id,
                  occurredAt,
                });
              } catch (entryError) {
                await supabase.from("transactions").delete().eq("id", txRow.id);
                throw entryError;
              }
            }
            archivedTo = "transactions";
            archivedId = txRow.id;
          }
        }

        if (archivedTo && archivedId) {
          await supabase.from("staging_records").update({
            status: "archived", resolved_at: now.toISOString(), resolved_action: "archived",
            target_record_id: archivedId, retry_count: retryCount + 1,
            ai_summary: ai.record_type ? `重试成功 → ${domainNameFromKey(ai.record_type) ?? ai.record_type}` : "重试成功",
          }).eq("id", stagingRetryId);

          await writeAiLog(supabase, {
            image_hash: hash, image_url: path, image_type: ai.image_type,
            record_type: recordType, occurred_at: occurredAt, status: "success",
            confidence: ai.confidence ?? 0, duration_ms: Date.now() - startedAt,
            target_table: archivedTo, target_id: archivedId, staging_record_id: stagingRetryId,
            ai_response: aiWithTimeContext, model_provider: aiProvider, model_name: aiModel,
            raw_response: JSON.stringify({ vision_attempts: visionAttempts, timings: timings.snapshot() }),
            prompt_version: "platform-v3-builtins-retry",
          });

          const _retryDomain = domainNameFromKey(recordType) ?? recordType;
          let _retryNotif = `✓ 重试成功 · 已归档到${_retryDomain}`;
          if (recordType === "expense") {
            const _s = await summarizeTodaySpend(supabase, userId);
            _retryNotif = `💸 重试成功 · 已记账${normalizedAmount !== null ? " " + fmtYuan(normalizedAmount) : ""}\n${todaySpendLine(_s)}`;
          } else if (recordType === "income") {
            const _s = await summarizeMonthIncome(supabase, userId);
            _retryNotif = `💰 重试成功 · 已入账${normalizedAmount !== null ? " " + fmtYuan(normalizedAmount) : ""}\n${monthIncomeLine(_s)}`;
          }
          await rememberCompanionSignals(supabase, {
            userId,
            ai,
            recordType,
            recordId: archivedId,
            recordTable: archivedTo,
            amount: normalizedAmount,
            occurredAt,
          });
          return new Response(JSON.stringify({
            status: "done", id: archivedId, record_type: recordType, retry: true,
            message: `✓ 重试成功，已归档到${_retryDomain}`,
            notification: aiFeedback ? feedbackNotification(aiFeedback, _retryNotif) : withCompanion(_retryNotif),
            time_context: timeContext,
            companion_message: companionMessage,
            ai_feedback: aiFeedback,
          }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
        }
      }

      // 重试失败：更新 staging 记录
      await supabase.from("staging_records").update({
        retry_count: retryCount + 1,
        last_error_type: !aiOk ? "AI_PROVIDER_ERROR" : "RETRY_STILL_UNCERTAIN",
        last_error_message: aiErrorMessage || `重试后仍无法确定（record_type=${recordType}, confidence=${ai.confidence ?? 0}）`,
        ai_summary: ai.record_type ? `重试 → ${ai.record_type} (confidence: ${ai.confidence ?? 0})` : "重试失败",
      }).eq("id", stagingRetryId);

      await writeAiLog(supabase, {
        image_hash: hash, image_url: path, image_type: ai.image_type,
        record_type: recordType, status: !aiOk ? "ai_error" : "pending",
        confidence: ai.confidence ?? 0, duration_ms: Date.now() - startedAt,
        staging_record_id: stagingRetryId, ai_response: retryAiWithTimeContext,
        error_message: aiErrorMessage, model_provider: aiProvider, model_name: aiModel,
        raw_response: JSON.stringify({ vision_attempts: visionAttempts, timings: timings.snapshot() }),
        prompt_version: "platform-v3-builtins-retry",
      });

      return new Response(JSON.stringify({
        status: "staging", staging_status: "retry_failed",
        message: "⚠ 重试仍未确定，请手动选择数据域归档",
        notification: withCompanion("⚠️ 重试仍未确定\n请打开 App 在待处理中手动归档"),
        time_context: retryTimeContext,
        companion_message: companionMessage,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const occurredDateTime = normalizeAiDateTime(ai.occurred_at) ?? normalizeAiDateTime(ai.order_finished_at);
    const orderFinishedDateTime = normalizeAiDateTime(ai.order_finished_at) ?? occurredDateTime;
    const occurredAt = occurredDateTime?.iso ?? null;
    const orderFinishedAt = orderFinishedDateTime?.iso ?? occurredAt;
    const timeContext = buildTimeContext({
      occurredAt,
      orderFinishedAt,
      clientCapturedAt,
      requestReceivedAt,
    });
    companionMessage = sanitizeCompanionMessageForTime(companionMessage, ai, timeContext);
    companionMessage = sanitizeCompanionMessageForContent(companionMessage, ai);
    ai.companion_message = companionMessage;
    let aiWithTimeContext: Record<string, unknown> = { ...ai, time_context: timeContext };
    const recordDate = occurredDateTime?.date ?? today;
    const recordTime = occurredDateTime?.time ?? nowTime;

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
        dispatcher,
        userId,
        timeContext,
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
        ai_response: aiWithTimeContext,
        raw_response: JSON.stringify({ dispatcher, vision_attempts: visionAttempts, timings: timings.snapshot() }),
        error_message: aiErrorMessage,
        model_provider: aiProvider,
        model_name: aiModel,
        prompt_version: "platform-v3-builtins",
      });

      const _stgSpend = await summarizeTodaySpend(supabase, userId);
      const _stgAmtPart = normalizedAmount !== null ? `已识别 ${fmtYuan(normalizedAmount)} · ` : "";
      const _stgPrimary = !aiOk
        ? "❌ AI 识别失败，已进入待处理"
        : `⚠️ ${_stgAmtPart}请打开 App 补全`;
      return new Response(JSON.stringify({
        status: "staging",
        staging_status: stagingStatus,
        id: staging?.id ?? null,
        ai_ok: aiOk,
        message: !aiOk ? "⚠ AI 识别失败，已进入待处理" : "⚠ 未确定数据域，已进入待处理",
        notification: withCompanion(`${_stgPrimary}\n${todaySpendLine(_stgSpend)}`),
        time_context: timeContext,
        companion_message: companionMessage,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (builtinKey) {
      const built = buildBuiltinPayload(ai);
      const domain = await getDomainByKey(supabase, builtinKey);
      const fallbackOccurredAt = built ? resolveBuiltinOccurredAt(builtinKey, occurredAt, built.payload) : (occurredAt ?? new Date().toISOString());
      const shouldAutoArchive = Boolean(domain && built && built.missingFields.length === 0 && (ai.confidence ?? 0) >= 0.75);
      if (shouldAutoArchive && built && companionSettings.enabled) {
        aiFeedback = buildBuiltinAIFeedback(builtinKey, built, timeContext, companionMessage);
        if (aiFeedback) {
          companionMessage = aiFeedback.emotion_line;
          ai.companion_message = companionMessage;
          aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
        }
      }
      if (!companionMessage && built) {
        companionMessage = sanitizeCompanionMessageForContent(buildBuiltinCompanionFallback(builtinKey, built), ai);
        ai.companion_message = companionMessage;
        aiWithTimeContext = { ...ai, time_context: timeContext };
      }

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
          dispatcher,
          userId,
          timeContext,
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
          ai_response: aiWithTimeContext,
          raw_response: JSON.stringify({ dispatcher, vision_attempts: visionAttempts, timings: timings.snapshot() }),
          error_message: !domain ? `data_domains.${builtinKey} 不存在` : null,
          model_provider: aiProvider,
          model_name: aiModel,
          prompt_version: "platform-v3-builtins",
        });

        const _bDomainName = domainNameFromKey(builtinKey) ?? builtinKey;
        const _bNotif = domain
          ? `⚠️ 已识别为${_bDomainName}\n请打开 App 确认后归档`
          : `⚠️ 未找到对应数据域\n已进入待处理`;
        return new Response(JSON.stringify({
          status: "staging",
          staging_status: domain ? "pending_review" : "routing_failed",
          id: staging?.id ?? null,
          record_type: builtinKey,
          ai_ok: aiOk,
          message: domain ? "⚠ 已识别为内置数据域，请确认后归档" : "⚠ 未找到对应数据域，已进入待处理",
          notification: withCompanion(_bNotif),
          time_context: timeContext,
          companion_message: companionMessage,
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      const { data: row, error: dataErr } = await supabase.from("data_records").insert({
        domain_id: domain.id,
        domain_key: builtinKey,
        domain_version: domain.version ?? "1.0",
        occurred_at: fallbackOccurredAt,
        title: built.title,
        summary: built.summary,
        payload_jsonb: { ...built.payload, time_context: timeContext, companion_message: companionMessage, ai_feedback: aiFeedback },
        user_id: userId || null,
        source: "ai_scan",
        source_image_path: path,
        source_image_hash: hash,
      }).select().single();
      timings.mark("db_insert");

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
          ai_response: aiWithTimeContext,
          raw_response: JSON.stringify({ dispatcher, vision_attempts: visionAttempts, timings: timings.snapshot() }),
          error_message: dataErr.message,
          model_provider: aiProvider,
          model_name: aiModel,
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
        ai_response: aiWithTimeContext,
        raw_response: JSON.stringify({ dispatcher, vision_attempts: visionAttempts, timings: timings.snapshot() }),
        error_message: aiErrorMessage,
        model_provider: aiProvider,
        model_name: aiModel,
        prompt_version: "platform-v3-builtins",
      });

      await rememberCompanionSignals(supabase, {
        userId,
        ai,
        recordType: builtinKey,
        recordId: row.id,
        recordTable: "data_records",
        amount: null,
        occurredAt: fallbackOccurredAt,
      });

      const _domainEmoji = builtinKey === "sport" ? "🏃" : builtinKey === "sleep" ? "🌙" : builtinKey === "reading" ? "📚" : builtinKey === "food" ? "🍱" : "✓";
      const _domainDoneNotif = `${_domainEmoji} 已归档到${domainNameFromKey(builtinKey) ?? builtinKey}`;
      return new Response(JSON.stringify({
        status: "done",
        id: row.id,
        record_type: builtinKey,
        ai_ok: aiOk,
        message: `✓ ${domainNameFromKey(builtinKey) ?? "记录"}已归档`,
        notification: aiFeedback ? feedbackNotification(aiFeedback, _domainDoneNotif) : withCompanion(_domainDoneNotif),
        time_context: timeContext,
        companion_message: companionMessage,
        ai_feedback: aiFeedback,
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
              ai_response: aiWithTimeContext,
              error_message: aiErrorMessage,
              model_provider: aiProvider,
              model_name: aiModel,
              raw_response: JSON.stringify({ vision_attempts: visionAttempts, timings: timings.snapshot() }),
            });
            if (uploadedNewObject) {
              const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
              if (removeErr) console.error("Cleanup duplicate income image failed:", removeErr);
            }
            const _iSum2 = await summarizeMonthIncome(supabase, userId);
            return new Response(JSON.stringify({
              status: "duplicate",
              id: refIncome.id,
              record_type: "income",
              ai_ok: aiOk,
              message: "该收入截图疑似已记录",
              notification: withCompanion(`🔁 该收入疑似已记录过\n${monthIncomeLine(_iSum2)}`),
              time_context: timeContext,
              companion_message: companionMessage,
            }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
          }
        }
      }

      if (companionSettings.enabled) {
        aiFeedback = buildIncomeAIFeedback(ai, normalizedAmount, timeContext);
        if (aiFeedback) {
          companionMessage = aiFeedback.emotion_line;
          ai.companion_message = companionMessage;
          aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
        }
      }

      const { data: row, error: incErr } = await supabase.from("income_records").insert({
        amount: normalizedAmount,
        category: incomeCategory,
        source_name: sourceName,
        income_date: recordDate,
        image_url: path,
        image_hash: hash,
        user_id: userId || null,
        source: "ai_scan",
        account_id: autoBoundAccount?.id ?? null,
        note: ai.platform ? `来自${ai.platform}截图识别` : "截图识别收入",
        companion_message: companionMessage,
      }).select().single();
      timings.mark("db_insert");

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
          ai_response: aiWithTimeContext,
          error_message: incErr.message,
          model_provider: aiProvider,
          model_name: aiModel,
          raw_response: JSON.stringify({ vision_attempts: visionAttempts, timings: timings.snapshot() }),
        });
        if (uploadedNewObject) {
          const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
          if (removeErr) console.error("Cleanup uploaded income image failed:", removeErr);
        }
        throw new Error(`Income insert failed: ${incErr.message}`);
      }

      if (row && autoBoundAccount) {
        try {
          await createAutoAccountEntry(supabase, {
            userId,
            accountId: autoBoundAccount.id,
            accountType: autoBoundAccount.type,
            recordType: "income",
            amount: normalizedAmount,
            sourceId: row.id,
            occurredAt,
          });
        } catch (entryError) {
          await supabase.from("income_records").delete().eq("id", row.id);
          throw entryError;
        }
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
        ai_response: aiWithTimeContext,
        error_message: aiErrorMessage,
        model_provider: aiProvider,
        model_name: aiModel,
        raw_response: JSON.stringify({ vision_attempts: visionAttempts, timings: timings.snapshot() }),
      });

      await rememberCompanionSignals(supabase, {
        userId,
        ai,
        recordType: "income",
        recordId: row.id,
        recordTable: "income_records",
        amount: normalizedAmount,
        occurredAt,
      });

      const _iDoneSum = await summarizeMonthIncome(supabase, userId);
      const _iSourceLabel = sourceName && sourceName !== "截图识别收入" ? ` · ${sourceName}` : "";
      const _incomeNotif = `💰 +${fmtYuan(normalizedAmount)}${_iSourceLabel}\n${monthIncomeLine(_iDoneSum)}`;
      return new Response(JSON.stringify({
        status: "done",
        id: row.id,
        record_type: "income",
        ai_ok: aiOk,
        message: "✓ 收入已记录",
        notification: aiFeedback ? feedbackNotification(aiFeedback, _incomeNotif, { preserveFallbackAll: true }) : withCompanion(_incomeNotif),
        time_context: timeContext,
        companion_message: companionMessage,
        ai_feedback: aiFeedback,
        data: row,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // 4.5 感知哈希去重：同一笔支出（同金额+同商家）的相似截图 → 拦截
    if (duplicateKind === "perceptual_hash" && duplicateRefId && normalizedAmount !== null) {
      const { data: refLog } = await supabase
        .from("ai_recognition_logs")
        .select("id,target_table,target_id,record_type,ai_response")
        .eq("id", duplicateRefId)
        .maybeSingle();

      if (refLog && refLog.record_type === "expense") {
        let refAmount: number | null = null;
        let refMerchant: string | null = null;
        try {
          const refAi = typeof refLog.ai_response === "string" ? JSON.parse(refLog.ai_response) : (refLog.ai_response || {});
          refAmount = normalizeAmount(refAi.amount);
          refMerchant = (refAi.merchant_name || "").trim();
        } catch {}

        const currentMerchant = (ai.merchant_name || "").trim();
        const amountMatch = refAmount !== null && normalizedAmount !== null && Math.abs(refAmount - normalizedAmount) <= 0.01;
        const merchantMatch = currentMerchant && refMerchant
          ? currentMerchant === refMerchant
          : !currentMerchant && !refMerchant;

        if (amountMatch && merchantMatch && refLog.target_id) {
          await writeAiLog(supabase, {
            image_hash: hash, perceptual_hash: perceptualHash, perceptual_distance: perceptualDistance,
            image_url: path, image_type: ai.image_type, record_type: "expense",
            occurred_at: occurredAt, order_finished_at: orderFinishedAt,
            duplicate_kind: duplicateKind, duplicate_ref_table: duplicateRefTable, duplicate_ref_id: duplicateRefId,
            target_table: "transactions", target_id: refLog.target_id, status: "duplicate",
            confidence: ai.confidence ?? 0, duration_ms: Date.now() - startedAt,
            ai_response: aiWithTimeContext, model_provider: aiProvider, model_name: aiModel,
            raw_response: JSON.stringify({ vision_attempts: visionAttempts, timings: timings.snapshot() }),
          });
          if (uploadedNewObject) {
            const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
            if (removeErr) console.error("Cleanup duplicate expense image failed:", removeErr);
          }
          const _eDupSum = await summarizeTodaySpend(supabase, userId);
          return new Response(JSON.stringify({
            status: "duplicate", id: refLog.target_id, record_type: "expense",
            ai_ok: aiOk, message: "该截图疑似已记录（相似图片）",
            notification: withCompanion(`🔁 该支出疑似已记录过（相似图片）\n${todaySpendLine(_eDupSum)}`),
            time_context: timeContext,
            companion_message: companionMessage,
          }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
        }
      }
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
    if (status === "done" && companionSettings.enabled) {
      aiFeedback = buildExpenseAIFeedback(ai, normalizedAmount, timeContext, possibleDuplicate);
      if (aiFeedback) {
        companionMessage = aiFeedback.emotion_line;
        ai.companion_message = companionMessage;
        aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
      }
    }

    // 6. 写入数据库
    const { data: row, error: insErr } = await supabase.from("transactions").insert({
      type: "expense",
      amount: normalizedAmount ?? 0.01,
      merchant_name: ai.merchant_name,
      platform: ai.platform,
      category: ai.category,
      payment_method: ai.payment_method,
      status: normalizedAmount === null ? "pending" : status,
      image_url: path,
      image_hash: hash,
      user_id: userId || null,
      is_large_transport: isLargeTransport,
      transaction_date: recordDate,
      transaction_time: recordTime,
      source: "ai_scan",
      account_id: autoBoundAccount?.id ?? null,
      companion_message: companionMessage,
    }).select().single();
    timings.mark("db_insert");

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
        ai_response: aiWithTimeContext,
        error_message: insErr.message,
        model_provider: aiProvider,
        model_name: aiModel,
        raw_response: JSON.stringify({ vision_attempts: visionAttempts, timings: timings.snapshot() }),
      });
      if (uploadedNewObject) {
        const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
        if (removeErr) console.error("Cleanup uploaded image failed:", removeErr);
      }
      throw new Error(`DB insert failed: ${insErr.message}`);
    }

    if (row && autoBoundAccount && normalizedAmount !== null) {
      try {
        await createAutoAccountEntry(supabase, {
          userId,
          accountId: autoBoundAccount.id,
          accountType: autoBoundAccount.type,
          recordType: "expense",
          amount: normalizedAmount,
          sourceId: row.id,
          occurredAt,
        });
      } catch (entryError) {
        await supabase.from("transactions").delete().eq("id", row.id);
        throw entryError;
      }
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
      ai_response: aiWithTimeContext,
      error_message: aiErrorMessage,
      model_provider: aiProvider,
      model_name: aiModel,
      raw_response: JSON.stringify({ vision_attempts: visionAttempts, timings: timings.snapshot() }),
    });

    await rememberCompanionSignals(supabase, {
      userId,
      ai,
      recordType: "expense",
      recordId: row.id,
      recordTable: "transactions",
      amount: normalizedAmount,
      occurredAt,
    });

    const _eDoneSum = await summarizeTodaySpend(supabase, userId);
    const _merchantPart = ai.merchant_name ? ` · ${ai.merchant_name}` : "";
    const _categoryPart = ai.category ? ` · ${ai.category}` : "";
    let _ePrimary: string;
    if (row.status === "done") {
      _ePrimary = `💸 -${fmtYuan(normalizedAmount)}${_merchantPart}${_categoryPart}`;
    } else {
      _ePrimary = `⚠️ -${fmtYuan(normalizedAmount)}${_merchantPart} · 请打开 App 补全`;
    }
    if (possibleDuplicate) {
      _ePrimary = `⚠️ ${_ePrimary.replace(/^[💸⚠️]\s*/, "")} · 疑似 3 分钟内重复`;
    }
    const _expenseNotif = `${_ePrimary}\n${todaySpendLine(_eDoneSum)}`;
    return new Response(JSON.stringify({
      status: row.status,
      id: row.id,
      ai_ok: aiOk,
      possible_duplicate: possibleDuplicate,
      dup_ref_id: dupRefId,
      message: possibleDuplicate
        ? `✓ 已记账（⚠ 3 分钟内有相同消费，请确认是否重复，参考 id: ${dupRefId}）`
        : row.status === "done" ? "✓ 已记账" : "⚠ 信息不全，请打开 PWA 补全",
      notification: aiFeedback ? feedbackNotification(aiFeedback, _expenseNotif, { preserveFallbackAll: true }) : withCompanion(_expenseNotif),
      time_context: timeContext,
      companion_message: companionMessage,
      ai_feedback: aiFeedback,
      data: row,
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});



