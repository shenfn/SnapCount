// 随手账 · Edge Function: ingest-receipt
// 部署: supabase functions deploy ingest-receipt --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2.45.0";
import jpeg from "npm:jpeg-js@0.4.4";
import { decode as decodePng } from "npm:fast-png@6.2.0";
import { PROMPT, buildPrompt, buildFeedbackPrompt, buildVoicePrompt } from "./prompts.ts";
import { submitExpressionFeedback } from "./expression-feedback.ts";
import {
  loadDomainProfiles,
  selectSignals,
  validateModelTone,
  hasUnsupportedFinanceCompanionClaim,
  hasModelOwnedStatisticalClaim,
  parsePaceMinutes,
} from "./signals.ts";
import type { CurrentFacts, DomainProfilesMap, DomainSignal } from "./signals.ts";
import { buildTimeContext, normalizeAiDate, normalizeAiDateTime } from "./time.ts";
import { scheduleExpressionShadowCapture } from "./expression-shadow.ts";
import type { TimeContext } from "./time.ts";
import {
  findLikelyFinancialDuplicate,
  type FinancialPerceptualCandidate,
  type RankedPerceptualCandidate,
} from "./duplicate-review.ts";

// 阿里云百炼 Qwen Vision（OpenAI 兼容协议）
// 默认使用 3.6 Flash 控制上传耗时，用户可显式切换到 3.7 Plus。
const QWEN_DEFAULT_ENDPOINT = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";
const QWEN_DEFAULT_MODEL    = "qwen3.6-flash";
const QWEN_PHOTO_DEFAULT_MODEL = "qwen3.6-flash";
const QWEN_ALLOWED_MODELS = new Set(["qwen3.6-flash", "qwen3.7-plus"]);
const BUCKET_NAME       = "receipt-images";

type ProviderName = "qwen";

function normalizeQwenModel(value: string | null | undefined, fallback: string): string {
  const normalized = value?.trim();
  return normalized && QWEN_ALLOWED_MODELS.has(normalized) ? normalized : fallback;
}

interface ProviderConfig {
  name: ProviderName;
  model: string;
  endpoint: string;
  apiKey: string;
  enableThinking?: boolean;
  photoModel?: string;
  photoEnableThinking?: boolean;
  requestTimeoutMs?: number;
}

interface VisionAttempt {
  provider: ProviderName;
  model: string;
  duration_ms: number;
  error?: string;
  raw_text_preview?: string;
}

interface VisionCallResult {
  ai: AIResult;
  provider: ProviderName;
  model: string;
  attempts: VisionAttempt[];
  rawText: string;
  extractedJson: string;
  responseId?: string | null;
  finishReason?: string | null;
  reasoningText?: string | null;
}

interface VisionProviderResult {
  ai: AIResult;
  rawText: string;
  extractedJson: string;
  responseId?: string | null;
  finishReason?: string | null;
  reasoningText?: string | null;
}

interface TraceResponseMeta {
  traceId: string;
  aiLogId?: string | null;
  captureKind?: string | null;
  sourceApp?: string | null;
  visionMode?: "screenshot" | "photo" | null;
  photoQualityMode?: boolean | null;
  modelProvider?: ProviderName | null;
  modelName?: string | null;
}

// 歺加载：延迟到请求时获取 Secret，避免模块初始化就崩溃
function getEnv(key: string): string {
  const v = Deno.env.get(key);
  if (!v) throw new Error(`Missing required secret: ${key}`);
  return v;
}

// 可选 secret：缺失时返回 null，由调用方使用 Qwen 默认配置。
function getEnvOptional(key: string): string | null {
  const v = Deno.env.get(key);
  return v && v.length > 0 ? v : null;
}

function getEnvBoolean(key: string, defaultValue: boolean): boolean {
  const v = getEnvOptional(key);
  if (v === null) return defaultValue;
  return !["0", "false", "no", "off"].includes(v.trim().toLowerCase());
}

function getEnvInteger(key: string, defaultValue: number, min: number, max: number): number {
  const raw = getEnvOptional(key);
  if (raw === null) return defaultValue;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? Math.max(min, Math.min(max, parsed)) : defaultValue;
}

function clipForDebug(value: unknown, max = 6000): string | null {
  if (value === null || value === undefined) return null;
  const text = typeof value === "string" ? value : JSON.stringify(value);
  return text.length > max ? `${text.slice(0, max)}...[truncated ${text.length - max} chars]` : text;
}

// ── 隐私脱敏工具 ──────────────────────────────────────────────────
// 对文本中的身份证号、手机号、银行卡号、邮箱做正则脱敏
function sanitizeText(text: string): string {
  if (!text || typeof text !== "string") return text;
  let result = text;
  // 身份证号（18位，最后一位可能是X）
  result = result.replace(/\b\d{17}[\dXx]\b/g, (m) =>
    m.slice(0, 3) + "***********" + m.slice(-4));
  // 手机号（1开头，11位）
  result = result.replace(/\b1[3-9]\d{9}\b/g, (m) =>
    m.slice(0, 3) + "****" + m.slice(-4));
  // 银行卡号（16-19位连续数字，非手机号/身份证场景）
  result = result.replace(/\b\d{16,19}\b/g, (m) =>
    "****".repeat(3) + m.slice(-4));
  // 邮箱
  result = result.replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, (m) => {
    const atIdx = m.indexOf("@");
    if (atIdx <= 1) return m;
    return m[0] + "***" + m.slice(atIdx);
  });
  return result;
}

// 递归脱敏：遍历对象/数组的所有字符串值
function sanitizeSensitiveData(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (typeof value === "string") return sanitizeText(value);
  if (typeof value === "number" || typeof value === "boolean") return value;
  if (Array.isArray(value)) return value.map(sanitizeSensitiveData);
  if (typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      result[k] = sanitizeSensitiveData(v);
    }
    return result;
  }
  return value;
}

// 隐私配置接口
interface PrivacyConfig {
  aiLogsEnabled: boolean;
  promptOptimizationEnabled: boolean;
  expressionImprovementEnabled: boolean;
  keepSourceImages: boolean;
  imageRetentionDays: number;
}

interface DomainLookupRow {
  id: string;
  key: string;
  version: string | null;
}

interface DomainRouteRow {
  key: string;
  name: string;
  routing_json: Record<string, unknown> | null;
}

interface RetentionConfigRow {
  is_active: boolean | null;
  keep_source_images: boolean | null;
  image_retention_days: number | null;
  updated_at: string | null;
}

interface UploadTokenConfigRow {
  user_id: string;
}

interface UserPreferenceRow {
  is_active: boolean | null;
  vision_primary: string | null;
  screenshot_vision_primary: string | null;
  photo_vision_primary: string | null;
  qwen_screenshot_model: string | null;
  qwen_photo_model: string | null;
  qwen_screenshot_enable_thinking: boolean | null;
  qwen_photo_enable_thinking: boolean | null;
  companion_enabled: boolean | null;
  companion_memory_enabled: boolean | null;
  companion_persona: string | null;
  companion_memory_strength: string | null;
  companion_expression_style: string | null;
  companion_custom_note: string | null;
  ai_logs_enabled: boolean | null;
  prompt_optimization_enabled: boolean | null;
  expression_improvement_enabled: boolean | null;
  keep_source_images: boolean | null;
  image_retention_days: number | null;
}

interface StagingRetryRow {
  id: string;
  image_path: string | null;
  image_hash: string | null;
  retry_count: number | null;
}

interface IdRow {
  id: string;
}

interface DataDuplicateRow extends IdRow {
  domain_key: string | null;
}

interface StagingDuplicateRow extends IdRow {
  record_type: string | null;
  status: string | null;
}

interface TransactionPerceptualRow extends IdRow {
  perceptual_hash: string | null;
  amount: string | number | null;
  merchant_name: string | null;
  platform: string | null;
  payment_method: string | null;
  transaction_date: string | null;
  transaction_time: string | null;
  created_at: string | null;
}

interface IncomePerceptualRow extends IdRow {
  perceptual_hash: string | null;
  amount: string | number | null;
  source_name: string | null;
  income_date: string | null;
  created_at: string | null;
}

interface StagingPerceptualRow extends IdRow {
  perceptual_hash: string | null;
  record_type: string | null;
  occurred_at: string | null;
  order_finished_at: string | null;
  created_at: string | null;
  extracted_json: unknown;
}

interface PerceptualLogRow extends IdRow {
  perceptual_hash: string | null;
  target_table: string | null;
  target_id: string | null;
  record_type: string | null;
  occurred_at: string | null;
  order_finished_at: string | null;
  created_at: string | null;
  ai_response: unknown;
}

interface FinancialPerceptualLookupResult {
  candidates: FinancialPerceptualCandidate[];
  financeColumnsAvailable: boolean;
}

interface TransactionCandidateRow extends IdRow {
  transaction_time: string | null;
}

interface InsertedRecordRow extends IdRow {
  status?: string;
  [key: string]: unknown;
}

const DEFAULT_PRIVACY_CONFIG: PrivacyConfig = {
  aiLogsEnabled: false,
  promptOptimizationEnabled: false,
  expressionImprovementEnabled: false,
  keepSourceImages: true,
  imageRetentionDays: -1,
};

async function sha256Short(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ShortcutResponseMode = "json" | "text";

function normalizeResponseMode(value: FormDataEntryValue | null): ShortcutResponseMode {
  if (typeof value !== "string") return "json";
  return value.trim().toLowerCase() === "text" ? "text" : "json";
}

function buildShortcutText(payload: Record<string, unknown>): string {
  const notification = normalizeString(payload.notification);
  if (notification) return notification;
  const message = normalizeString(payload.message);
  if (message) return message;
  const error = normalizeString(payload.error);
  if (error) return error;
  return "截图已处理，打开 App 查看";
}

function respondShortcut(
  payload: Record<string, unknown>,
  options: {
    mode: ShortcutResponseMode;
    status?: number;
  },
): Response {
  const status = options.status ?? 200;
  const notificationText = buildShortcutText(payload);
  const enrichedPayload = {
    ...payload,
    notification_text: notificationText,
  };
  if (options.mode === "text") {
    return new Response(notificationText, {
      status,
      headers: { ...corsHeaders, "Content-Type": "text/plain; charset=utf-8" },
    });
  }
  return new Response(JSON.stringify(enrichedPayload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function withTraceMeta(payload: Record<string, unknown>, trace: TraceResponseMeta): Record<string, unknown> {
  return {
    ...payload,
    trace_id: trace.traceId,
    ai_log_id: trace.aiLogId ?? null,
    capture_kind: trace.captureKind ?? null,
    source_app: trace.sourceApp ?? null,
    vision_mode: trace.visionMode ?? null,
    photo_quality_mode: trace.photoQualityMode ?? null,
    model_provider: trace.modelProvider ?? null,
    model_name: trace.modelName ?? null,
  };
}

// ---- Timings: 链路分段耗时埋点 ----
// 每个 mark(label) 记录"自上次 mark 以来"的耗时（毫秒），最终通过 snapshot() 输出 dict
// 最终落盘到 ai_recognition_logs.raw_response.timings，便于在 Dashboard 排查慢请求
interface Timings {
  mark(label: string): void;
  record(label: string, durationMs: number): void;
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
    record(label: string, durationMs: number) {
      data[label] = (data[label] ?? 0) + Math.max(0, Math.round(durationMs));
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

function decodeImage(bytes: Uint8Array, mime: string): { data: Uint8Array; width: number; height: number } | null {
  try {
    if (mime.includes("png")) {
      const img = decodePng(bytes);
      return { data: Uint8Array.from(img.data), width: img.width, height: img.height };
    }
    const img = jpeg.decode(bytes, { useTArray: true });
    return { data: img.data, width: img.width, height: img.height };
  } catch (e) {
    console.warn("Image decode for perceptual hash failed:", e);
    return null;
  }
}

function computePerceptualHashFromDecoded(
  img: { data: Uint8Array; width: number; height: number } | null,
): string | null {
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

function imageFeaturesFromDecoded(
  img: { data: Uint8Array; width: number; height: number } | null,
  mime: string,
): ImageFeatures {
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

function analyzeImage(bytes: Uint8Array, mime: string): {
  features: ImageFeatures;
  perceptualHash: string | null;
} {
  const decoded = decodeImage(bytes, mime);
  return {
    features: imageFeaturesFromDecoded(decoded, mime),
    perceptualHash: computePerceptualHashFromDecoded(decoded),
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

interface TestMeta {
  is_test: true;
  source: "local_validation";
  test_run_id: string;
  test_case_domain: string | null;
  test_case_date: string | null;
  test_case_file: string | null;
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

function normalizeShortString(value: unknown, max = 160): string | null {
  const text = normalizeString(value);
  return text ? text.slice(0, max) : null;
}

function buildTestMeta(form: FormData): TestMeta | null {
  const runId = normalizeShortString(form.get("test_run_id"));
  if (!runId) return null;
  return {
    is_test: true,
    source: "local_validation",
    test_run_id: runId,
    test_case_domain: normalizeShortString(form.get("test_case_domain"), 80),
    test_case_date: normalizeShortString(form.get("test_case_date"), 32),
    test_case_file: normalizeShortString(form.get("test_case_file"), 240),
  };
}

function withTestMeta<T extends Record<string, unknown>>(payload: T, testMeta: TestMeta | null): T & { test_meta?: TestMeta } {
  return testMeta ? { ...payload, test_meta: testMeta } : payload;
}

function normalizeIsoDateTime(value: unknown): string | null {
  const text = normalizeString(value);
  if (!text) return null;
  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function diffMs(startIso: string | null, endIso: string | null): number | null {
  if (!startIso || !endIso) return null;
  const start = new Date(startIso).getTime();
  const end = new Date(endIso).getTime();
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) return null;
  return Math.round((end - start) * 100) / 100;
}

interface ClientTimingDebug {
  server_received_at: string | null;
  shortcut_started_at: string | null;
  image_prepared_at: string | null;
  request_started_at: string | null;
  request_sent_at: string | null;
  response_received_at: string | null;
  notification_shown_at: string | null;
  resize_ms: number | null;
  preprocess_ms: number | null;
  request_ms: number | null;
  response_parse_ms: number | null;
  notification_delay_ms: number | null;
  total_ms: number | null;
  edge_queue_ms: number | null;
}

function collectClientTiming(form: FormData, requestReceivedAtIso: string): ClientTimingDebug | null {
  const shortcutStartedAt = normalizeIsoDateTime(
    form.get("client_shortcut_started_at") ?? form.get("shortcut_started_at") ?? form.get("client_started_at"),
  );
  const imagePreparedAt = normalizeIsoDateTime(
    form.get("client_image_prepared_at") ?? form.get("image_prepared_at") ?? form.get("client_upload_ready_at"),
  );
  const requestStartedAt = normalizeIsoDateTime(
    form.get("client_request_started_at") ?? form.get("request_started_at"),
  );
  const requestSentAt = normalizeIsoDateTime(
    form.get("client_request_sent_at") ?? form.get("request_sent_at"),
  );
  const responseReceivedAt = normalizeIsoDateTime(
    form.get("client_response_received_at") ?? form.get("response_received_at"),
  );
  const notificationShownAt = normalizeIsoDateTime(
    form.get("client_notification_shown_at") ?? form.get("notification_shown_at"),
  );

  const resizeMs = normalizeNumber(form.get("client_resize_ms") ?? form.get("shortcut_resize_ms") ?? form.get("resize_ms"));
  const preprocessMs = normalizeNumber(
    form.get("client_preprocess_ms") ?? form.get("shortcut_preprocess_ms") ?? form.get("preprocess_ms"),
  );
  const requestMs = normalizeNumber(form.get("client_request_ms") ?? form.get("shortcut_request_ms") ?? form.get("request_ms"));
  const responseParseMs = normalizeNumber(
    form.get("client_response_parse_ms") ?? form.get("shortcut_response_parse_ms") ?? form.get("response_parse_ms"),
  );
  const notificationDelayMs = normalizeNumber(
    form.get("client_notification_delay_ms") ?? form.get("shortcut_notification_delay_ms") ?? form.get("notification_delay_ms"),
  );
  const totalMs = normalizeNumber(form.get("client_total_ms") ?? form.get("shortcut_total_ms") ?? form.get("total_ms"));

  const derivedPreprocessMs = preprocessMs
    ?? diffMs(shortcutStartedAt, imagePreparedAt)
    ?? diffMs(shortcutStartedAt, requestStartedAt);
  const derivedRequestMs = requestMs
    ?? diffMs(requestStartedAt, responseReceivedAt)
    ?? diffMs(requestSentAt, responseReceivedAt);
  const derivedNotificationDelayMs = notificationDelayMs
    ?? diffMs(responseReceivedAt, notificationShownAt);
  const derivedTotalMs = totalMs
    ?? diffMs(shortcutStartedAt, notificationShownAt)
    ?? diffMs(shortcutStartedAt, responseReceivedAt);
  const edgeQueueMs = diffMs(requestStartedAt ?? requestSentAt, requestReceivedAtIso);

  const hasAnyValue = [
    shortcutStartedAt,
    imagePreparedAt,
    requestStartedAt,
    requestSentAt,
    responseReceivedAt,
    notificationShownAt,
    resizeMs,
    derivedPreprocessMs,
    derivedRequestMs,
    responseParseMs,
    derivedNotificationDelayMs,
    derivedTotalMs,
    edgeQueueMs,
  ].some((value) => value !== null && value !== undefined);

  if (!hasAnyValue) return null;

  return {
    server_received_at: requestReceivedAtIso,
    shortcut_started_at: shortcutStartedAt,
    image_prepared_at: imagePreparedAt,
    request_started_at: requestStartedAt,
    request_sent_at: requestSentAt,
    response_received_at: responseReceivedAt,
    notification_shown_at: notificationShownAt,
    resize_ms: resizeMs,
    preprocess_ms: derivedPreprocessMs,
    request_ms: derivedRequestMs,
    response_parse_ms: responseParseMs,
    notification_delay_ms: derivedNotificationDelayMs,
    total_ms: derivedTotalMs,
    edge_queue_ms: edgeQueueMs,
  };
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
  userId?: string | null,
): Promise<{ id: string; key: string; version?: string | null } | null> {
  // 1. 优先查系统共享域（is_system=true AND user_id IS NULL）
  const { data: rawSystemDomain, error: sysErr } = await supabase
    .from("data_domains")
    .select("id,key,version")
    .eq("key", key)
    .eq("status", "active")
    .eq("is_system", true)
    .is("user_id", null)
    .maybeSingle();
  if (sysErr) console.error("Domain lookup (system) failed:", sysErr);
  const systemDomain = rawSystemDomain as DomainLookupRow | null;
  if (systemDomain) return systemDomain;

  // 2. 系统域没有，查当前用户的私有域
  if (userId) {
    const { data: rawUserDomain, error: userErr } = await supabase
      .from("data_domains")
      .select("id,key,version")
      .eq("key", key)
      .eq("status", "active")
      .eq("user_id", userId)
      .maybeSingle();
    if (userErr) console.error("Domain lookup (user) failed:", userErr);
    const userDomain = rawUserDomain as DomainLookupRow | null;
    if (userDomain) return userDomain;
  }

  return null;
}

async function runLowCostDispatcher(
  supabase: ReturnType<typeof createClient>,
  params: {
    rawText: string | null;
    sourceApp: string | null;
    imageFeatures: ImageFeatures;
    userId?: string | null;
  },
): Promise<DispatcherResult> {
  const text = [params.rawText, params.sourceApp].filter(Boolean).join(" ");

  // 查系统共享域 + 当前用户私有域
  const { data: systemDomains, error: sysErr } = await supabase
    .from("data_domains")
    .select("key,name,routing_json,status")
    .eq("status", "active")
    .eq("is_system", true)
    .is("user_id", null);

  const typedSystemDomains = (systemDomains ?? []) as DomainRouteRow[];
  let userDomains: DomainRouteRow[] = [];
  if (params.userId) {
    const { data: uDomains, error: uErr } = await supabase
      .from("data_domains")
      .select("key,name,routing_json,status")
      .eq("status", "active")
      .eq("user_id", params.userId);
    if (uErr) console.error("Dispatcher user domain load failed:", uErr);
    userDomains = (uDomains ?? []) as DomainRouteRow[];
  }

  if (sysErr) console.error("Dispatcher system domain load failed:", sysErr);
  const domains = [...typedSystemDomains, ...userDomains];

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

function looksLikeScreenshotCaptureKind(value: string | null): boolean {
  const text = normalizeComparableText(value);
  return Boolean(text) && (
    text.includes("screenshot") ||
    text.includes("screen") ||
    text.includes("截图") ||
    text.includes("截屏")
  );
}

function looksLikePhotoCaptureKind(value: string | null): boolean {
  const text = normalizeComparableText(value);
  return Boolean(text) && (
    text.includes("photo") ||
    text.includes("camera") ||
    text.includes("拍照") ||
    text.includes("相机") ||
    text.includes("food")
  );
}

function looksLikeCameraCaptureKind(value: string | null): boolean {
  const text = normalizeComparableText(value);
  return Boolean(text) && (
    text.includes("camera") ||
    text.includes("拍照") ||
    text.includes("相机")
  );
}

function shouldUsePhotoQualityVision(params: {
  captureKind: string | null;
  rawText: string | null;
  sourceApp: string | null;
  imageFeatures: ImageFeatures;
  dispatcher: DispatcherResult;
}): boolean {
  if (looksLikeScreenshotCaptureKind(params.captureKind)) return false;
  if (looksLikePhotoCaptureKind(params.captureKind)) return true;
  if (params.dispatcher.selected_domain_key === "food") return true;
  if (params.dispatcher.selected_domain_key && params.dispatcher.selected_domain_key !== "food") return false;
  if (params.rawText || params.sourceApp) return false;

  const megapixels = params.imageFeatures.megapixels ?? 0;
  return params.imageFeatures.decode_ok && !params.imageFeatures.is_tiny_image && megapixels >= 0.5;
}

function selectVisionProvidersForImage(
  providers: ProviderConfig[],
  params: {
    photoPrimary: string | null;
    captureKind: string | null;
    rawText: string | null;
    sourceApp: string | null;
    imageFeatures: ImageFeatures;
    dispatcher: DispatcherResult;
  },
): ProviderConfig[] {
  if (!shouldUsePhotoQualityVision(params)) return providers;
  if (looksLikeCameraCaptureKind(params.captureKind)) {
    const qwen = providers[0];
    if (!qwen) return [];
    return [{
      ...qwen,
      model: qwen.photoModel ?? QWEN_PHOTO_DEFAULT_MODEL,
      enableThinking: false,
      requestTimeoutMs: 15_000,
    }];
  }
  const photoProviders = providers.map((p) => p.name === "qwen"
    ? {
      ...p,
      model: p.photoModel ?? QWEN_PHOTO_DEFAULT_MODEL,
      enableThinking: p.photoEnableThinking ?? false,
    }
    : p);

  const preferred = params.photoPrimary && params.photoPrimary !== "auto"
    ? params.photoPrimary
    : "qwen";
  const preferredIdx = photoProviders.findIndex((p) => p.name === preferred);
  if (preferredIdx <= 0) return photoProviders;

  const [picked] = photoProviders.splice(preferredIdx, 1);
  return [picked, ...photoProviders];
}

async function writeAiLog(
  supabase: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
  privacyConfig: PrivacyConfig = DEFAULT_PRIVACY_CONFIG,
): Promise<string | null> {
  // 隐私控制：用户关闭 AI 日志记录时不写任何日志
  if (!privacyConfig.aiLogsEnabled) return null;

  // 隐私控制：prompt_optimization_enabled=false 时不写入 raw_response
  if (!privacyConfig.promptOptimizationEnabled) {
    payload.raw_response = null;
  } else {
    // 开启时也要脱敏后再写入
    if (payload.raw_response && typeof payload.raw_response === "string") {
      payload.raw_response = sanitizeText(payload.raw_response);
    }
  }

  // ai_response 始终脱敏后写入
  if (payload.ai_response) {
    payload.ai_response = sanitizeSensitiveData(payload.ai_response);
  }

  // error_message 脱敏
  if (payload.error_message && typeof payload.error_message === "string") {
    payload.error_message = sanitizeText(payload.error_message);
  }

  const { data, error } = await supabase.from("ai_recognition_logs")
    .insert(payload)
    .select("id")
    .single();
  if (error) {
    console.error("AI log insert failed:", error);
    return null;
  }
  return (data?.id as string | undefined) ?? null;
}

interface AiRawDebugPayload {
  traceId?: string | null;
  promptVersion: string;
  promptHash: string | null;
  visionAttempts: VisionAttempt[];
  timings: Record<string, number>;
  clientTiming?: {
    server_received_at?: string | null;
    shortcut_started_at?: string | null;
    image_prepared_at?: string | null;
    request_started_at?: string | null;
    request_sent_at?: string | null;
    response_received_at?: string | null;
    notification_shown_at?: string | null;
    resize_ms?: number | null;
    preprocess_ms?: number | null;
    request_ms?: number | null;
    response_parse_ms?: number | null;
    notification_delay_ms?: number | null;
    total_ms?: number | null;
    edge_queue_ms?: number | null;
  } | null;
  dispatcher?: DispatcherResult | null;
  modelRaw?: {
    response_id?: string | null;
    finish_reason?: string | null;
    text?: string | null;
    extracted_json?: string | null;
    reasoning_text?: string | null;
  } | null;
  companion?: {
    model_raw?: string | null;
    normalized?: string | null;
    content_guarded?: string | null;
    time_guarded?: string | null;
    final?: string | null;
    disabled?: boolean | null;
    fallback_used?: boolean | null;
    feedback_used?: boolean | null;
    ai_feedback?: AIFeedback | null;
    voice?: {
      enabled: boolean;
      error?: string | null;
      signals?: string[];
      number_violations?: string[];
    } | null;
  } | null;
  notification?: {
    final?: string | null;
    source?: string | null;
    fallback?: string | null;
  } | null;
  visionMode?: "screenshot" | "photo" | null;
  photoQualityMode?: boolean | null;
  captureKind?: string | null;
  sourceApp?: string | null;
}

function buildAiRawDebug(payload: AiRawDebugPayload): string {
  const dispatcher = payload.dispatcher
    ? {
      ...payload.dispatcher,
      raw_text: clipForDebug((payload.dispatcher as { raw_text?: unknown }).raw_text, 4000),
    }
    : null;

  return JSON.stringify({
    debug_version: "ai-raw-v1",
    trace_id: payload.traceId ?? null,
    prompt: {
      version: payload.promptVersion,
      hash: payload.promptHash,
    },
    request_context: {
      capture_kind: payload.captureKind ?? null,
      source_app: payload.sourceApp ?? null,
      vision_mode: payload.visionMode ?? null,
      photo_quality_mode: payload.photoQualityMode ?? null,
    },
    client_timing: payload.clientTiming ?? null,
    dispatcher,
    model_raw: {
      response_id: payload.modelRaw?.response_id ?? null,
      finish_reason: payload.modelRaw?.finish_reason ?? null,
      text: clipForDebug(payload.modelRaw?.text, 8000),
      extracted_json: clipForDebug(payload.modelRaw?.extracted_json, 8000),
      reasoning_text: clipForDebug(payload.modelRaw?.reasoning_text, 4000),
    },
    companion: payload.companion ? {
      model_raw: clipForDebug(payload.companion.model_raw, 2000),
      normalized: clipForDebug(payload.companion.normalized, 2000),
      content_guarded: clipForDebug(payload.companion.content_guarded, 2000),
      time_guarded: clipForDebug(payload.companion.time_guarded, 2000),
      final: clipForDebug(payload.companion.final, 2000),
      disabled: payload.companion.disabled ?? null,
      fallback_used: payload.companion.fallback_used ?? null,
      feedback_used: payload.companion.feedback_used ?? null,
      ai_feedback: payload.companion.ai_feedback ?? null,
      voice: payload.companion.voice ?? null,
    } : null,
    notification: payload.notification ? {
      final: clipForDebug(payload.notification.final, 3000),
      source: payload.notification.source ?? null,
      fallback: clipForDebug(payload.notification.fallback, 2000),
    } : null,
    vision_attempts: payload.visionAttempts,
    timings: payload.timings,
  });
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

type CompanionContext = {
  settings: CompanionSettings;
  memory: Record<string, unknown> | null;
};

const DEFAULT_COMPANION_SETTINGS: CompanionSettings = {
  enabled: true,
  memoryEnabled: true,
  persona: "observer",
  memoryStrength: "balanced",
  expressionStyle: "plain",
  customNote: null,
};

const COMPANION_CONTEXT_TIMEOUT_MS = 900;

async function withTimeoutFallback<T>(
  promise: Promise<T>,
  timeoutMs: number,
  fallback: T,
  label: string,
): Promise<T> {
  let settled = false;
  return await new Promise<T>((resolve) => {
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      console.warn(`${label} timed out after ${timeoutMs}ms; continuing with fallback`);
      resolve(fallback);
    }, timeoutMs);

    promise.then((value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(value);
    }).catch((error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      console.warn(`${label} failed:`, error?.message ?? error);
      resolve(fallback);
    });
  });
}

async function loadCompanionContext(
  supabase: ReturnType<typeof createClient>,
  userId: string | null,
  fallbackSettings: CompanionSettings = DEFAULT_COMPANION_SETTINGS,
): Promise<CompanionContext> {
  if (!userId) return { settings: fallbackSettings, memory: null };
  const { data, error } = await supabase.rpc("get_companion_context", { p_user_id: userId });
  if (error) {
    console.warn("Companion context fetch failed:", error.message);
    return { settings: fallbackSettings, memory: null };
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
  if ((recordType === "expense" || recordType === "income")
    && hasUnsupportedFinanceCompanionClaim(text)) return null;
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
  return text.length > max ? clipAtNaturalBoundary(text, max) : text;
}

// 超长文案在标点处收尾,避免"看来你是真…"这种句中截断
function clipAtNaturalBoundary(text: string, max: number): string {
  const head = text.slice(0, max);
  let cut = -1;
  for (const p of ["。", "！", "？", "；", "，", ","]) {
    cut = Math.max(cut, head.lastIndexOf(p));
  }
  if (cut >= Math.floor(max * 0.5)) return `${head.slice(0, cut)}。`;
  return `${head.slice(0, max - 1)}…`;
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

function expenseCategoryLabel(category: string | null): string | null {
  if (!category) return null;
  const key = category.toLowerCase();
  if (["food", "餐饮", "美食"].includes(key)) return "餐饮";
  if (["transport", "交通"].includes(key)) return "交通";
  if (["shopping", "购物"].includes(key)) return "购物";
  if (["life", "生活"].includes(key)) return "生活";
  if (["entertainment", "娱乐"].includes(key)) return "娱乐";
  if (["medical", "health", "医疗", "健康"].includes(key)) return "健康";
  if (key === "other") return "其他";
  return category;
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
  if (hasUnsupportedFinanceCompanionClaim(text)) return null;
  return text;
}

function buildSignalFallbackAIFeedback(
  domainKey: string,
  signals: DomainSignal[],
  timingSignal: AIFeedback["timing_signal"] | null,
): AIFeedback | null {
  const signal = signals[0];
  if (!signal) return null;
  const fact = compactFeedbackText(signal.fact, 34) ?? signal.fact;
  const badgeByKind: Record<string, string> = {
    merchant_repeat: "本周复现",
    unusual_amount: "金额偏高",
    week_velocity: "周节奏变化",
    late_night_spend: "夜间消费",
    vs_baseline_normal: "正常水位",
    vs_baseline_below: "低于常态",
    vs_baseline_above: "更充足",
    consecutive_short: "连续偏短",
    pace_vs_self: "和自己比",
    rhythm_return: "重新接上",
    weekly_progress: "本周节奏",
    meal_vs_baseline: "和常态比",
    dish_ritual: "常点出现",
    late_snack_streak: "夜间加餐",
    book_switch: "换书记录",
    progress_momentum: "进度推进",
    streak: "连续阅读",
    liability_delta: "负债变化",
    due_reminder: "还款临近",
    record_acknowledge: "记录已归档",
  };
  const bandByKind: Record<string, AIFeedback["band"]> = {
    unusual_amount: "watch",
    week_velocity: "watch",
    late_night_spend: "watch",
    vs_baseline_below: "watch",
    consecutive_short: "watch",
    late_snack_streak: "watch",
    due_reminder: "watch",
    vs_baseline_above: "positive",
    pace_vs_self: "positive",
    rhythm_return: "positive",
    weekly_progress: "positive",
    progress_momentum: "positive",
    streak: "positive",
  };
  return {
    version: "feedback-v1",
    domain_key: domainKey,
    badge: badgeByKind[signal.kind] ?? "个人信号",
    icon: domainKey === "sleep" ? "🌙" : domainKey === "sport" ? "🏃" : domainKey === "food" ? "🍱" : domainKey === "reading" ? "📚" : domainKey === "wallet" ? "💳" : "💸",
    band: bandByKind[signal.kind] ?? "neutral",
    tone: "signal_fallback",
    emotion_line: fact,
    utility_line: null,
    detail_reason: signal.fact,
    internal_score: 68,
    confidence: 0.7,
    source: "rule",
    timing_signal: timingSignal,
  };
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
        utility_line: hours !== null ? `这晚约 ${Math.round(hours * 10) / 10} 小时。` : null,
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
  const categoryLabel = expenseCategoryLabel(category);
  const merchant = normalizeString(ai.merchant_name);
  const aiLine = financeCompanionLine(ai);
  const financeText = `${merchant ?? ""} ${category ?? ""} ${ai.platform ?? ""}`;
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
      badge: categoryLabel === "餐饮" ? "小额餐饮" : "小额支出",
      icon: "💸",
      band: "neutral",
      tone: "quiet_accounting",
      emotion_line: aiLine ?? (merchant
        ? `${merchant} ${fmtYuan(amount)}，这笔小额已落账。`
        : `${fmtYuan(amount)} 的小额支出已落账。`),
      utility_line: categoryLabel ? `分类记到${categoryLabel}，后面看一周频率。` : "先把这笔收住，后面再看频率。",
      detail_reason: `本笔支出 ${fmtYuan(amount)}，属于小额消费，价值在于频率追踪。`,
      internal_score: 62,
      confidence: 0.7,
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

function storedJsonObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  if (typeof value !== "string") return {};
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function transactionOccurredAt(date: string | null, time: string | null): string | null {
  if (!date || !time) return null;
  const normalizedTime = time.length === 5 ? `${time}:00` : time.slice(0, 8);
  return `${date}T${normalizedTime}+08:00`;
}

async function loadRecentFinancialPerceptualCandidates(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  excludedStagingId: string | null,
): Promise<FinancialPerceptualLookupResult> {
  const activeStagingStatuses = [
    "unassigned",
    "assigned",
    "failed",
    "unrouted",
    "routed",
    "routing_failed",
    "extracted",
    "pending_review",
    "extraction_failed",
    "schema_failed",
    "ai_error",
  ];

  let stagingQuery = supabase
    .from("staging_records")
    .select("id,perceptual_hash,record_type,occurred_at,order_finished_at,created_at,extracted_json")
    .eq("user_id", userId)
    .not("perceptual_hash", "is", null)
    .in("record_type", ["expense", "income"])
    .in("status", activeStagingStatuses)
    .order("created_at", { ascending: false })
    .limit(60);
  if (excludedStagingId) stagingQuery = stagingQuery.neq("id", excludedStagingId);

  const [transactionResult, incomeResult, stagingResult, legacyLogResult] = await Promise.all([
    supabase
      .from("transactions")
      .select("id,perceptual_hash,amount,merchant_name,platform,payment_method,transaction_date,transaction_time,created_at")
      .eq("user_id", userId)
      .not("perceptual_hash", "is", null)
      .order("created_at", { ascending: false })
      .limit(60),
    supabase
      .from("income_records")
      .select("id,perceptual_hash,amount,source_name,income_date,created_at")
      .eq("user_id", userId)
      .not("perceptual_hash", "is", null)
      .order("created_at", { ascending: false })
      .limit(60),
    stagingQuery,
    supabase
      .from("ai_recognition_logs")
      .select("id,perceptual_hash,target_table,target_id,record_type,occurred_at,order_finished_at,created_at,ai_response")
      .eq("user_id", userId)
      .not("perceptual_hash", "is", null)
      .not("target_id", "is", null)
      .in("target_table", ["transactions", "income_records"])
      .in("record_type", ["expense", "income"])
      .order("created_at", { ascending: false })
      .limit(60),
  ]);

  const financeColumnsAvailable = !transactionResult.error && !incomeResult.error;
  if (transactionResult.error || incomeResult.error) {
    console.warn("Finance perceptual columns unavailable; continuing without persisted fingerprints", {
      transaction_error: transactionResult.error?.code ?? null,
      income_error: incomeResult.error?.code ?? null,
    });
  }
  if (stagingResult.error) {
    console.warn("Staging perceptual lookup failed; continuing without staging candidates", {
      code: stagingResult.error.code ?? null,
    });
  }
  if (legacyLogResult.error) {
    console.warn("Legacy perceptual lookup failed; continuing without AI-log candidates", {
      code: legacyLogResult.error.code ?? null,
    });
  }

  const candidates: FinancialPerceptualCandidate[] = [];
  for (const row of (transactionResult.data ?? []) as TransactionPerceptualRow[]) {
    candidates.push({
      id: `transactions:${row.id}`,
      perceptualHash: row.perceptual_hash,
      recordType: "expense",
      referenceTable: "transactions",
      referenceId: row.id,
      amount: normalizeAmount(row.amount),
      merchantOrSource: row.merchant_name,
      platform: row.platform,
      paymentMethod: row.payment_method,
      occurredAt: transactionOccurredAt(row.transaction_date, row.transaction_time),
      occurredDate: row.transaction_date,
      timePrecision: row.transaction_time ? "datetime" : row.transaction_date ? "date" : "none",
      createdAt: row.created_at,
    });
  }

  for (const row of (incomeResult.data ?? []) as IncomePerceptualRow[]) {
    candidates.push({
      id: `income_records:${row.id}`,
      perceptualHash: row.perceptual_hash,
      recordType: "income",
      referenceTable: "income_records",
      referenceId: row.id,
      amount: normalizeAmount(row.amount),
      merchantOrSource: row.source_name,
      occurredDate: row.income_date,
      timePrecision: row.income_date ? "date" : "none",
      createdAt: row.created_at,
    });
  }

  for (const row of (stagingResult.data ?? []) as StagingPerceptualRow[]) {
    if (row.record_type !== "expense" && row.record_type !== "income") continue;
    const ai = storedJsonObject(row.extracted_json);
    const occurredAt = row.occurred_at || row.order_finished_at
      || normalizeString(ai.occurred_at) || normalizeString(ai.order_finished_at);
    candidates.push({
      id: `staging_records:${row.id}`,
      perceptualHash: row.perceptual_hash,
      recordType: row.record_type,
      referenceTable: "staging_records",
      referenceId: row.id,
      amount: normalizeAmount(ai.amount),
      merchantOrSource: normalizeString(row.record_type === "income" ? ai.source_name : ai.merchant_name),
      platform: normalizeString(ai.platform),
      paymentMethod: normalizeString(ai.payment_method),
      occurredAt,
      occurredDate: occurredAt?.slice(0, 10) ?? null,
      timePrecision: occurredAt ? "datetime" : "none",
      createdAt: row.created_at,
    });
  }

  const seenReferences = new Set(candidates.map((candidate) => `${candidate.referenceTable}:${candidate.referenceId}`));
  for (const row of (legacyLogResult.data ?? []) as PerceptualLogRow[]) {
    const recordType = row.record_type === "income" ? "income" : row.record_type === "expense" ? "expense" : null;
    const referenceTable = row.target_table === "income_records"
      ? "income_records"
      : row.target_table === "transactions"
        ? "transactions"
        : null;
    if (!recordType || !referenceTable || !row.target_id) continue;
    const referenceKey = `${referenceTable}:${row.target_id}`;
    if (seenReferences.has(referenceKey)) continue;

    const ai = storedJsonObject(row.ai_response);
    const occurredAt = row.occurred_at || row.order_finished_at
      || normalizeString(ai.occurred_at) || normalizeString(ai.order_finished_at);
    candidates.push({
      id: `ai_recognition_logs:${row.id}`,
      perceptualHash: row.perceptual_hash,
      recordType,
      referenceTable,
      referenceId: row.target_id,
      amount: normalizeAmount(ai.amount),
      merchantOrSource: normalizeString(recordType === "income" ? ai.source_name : ai.merchant_name),
      platform: normalizeString(ai.platform),
      paymentMethod: normalizeString(ai.payment_method),
      occurredAt,
      occurredDate: occurredAt?.slice(0, 10) ?? null,
      timePrecision: occurredAt ? "datetime" : "none",
      createdAt: row.created_at,
    });
    seenReferences.add(referenceKey);
  }

  return { candidates, financeColumnsAvailable };
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
    testMeta?: TestMeta | null;
    aiFeedback?: AIFeedback | null;
    companionMessage?: string | null;
    duplicateReview?: {
      kind: "perceptual_hash";
      distance: number;
      referenceTable: string;
      referenceId: string;
      recordType: "expense" | "income";
    } | null;
  },
  privacyConfig: PrivacyConfig = DEFAULT_PRIVACY_CONFIG,
): Promise<{ id: string } | null> {
  const detectedDomainKey = isBuiltinDomain(payload.ai.domain_key)
    ? payload.ai.domain_key
    : payload.ai.record_type === "income" || payload.ai.record_type === "expense" || isBuiltinDomain(payload.ai.record_type)
      ? payload.ai.record_type
      : null;
  const detectedDomainName = domainNameFromKey(detectedDomainKey);
  const summaryParts = [
    payload.duplicateReview
      ? "疑似与已有记录重复"
      : payload.ai.record_type && payload.ai.record_type !== "uncertain"
        ? `疑似${detectedDomainName}`
        : "无法确定数据域",
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
    extracted_json: sanitizeSensitiveData({
      ...payload.ai,
      time_context: payload.timeContext ?? null,
      // 首轮视觉模型同时承担识别，未经信号层校验的反馈不得进入用户可见待处理数据。
      ai_feedback: payload.aiFeedback ?? null,
      companion_message: payload.companionMessage ?? payload.ai.companion_message ?? null,
      review_reason: payload.duplicateReview ? "possible_duplicate" : null,
      duplicate_review: payload.duplicateReview ?? null,
      ...(payload.testMeta ? { test_meta: payload.testMeta } : {}),
    }),
    companion_message: payload.companionMessage ?? payload.ai.companion_message ?? null,
    // 隐私控制：prompt_optimization_enabled=false 时不清空 raw_text（中转站需要用于路由判断）
    // 但做脱敏处理
    raw_text: privacyConfig.promptOptimizationEnabled
      ? sanitizeText(payload.dispatcher?.raw_text ?? "") || null
      : null,
    routing_candidates: payload.dispatcher?.candidate_domains?.length
      ? payload.dispatcher.candidate_domains
      : detectedDomainKey
        ? [{ key: detectedDomainKey, name: detectedDomainName, confidence: payload.ai.confidence ?? 0 }]
        : [],
    quality_report: {
      error_type: payload.errorType ?? null,
      time_context: payload.timeContext ?? null,
      missing_fields: [],
      review_reason: payload.duplicateReview ? "possible_duplicate" : null,
      duplicate_review: payload.duplicateReview ?? null,
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
    let existingQuery = supabase
      .from("staging_records")
      .select("id")
      .eq("image_hash", payload.imageHash);
    if (payload.userId) {
      existingQuery = existingQuery.eq("user_id", payload.userId);
    }
    const { data: existing } = await existingQuery.maybeSingle();
    if (existing) return existing as IdRow;
    return null;
  }
  return data as IdRow;
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

// ============================================================
// 第二次调用：基于已识别字段 + 用户记忆，用高 temperature 生成「陪伴文案 + AI 即时反馈」
// 目的：把识别（需要 temp=0.1 稳定）和文案（需要 temp≈0.85 多样性）解耦
// 用纯文本调用（不需要图片），延迟 1-2 秒，失败时返回 null 让上层走规则兜底
// ============================================================
interface FeedbackCallResult {
  companion_message: string | null;
  ai_feedback: Partial<AIFeedback> | null;
  raw_text: string | null;
  duration_ms: number;
  error?: string;
}

async function callTextOnlyJsonGeneration(
  config: ProviderConfig,
  promptText: string,
  temperature: number = 0.85,
): Promise<{ rawText: string; parsed: Record<string, unknown> }> {
  const body: Record<string, unknown> = {
    model: config.model,
    messages: [{ role: "user", content: promptText }],
    temperature,
    max_completion_tokens: 1024,
  };
  // 文案调用不需要思考，关掉以加速。
  body.enable_thinking = false;
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
    await resp.body?.cancel();
    throw new Error(`${config.name} text API error ${resp.status}`);
  }
  const data = await resp.json();
  const message = data?.choices?.[0]?.message ?? {};
  const rawText = typeof message.content === "string" ? message.content : JSON.stringify(message.content ?? {});
  const extracted = extractJson(rawText);
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(extracted) as Record<string, unknown>;
  } catch (parseError) {
    throw new Error(`Failed to parse feedback JSON: ${String(parseError)}`);
  }
  return { rawText, parsed };
}

function clipChineseLen(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.replace(/[\r\n]+/g, " ").trim();
  if (!trimmed) return null;
  if (trimmed.length <= max) return trimmed;
  return clipAtNaturalBoundary(trimmed, max);
}

const ALLOWED_BANDS = new Set(["positive", "neutral", "watch", "recover", "ritual"]);

function normalizeFeedbackPayload(
  parsed: Record<string, unknown>,
  domainKey: string,
  timingSignal: AIFeedback["timing_signal"] | null,
): { companion_message: string | null; ai_feedback: Partial<AIFeedback> | null } {
  const companionRaw = parsed.companion_message;
  const companion = typeof companionRaw === "string" ? clipChineseLen(companionRaw, 30) : null;

  const fb = parsed.ai_feedback;
  if (!fb || typeof fb !== "object") {
    return { companion_message: companion, ai_feedback: null };
  }
  const fbObj = fb as Record<string, unknown>;
  const band = typeof fbObj.band === "string" && ALLOWED_BANDS.has(fbObj.band) ? fbObj.band : "neutral";
  const badge = clipChineseLen(fbObj.badge, 10) ?? "即时反馈";
  const emotionLine = clipChineseLen(fbObj.emotion_line, 30);
  const utilityLine = clipChineseLen(fbObj.utility_line, 32);
  const detailReason = clipChineseLen(fbObj.detail_reason, 64);
  const confidenceNum = typeof fbObj.confidence === "number" ? fbObj.confidence : Number(fbObj.confidence);
  const confidence = Number.isFinite(confidenceNum) ? Math.max(0, Math.min(1, confidenceNum)) : 0.7;
  if (!emotionLine || confidence < 0.5) {
    return { companion_message: companion, ai_feedback: null };
  }
  return {
    companion_message: companion,
    ai_feedback: {
      version: "feedback-v1",
      domain_key: domainKey,
      badge,
      icon: typeof fbObj.icon === "string" ? fbObj.icon : iconForDomain(domainKey),
      band: band as AIFeedback["band"],
      tone: "ai_generated",
      emotion_line: emotionLine,
      utility_line: utilityLine,
      detail_reason: detailReason,
      confidence,
      internal_score: Math.round(confidence * 100),
      source: "hybrid",
      timing_signal: timingSignal,
    },
  };
}

function iconForDomain(domainKey: string): string {
  if (domainKey === "sport") return "🏃";
  if (domainKey === "sleep") return "🌙";
  if (domainKey === "food") return "🍱";
  if (domainKey === "reading") return "📚";
  if (domainKey === "wallet") return "💳";
  if (domainKey === "income") return "💰";
  return "💸";
}

async function regenerateFeedbackWithSecondCall(opts: {
  ai: AIResult;
  domainKey: string;
  builtPayload?: Record<string, unknown> | null;
  timeContext: TimeContext | null;
  timingSignal: AIFeedback["timing_signal"] | null;
  promptCtx: PromptContextLike;
  textProvider: ProviderConfig | null;
}): Promise<FeedbackCallResult> {
  const startedAt = Date.now();
  if (!opts.textProvider) {
    return {
      companion_message: null,
      ai_feedback: null,
      raw_text: null,
      duration_ms: 0,
      error: "no_text_provider",
    };
  }
  try {
    const promptText = buildFeedbackPrompt({
      clientLocalTime: opts.promptCtx.clientLocalTime ?? null,
      weekday: opts.promptCtx.weekday ?? null,
      recognizedFields: {
        record_type: opts.ai.record_type ?? null,
        domain_key: opts.ai.domain_key ?? null,
        image_type: opts.ai.image_type ?? null,
        amount: opts.ai.amount,
        merchant_name: opts.ai.merchant_name,
        platform: opts.ai.platform,
        category: opts.ai.category,
        payment_method: opts.ai.payment_method,
        source_name: opts.ai.source_name ?? null,
        income_category: opts.ai.income_category ?? null,
        title: opts.ai.title ?? null,
        summary: opts.ai.summary ?? null,
        occurred_at: opts.ai.occurred_at ?? null,
        confidence: opts.ai.confidence,
      },
      builtPayload: opts.builtPayload ?? null,
      timeContext: opts.timeContext ? (opts.timeContext as unknown as Record<string, unknown>) : null,
      memory: opts.promptCtx.memory ?? null,
      memoryEnabled: opts.promptCtx.memoryEnabled,
      persona: opts.promptCtx.persona ?? null,
      memoryStrength: opts.promptCtx.memoryStrength ?? null,
      expressionStyle: opts.promptCtx.expressionStyle ?? null,
      customNote: opts.promptCtx.customNote ?? null,
      recentCompanionLines: opts.promptCtx.recentCompanionLines ?? [],
    });
    const { rawText, parsed } = await callTextOnlyJsonGeneration(opts.textProvider, promptText, 0.85);
    const normalized = normalizeFeedbackPayload(parsed, opts.domainKey, opts.timingSignal);
    const recordFacts = voiceRecordFacts(
      opts.domainKey,
      opts.ai,
      opts.builtPayload ?? null,
      normalizeAmount(opts.ai.amount),
    );
    const check = validateModelTone([
      normalized.companion_message,
      normalized.ai_feedback?.emotion_line ?? null,
      normalized.ai_feedback?.utility_line ?? null,
      normalized.ai_feedback?.detail_reason ?? null,
      normalized.ai_feedback?.badge ?? null,
    ], JSON.stringify(recordFacts));
    if (!check.ok) {
      const bad = new Set(check.badIndexes);
      const companion = bad.has(0) ? null : normalized.companion_message;
      let aiFeedback = normalized.ai_feedback;
      if (aiFeedback) {
        if (bad.has(1)) {
          aiFeedback = null;
        } else {
          aiFeedback = {
            ...aiFeedback,
            badge: bad.has(4) ? "即时反馈" : aiFeedback.badge,
            utility_line: bad.has(2) ? null : aiFeedback.utility_line,
            detail_reason: bad.has(3) ? null : aiFeedback.detail_reason,
          };
        }
      }
      return {
        companion_message: companion,
        ai_feedback: aiFeedback,
        raw_text: rawText,
        duration_ms: Date.now() - startedAt,
        ...(!companion && !aiFeedback ? { error: "evidence_validation_failed" } : {}),
      };
    }
    return {
      companion_message: normalized.companion_message,
      ai_feedback: normalized.ai_feedback,
      raw_text: rawText,
      duration_ms: Date.now() - startedAt,
    };
  } catch (err) {
    return {
      companion_message: null,
      ai_feedback: null,
      raw_text: null,
      duration_ms: Date.now() - startedAt,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

interface PromptContextLike {
  clientLocalTime?: string | null;
  weekday?: string | null;
  memory?: Record<string, unknown> | null;
  memoryEnabled?: boolean | null;
  persona?: string | null;
  memoryStrength?: string | null;
  expressionStyle?: string | null;
  customNote?: string | null;
  recentCompanionLines?: string[];
}

// ============================================================
// 信号驱动 Voice 层:事实(画像) → 信号(代码) → 规则事实 + 模型语气
// 模型统计断言违规即丢弃，画像数字与时间口径由规则层原样呈现。
// ============================================================

function isLateNightLocal(clientLocalTime: string | null | undefined): boolean {
  if (!clientLocalTime) return false;
  const m = clientLocalTime.match(/\s(\d{2}):/);
  return m ? Number(m[1]) >= 21 : false;
}

function buildCurrentFactsFor(
  domainKey: string,
  ai: AIResult,
  builtPayload: Record<string, unknown> | null,
  normalizedAmount: number | null,
  clientLocalTime: string | null,
): CurrentFacts {
  const p = builtPayload ?? {};
  const late = isLateNightLocal(clientLocalTime);
  if (domainKey === "expense") {
    return {
      amount: normalizedAmount,
      merchant: ai.merchant_name ?? null,
      category: ai.category ?? null,
      platform: ai.platform ?? null,
      isLateNight: late,
    };
  }
  if (domainKey === "income") {
    return {
      amount: normalizedAmount,
      merchant: ai.source_name ?? ai.merchant_name ?? null,
      category: ai.income_category ?? null,
      platform: ai.platform ?? null,
    };
  }
  if (domainKey === "sleep") {
    return {
      hours: normalizeNumber(p.sleep_hours) ?? (normalizeNumber(p.sleep_minutes) !== null ? normalizeNumber(p.sleep_minutes)! / 60 : null),
      score: normalizeNumber(p.quality_score),
    };
  }
  if (domainKey === "sport") {
    return {
      sportType: normalizeString(p.sport_type),
      durationMin: normalizeNumber(p.duration_minutes),
      distanceKm: normalizeNumber(p.distance_km),
      paceMin: parsePaceMinutes(p.avg_pace),
    };
  }
  if (domainKey === "food") {
    const dishes = Array.isArray(p.dishes) ? p.dishes : [];
    return {
      mealType: normalizeString(p.meal_type),
      kcal: normalizeNumber(p.total_calorie_kcal),
      dishNames: dishes
        .map((d) => d && typeof d === "object" ? normalizeString((d as Record<string, unknown>).name) : null)
        .filter((n): n is string => !!n),
      isLateNight: late,
    };
  }
  if (domainKey === "reading") {
    return {
      bookName: normalizeString(p.book_name),
      readingMinutes: normalizeNumber(p.reading_minutes),
      progressPercent: normalizeNumber(p.progress_percent),
    };
  }
  if (domainKey === "wallet") {
    return {
      recordKind: normalizeString(p.record_kind),
      accountName: normalizeString(p.account_name),
      walletAmount: normalizeNumber(p.amount),
    };
  }
  return {};
}

// Voice prompt 用的记录字段白名单:识别字段全集会带入无关信息(签约/广告等),只给必要项
function voiceRecordFacts(
  domainKey: string,
  ai: AIResult,
  builtPayload: Record<string, unknown> | null,
  normalizedAmount: number | null,
): Record<string, unknown> {
  if (domainKey === "expense" || domainKey === "income") {
    return {
      record_type: domainKey,
      amount: normalizedAmount ?? ai.amount ?? null,
      merchant_name: ai.merchant_name ?? null,
      source_name: ai.source_name ?? null,
      category: ai.category ?? null,
      platform: ai.platform ?? null,
      occurred_at: ai.occurred_at ?? null,
    };
  }
  return {
    record_type: domainKey,
    title: ai.title ?? null,
    summary: ai.summary ?? null,
    payload: builtPayload ?? null,
    occurred_at: ai.occurred_at ?? null,
  };
}

interface VoiceCallResult extends FeedbackCallResult {
  signals: DomainSignal[];
  number_violations?: string[];
}

async function generateVoiceFeedback(opts: {
  ai: AIResult;
  domainKey: string;
  builtPayload?: Record<string, unknown> | null;
  normalizedAmount?: number | null;
  domainProfiles: DomainProfilesMap;
  timingSignal: AIFeedback["timing_signal"] | null;
  clientLocalTime: string | null;
  weekday: string | null;
  persona?: string | null;
  expressionStyle?: string | null;
  customNote?: string | null;
  recentCompanionLines?: string[];
  textProvider: ProviderConfig | null;
}): Promise<VoiceCallResult> {
  const startedAt = Date.now();
  const cur = buildCurrentFactsFor(
    opts.domainKey, opts.ai, opts.builtPayload ?? null,
    opts.normalizedAmount ?? null, opts.clientLocalTime,
  );
  const signals = selectSignals(opts.domainKey, opts.domainProfiles, cur);
  if (!opts.textProvider) {
    return { companion_message: null, ai_feedback: null, raw_text: null, duration_ms: 0, error: "no_text_provider", signals };
  }
  const recordFacts = voiceRecordFacts(opts.domainKey, opts.ai, opts.builtPayload ?? null, opts.normalizedAmount ?? null);
  try {
    const promptText = buildVoicePrompt({
      clientLocalTime: opts.clientLocalTime,
      weekday: opts.weekday,
      domainKey: opts.domainKey,
      recordFacts,
      signals: signals.map((s) => ({ kind: s.kind, fact: s.fact })),
      persona: opts.persona ?? null,
      expressionStyle: opts.expressionStyle ?? null,
      customNote: opts.customNote ?? null,
      recentCompanionLines: opts.recentCompanionLines ?? [],
    });
    const { rawText, parsed } = await callTextOnlyJsonGeneration(opts.textProvider, promptText, 0.8);
    const normalized = normalizeFeedbackPayload(parsed, opts.domainKey, opts.timingSignal);
    // 模型只拥有语气：画像统计数字与时间口径由规则层直接呈现。
    const check = validateModelTone(
      [
        normalized.companion_message,
        normalized.ai_feedback?.emotion_line ?? null,
        normalized.ai_feedback?.utility_line ?? null,
        normalized.ai_feedback?.detail_reason ?? null,
        normalized.ai_feedback?.badge ?? null,
      ],
      JSON.stringify(recordFacts),
    );
    const bad = new Set(check.badIndexes);
    const companion = bad.has(0) ? null : normalized.companion_message;
    let modelFeedback = normalized.ai_feedback;
    if (modelFeedback) {
      if (bad.has(1)) {
        modelFeedback = null;
      } else {
        modelFeedback = {
          ...modelFeedback,
          badge: bad.has(4) ? "即时反馈" : modelFeedback.badge,
          utility_line: bad.has(2) ? null : modelFeedback.utility_line,
          detail_reason: bad.has(3) ? null : modelFeedback.detail_reason,
        };
      }
    }

    const verifiedSignals = signals.filter((signal) => signal.kind !== "record_acknowledge");
    if (verifiedSignals.length > 0) {
      const ruleFeedback = buildSignalFallbackAIFeedback(opts.domainKey, verifiedSignals, opts.timingSignal);
      if (ruleFeedback) {
        const tone = companion ?? modelFeedback?.emotion_line ?? null;
        return {
          companion_message: tone ?? ruleFeedback.emotion_line,
          ai_feedback: {
            ...ruleFeedback,
            emotion_line: tone ?? ruleFeedback.emotion_line,
            source: tone ? "hybrid" : "rule",
          },
          raw_text: rawText,
          duration_ms: Date.now() - startedAt,
          signals,
          ...(!check.ok ? { number_violations: check.violations } : {}),
        };
      }
    }

    if (!check.ok) {
      console.warn(`[voice] number validation failed domain=${opts.domainKey} count=${check.violations.length}`);
      // 有存活内容时不设 error(调用方据此判断是否走兜底),但保留 number_violations 供 trace 观察
      if (!companion && !modelFeedback) {
        return {
          companion_message: null, ai_feedback: null, raw_text: rawText,
          duration_ms: Date.now() - startedAt, error: "evidence_validation_failed",
          signals, number_violations: check.violations,
        };
      }
      return {
        companion_message: companion, ai_feedback: modelFeedback, raw_text: rawText,
        duration_ms: Date.now() - startedAt, signals, number_violations: check.violations,
      };
    }
    return {
      companion_message: companion,
      ai_feedback: modelFeedback,
      raw_text: rawText,
      duration_ms: Date.now() - startedAt,
      signals,
    };
  } catch (err) {
    return {
      companion_message: null, ai_feedback: null, raw_text: null,
      duration_ms: Date.now() - startedAt,
      error: err instanceof Error ? err.message : String(err),
      signals,
    };
  }
}

// 归档成功后 fire-and-forget 刷新该域画像(单用户单域全量重算,毫秒级)
function fireAndForgetProfileRefresh(
  supabase: ReturnType<typeof createClient>,
  userId: string | null,
  domainKey: string,
): void {
  if (!userId) return;
  if (!["expense", "sleep", "sport", "food", "reading", "wallet"].includes(domainKey)) return;
  const task = supabase.rpc("refresh_domain_profile", { p_user_id: userId, p_domain_key: domainKey })
    .then(({ error }: { error: { message: string } | null }) => {
      if (error) console.warn(`[profile] refresh ${domainKey} failed:`, error.message);
    });
  try {
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(task) ?? task;
  } catch {
    // waitUntil 不可用时 task 已在事件循环中,尽力而为
  }
}

// Qwen OpenAI-compatible Vision 调用。
async function callOpenAICompatibleVision(
  imageBytes: Uint8Array,
  mime: string,
  config: ProviderConfig,
  promptText: string = PROMPT,
): Promise<VisionProviderResult> {
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
    // JSON 实际只需 ~500 token；Qwen 思考模式需要额外预算给 reasoning_content。
    max_completion_tokens: config.enableThinking !== false ? 4096 : 1024,
  };
  body.enable_thinking = config.enableThinking !== false;
  const timeoutMs = config.requestTimeoutMs ?? (config.enableThinking === true
    ? getEnvInteger("VISION_THINKING_TIMEOUT_MS", 20_000, 8_000, 45_000)
    : getEnvInteger("VISION_PROVIDER_TIMEOUT_MS", 15_000, 5_000, 30_000));
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let resp: Response;
  try {
    resp = await fetch(config.endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${config.apiKey}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (error) {
    if (controller.signal.aborted) {
      throw new Error(`${config.name} timed out after ${timeoutMs}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
  if (!resp.ok) {
    await resp.body?.cancel();
    throw new Error(`${config.name} API error ${resp.status}`);
  }
  const data = await resp.json();
  const message = data?.choices?.[0]?.message ?? {};
  const text = typeof message.content === "string" ? message.content : JSON.stringify(message.content ?? {});
  const extractedJson = extractJson(text);
  const responseId = typeof data?.id === "string" ? data.id : null;
  const finishReason = typeof data?.choices?.[0]?.finish_reason === "string" ? data.choices[0].finish_reason : null;
  const reasoningText = typeof message.reasoning_content === "string" ? message.reasoning_content : null;
  let ai: AIResult;
  try {
    ai = JSON.parse(extractedJson) as AIResult;
  } catch (parseError) {
    const err = new Error(`Failed to parse vision JSON: ${String(parseError)}`);
    Object.assign(err, { rawText: text, extractedJson, responseId, finishReason, reasoningText });
    throw err;
  }
  return {
    ai,
    rawText: text,
    extractedJson,
    responseId,
    finishReason,
    reasoningText,
  };
}

// 保留 attempts 结构，便于记录 Qwen 调用失败的耗时和错误上下文。
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
  let lastRawText: string | null = null;
  let lastExtractedJson: string | null = null;
  let lastResponseId: string | null = null;
  let lastFinishReason: string | null = null;
  let lastReasoningText: string | null = null;
  for (const cfg of providers) {
    const startedAt = Date.now();
    try {
      const result = await callOpenAICompatibleVision(imageBytes, mime, cfg, promptText);
      attempts.push({
        provider: cfg.name,
        model: cfg.model,
        duration_ms: Date.now() - startedAt,
        raw_text_preview: clipForDebug(result.rawText, 600) ?? undefined,
      });
      return {
        ai: result.ai,
        provider: cfg.name,
        model: cfg.model,
        attempts,
        rawText: result.rawText,
        extractedJson: result.extractedJson,
        responseId: result.responseId,
        finishReason: result.finishReason,
        reasoningText: result.reasoningText,
      };
    } catch (e) {
      const errMsg = String(e);
      const errWithDebug = e as Error & {
        rawText?: string;
        extractedJson?: string;
        responseId?: string | null;
        finishReason?: string | null;
        reasoningText?: string | null;
      };
      if (typeof errWithDebug.rawText === "string") {
        lastRawText = errWithDebug.rawText;
        lastExtractedJson = errWithDebug.extractedJson ?? null;
        lastResponseId = errWithDebug.responseId ?? null;
        lastFinishReason = errWithDebug.finishReason ?? null;
        lastReasoningText = errWithDebug.reasoningText ?? null;
      }
      attempts.push({
        provider: cfg.name,
        model: cfg.model,
        duration_ms: Date.now() - startedAt,
        error: errMsg,
        raw_text_preview: clipForDebug(errWithDebug.rawText, 600) ?? undefined,
      });
      console.warn(`[vision-fallback] provider=${cfg.name} failed: ${errMsg}`);
    }
  }
  // 全部失败：抛带聚合信息的错误
  const summary = attempts.map(a => `${a.provider}: ${a.error}`).join(" | ");
  const err = new Error(`All vision providers failed → ${summary}`);
  // 把 attempts 挂到 error 上，外层可以读取写入日志
  (err as Error & { attempts?: VisionAttempt[] }).attempts = attempts;
  Object.assign(err, {
    rawText: lastRawText,
    extractedJson: lastExtractedJson,
    responseId: lastResponseId,
    finishReason: lastFinishReason,
    reasoningText: lastReasoningText,
  });
  throw err;
}

const IMAGE_REFERENCE_TARGETS: Array<{ table: string; column: string }> = [
  { table: "transactions", column: "image_url" },
  { table: "income_records", column: "image_url" },
  { table: "data_records", column: "source_image_path" },
  { table: "staging_records", column: "image_path" },
  { table: "ai_recognition_logs", column: "image_url" },
];

type ImageReferenceExclusion = { table: string; id: string };

type ImageCleanupQueueRow = {
  id: string;
  bucket_path: string;
  bucket_name: string | null;
  user_id: string | null;
  attempts: number;
  created_at: string;
  cleanup_reason: ImageCleanupReason;
  source_table: string | null;
  source_id: string | null;
  storage_deleted_at: string | null;
};

type ImageCleanupReason = "retention" | "manual_cleanup" | "immediate" | "record_delete" | "account_delete" | "upload_rollback";

type ImageCleanupResult = {
  processed: number;
  failed: number;
  deadLetter: number;
  skippedExternal: number;
  remaining: number;
};

function isUserOwnedStoragePath(path: string, userId: string): boolean {
  return path.startsWith(`${userId}/`) || path.startsWith(`tmp/${userId}/`);
}

function isLegacyStoragePath(path: string): boolean {
  return /^[0-9]{4}-[0-9]{2}-[0-9]{2}\/[A-Za-z0-9][A-Za-z0-9._-]*$/.test(path);
}

function normalizeManagedStoragePath(value: string): string | null {
  const raw = value.trim();
  if (!raw || /^data:/i.test(raw)) return null;

  if (/^https?:\/\//i.test(raw)) {
    try {
      const parsed = new URL(raw);
      if (parsed.origin !== new URL(getEnv("SUPABASE_URL")).origin) return null;
      const prefixes = [
        `/storage/v1/object/sign/${BUCKET_NAME}/`,
        `/storage/v1/object/authenticated/${BUCKET_NAME}/`,
        `/storage/v1/object/public/${BUCKET_NAME}/`,
      ];
      const prefix = prefixes.find((candidate) => parsed.pathname.startsWith(candidate));
      if (!prefix) return null;
      return decodeURIComponent(parsed.pathname.slice(prefix.length)) || null;
    } catch {
      return null;
    }
  }

  return raw.split(/[?#]/, 1)[0]?.trim() || null;
}

async function collectNormalizedReferenceIds(
  supabase: ReturnType<typeof createClient>,
  table: string,
  column: string,
  userId: string,
  path: string,
  exclusion?: ImageReferenceExclusion,
): Promise<string[]> {
  const ids: string[] = [];
  let lastId: string | null = null;
  for (;;) {
    let query = supabase.from(table)
      .select(`id,${column}`)
      .eq("user_id", userId)
      .ilike(column, "http%")
      .order("id", { ascending: true })
      .limit(500);
    if (exclusion?.table === table) query = query.neq("id", exclusion.id);
    if (lastId) query = query.gt("id", lastId);
    const { data, error } = await query;
    if (error) throw new Error(`Failed to inspect managed URL references in ${table}.${column}: ${error.message}`);
    const rows = (data ?? []) as unknown as Array<Record<string, unknown>>;
    for (const row of rows) {
      const value = row[column];
      if (typeof row.id === "string"
        && typeof value === "string"
        && normalizeManagedStoragePath(value) === path) {
        ids.push(row.id);
      }
    }
    if (rows.length < 500) break;
    const nextId = rows.at(-1)?.id;
    if (typeof nextId !== "string" || nextId === lastId) {
      throw new Error(`Reference pagination did not advance for ${table}.${column}`);
    }
    lastId = nextId;
  }
  return ids;
}

async function collectUserScopedStoragePaths(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<string[]> {
  const paths = new Set<string>();
  const directories = [userId, `tmp/${userId}`];
  const visited = new Set<string>();
  while (directories.length > 0) {
    const directory = directories.shift();
    if (!directory || visited.has(directory)) continue;
    visited.add(directory);
    if (visited.size > 10_000) throw new Error("Storage directory traversal limit exceeded");

    for (let offset = 0; ; offset += 1_000) {
      const { data, error } = await supabase.storage.from(BUCKET_NAME).list(directory, {
        limit: 1_000,
        offset,
        sortBy: { column: "name", order: "asc" },
      });
      if (error) throw new Error(`Failed to list user Storage objects: ${error.message}`);
      const entries = (data ?? []) as unknown as Array<Record<string, unknown>>;
      for (const entry of entries) {
        if (typeof entry.name !== "string" || entry.name.length === 0) continue;
        const entryPath = `${directory}/${entry.name}`;
        const isFile = typeof entry.id === "string" || entry.metadata != null;
        if (isFile) paths.add(entryPath);
        else directories.push(entryPath);
      }
      if (entries.length < 1_000) break;
    }
  }
  return [...paths];
}

async function authenticatedUserId(req: Request): Promise<string | null> {
  const authHeader = req.headers.get("Authorization") || "";
  const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  const anonKey = getEnvOptional("ANON_PUBLIC_KEY");
  if (!bearerToken || !anonKey || bearerToken === anonKey) return null;
  try {
    const userClient = createClient(getEnv("SUPABASE_URL"), anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error } = await userClient.auth.getUser();
    return error ? null : user?.id ?? null;
  } catch {
    return null;
  }
}

function authenticatedSupabaseClient(req: Request): ReturnType<typeof createClient> | null {
  const authHeader = req.headers.get("Authorization") || "";
  const anonKey = getEnvOptional("ANON_PUBLIC_KEY");
  if (!authHeader.startsWith("Bearer ") || !anonKey) return null;
  return createClient(getEnv("SUPABASE_URL"), anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
}

function isCleanupWorkerRequest(req: Request): boolean {
  const actual = req.headers.get("X-Image-Cleanup-Token") || "";
  const expected = getEnvOptional("IMAGE_CLEANUP_WORKER_TOKEN") || "";
  if (!actual || actual.length !== expected.length) return false;
  let difference = 0;
  for (let index = 0; index < actual.length; index += 1) {
    difference |= actual.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return difference === 0;
}

async function collectUserImagePaths(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<{ ownedPaths: string[]; skippedExternal: number }> {
  const paths = new Set<string>();
  const externalPaths = new Set<string>();
  const pageSize = 500;
  for (const { table, column } of IMAGE_REFERENCE_TARGETS) {
    let lastId: string | null = null;
    for (;;) {
      let query = supabase.from(table)
        .select(`id,${column}`)
        .eq("user_id", userId)
        .not(column, "is", null)
        .order("id", { ascending: true })
        .limit(pageSize);
      if (lastId) query = query.gt("id", lastId);
      const { data, error } = await query;
      if (error) throw new Error(`Failed to collect ${table}.${column}: ${error.message}`);
      const rows = (data ?? []) as unknown as Array<Record<string, unknown>>;
      for (const row of rows) {
        const rawPath = row[column];
        if (typeof rawPath !== "string" || rawPath.length === 0) continue;
        const normalizedPath = normalizeManagedStoragePath(rawPath);
        if (normalizedPath
          && (isUserOwnedStoragePath(normalizedPath, userId) || isLegacyStoragePath(normalizedPath))) {
          paths.add(normalizedPath);
        } else {
          externalPaths.add(rawPath);
        }
      }
      if (rows.length < pageSize) break;
      const nextId = rows.at(-1)?.id;
      if (typeof nextId !== "string" || nextId === lastId) {
        throw new Error(`Image path pagination did not advance for ${table}.${column}`);
      }
      lastId = nextId;
    }
  }
  for (const storagePath of await collectUserScopedStoragePaths(supabase, userId)) {
    paths.add(storagePath);
  }
  return { ownedPaths: [...paths], skippedExternal: externalPaths.size };
}

async function enqueueImageCleanup(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  paths: string[],
  cleanupReason: ImageCleanupReason,
): Promise<void> {
  if (paths.length === 0) return;
  const uniquePaths = [...new Set(paths)];
  for (let offset = 0; offset < uniquePaths.length; offset += 200) {
    const batch = uniquePaths.slice(offset, offset + 200);
    const now = new Date().toISOString();
    const { error: retryError } = await supabase.from("image_cleanup_queue").update({
      status: "pending",
      attempts: 0,
      cleanup_reason: cleanupReason,
      last_error: null,
      processed_at: null,
      last_attempt_at: null,
      next_retry_at: now,
      deleted_at: null,
      storage_deleted_at: null,
      references_cleared_at: null,
      updated_at: now,
    })
      .eq("user_id", userId)
      .in("bucket_path", batch)
      .in("status", ["failed", "dead_letter", "done", "skipped_external"]);
    if (retryError) throw new Error(`Failed to requeue image cleanup: ${retryError.message}`);

    const { error: pendingError } = await supabase.from("image_cleanup_queue").update({
      cleanup_reason: cleanupReason,
      next_retry_at: now,
      updated_at: now,
    })
      .eq("user_id", userId)
      .in("bucket_path", batch)
      .eq("status", "pending");
    if (pendingError) throw new Error(`Failed to reprioritize image cleanup: ${pendingError.message}`);

    const { error: insertError } = await supabase.from("image_cleanup_queue").upsert(
      batch.map((path) => ({
        user_id: userId,
        bucket_name: BUCKET_NAME,
        bucket_path: path,
        status: "pending",
        attempts: 0,
        cleanup_reason: cleanupReason,
        last_error: null,
        processed_at: null,
        last_attempt_at: null,
        next_retry_at: now,
        deleted_at: null,
        storage_deleted_at: null,
        references_cleared_at: null,
        updated_at: now,
      })),
      { onConflict: "user_id,bucket_path", ignoreDuplicates: true },
    );
    if (insertError) throw new Error(`Failed to enqueue image cleanup: ${insertError.message}`);
  }
}

async function cleanupUploadedObjectOrQueue(
  supabase: ReturnType<typeof createClient>,
  userId: string | null,
  path: string,
): Promise<void> {
  if (!userId || !isUserOwnedStoragePath(path, userId)) return;
  try {
    await enqueueImageCleanup(supabase, userId, [path], "upload_rollback");
    const result = await processImageCleanupQueue(supabase, {
      userId,
      bucketPath: path,
      limit: 1,
      force: true,
    });
    if (result.failed > 0 || result.deadLetter > 0 || result.remaining > 0) {
      console.error("Uploaded image rollback deferred", { result });
    }
  } catch (cleanupError) {
    console.error("Failed to queue uploaded image rollback", { error: String(cleanupError) });
  }
}

async function hasBusinessImageReference(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  path: string,
  exclusion?: ImageReferenceExclusion,
): Promise<boolean> {
  const normalizedPath = normalizeManagedStoragePath(path);
  if (!normalizedPath) return false;
  const businessTargets = IMAGE_REFERENCE_TARGETS.filter(({ table }) => table !== "ai_recognition_logs");
  for (const { table, column } of businessTargets) {
    let query = supabase.from(table)
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq(column, normalizedPath);
    if (exclusion?.table === table) query = query.neq("id", exclusion.id);
    const { count, error } = await query;
    if (error) throw new Error(`Failed to verify ${table}.${column}: ${error.message}`);
    if ((count ?? 0) > 0) return true;
    if ((await collectNormalizedReferenceIds(supabase, table, column, userId, normalizedPath, exclusion)).length > 0) {
      return true;
    }
  }
  return false;
}

async function clearDiscardedStagingImageReference(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  stagingId: string,
): Promise<void> {
  const { error } = await supabase.from("staging_records")
    .update({ image_path: null })
    .eq("id", stagingId)
    .eq("user_id", userId)
    .eq("status", "discarded");
  if (error) throw new Error(`Failed to clear discarded staging image reference: ${error.message}`);
}

async function clearImageReferences(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  path: string,
): Promise<void> {
  const normalizedPath = normalizeManagedStoragePath(path);
  if (!normalizedPath) throw new Error("Managed Storage path is invalid");
  for (const { table, column } of IMAGE_REFERENCE_TARGETS) {
    const { error } = await supabase.from(table)
      .update({ [column]: null })
      .eq("user_id", userId)
      .eq(column, normalizedPath);
    if (error) throw new Error(`Failed to clear ${table}.${column}: ${error.message}`);
    const signedReferenceIds = await collectNormalizedReferenceIds(
      supabase,
      table,
      column,
      userId,
      normalizedPath,
    );
    for (let offset = 0; offset < signedReferenceIds.length; offset += 100) {
      const { error: signedReferenceError } = await supabase.from(table)
        .update({ [column]: null })
        .eq("user_id", userId)
        .in("id", signedReferenceIds.slice(offset, offset + 100));
      if (signedReferenceError) {
        throw new Error(`Failed to clear managed URL references in ${table}.${column}: ${signedReferenceError.message}`);
      }
    }
  }
}

async function clearImageReferencesBatch(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  paths: string[],
): Promise<void> {
  const normalizedPaths = [...new Set(paths.map(normalizeManagedStoragePath).filter((path): path is string => Boolean(path)))];
  if (normalizedPaths.length === 0) return;
  const pathSet = new Set(normalizedPaths);

  for (const { table, column } of IMAGE_REFERENCE_TARGETS) {
    for (let offset = 0; offset < normalizedPaths.length; offset += 50) {
      const { error: directError } = await supabase.from(table)
        .update({ [column]: null })
        .eq("user_id", userId)
        .in(column, normalizedPaths.slice(offset, offset + 50));
      if (directError) throw new Error(`Failed to batch-clear ${table}.${column}: ${directError.message}`);
    }

    const signedReferenceIds: string[] = [];
    let lastId: string | null = null;
    for (;;) {
      let query = supabase.from(table)
        .select(`id,${column}`)
        .eq("user_id", userId)
        .ilike(column, "http%")
        .order("id", { ascending: true })
        .limit(500);
      if (lastId) query = query.gt("id", lastId);
      const { data, error } = await query;
      if (error) throw new Error(`Failed to inspect managed URL references in ${table}.${column}: ${error.message}`);
      const rows = (data ?? []) as unknown as Array<Record<string, unknown>>;
      for (const row of rows) {
        const value = row[column];
        if (typeof row.id === "string"
          && typeof value === "string"
          && pathSet.has(normalizeManagedStoragePath(value) ?? "")) {
          signedReferenceIds.push(row.id);
        }
      }
      if (rows.length < 500) break;
      const nextId = rows.at(-1)?.id;
      if (typeof nextId !== "string" || nextId === lastId) {
        throw new Error(`Reference pagination did not advance for ${table}.${column}`);
      }
      lastId = nextId;
    }

    for (let offset = 0; offset < signedReferenceIds.length; offset += 100) {
      const { error } = await supabase.from(table)
        .update({ [column]: null })
        .eq("user_id", userId)
        .in("id", signedReferenceIds.slice(offset, offset + 100));
      if (error) throw new Error(`Failed to batch-clear managed URLs in ${table}.${column}: ${error.message}`);
    }
  }
}

async function claimImageCleanupRows(
  supabase: ReturnType<typeof createClient>,
  rows: ImageCleanupQueueRow[],
): Promise<ImageCleanupQueueRow[]> {
  const claimed: ImageCleanupQueueRow[] = [];
  const rowsByAttempt = new Map<number, ImageCleanupQueueRow[]>();
  for (const row of rows) {
    const attempts = row.attempts ?? 0;
    rowsByAttempt.set(attempts, [...(rowsByAttempt.get(attempts) ?? []), row]);
  }

  for (const [attempts, attemptRows] of rowsByAttempt) {
    const attemptedAt = new Date().toISOString();
    const { data, error } = await supabase.from("image_cleanup_queue")
      .update({
        status: "processing",
        attempts: attempts + 1,
        last_attempt_at: attemptedAt,
        next_retry_at: null,
        updated_at: attemptedAt,
      })
      .in("id", attemptRows.map((row) => row.id))
      .eq("attempts", attempts)
      .in("status", ["pending", "failed"])
      .select("id,bucket_path,bucket_name,user_id,attempts,created_at,cleanup_reason,source_table,source_id,storage_deleted_at");
    if (error) throw new Error(`Failed to claim image cleanup batch: ${error.message}`);
    claimed.push(...((data ?? []) as ImageCleanupQueueRow[]));
  }
  return claimed;
}

async function failClaimedImageCleanupRows(
  supabase: ReturnType<typeof createClient>,
  rows: ImageCleanupQueueRow[],
  errorMessage: string,
): Promise<{ failed: number; deadLetter: number }> {
  let deadLetter = 0;
  const rowsByAttempt = new Map<number, ImageCleanupQueueRow[]>();
  for (const row of rows) {
    const attempts = row.attempts ?? 1;
    rowsByAttempt.set(attempts, [...(rowsByAttempt.get(attempts) ?? []), row]);
  }
  for (const [attempts, attemptRows] of rowsByAttempt) {
    const exhausted = attempts >= 8;
    if (exhausted) deadLetter += attemptRows.length;
    const retryDelayMinutes = Math.min(12 * 60, Math.pow(5, Math.max(0, attempts - 1)));
    const { error } = await supabase.from("image_cleanup_queue").update({
      status: exhausted ? "dead_letter" : "failed",
      last_error: errorMessage,
      next_retry_at: exhausted ? null : new Date(Date.now() + retryDelayMinutes * 60 * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    }).in("id", attemptRows.map((row) => row.id)).eq("status", "processing");
    if (error) throw new Error(`Failed to persist cleanup batch failure: ${error.message}`);
  }
  return { failed: rows.length, deadLetter };
}

async function processAccountDeletionCleanupRows(
  supabase: ReturnType<typeof createClient>,
  inputRows: ImageCleanupQueueRow[],
): Promise<Omit<ImageCleanupResult, "remaining">> {
  const claimedRows = await claimImageCleanupRows(supabase, inputRows);
  let processed = 0;
  let failed = 0;
  let deadLetter = 0;
  let skippedExternal = 0;

  const externalRows = claimedRows.filter((row) => /^(https?:\/\/|data:)/i.test(row.bucket_path));
  if (externalRows.length > 0) {
    const now = new Date().toISOString();
    const { error } = await supabase.from("image_cleanup_queue").update({
      status: "skipped_external",
      last_error: "external URL is not managed by Supabase Storage",
      processed_at: now,
      next_retry_at: null,
      updated_at: now,
    }).in("id", externalRows.map((row) => row.id)).eq("status", "processing");
    if (error) throw new Error(`Failed to record skipped cleanup batch: ${error.message}`);
    skippedExternal += externalRows.length;
  }

  const candidateRows = claimedRows.filter((row) => !externalRows.some((external) => external.id === row.id));
  const legacyPaths = candidateRows
    .filter((row) => isLegacyStoragePath(row.bucket_path))
    .map((row) => row.bucket_path);
  const ownedLegacyPaths = new Set<string>();
  if (legacyPaths.length > 0) {
    const { data, error } = await supabase.from("receipt_image_owners")
      .select("bucket_path,user_id")
      .eq("bucket_name", BUCKET_NAME)
      .in("bucket_path", legacyPaths);
    if (error) throw new Error(`Failed to verify legacy cleanup ownership: ${error.message}`);
    for (const owner of data ?? []) {
      const row = owner as { bucket_path?: string; user_id?: string };
      if (row.bucket_path && row.user_id) ownedLegacyPaths.add(`${row.user_id}:${row.bucket_path}`);
    }
  }

  const invalidRows = candidateRows.filter((row) => (
    !row.user_id
    || row.bucket_name !== BUCKET_NAME
    || (!isUserOwnedStoragePath(row.bucket_path, row.user_id)
      && !(isLegacyStoragePath(row.bucket_path) && ownedLegacyPaths.has(`${row.user_id}:${row.bucket_path}`)))
  ));
  if (invalidRows.length > 0) {
    const result = await failClaimedImageCleanupRows(supabase, invalidRows, "Cleanup path ownership cannot be verified");
    failed += result.failed;
    deadLetter += result.deadLetter;
  }

  const invalidIds = new Set(invalidRows.map((row) => row.id));
  const validRows = candidateRows.filter((row) => !invalidIds.has(row.id));
  const rowsByUser = new Map<string, ImageCleanupQueueRow[]>();
  for (const row of validRows) {
    const userId = row.user_id!;
    rowsByUser.set(userId, [...(rowsByUser.get(userId) ?? []), row]);
  }

  for (const [userId, userRows] of rowsByUser) {
    try {
      const rowsNeedingStorageDelete = userRows.filter((row) => !row.storage_deleted_at);
      if (rowsNeedingStorageDelete.length > 0) {
        const { error: removeError } = await supabase.storage.from(BUCKET_NAME)
          .remove(rowsNeedingStorageDelete.map((row) => row.bucket_path));
        if (removeError) throw new Error(removeError.message);
        const storageDeletedAt = new Date().toISOString();
        const { error: storageAuditError } = await supabase.from("image_cleanup_queue").update({
          storage_deleted_at: storageDeletedAt,
          updated_at: storageDeletedAt,
        }).in("id", rowsNeedingStorageDelete.map((row) => row.id)).eq("status", "processing");
        if (storageAuditError) throw new Error(`Failed to record Storage deletion batch: ${storageAuditError.message}`);
      }

      await clearImageReferencesBatch(supabase, userId, userRows.map((row) => row.bucket_path));
      const completedAt = new Date().toISOString();
      const { error: doneError } = await supabase.from("image_cleanup_queue").update({
        status: "done",
        last_error: null,
        processed_at: completedAt,
        deleted_at: completedAt,
        references_cleared_at: completedAt,
        next_retry_at: null,
        updated_at: completedAt,
      }).in("id", userRows.map((row) => row.id)).eq("status", "processing");
      if (doneError) throw new Error(`Failed to complete cleanup batch: ${doneError.message}`);
      processed += userRows.length;
    } catch (batchError) {
      const result = await failClaimedImageCleanupRows(supabase, userRows, String(batchError));
      failed += result.failed;
      deadLetter += result.deadLetter;
    }
  }

  return { processed, failed, deadLetter, skippedExternal };
}

async function legacyStoragePathCanBeDeleted(
  supabase: ReturnType<typeof createClient>,
  row: ImageCleanupQueueRow,
): Promise<boolean> {
  if (!row.user_id) return false;
  const normalizedPath = normalizeManagedStoragePath(row.bucket_path);
  if (!normalizedPath) return false;
  let hasOwnerReference = false;
  for (const { table, column } of IMAGE_REFERENCE_TARGETS) {
    let lastId: string | null = null;
    for (;;) {
      let query = supabase.from(table)
        .select(`id,user_id,${column}`)
        .not(column, "is", null)
        .order("id", { ascending: true })
        .limit(500);
      if (lastId) query = query.gt("id", lastId);
      const { data, error } = await query;
      if (error) throw new Error(`Failed to verify legacy path ownership in ${table}.${column}: ${error.message}`);
      const references = (data ?? []) as unknown as Array<Record<string, unknown>>;
      for (const reference of references) {
        const referencePath = reference[column];
        if (typeof referencePath !== "string"
          || normalizeManagedStoragePath(referencePath) !== normalizedPath) continue;
        const referenceUserId = typeof reference.user_id === "string" ? reference.user_id : null;
        if (referenceUserId !== row.user_id) return false;
        hasOwnerReference = true;
      }
      if (references.length < 500) break;
      const nextId = references.at(-1)?.id;
      if (typeof nextId !== "string" || nextId === lastId) {
        throw new Error(`Legacy ownership pagination did not advance for ${table}.${column}`);
      }
      lastId = nextId;
    }
  }
  return hasOwnerReference
    || (row.cleanup_reason === "record_delete" && Boolean(row.source_table && row.source_id));
}

async function processImageCleanupQueue(
  supabase: ReturnType<typeof createClient>,
  options: {
    userId?: string;
    bucketPath?: string;
    cleanupReason?: ImageCleanupReason;
    excludeCleanupReason?: ImageCleanupReason;
    limit?: number;
    force?: boolean;
  } = {},
): Promise<ImageCleanupResult> {
  const limit = Math.min(Math.max(options.limit ?? 100, 1), 500);
  const { error: accountRetryError } = await supabase.from("image_cleanup_queue").update({
    status: "failed",
    attempts: 0,
    next_retry_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  })
    .eq("status", "dead_letter")
    .eq("cleanup_reason", "account_delete")
    .lt("updated_at", new Date(Date.now() - 60 * 60 * 1000).toISOString());
  if (accountRetryError) throw new Error(`Failed to recover account deletion dead letters: ${accountRetryError.message}`);
  let staleQuery = supabase.from("image_cleanup_queue")
    .update({
      status: "failed",
      last_error: "stale processing lease recovered",
      next_retry_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("status", "processing")
    .lt("updated_at", new Date(Date.now() - 15 * 60 * 1000).toISOString());
  if (options.userId) staleQuery = staleQuery.eq("user_id", options.userId);
  if (options.bucketPath) staleQuery = staleQuery.eq("bucket_path", options.bucketPath);
  const { error: staleError } = await staleQuery;
  if (staleError) throw new Error(`Failed to recover stale image cleanup rows: ${staleError.message}`);

  let query = supabase.from("image_cleanup_queue")
    .select("id,bucket_path,user_id,attempts,created_at,cleanup_reason,bucket_name,source_table,source_id,storage_deleted_at")
    .in("status", ["pending", "failed"])
    .lt("attempts", 8)
    .or(`next_retry_at.is.null,next_retry_at.lte.${new Date().toISOString()}`)
    .order("created_at", { ascending: true })
    .limit(limit);
  if (options.userId) query = query.eq("user_id", options.userId);
  if (options.bucketPath) query = query.eq("bucket_path", options.bucketPath);
  if (options.cleanupReason) query = query.eq("cleanup_reason", options.cleanupReason);
  if (options.excludeCleanupReason) query = query.neq("cleanup_reason", options.excludeCleanupReason);
  const { data, error } = await query;
  if (error) throw new Error(`Failed to read image cleanup queue: ${error.message}`);

  let processed = 0;
  let failed = 0;
  let deadLetter = 0;
  let skippedExternal = 0;
  const cleanupRows = (data ?? []) as ImageCleanupQueueRow[];
  const accountDeletionRows = cleanupRows.filter((row) => row.cleanup_reason === "account_delete");
  if (accountDeletionRows.length > 0) {
    const batchResult = await processAccountDeletionCleanupRows(supabase, accountDeletionRows);
    processed += batchResult.processed;
    failed += batchResult.failed;
    deadLetter += batchResult.deadLetter;
    skippedExternal += batchResult.skippedExternal;
  }
  const accountDeletionIds = new Set(accountDeletionRows.map((row) => row.id));
  for (const row of cleanupRows.filter((candidate) => !accountDeletionIds.has(candidate.id))) {
    const attempts = row.attempts ?? 0;
    const attemptedAt = new Date().toISOString();
    const { data: claimed, error: claimError } = await supabase.from("image_cleanup_queue")
      .update({
        status: "processing",
        attempts: attempts + 1,
        last_attempt_at: attemptedAt,
        next_retry_at: null,
        updated_at: attemptedAt,
      })
      .eq("id", row.id)
      .eq("attempts", attempts)
      .in("status", ["pending", "failed"])
      .select("id")
      .maybeSingle();
    if (claimError) throw new Error(`Failed to claim image cleanup row: ${claimError.message}`);
    if (!claimed) continue;

    try {
      if (!row.user_id) throw new Error("Cleanup row has no user_id");
      if (!options.force && row.cleanup_reason === "retention") {
        const { data: rawConfig, error: configError } = await supabase.from("user_configs")
          .select("is_active,keep_source_images,image_retention_days,updated_at")
          .eq("user_id", row.user_id)
          .maybeSingle();
        if (configError) throw new Error(`Failed to verify image retention policy: ${configError.message}`);
        const config = rawConfig as RetentionConfigRow | null;

        const policyChangedAfterQueue = Boolean(
          config?.updated_at && new Date(config.updated_at).getTime() > new Date(row.created_at).getTime()
        );
        const noLongerEligible = !config
          || config.is_active !== true
          || (config.keep_source_images === true && (config.image_retention_days ?? -1) < 0)
          || policyChangedAfterQueue;
        if (noLongerEligible) {
          const { error: cancelError } = await supabase.from("image_cleanup_queue").delete().eq("id", row.id);
          if (cancelError) throw new Error(`Failed to cancel stale image cleanup: ${cancelError.message}`);
          continue;
        }
      }
      if (["record_delete", "upload_rollback"].includes(row.cleanup_reason)) {
        const stagingSource = row.cleanup_reason === "record_delete"
          && row.source_table === "staging_records"
          && Boolean(row.source_id)
          ? { table: "staging_records", id: row.source_id! }
          : undefined;
        const hasOtherReference = await hasBusinessImageReference(
          supabase,
          row.user_id,
          row.bucket_path,
          stagingSource,
        );
        if (hasOtherReference && stagingSource) {
          await clearDiscardedStagingImageReference(supabase, row.user_id, stagingSource.id);
          const skippedAt = new Date().toISOString();
          const { error: skippedError } = await supabase.from("image_cleanup_queue").update({
            status: "skipped_shared",
            last_error: "Storage object retained because another business record still references it",
            processed_at: skippedAt,
            references_cleared_at: skippedAt,
            next_retry_at: null,
            updated_at: skippedAt,
          }).eq("id", row.id).eq("status", "processing");
          if (skippedError) throw new Error(`Failed to record shared image cleanup: ${skippedError.message}`);
          continue;
        }
        if (hasOtherReference) {
          const { error: cancelError } = await supabase.from("image_cleanup_queue").delete().eq("id", row.id);
          if (cancelError) throw new Error(`Failed to cancel referenced image cleanup: ${cancelError.message}`);
          continue;
        }
      }
      if (/^(https?:\/\/|data:)/i.test(row.bucket_path)) {
        const { error: skippedError } = await supabase.from("image_cleanup_queue").update({
          status: "skipped_external",
          last_error: "external URL is not managed by Supabase Storage",
          processed_at: new Date().toISOString(),
          next_retry_at: null,
          updated_at: new Date().toISOString(),
        }).eq("id", row.id);
        if (skippedError) throw new Error(skippedError.message);
        skippedExternal += 1;
        continue;
      }
      if (!row.storage_deleted_at && !isUserOwnedStoragePath(row.bucket_path, row.user_id)) {
        if (!isLegacyStoragePath(row.bucket_path) || !await legacyStoragePathCanBeDeleted(supabase, row)) {
          throw new Error("Cleanup path ownership cannot be verified");
        }
      }
      let storageDeletedAt = row.storage_deleted_at;
      if (!storageDeletedAt) {
        const { error: removeError } = await supabase.storage.from(BUCKET_NAME).remove([row.bucket_path]);
        if (removeError) throw new Error(removeError.message);
        storageDeletedAt = new Date().toISOString();
        const { error: storageAuditError } = await supabase.from("image_cleanup_queue").update({
          storage_deleted_at: storageDeletedAt,
          updated_at: storageDeletedAt,
        }).eq("id", row.id);
        if (storageAuditError) throw new Error(`Failed to record Storage deletion: ${storageAuditError.message}`);
      }
      await clearImageReferences(supabase, row.user_id, row.bucket_path);
      const referencesClearedAt = new Date().toISOString();
      const { error: doneError } = await supabase.from("image_cleanup_queue").update({
        status: "done",
        last_error: null,
        processed_at: referencesClearedAt,
        deleted_at: storageDeletedAt,
        references_cleared_at: referencesClearedAt,
        next_retry_at: null,
        updated_at: referencesClearedAt,
      }).eq("id", row.id);
      if (doneError) throw new Error(doneError.message);
      processed += 1;
    } catch (cleanupError) {
      failed += 1;
      const nextAttempt = attempts + 1;
      const exhausted = nextAttempt >= 8;
      const retryDelayMinutes = Math.min(12 * 60, Math.pow(5, attempts));
      const { error: failureUpdateError } = await supabase.from("image_cleanup_queue").update({
        status: exhausted ? "dead_letter" : "failed",
        last_error: String(cleanupError),
        next_retry_at: exhausted ? null : new Date(Date.now() + retryDelayMinutes * 60 * 1000).toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", row.id);
      if (failureUpdateError) throw new Error(`Failed to persist cleanup failure: ${failureUpdateError.message}`);
      if (exhausted) deadLetter += 1;
    }
  }

  let remainingQuery = supabase.from("image_cleanup_queue")
    .select("id", { count: "exact", head: true })
    .in("status", ["pending", "failed", "processing", "dead_letter"]);
  if (options.userId) remainingQuery = remainingQuery.eq("user_id", options.userId);
  if (options.bucketPath) remainingQuery = remainingQuery.eq("bucket_path", options.bucketPath);
  if (options.cleanupReason) remainingQuery = remainingQuery.eq("cleanup_reason", options.cleanupReason);
  if (options.excludeCleanupReason) remainingQuery = remainingQuery.neq("cleanup_reason", options.excludeCleanupReason);
  const { count, error: remainingError } = await remainingQuery;
  if (remainingError) throw new Error(`Failed to count remaining image cleanup rows: ${remainingError.message}`);
  if (count === null) throw new Error("Image cleanup remaining count was unavailable");
  let deadLetterQuery = supabase.from("image_cleanup_queue")
    .select("id", { count: "exact", head: true })
    .eq("status", "dead_letter");
  if (options.userId) deadLetterQuery = deadLetterQuery.eq("user_id", options.userId);
  if (options.bucketPath) deadLetterQuery = deadLetterQuery.eq("bucket_path", options.bucketPath);
  if (options.cleanupReason) deadLetterQuery = deadLetterQuery.eq("cleanup_reason", options.cleanupReason);
  if (options.excludeCleanupReason) deadLetterQuery = deadLetterQuery.neq("cleanup_reason", options.excludeCleanupReason);
  const { count: deadLetterCount, error: deadLetterError } = await deadLetterQuery;
  if (deadLetterError) throw new Error(`Failed to count dead-letter image cleanup rows: ${deadLetterError.message}`);
  if (deadLetterCount === null) throw new Error("Image cleanup dead-letter count was unavailable");
  return { processed, failed, deadLetter: Math.max(deadLetter, deadLetterCount), skippedExternal, remaining: count };
}

async function cleanupAllUserImages(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  cleanupReason: "manual_cleanup" | "account_delete" = "manual_cleanup",
  options: { maxBatches?: number; batchSize?: number } = {},
): Promise<{ total: number; queued: number; processed: number; failed: number; deadLetter: number; skippedExternal: number; remaining: number }> {
  const collected = await collectUserImagePaths(supabase, userId);
  await enqueueImageCleanup(supabase, userId, collected.ownedPaths, cleanupReason);
  let processed = 0;
  let failed = 0;
  let deadLetter = 0;
  let remaining = 0;
  const maxBatches = Math.min(Math.max(options.maxBatches ?? 10, 1), 20);
  const batchSize = Math.min(Math.max(options.batchSize ?? 100, 1), 200);
  for (let batch = 0; batch < maxBatches; batch += 1) {
    const result = await processImageCleanupQueue(supabase, { userId, limit: batchSize, force: true });
    processed += result.processed;
    failed += result.failed;
    deadLetter = result.deadLetter;
    remaining = result.remaining;
    if (remaining === 0 || result.processed === 0) break;
  }
  return {
    total: collected.ownedPaths.length + collected.skippedExternal,
    queued: collected.ownedPaths.length,
    processed,
    failed,
    deadLetter,
    skippedExternal: collected.skippedExternal,
    remaining,
  };
}

async function updateAccountDeletionRequest(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  values: Record<string, unknown>,
): Promise<void> {
  const { error } = await supabase.from("account_deletion_requests")
    .update({ ...values, updated_at: new Date().toISOString() })
    .eq("user_id", userId);
  if (error) throw new Error(`Failed to update account deletion request: ${error.message}`);
}

async function prepareAccountDeletion(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<Awaited<ReturnType<typeof cleanupAllUserImages>>> {
  const updatedAt = new Date().toISOString();
  const { error: deactivateError } = await supabase.from("user_configs").update({
    is_active: false,
    upload_token: null,
    updated_at: updatedAt,
  }).eq("user_id", userId);
  if (deactivateError) {
    throw new Error(`Failed to deactivate account credentials: ${deactivateError.message}`);
  }

  const collected = await collectUserImagePaths(supabase, userId);
  await enqueueImageCleanup(supabase, userId, collected.ownedPaths, "account_delete");
  const { count: remaining, error: countError } = await supabase.from("image_cleanup_queue")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("cleanup_reason", "account_delete")
    .in("status", ["pending", "failed", "processing", "dead_letter"]);
  if (countError || remaining === null) {
    throw new Error(`Failed to count queued account images: ${countError?.message ?? "count unavailable"}`);
  }
  const cleanup = {
    total: collected.ownedPaths.length + collected.skippedExternal,
    queued: collected.ownedPaths.length,
    processed: 0,
    failed: 0,
    deadLetter: 0,
    skippedExternal: collected.skippedExternal,
    remaining,
  };
  await updateAccountDeletionRequest(supabase, userId, {
    status: "cleaning",
    total_images: cleanup.total,
    deleted_images: cleanup.processed,
    remaining_images: cleanup.remaining,
    skipped_external: cleanup.skippedExternal,
    last_error: null,
    next_retry_at: null,
  });
  return cleanup;
}

async function rescanAccountDeletionImages(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<Awaited<ReturnType<typeof cleanupAllUserImages>>> {
  const collected = await collectUserImagePaths(supabase, userId);
  await enqueueImageCleanup(supabase, userId, collected.ownedPaths, "account_delete");
  const { count: remaining, error: countError } = await supabase.from("image_cleanup_queue")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .in("status", ["pending", "failed", "processing", "dead_letter"]);
  if (countError || remaining === null) {
    throw new Error(`Failed to count rescanned account images: ${countError?.message ?? "count unavailable"}`);
  }
  return {
    total: collected.ownedPaths.length + collected.skippedExternal,
    queued: collected.ownedPaths.length,
    processed: 0,
    failed: 0,
    deadLetter: 0,
    skippedExternal: collected.skippedExternal,
    remaining,
  };
}

async function finalizeAccountDeletion(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<boolean> {
  try {
    await updateAccountDeletionRequest(supabase, userId, {
      status: "deleting",
      last_error: null,
      next_retry_at: null,
    });
    const { error: dataError } = await supabase.rpc("delete_user_account_data", { p_user_id: userId });
    if (dataError) throw new Error(`删除账户数据失败：${dataError.message}`);

    const { count: postDeleteQueueCount, error: postDeleteQueueError } = await supabase
      .from("image_cleanup_queue")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .in("status", ["pending", "failed", "processing", "dead_letter"]);
    if (postDeleteQueueError || postDeleteQueueCount === null) {
      throw new Error("Unable to verify image cleanup after deleting account data");
    }
    if (postDeleteQueueCount > 0) {
      await updateAccountDeletionRequest(supabase, userId, {
        status: "cleaning",
        remaining_images: postDeleteQueueCount,
        next_retry_at: new Date().toISOString(),
      });
      return false;
    }

    const { error: queueDeleteError } = await supabase.from("image_cleanup_queue").delete().eq("user_id", userId);
    if (queueDeleteError) throw new Error(`删除图片清理审计失败：${queueDeleteError.message}`);
    const { error: authError } = await supabase.auth.admin.deleteUser(userId);
    if (authError && !/not found/i.test(authError.message)) {
      throw new Error(`删除登录账户失败：${authError.message}`);
    }
    const { error: requestDeleteError } = await supabase.from("account_deletion_requests").delete().eq("user_id", userId);
    if (requestDeleteError) throw new Error(`删除账户清理请求失败：${requestDeleteError.message}`);
    return true;
  } catch (deletionError) {
    const { data: existing } = await supabase.from("account_deletion_requests")
      .select("attempts")
      .eq("user_id", userId)
      .maybeSingle();
    const attempts = Number(existing?.attempts ?? 0) + 1;
    await updateAccountDeletionRequest(supabase, userId, {
      status: "failed",
      attempts,
      last_error: String(deletionError),
      next_retry_at: new Date(Date.now() + Math.min(12 * 60, Math.pow(5, attempts - 1)) * 60 * 1000).toISOString(),
    }).catch((requestError) => {
      console.error("Failed to persist account deletion failure", {
        error_type: requestError instanceof Error ? requestError.name : typeof requestError,
      });
    });
    console.error("Account deletion finalization failed", {
      error_type: deletionError instanceof Error ? deletionError.name : typeof deletionError,
    });
    return false;
  }
}

async function finalizeReadyAccountDeletions(
  supabase: ReturnType<typeof createClient>,
): Promise<{ prepared: number; completed: number; failed: number }> {
  const now = new Date().toISOString();
  const { data, error } = await supabase.from("account_deletion_requests")
    .select("user_id,status")
    .in("status", ["requested", "cleaning", "deleting", "failed"])
    .or(`next_retry_at.is.null,next_retry_at.lte.${now}`)
    .order("requested_at", { ascending: true })
    .limit(1);
  if (error) throw new Error(`Failed to read pending account deletions: ${error.message}`);

  let completed = 0;
  let failed = 0;
  let prepared = 0;
  for (const row of data ?? []) {
    const userId = String(row.user_id);
    let status = String(row.status);
    try {
      if (status === "requested") {
        await prepareAccountDeletion(supabase, userId);
        prepared += 1;
        status = "cleaning";
      }
      if (status === "deleting") {
        const rescan = await rescanAccountDeletionImages(supabase, userId);
        if (rescan.remaining > 0) {
          await updateAccountDeletionRequest(supabase, userId, {
            status: "cleaning",
            total_images: rescan.total,
            remaining_images: rescan.remaining,
            skipped_external: rescan.skippedExternal,
            last_error: null,
            next_retry_at: new Date().toISOString(),
          });
          continue;
        }
      }
    } catch (cleanupError) {
      failed += 1;
      await updateAccountDeletionRequest(supabase, userId, {
        status: String(row.status),
        last_error: String(cleanupError),
        next_retry_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      }).catch(() => undefined);
      continue;
    }
    const { count, error: queueError } = await supabase.from("image_cleanup_queue")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .in("status", ["pending", "failed", "processing", "dead_letter"]);
    if (queueError || count === null) {
      failed += 1;
      console.error("Failed to verify account deletion queue", {
        error_code: queueError?.code ?? null,
      });
      continue;
    }
    if (count > 0) continue;
    if (status !== "deleting" && status !== "failed") {
      await updateAccountDeletionRequest(supabase, userId, {
        status: "deleting",
        remaining_images: 0,
        last_error: null,
        next_retry_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      });
      continue;
    }
    if (await finalizeAccountDeletion(supabase, userId)) completed += 1;
    else failed += 1;
  }

  await supabase.from("account_deletion_requests")
    .delete()
    .eq("status", "completed")
    .lt("completed_at", new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString());
  return { prepared, completed, failed };
}

Deno.serve(async (req) => {
  const requestUrl = new URL(req.url);
  let responseMode: ShortcutResponseMode = requestUrl.searchParams.get("response_mode") === "text" ? "text" : "json";
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return respondShortcut({ error: "Method not allowed" }, { mode: responseMode, status: 405 });
  }

  // 在请求内层初始化客户端，避免启动崩溃
  let supabase: ReturnType<typeof createClient>;
  let visionProviders: ProviderConfig[] = [];
  try {
    supabase = createClient(getEnv("SUPABASE_URL"), getEnv("SUPABASE_SERVICE_ROLE_KEY"));

    const qwenProvider: ProviderConfig = {
      name: "qwen",
      model: normalizeQwenModel(getEnvOptional("QWEN_MODEL"), QWEN_DEFAULT_MODEL),
      endpoint: getEnvOptional("QWEN_ENDPOINT") ?? QWEN_DEFAULT_ENDPOINT,
      apiKey: getEnv("QWEN_API_KEY"),
      enableThinking: getEnvBoolean("QWEN_ENABLE_THINKING", false),
      photoModel: normalizeQwenModel(getEnvOptional("QWEN_PHOTO_MODEL"), QWEN_PHOTO_DEFAULT_MODEL),
      photoEnableThinking: getEnvBoolean("QWEN_PHOTO_ENABLE_THINKING", false),
    };
    visionProviders = [qwenProvider];
  } catch (e) {
    return respondShortcut({ error: `Secret config error: ${String(e)}` }, { mode: responseMode, status: 500 });
  }

  // 二次文案调用仍使用 Qwen，只允许单独覆盖 Qwen API Key 和白名单模型。
  const textProvider: ProviderConfig | null = visionProviders[0]
    ? {
      ...visionProviders[0],
      apiKey: Deno.env.get("FEEDBACK_TEXT_API_KEY") || visionProviders[0].apiKey,
      model: normalizeQwenModel(Deno.env.get("FEEDBACK_TEXT_MODEL"), visionProviders[0].model),
      enableThinking: false,
    }
    : null;

  // 信号驱动 Voice 层开关:默认开;设 VOICE_SIGNALS_ENABLED=false 回退旧记忆注入链路
  const voiceSignalsEnabled = (Deno.env.get("VOICE_SIGNALS_ENABLED") ?? "true") !== "false";

  const requestTraceId = crypto.randomUUID();
  let lastAiLogId: string | null = null;
  let temporaryImageCleanup: { userId: string; path: string } | null = null;

  try {
    const startedAt = Date.now();
    const timings = makeTimings();
    const traceId = requestTraceId;
    // 隐私配置：默认最严格，用户查询后覆盖
    let privacyConfig: PrivacyConfig = { ...DEFAULT_PRIVACY_CONFIG };
    const writeTraceAiLog = async (payload: Record<string, unknown>): Promise<string | null> => {
      // 统一注入 user_id，确保所有 AI 日志都能按用户隔离查询
      // userId 在下方身份校验流程中赋值（JWT 或 upload_token 反查），闭包按引用捕获
      const enrichedPayload = userId ? { ...payload, user_id: userId } : payload;
      const aiLogId = await writeAiLog(supabase, enrichedPayload, privacyConfig);
      if (aiLogId) lastAiLogId = aiLogId;
      return aiLogId;
    };

    // ── action 类请求拦截（非图片上传，JSON body）──
    const contentType = req.headers.get("Content-Type") || "";
    if (contentType.includes("application/json")) {
      const jsonBody = await req.json().catch(() => ({}));
      const action = jsonBody?.action;

      if (action === "submit_expression_feedback") {
        const actionUserId = await authenticatedUserId(req);
        if (!actionUserId) {
          return new Response(JSON.stringify({ error: "未授权" }), {
            status: 401, headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        }
        try {
          const result = await submitExpressionFeedback(supabase, actionUserId, jsonBody);
          return new Response(JSON.stringify({ ok: true, data: result }), {
            headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        } catch (feedbackError) {
          return new Response(JSON.stringify({
            ok: false,
            error: feedbackError instanceof Error ? feedbackError.message : String(feedbackError),
          }), {
            status: 400, headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        }
      }

      if (action === "process_image_cleanup_queue") {
        if (!isCleanupWorkerRequest(req)) {
          return new Response(JSON.stringify({ error: "Unauthorized worker request" }), {
            status: 401, headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        }
        const { data: workerRun, error: workerRunError } = await supabase.from("image_cleanup_worker_runs")
          .insert({ status: "running", invocation_source: "scheduled" })
          .select("id")
          .single();
        if (workerRunError || !workerRun) {
          throw new Error(`Failed to create cleanup worker run: ${workerRunError?.message ?? "missing run id"}`);
        }
        const workerRunId = String(workerRun.id);
        try {
          const beforeCleanup = await finalizeReadyAccountDeletions(supabase);
          const accountCleanup = await processImageCleanupQueue(supabase, {
            cleanupReason: "account_delete",
            limit: 100,
            force: true,
          });
          const afterCleanup = await finalizeReadyAccountDeletions(supabase);
          const generalCleanup = await processImageCleanupQueue(supabase, {
            excludeCleanupReason: "account_delete",
            limit: 50,
          });
          const result = {
            processed: accountCleanup.processed + generalCleanup.processed,
            failed: accountCleanup.failed + generalCleanup.failed,
            deadLetter: accountCleanup.deadLetter + generalCleanup.deadLetter,
            skippedExternal: accountCleanup.skippedExternal + generalCleanup.skippedExternal,
            remaining: accountCleanup.remaining + generalCleanup.remaining,
          };
          const accountDeletions = {
            prepared: beforeCleanup.prepared + afterCleanup.prepared,
            completed: beforeCleanup.completed + afterCleanup.completed,
            failed: beforeCleanup.failed + afterCleanup.failed,
          };
          if (accountCleanup.remaining > 0 && accountCleanup.processed >= 100) {
            const { data: continuationQueued, error: continuationError } = await supabase.rpc("invoke_image_cleanup_worker");
            if (continuationError || continuationQueued !== true) {
              console.warn("Account deletion continuation will rely on the next scheduled run", {
                error_code: continuationError?.code ?? null,
              });
            }
          }
          const { error: completeRunError } = await supabase.from("image_cleanup_worker_runs").update({
            status: "succeeded",
            completed_at: new Date().toISOString(),
            processed: result.processed,
            failed: result.failed,
            remaining: result.remaining,
          }).eq("id", workerRunId);
          if (completeRunError) throw new Error(`Failed to complete cleanup worker run: ${completeRunError.message}`);
          return new Response(JSON.stringify({ status: "ok", ...result, account_deletions: accountDeletions }), {
            headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        } catch (workerError) {
          await supabase.from("image_cleanup_worker_runs").update({
            status: "failed",
            completed_at: new Date().toISOString(),
            error_message: String(workerError),
          }).eq("id", workerRunId);
          throw workerError;
        }
      }

      if (action === "delete_record") {
        const actionUserId = await authenticatedUserId(req);
        const userClient = authenticatedSupabaseClient(req);
        if (!actionUserId || !userClient) {
          return new Response(JSON.stringify({ error: "未授权" }), {
            status: 401, headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        }

        const reference = typeof jsonBody?.reference === "string" ? jsonBody.reference.trim() : "";
        const referenceParts = reference.split("/", 2);
        const recordKind = String(jsonBody?.record_kind ?? (referenceParts.length === 2 ? referenceParts[0] : "")).trim();
        const recordId = String(jsonBody?.record_id ?? (referenceParts.length === 2 ? referenceParts[1] : "")).trim();
        if (!recordKind || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(recordId)) {
          return new Response(JSON.stringify({ error: "记录类型或 ID 无效" }), {
            status: 400, headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        }

        const { data, error: deleteError } = await userClient.rpc("delete_record_with_cleanup", {
          p_kind: recordKind,
          p_id: recordId,
        });
        if (deleteError) {
          return new Response(JSON.stringify({ error: `删除记录失败：${deleteError.message}` }), {
            status: 400, headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        }

        const deletion = data as { reference?: string; image_path?: string; cleanup_queued?: boolean } | null;
        let cleanup: { processed: number; failed: number; remaining: number } | null = null;
        let cleanupPending = false;
        if (deletion?.cleanup_queued && deletion.image_path) {
          try {
            cleanup = await processImageCleanupQueue(supabase, {
              userId: actionUserId,
              bucketPath: deletion.image_path,
              limit: 1,
              force: true,
            });
            cleanupPending = cleanup.failed > 0 || cleanup.remaining > 0;
          } catch (cleanupError) {
            cleanupPending = true;
            console.error("Record image cleanup deferred", {
              error_type: cleanupError instanceof Error ? cleanupError.name : typeof cleanupError,
            });
          }
        }

        return new Response(JSON.stringify({
          status: "deleted",
          reference: deletion?.reference ?? `${recordKind}/${recordId}`,
          cleanup_queued: deletion?.cleanup_queued ?? false,
          cleanup_pending: cleanupPending,
          cleanup,
        }), {
          headers: { "Content-Type": "application/json", ...corsHeaders },
        });
      }

      if (action === "cleanup_all_images") {
        const actionUserId = await authenticatedUserId(req);
        if (!actionUserId) {
          return new Response(JSON.stringify({ error: "未授权" }), {
            status: 401, headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        }

        const result = await cleanupAllUserImages(supabase, actionUserId);
        const completed = result.failed === 0 && result.deadLetter === 0 && result.remaining === 0;
        return new Response(JSON.stringify({
          status: completed ? "ok" : "pending",
          deleted: result.processed,
          queued: result.queued,
          failed: result.failed,
          dead_letter: result.deadLetter,
          remaining: result.remaining,
          skipped_external: result.skippedExternal,
          total: result.total,
        }), {
          status: completed ? 200 : 202,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        });
      }

      if (action === "delete_account") {
        const actionUserId = await authenticatedUserId(req);
        if (!actionUserId) {
          return new Response(JSON.stringify({ error: "未授权" }), {
            status: 401, headers: { "Content-Type": "application/json", ...corsHeaders },
          });
        }

        const requestedAt = new Date().toISOString();
        const { error: requestError } = await supabase.from("account_deletion_requests").upsert({
          user_id: actionUserId,
          status: "requested",
          requested_at: requestedAt,
          updated_at: requestedAt,
          completed_at: null,
          attempts: 0,
          next_retry_at: null,
          last_error: null,
        }, { onConflict: "user_id" });
        if (requestError) {
          throw new Error(`Failed to create account deletion request: ${requestError.message}`);
        }

        const { error: deactivateError } = await supabase.from("user_configs").update({
          is_active: false,
          upload_token: null,
          updated_at: requestedAt,
        }).eq("user_id", actionUserId);
        if (deactivateError) {
          throw new Error(`Failed to deactivate account credentials: ${deactivateError.message}`);
        }

        const { data: workerInvoked, error: workerInvokeError } = await supabase.rpc("invoke_image_cleanup_worker");
        if (workerInvokeError || workerInvoked !== true) {
          console.warn("Account deletion worker will rely on the next scheduled run", {
            error_code: workerInvokeError?.code ?? null,
          });
        }

        return new Response(JSON.stringify({
          status: "deletion_pending",
          message: "账户删除已提交，剩余云端原图将在后台清理，完成后自动删除账户。",
          cleanup: null,
          worker_invoked: workerInvoked === true,
        }), {
          status: 202,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        });
      }

      return new Response(JSON.stringify({ error: `不支持的操作：${String(action ?? "")}` }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    // 1. 接收图片（multipart/form-data，字段名 image）
    const form = await req.formData();
    responseMode = normalizeResponseMode(form.get("response_mode")) === "text" ? "text" : responseMode;
    const testMeta = buildTestMeta(form);
    timings.mark("form_parse");
    // ── 身份校验（三级优先级）──
    // 1. JWT 优先：从 Authorization 头解析真实 user_id
    // 2. upload_token：通过 user_configs 反查 user_id
    // 3. 都没有：401 拒绝
    let userId: string | null = null;
    const authHeader = req.headers.get("Authorization") || "";
    const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";

    // 尝试 JWT 验证（仅当 Bearer token 不是 anon key 时）
    if (bearerToken) {
      const anonKey = getEnvOptional("ANON_PUBLIC_KEY");
      if (anonKey && bearerToken !== anonKey) {
        try {
          const userClient = createClient(getEnv("SUPABASE_URL"), anonKey, {
            global: { headers: { Authorization: authHeader } },
          });
          const { data: { user: jwtUser }, error: jwtErr } = await userClient.auth.getUser();
          if (!jwtErr && jwtUser) {
            userId = jwtUser.id;
          }
        } catch {
          // JWT 解析失败，静默跳过，走 upload_token 降级
        }
      }
    }

    // JWT 成功：如果 form 里也传了 user_id，必须和 JWT 一致
    if (userId) {
      const formUserId = normalizeString(form.get("user_id"));
      if (formUserId && formUserId !== userId) {
        return respondShortcut(
          { error: "user_id 与登录身份不匹配" },
          { mode: responseMode, status: 401 }
        );
      }
    } else {
      // 没有 JWT，尝试 upload_token 反查
      const uploadToken = normalizeString(form.get("upload_token"));
      if (uploadToken) {
        const { data: rawConfig } = await supabase.from("user_configs")
          .select("user_id")
          .eq("upload_token", uploadToken)
          .eq("is_active", true)
          .maybeSingle();
        const config = rawConfig as UploadTokenConfigRow | null;
        if (config) userId = config.user_id;
      }

      // 既没有有效 JWT，也没有有效 upload_token，拒绝请求
      if (!userId) {
        return respondShortcut(
          { error: "缺少有效身份信息：请通过登录或 upload_token 认证" },
          { mode: responseMode, status: 401 }
        );
      }
    }

    const { count: deletionRequestCount, error: deletionRequestError } = await supabase
      .from("account_deletion_requests")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .in("status", ["requested", "cleaning", "deleting", "failed"]);
    if (deletionRequestError) {
      throw new Error(`Failed to verify account deletion state: ${deletionRequestError.message}`);
    }
    if ((deletionRequestCount ?? 0) > 0) {
      return respondShortcut(
        { error: "账户已停用或正在删除，不能继续上传" },
        { mode: responseMode, status: 410 },
      );
    }

    let companionSettings: CompanionSettings = DEFAULT_COMPANION_SETTINGS;
    let companionContextPromise: Promise<CompanionContext> = Promise.resolve({
      settings: DEFAULT_COMPANION_SETTINGS,
      memory: null,
    });
    // 信号层画像:与 companion context 并行加载,零额外等待
    let domainProfilesPromise: Promise<DomainProfilesMap> = Promise.resolve({});
    let photoVisionPrimary: string | null = "qwen";

    // 用户级 Qwen 模型偏好。
    // 取值 auto 表示跟随平台默认；其它强制指定 provider 优先
    if (userId) {
      const { data: rawPreferenceRow } = await supabase.from("user_configs")
        .select("is_active, vision_primary, screenshot_vision_primary, photo_vision_primary, qwen_screenshot_model, qwen_photo_model, qwen_screenshot_enable_thinking, qwen_photo_enable_thinking, companion_enabled, companion_memory_enabled, companion_persona, companion_memory_strength, companion_expression_style, companion_custom_note, ai_logs_enabled, prompt_optimization_enabled, expression_improvement_enabled, keep_source_images, image_retention_days")
        .eq("user_id", userId)
        .maybeSingle();
      const prefRow = rawPreferenceRow as UserPreferenceRow | null;
      if (prefRow?.is_active === false) {
        return respondShortcut(
          { error: "账户已停用或正在删除，不能继续上传" },
          { mode: responseMode, status: 410 },
        );
      }
      // 读取隐私配置
      privacyConfig = {
        aiLogsEnabled: prefRow?.ai_logs_enabled ?? false,
        promptOptimizationEnabled: prefRow?.prompt_optimization_enabled ?? false,
        expressionImprovementEnabled: prefRow?.expression_improvement_enabled ?? false,
        keepSourceImages: prefRow?.keep_source_images ?? true,
        imageRetentionDays: prefRow?.image_retention_days ?? -1,
      };
      photoVisionPrimary = prefRow?.photo_vision_primary ?? "qwen";
      companionSettings = {
        enabled: prefRow?.companion_enabled ?? true,
        memoryEnabled: prefRow?.companion_memory_enabled ?? true,
        persona: prefRow?.companion_persona ?? "observer",
        memoryStrength: prefRow?.companion_memory_strength ?? "balanced",
        expressionStyle: prefRow?.companion_expression_style ?? "plain",
        customNote: prefRow?.companion_custom_note ?? null,
      };
      const qwenIdx = visionProviders.findIndex((p) => p.name === "qwen");
      if (qwenIdx >= 0 && prefRow) {
        const qwenCfg = visionProviders[qwenIdx];
        visionProviders[qwenIdx] = {
          ...qwenCfg,
          model: normalizeQwenModel(prefRow.qwen_screenshot_model, qwenCfg.model),
          enableThinking: typeof prefRow.qwen_screenshot_enable_thinking === "boolean"
            ? prefRow.qwen_screenshot_enable_thinking
            : qwenCfg.enableThinking,
          photoModel: normalizeQwenModel(prefRow.qwen_photo_model, qwenCfg.photoModel ?? QWEN_PHOTO_DEFAULT_MODEL),
          photoEnableThinking: typeof prefRow.qwen_photo_enable_thinking === "boolean"
            ? prefRow.qwen_photo_enable_thinking
            : qwenCfg.photoEnableThinking,
        };
      }
      companionContextPromise = loadCompanionContext(supabase, userId, companionSettings);
      domainProfilesPromise = loadDomainProfiles(supabase, userId);
    }

    const respondWithExpressionShadow = (
      payload: Record<string, unknown>,
      options: { mode: ShortcutResponseMode; status?: number },
    ): Response => {
      scheduleExpressionShadowCapture(supabase, {
        userId,
        payload,
        responseMode: options.mode,
        improvementConsent: privacyConfig.expressionImprovementEnabled,
      });
      return respondShortcut(payload, options);
    };

    const stagingRetryId = normalizeString(form.get("staging_record_id"));
    let file = form.get("image") as File | null;
    let retryImageBytes: Uint8Array | null = null;
    let retryImageMime = "image/jpeg";
    let retryImagePath: string | null = null;
    let retryImageHash: string | null = null;
    if (stagingRetryId && !file) {
      const { data: rawStagingRow } = await supabase.from("staging_records")
        .select("id,image_path,image_hash,retry_count")
        .eq("id", stagingRetryId)
        .eq("user_id", userId)
        .maybeSingle();
      const stagingRow = rawStagingRow as StagingRetryRow | null;
      if (!stagingRow || !stagingRow.image_path) {
        return respondShortcut({ error: "Staging record not found or missing image" }, { mode: responseMode, status: 404 });
      }
      if ((stagingRow.retry_count || 0) >= 3) {
        return respondShortcut({ error: "Retry limit exceeded (max 3)" }, { mode: responseMode, status: 400 });
      }
      const { data: imgData, error: imgErr } = await supabase.storage.from(BUCKET_NAME).download(stagingRow.image_path);
      if (imgErr || !imgData) {
        return respondShortcut({ error: "Failed to download image: " + (imgErr?.message || "not found") }, { mode: responseMode, status: 500 });
      }
      retryImageBytes = new Uint8Array(await imgData.arrayBuffer());
      if (stagingRow.image_path.endsWith(".png")) retryImageMime = "image/png";
      retryImagePath = stagingRow.image_path;
      retryImageHash = stagingRow.image_hash;
    }
    if (!file && !retryImageBytes) {
      return respondShortcut({ error: "Missing 'image' field" }, { mode: responseMode, status: 400 });
    }
    let bytes: Uint8Array;
    let buf: ArrayBuffer;
    let mime: string;
    if (retryImageBytes) {
      bytes = retryImageBytes;
      buf = Uint8Array.from(bytes).buffer;
      mime = retryImageMime;
    } else {
      buf = await file!.arrayBuffer();
      bytes = new Uint8Array(buf);
      mime = file!.type || "image/jpeg";
    }
    const isRetry = !!stagingRetryId;
    const promptVersion = isRetry ? "platform-v3-builtins-retry" : "platform-v3-builtins";
    const rawText = normalizeText(form.get("ocr_text") ?? form.get("text") ?? form.get("raw_text"));
    const sourceApp = normalizeText(form.get("source_app") ?? form.get("app_name"));
    const captureKind = normalizeText(form.get("capture_kind") ?? form.get("capture_type") ?? form.get("image_source") ?? form.get("media_type"));
    const clientCapturedAt = form.get("client_captured_at") ?? form.get("client_upload_at") ?? form.get("shortcut_time") ?? form.get("captured_at");
    const imageAnalysis = looksLikeCameraCaptureKind(captureKind)
      ? { features: imageFeaturesFromDecoded(null, mime), perceptualHash: null }
      : analyzeImage(bytes, mime);
    const imageFeatures = imageAnalysis.features;
    const perceptualHash = imageAnalysis.perceptualHash;

    // 时间锚点：以请求接收时间为基准，附带北京时区换算；陪伴文案 prompt 需要本地时间感
    const now = new Date();
    const requestReceivedAt = now.toISOString();
    const clientTiming = collectClientTiming(form, requestReceivedAt);
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

    // 2. 计算 hash 去重
    const hash = retryImageHash || await sha256(buf);
    timings.mark("hash");
    let perceptualDistance: number | null = null;
    let perceptualMatch: RankedPerceptualCandidate | null = null;
    const perceptualCandidatesPromise = perceptualHash
      ? withTimeoutFallback(
        loadRecentFinancialPerceptualCandidates(supabase, userId!, stagingRetryId),
        900,
        { candidates: [], financeColumnsAvailable: false } as FinancialPerceptualLookupResult,
        "perceptual_lookup",
      )
      : Promise.resolve({ candidates: [], financeColumnsAvailable: false } as FinancialPerceptualLookupResult);

    let stagingDuplicateBuilder = supabase
      .from("staging_records")
      .select("id,record_type,status")
      .eq("image_hash", hash)
      .eq("user_id", userId)
      .in("status", [
        "unassigned",
        "assigned",
        "failed",
        "unrouted",
        "routed",
        "routing_failed",
        "extracted",
        "pending_review",
        "extraction_failed",
        "schema_failed",
        "ai_error",
      ]);
    if (stagingRetryId) stagingDuplicateBuilder = stagingDuplicateBuilder.neq("id", stagingRetryId);
    const stagingDuplicateQuery = stagingDuplicateBuilder.limit(1).maybeSingle();

    const [transactionDuplicateResult, incomeDuplicateResult, dataDuplicateResult, stagingDuplicateResult] = await Promise.all([
      supabase
        .from("transactions")
        .select("id")
        .eq("image_hash", hash)
        .eq("user_id", userId)
        .limit(1)
        .maybeSingle(),
      supabase
        .from("income_records")
        .select("id")
        .eq("image_hash", hash)
        .eq("user_id", userId)
        .limit(1)
        .maybeSingle(),
      supabase
        .from("data_records")
        .select("id,domain_key")
        .eq("source_image_hash", hash)
        .eq("user_id", userId)
        .limit(1)
        .maybeSingle(),
      stagingDuplicateQuery,
    ]);
    const exactLookupError = transactionDuplicateResult.error
      || incomeDuplicateResult.error
      || dataDuplicateResult.error
      || stagingDuplicateResult.error;
    if (exactLookupError) {
      throw new Error(`Exact duplicate check failed: ${exactLookupError.message}`);
    }
    timings.mark("dup_check");

    const txDup = transactionDuplicateResult.data as IdRow | null;
    if (txDup) {
      const aiLogId = await writeTraceAiLog({
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: null,
        duplicate_kind: "exact_hash",
        status: "duplicate",
        record_type: "expense",
        target_table: "transactions",
        target_id: txDup.id,
        duration_ms: Date.now() - startedAt,
      });
      const _spendSum = await summarizeTodaySpend(supabase, userId);
      return respondWithExpressionShadow(withTraceMeta({
        status: "duplicate", id: txDup.id, record_type: "expense",
        message: "该截图已记账",
        notification: `🔁 该截图已记账过\n${todaySpendLine(_spendSum)}`,
      }, { traceId, aiLogId, captureKind, sourceApp }), { mode: responseMode });
    }
    const incDup = incomeDuplicateResult.data as IdRow | null;
    if (incDup) {
      const aiLogId = await writeTraceAiLog({
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: null,
        duplicate_kind: "exact_hash",
        status: "duplicate",
        record_type: "income",
        target_table: "income_records",
        target_id: incDup.id,
        duration_ms: Date.now() - startedAt,
      });
      const _incSum = await summarizeMonthIncome(supabase, userId);
      return respondWithExpressionShadow(withTraceMeta({
        status: "duplicate", id: incDup.id, record_type: "income",
        message: "该收入截图已记录",
        notification: `🔁 该收入截图已记录过\n${monthIncomeLine(_incSum)}`,
      }, { traceId, aiLogId, captureKind, sourceApp }), { mode: responseMode });
    }
    const dataDup = dataDuplicateResult.data as DataDuplicateRow | null;
    if (dataDup) {
      const aiLogId = await writeTraceAiLog({
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: null,
        duplicate_kind: "exact_hash",
        status: "duplicate",
        record_type: dataDup.domain_key,
        target_table: "data_records",
        target_id: dataDup.id,
        data_record_id: dataDup.id,
        duration_ms: Date.now() - startedAt,
        prompt_version: promptVersion,
      });
      return respondWithExpressionShadow(withTraceMeta({
        status: "duplicate", id: dataDup.id, record_type: dataDup.domain_key,
        message: "该截图已归档",
        notification: `🔁 该截图已归档过 · ${domainNameFromKey(dataDup.domain_key) ?? dataDup.domain_key}`,
      }, { traceId, aiLogId, captureKind, sourceApp }), { mode: responseMode });
    }

    const stagingDup = stagingDuplicateResult.data as StagingDuplicateRow | null;
    if (stagingDup) {
      const aiLogId = await writeTraceAiLog({
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: null,
        duplicate_kind: "exact_hash",
        status: "duplicate",
        record_type: stagingDup.record_type ?? "uncertain",
        target_table: "staging_records",
        target_id: stagingDup.id,
        staging_record_id: stagingDup.id,
        duration_ms: Date.now() - startedAt,
        prompt_version: promptVersion,
      });
      return respondWithExpressionShadow(withTraceMeta({
        status: "duplicate",
        staging_status: stagingDup.status,
        id: stagingDup.id,
        record_type: stagingDup.record_type ?? "uncertain",
        message: "该截图已在待处理中",
        notification: "🔁 该截图已在中转站等待处理",
      }, { traceId, aiLogId, captureKind, sourceApp }), { mode: responseMode });
    }

    const companionContext = await withTimeoutFallback(
      companionContextPromise,
      COMPANION_CONTEXT_TIMEOUT_MS,
      { settings: companionSettings, memory: null },
      "companion_context",
    );
    const domainProfiles = await withTimeoutFallback(
      domainProfilesPromise,
      COMPANION_CONTEXT_TIMEOUT_MS,
      {} as DomainProfilesMap,
      "domain_profiles",
    );
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
    const visionPromptHash = await sha256Short(visionPrompt);

    const dispatcher = await runLowCostDispatcher(supabase, { rawText, sourceApp, imageFeatures, userId });
    timings.mark("dispatcher");
    let duplicateKind: string | null = null;
    let duplicateRefTable: string | null = null;
    let duplicateRefId: string | null = null;

    // 3. 上传到 Storage（重试模式跳过，图片已存在）
    // 隐私控制：keep_source_images=false 时仅以 tmp/ 路径完成识别，并在请求结束前删除
    const storagePath = isRetry ? (retryImagePath!) : `${userId}/${new Date().toISOString().slice(0,10)}/${hash.slice(0,12)}.${mime.includes("png") ? "png" : "jpg"}`;
    const path = (!isRetry && !privacyConfig.keepSourceImages) ? `tmp/${storagePath}` : storagePath;
    if (!privacyConfig.keepSourceImages) {
      temporaryImageCleanup = { userId, path };
    }
    let uploadedNewObject = false;
    const storageUploadPromise = (async () => {
      const uploadStartedAt = Date.now();
      if (isRetry) {
        return { uploaded: false, error: null as Error | null, durationMs: 0 };
      }
      const { error: upErr } = await supabase.storage.from(BUCKET_NAME)
        .upload(path, bytes, { contentType: mime, upsert: false });
      if (upErr && !upErr.message.includes("already exists")) {
        return {
          uploaded: false,
          error: new Error(`Upload failed: ${upErr.message}`),
          durationMs: Date.now() - uploadStartedAt,
        };
      }
      return {
        uploaded: !upErr,
        error: null as Error | null,
        durationMs: Date.now() - uploadStartedAt,
      };
    })();

    // 4. 调用 Qwen Vision 识别。
    //    始终调用，不因低成本路由无匹配而跳过
    let ai: AIResult;
    let aiOk = true;
    let aiErrorMessage: string | null = null;
    let aiProvider: ProviderName = "qwen";
    let aiModel: string = QWEN_DEFAULT_MODEL;
    let visionAttempts: VisionAttempt[] = [];
    let visionRawText: string | null = null;
    let visionExtractedJson: string | null = null;
    let visionResponseId: string | null = null;
    let visionFinishReason: string | null = null;
    let visionReasoningText: string | null = null;
    const usePhotoQualityVision = shouldUsePhotoQualityVision({
      captureKind,
      rawText,
      sourceApp,
      imageFeatures,
      dispatcher,
    });
    const visionMode: "screenshot" | "photo" = usePhotoQualityVision ? "photo" : "screenshot";
    const traceMetaBase = {
      traceId,
      captureKind,
      sourceApp,
      visionMode,
      photoQualityMode: usePhotoQualityVision,
    };
    const activeVisionProviders = selectVisionProvidersForImage(visionProviders, {
      photoPrimary: photoVisionPrimary,
      captureKind,
      rawText,
      sourceApp,
      imageFeatures,
      dispatcher,
    });
    try {
      const visionResult = await callVisionWithFallback(bytes, mime, activeVisionProviders, visionPrompt);
      ai = visionResult.ai;
      aiProvider = visionResult.provider;
      aiModel = visionResult.model;
      visionAttempts = visionResult.attempts;
      visionRawText = visionResult.rawText;
      visionExtractedJson = visionResult.extractedJson;
      visionResponseId = visionResult.responseId ?? null;
      visionFinishReason = visionResult.finishReason ?? null;
      visionReasoningText = visionResult.reasoningText ?? null;
    } catch (e) {
      aiOk = false;
      aiErrorMessage = String(e);
      // 从聚合错误中读出 attempts（如果有）
      const debugError = e as Error & {
        attempts?: VisionAttempt[];
        rawText?: string | null;
        extractedJson?: string | null;
        responseId?: string | null;
        finishReason?: string | null;
        reasoningText?: string | null;
      };
      const attempts = debugError.attempts;
      if (attempts) visionAttempts = attempts;
      visionRawText = debugError.rawText ?? null;
      visionExtractedJson = debugError.extractedJson ?? null;
      visionResponseId = debugError.responseId ?? null;
      visionFinishReason = debugError.finishReason ?? null;
      visionReasoningText = debugError.reasoningText ?? null;
      // 标注最终归属：使用最后一次尝试的 provider，便于排查
      const lastAttempt = visionAttempts[visionAttempts.length - 1];
      if (lastAttempt) {
        aiProvider = lastAttempt.provider;
        aiModel = lastAttempt.model;
      }
      ai = { image_type: "other", record_type: "uncertain", domain_key: null, title: null, summary: null, amount: null, merchant_name: null, platform: null, category: null, payment_method: null, income_category: null, source_name: null, occurred_at: null, order_finished_at: null, payload_jsonb: null, confidence: 0 };
      console.error("All vision providers failed", {
        providers: visionAttempts.map((attempt) => ({
          provider: attempt.provider,
          model: attempt.model,
          duration_ms: attempt.duration_ms,
        })),
      });
    }
    timings.mark("vision_total");
    const storageUpload = await storageUploadPromise;
    timings.record("storage_upload", storageUpload.durationMs);
    if (storageUpload.error) throw storageUpload.error;
    uploadedNewObject = storageUpload.uploaded;
    // 慢请求采样：vision 阶段 > 5s 时打印 warn，方便从函数日志直接搜
    const _visionMs = timings.snapshot().vision_total ?? 0;
    if (_visionMs > 5000) {
      console.warn(`[slow] vision_total=${_visionMs}ms provider=${aiProvider} attempts=${visionAttempts.length}`);
    }
    const responseTraceMeta = (aiLogId?: string | null): TraceResponseMeta => ({
      ...traceMetaBase,
      aiLogId,
      modelProvider: aiProvider,
      modelName: aiModel,
    });

    const normalizedAmount = normalizeAmount(ai.amount);
    const modelRawCompanion = typeof ai.companion_message === "string" ? ai.companion_message : null;
    let normalizedCompanion: string | null = null;
    let contentGuardedCompanion: string | null = null;
    let evidenceGuardedCompanion: string | null = null;
    let companionEvidenceViolations: string[] = [];
    let timeGuardedCompanion: string | null = null;
    let companionFallbackUsed = false;
    let companionFeedbackUsed = false;
    let companionMessage: string | null = null;
    let aiFeedback: AIFeedback | null = null;
    let companionVoiceDebug: {
      enabled: boolean;
      error?: string | null;
      signals?: string[];
      number_violations?: string[];
    } | null = null;
    const companionDebug = () => ({
      model_raw: modelRawCompanion,
      normalized: normalizedCompanion,
      content_guarded: contentGuardedCompanion,
      evidence_guarded: evidenceGuardedCompanion,
      evidence_violations: companionEvidenceViolations,
      time_guarded: timeGuardedCompanion,
      final: companionMessage,
      disabled: !companionSettings.enabled,
      fallback_used: companionFallbackUsed,
      feedback_used: companionFeedbackUsed,
      ai_feedback: aiFeedback,
      voice: companionVoiceDebug,
    });
    const rawDebug = (options: {
      dispatcher?: DispatcherResult | null;
      promptVersionOverride?: string;
      notification?: AiRawDebugPayload["notification"];
    } = {}) => buildAiRawDebug({
      traceId,
      promptVersion: options.promptVersionOverride ?? promptVersion,
      promptHash: visionPromptHash,
      dispatcher: options.dispatcher,
      visionAttempts,
      timings: timings.snapshot(),
      clientTiming,
      visionMode,
      photoQualityMode: usePhotoQualityVision,
      captureKind,
      sourceApp,
      modelRaw: {
        response_id: visionResponseId,
        finish_reason: visionFinishReason,
        text: visionRawText,
        extracted_json: visionExtractedJson,
        reasoning_text: visionReasoningText,
      },
      companion: companionDebug(),
      notification: options.notification,
    });
    // 归一化陪伴文案：去前后空白和引号、压缩换行、截断到 60 字符（约 30 个汉字裕量）
    if (typeof ai.companion_message === "string") {
      const trimmed = ai.companion_message.replace(/[\r\n]+/g, " ").trim().replace(/^["'""''「『]+|["'""''」』]+$/g, "");
      ai.companion_message = trimmed ? trimmed.slice(0, 60) : null;
    } else {
      ai.companion_message = null;
    }
    normalizedCompanion = ai.companion_message;
    if (!companionSettings.enabled) ai.companion_message = null;
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
    if (ai.companion_message && hasModelOwnedStatisticalClaim(ai.companion_message)) {
      ai.companion_message = null;
    }
    ai.companion_message = sanitizeCompanionMessageForContent(ai.companion_message, ai);
    contentGuardedCompanion = ai.companion_message;
    if (ai.companion_message) {
      const evidenceDomainKey = builtinKey ?? recordType;
      const builtPayload = builtinKey ? buildBuiltinPayload(ai)?.payload ?? null : null;
      const evidenceCheck = validateModelTone(
        [ai.companion_message],
        JSON.stringify(voiceRecordFacts(evidenceDomainKey, ai, builtPayload, normalizedAmount)),
      );
      companionEvidenceViolations = evidenceCheck.violations;
      if (!evidenceCheck.ok) ai.companion_message = null;
    }
    evidenceGuardedCompanion = ai.companion_message;
    companionMessage = ai.companion_message;
    const withCompanion = (text: string) => companionMessage ? `${companionMessage}\n${text}` : text;
    const perceptualLookup = await perceptualCandidatesPromise;
    const perceptualStorageAvailable = perceptualLookup.financeColumnsAvailable && Boolean(perceptualHash);
    const accountHint = !builtinKey ? buildAccountHint(ai, recordType) : null;
    const userAccounts = !builtinKey ? await loadUserAccounts(supabase, userId) : [];
    const accountCandidates = !builtinKey ? rankAccountCandidates(userAccounts, accountHint) : [];
    const autoBoundAccount = !builtinKey ? chooseAutoBindAccount(accountCandidates) : null;

    // 重试模式：处理结果后直接返回
    if (isRetry && stagingRetryId) {
      const hasRequiredFinancialAmount = !["expense", "income"].includes(recordType) || normalizedAmount !== null;
      const retryResult = aiOk && (recordType !== "uncertain") && hasRequiredFinancialAmount && (ai.confidence ?? 0) >= 0.5;
      const retryCountRow = (await supabase.from("staging_records")
        .select("retry_count")
        .eq("id", stagingRetryId)
        .eq("user_id", userId)
        .maybeSingle()).data as { retry_count: number | null } | null;
      const retryCount = retryCountRow?.retry_count ?? 0;
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
      timeGuardedCompanion = companionMessage;
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
        timeGuardedCompanion = companionMessage;
        ai.companion_message = companionMessage;
        let aiWithTimeContext: Record<string, unknown> = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
        const recordDate = occurredDateTime?.date ?? today;
        const recordTime = occurredDateTime?.time ?? nowTime;

        if (recordType === "income") {
          const incomeCat = ["salary","bonus","freelance","investment","reimbursement","other"].includes(ai.income_category ?? "") ? ai.income_category! : "other";
          const { data: rawIncomeRow } = await supabase.from("income_records").insert({
            amount: normalizedAmount, category: incomeCat,
            source_name: ai.source_name ?? ai.merchant_name ?? "截图识别收入",
            income_date: recordDate, image_url: path, image_hash: hash,
            ...(perceptualStorageAvailable ? { perceptual_hash: perceptualHash } : {}),
            user_id: userId || null, source: "ai_scan",
            account_id: autoBoundAccount?.id ?? null,
            companion_message: companionMessage,
            ai_feedback: aiFeedback,
          }).select("id").single();
          const incRow = rawIncomeRow as IdRow | null;
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
                if (uploadedNewObject) await cleanupUploadedObjectOrQueue(supabase, userId, path);
                throw entryError;
              }
            }
            archivedTo = "income_records";
            archivedId = incRow.id;
          }
        } else if (builtinKey) {
          const built = buildBuiltinPayload(ai);
          const domain = await getDomainByKey(supabase, builtinKey, userId);
          if (domain && built) {
            const retryFeedback = built.missingFields.length === 0 && (ai.confidence ?? 0) >= 0.75 && companionSettings.enabled
                ? buildBuiltinAIFeedback(builtinKey, built, timeContext, companionMessage)
              : null;
            if (retryFeedback) {
              aiFeedback = retryFeedback;
              companionFeedbackUsed = true;
              companionMessage = retryFeedback.emotion_line;
              ai.companion_message = companionMessage;
              aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
            }
            const { data: rawDataRow } = await supabase.from("data_records").insert({
              domain_id: domain.id, domain_key: builtinKey, domain_version: domain.version ?? "1.0",
              occurred_at: occurredAt, title: built.title, summary: built.summary,
              payload_jsonb: withTestMeta({ ...built.payload, time_context: timeContext, companion_message: companionMessage, ai_feedback: aiFeedback }, testMeta), user_id: userId || null, source: "ai_scan", source_image_path: path, source_image_hash: hash,
            }).select("id").single();
            const dataRow = rawDataRow as IdRow | null;
            if (dataRow) { archivedTo = "data_records"; archivedId = dataRow.id; }
          }
        } else {
          // expense
          const isComplete = normalizedAmount !== null && ai.platform !== null && ai.category !== null && ai.payment_method !== null;
          const { data: rawTransactionRow } = await supabase.from("transactions").insert({
            type: "expense", amount: normalizedAmount,
            merchant_name: ai.merchant_name, platform: ai.platform, category: ai.category,
            payment_method: ai.payment_method, status: isComplete ? "done" : "pending",
            image_url: path, image_hash: hash,
            ...(perceptualStorageAvailable ? { perceptual_hash: perceptualHash } : {}),
            transaction_date: recordDate, transaction_time: recordTime, user_id: userId || null, source: "ai_scan",
            account_id: autoBoundAccount?.id ?? null,
            companion_message: companionMessage,
            ai_feedback: aiFeedback,
          }).select("id").single();
          const txRow = rawTransactionRow as IdRow | null;
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
                if (uploadedNewObject) await cleanupUploadedObjectOrQueue(supabase, userId, path);
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
          }).eq("id", stagingRetryId).eq("user_id", userId);

          const aiLogId = await writeTraceAiLog({
            image_hash: hash, image_url: path, image_type: ai.image_type,
            record_type: recordType, occurred_at: occurredAt, status: "success",
            confidence: ai.confidence ?? 0, duration_ms: Date.now() - startedAt,
            target_table: archivedTo, target_id: archivedId, staging_record_id: stagingRetryId,
            ai_response: aiWithTimeContext, model_provider: aiProvider, model_name: aiModel,
            raw_response: rawDebug({ promptVersionOverride: "platform-v3-builtins-retry" }),
            prompt_version: promptVersion,
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
          fireAndForgetProfileRefresh(supabase, userId, recordType);
          return respondWithExpressionShadow(withTraceMeta({
            status: "done", id: archivedId, record_type: recordType, retry: true,
            message: `✓ 重试成功，已归档到${_retryDomain}`,
            notification: aiFeedback ? feedbackNotification(aiFeedback, _retryNotif) : withCompanion(_retryNotif),
            time_context: timeContext,
            companion_message: companionMessage,
            ai_feedback: aiFeedback,
          }, responseTraceMeta(aiLogId)), { mode: responseMode });
        }
      }

      // 重试失败：更新 staging 记录
      await supabase.from("staging_records").update({
        retry_count: retryCount + 1,
        last_error_type: !aiOk ? "AI_PROVIDER_ERROR" : "RETRY_STILL_UNCERTAIN",
        last_error_message: aiErrorMessage || `重试后仍无法确定（record_type=${recordType}, confidence=${ai.confidence ?? 0}）`,
        ai_summary: ai.record_type ? `重试 → ${ai.record_type} (confidence: ${ai.confidence ?? 0})` : "重试失败",
      }).eq("id", stagingRetryId).eq("user_id", userId);

      const aiLogId = await writeTraceAiLog({
        image_hash: hash, image_url: path, image_type: ai.image_type,
        record_type: recordType, status: !aiOk ? "ai_error" : "pending",
        confidence: ai.confidence ?? 0, duration_ms: Date.now() - startedAt,
        staging_record_id: stagingRetryId, ai_response: retryAiWithTimeContext,
        error_message: aiErrorMessage, model_provider: aiProvider, model_name: aiModel,
        raw_response: rawDebug({
          promptVersionOverride: "platform-v3-builtins-retry",
          notification: {
            final: withCompanion("⚠️ 重试仍未确定\n请打开 App 在待处理中手动归档"),
            source: companionMessage ? "companion" : "base",
            fallback: "⚠️ 重试仍未确定\n请打开 App 在待处理中手动归档",
          },
        }),
        prompt_version: promptVersion,
      });

      return respondWithExpressionShadow(withTraceMeta({
        status: "staging", staging_status: "retry_failed",
        message: "⚠ 重试仍未确定，请手动选择数据域归档",
        notification: withCompanion("⚠️ 重试仍未确定\n请打开 App 在待处理中手动归档"),
        time_context: retryTimeContext,
        companion_message: companionMessage,
      }, responseTraceMeta(aiLogId)), { mode: responseMode });
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
    timeGuardedCompanion = companionMessage;
    ai.companion_message = companionMessage;
    let aiWithTimeContext: Record<string, unknown> = { ...ai, time_context: timeContext };
    const recordDate = occurredDateTime?.date ?? today;
    const recordTime = occurredDateTime?.time ?? nowTime;

    if (!isRetry && perceptualHash && (recordType === "expense" || recordType === "income")) {
      const currentOccurredAt = occurredAt
        || (recordType === "expense" ? transactionOccurredAt(recordDate, recordTime) : null);
      perceptualMatch = findLikelyFinancialDuplicate(perceptualHash, {
        recordType,
        amount: normalizedAmount,
        merchantOrSource: recordType === "income"
          ? ai.source_name ?? ai.merchant_name ?? "截图识别收入"
          : ai.merchant_name ?? null,
        platform: ai.platform ?? null,
        paymentMethod: ai.payment_method ?? null,
        occurredAt: currentOccurredAt,
        occurredDate: recordDate,
        timePrecision: currentOccurredAt ? "datetime" : recordDate ? "date" : "none",
      }, perceptualLookup.candidates);
      if (perceptualMatch) {
        perceptualDistance = perceptualMatch.distance;
        duplicateKind = "perceptual_hash";
        duplicateRefTable = perceptualMatch.referenceTable;
        duplicateRefId = perceptualMatch.referenceId;
      }
    }

    const missingFinancialAmount = !builtinKey && ["expense", "income"].includes(recordType) && normalizedAmount === null;
    if (!aiOk || missingFinancialAmount || (!builtinKey && recordType === "uncertain") || (!builtinKey && (ai.confidence ?? 0) < 0.35 && normalizedAmount === null)) {
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
        testMeta,
      }, privacyConfig);
      const aiLogId = await writeTraceAiLog({
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
        raw_response: rawDebug({ dispatcher }),
        error_message: aiErrorMessage,
        model_provider: aiProvider,
        model_name: aiModel,
        prompt_version: promptVersion,
      });

      const _stgSpend = await summarizeTodaySpend(supabase, userId);
      const _stgAmtPart = normalizedAmount !== null ? `已识别 ${fmtYuan(normalizedAmount)} · ` : "";
      const _stgPrimary = !aiOk
        ? "❌ AI 识别失败，已进入待处理"
        : `⚠️ ${_stgAmtPart}请打开 App 补全`;
      return respondWithExpressionShadow(withTraceMeta({
        status: "staging",
        staging_status: stagingStatus,
        id: staging?.id ?? null,
        ai_ok: aiOk,
        message: !aiOk ? "⚠ AI 识别失败，已进入待处理" : "⚠ 未确定数据域，已进入待处理",
        notification: withCompanion(`${_stgPrimary}\n${todaySpendLine(_stgSpend)}`),
        time_context: timeContext,
        companion_message: companionMessage,
      }, responseTraceMeta(aiLogId)), { mode: responseMode });
    }

    if (builtinKey) {
      const built = buildBuiltinPayload(ai);
      const domain = await getDomainByKey(supabase, builtinKey, userId);
      const fallbackOccurredAt = built ? resolveBuiltinOccurredAt(builtinKey, occurredAt, built.payload) : (occurredAt ?? new Date().toISOString());
      const shouldAutoArchive = Boolean(domain && built && built.missingFields.length === 0 && (ai.confidence ?? 0) >= 0.75);
      if (shouldAutoArchive && built && companionSettings.enabled) {
        // 信号驱动 Voice 层优先:个人画像信号 → 模型翻译;失败/违规 → 规则渲染兜底
        let _voiceCall: VoiceCallResult | null = null;
        if (voiceSignalsEnabled) {
          _voiceCall = await generateVoiceFeedback({
            ai,
            domainKey: builtinKey,
            builtPayload: built.payload,
            normalizedAmount: null,
            domainProfiles,
            timingSignal: timingSignalFor(builtinKey, timeContext),
            clientLocalTime,
            weekday: _weekdayCN,
            persona: companionSettings.persona,
            expressionStyle: companionSettings.expressionStyle,
            customNote: companionSettings.customNote,
            recentCompanionLines: [],
            textProvider,
          });
          if (_voiceCall.duration_ms > 0) {
            console.log(`[feedback] voice ${builtinKey} ok=${!_voiceCall.error} signals=${_voiceCall.signals.map((s) => s.kind).join(",") || "none"} duration=${_voiceCall.duration_ms}ms`);
          }
          companionVoiceDebug = {
            enabled: true,
            error: _voiceCall.error ?? null,
            signals: _voiceCall.signals.map((s) => s.kind),
            number_violations: _voiceCall.number_violations ?? [],
          };
          if (_voiceCall.ai_feedback) {
            aiFeedback = _voiceCall.ai_feedback as AIFeedback;
            companionFeedbackUsed = true;
            companionMessage = _voiceCall.companion_message ?? aiFeedback.emotion_line;
            ai.companion_message = companionMessage;
            aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
          } else if (_voiceCall.companion_message) {
            // ai_feedback 被逐句抢救丢弃,但 companion_message 存活,保留它
            companionMessage = _voiceCall.companion_message;
            ai.companion_message = companionMessage;
            aiWithTimeContext = { ...ai, time_context: timeContext };
          } else {
            // Voice 完全失败,清除视觉模型文案防止幻觉数字泄漏
            companionMessage = null;
            ai.companion_message = null;
          }
        }
        if (!aiFeedback) {
          aiFeedback = voiceSignalsEnabled
            ? buildSignalFallbackAIFeedback(builtinKey, _voiceCall?.signals ?? [], timingSignalFor(builtinKey, timeContext))
            : null;
        }
        if (!aiFeedback) {
          aiFeedback = buildBuiltinAIFeedback(builtinKey, built, timeContext, voiceSignalsEnabled ? null : companionMessage);
          if (aiFeedback) {
            companionFeedbackUsed = true;
            // 仅当 companionMessage 未从 Voice 存活时才用规则兜底的 emotion_line
            if (!companionMessage) {
              companionMessage = aiFeedback.emotion_line;
              ai.companion_message = companionMessage;
            }
            aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
          }
        }
      }
      if (!companionMessage && built) {
        companionMessage = sanitizeCompanionMessageForContent(buildBuiltinCompanionFallback(builtinKey, built), ai);
        companionFallbackUsed = true;
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
          testMeta,
        }, privacyConfig);
        const aiLogId = await writeTraceAiLog({
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
          raw_response: rawDebug({ dispatcher }),
          error_message: !domain ? `data_domains.${builtinKey} 不存在` : null,
          model_provider: aiProvider,
          model_name: aiModel,
          prompt_version: promptVersion,
        });

        const _bDomainName = domainNameFromKey(builtinKey) ?? builtinKey;
        const _bNotif = domain
          ? `⚠️ 已识别为${_bDomainName}\n请打开 App 确认后归档`
          : `⚠️ 未找到对应数据域\n已进入待处理`;
        return respondWithExpressionShadow(withTraceMeta({
          status: "staging",
          staging_status: domain ? "pending_review" : "routing_failed",
          id: staging?.id ?? null,
          record_type: builtinKey,
          ai_ok: aiOk,
          message: domain ? "⚠ 已识别为内置数据域，请确认后归档" : "⚠ 未找到对应数据域，已进入待处理",
          notification: withCompanion(_bNotif),
          time_context: timeContext,
          companion_message: companionMessage,
        }, responseTraceMeta(aiLogId)), { mode: responseMode });
      }

      const { data: rawDataRow, error: dataErr } = await supabase.from("data_records").insert({
        domain_id: domain.id,
        domain_key: builtinKey,
        domain_version: domain.version ?? "1.0",
        occurred_at: fallbackOccurredAt,
        title: built.title,
        summary: built.summary,
        payload_jsonb: withTestMeta({ ...built.payload, time_context: timeContext, companion_message: companionMessage, ai_feedback: aiFeedback }, testMeta),
        user_id: userId || null,
        source: "ai_scan",
        source_image_path: path,
        source_image_hash: hash,
      }).select().single();
      timings.mark("db_insert");

      if (dataErr) {
        await writeTraceAiLog({
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
          raw_response: rawDebug({ dispatcher }),
          error_message: dataErr.message,
          model_provider: aiProvider,
          model_name: aiModel,
          prompt_version: promptVersion,
        });
        if (uploadedNewObject) {
          await cleanupUploadedObjectOrQueue(supabase, userId, path);
        }
        throw new Error(`Data record insert failed: ${dataErr.message}`);
      }
      const row = rawDataRow as InsertedRecordRow;

      const aiLogId = await writeTraceAiLog({
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
        raw_response: rawDebug({ dispatcher }),
        error_message: aiErrorMessage,
        model_provider: aiProvider,
        model_name: aiModel,
        prompt_version: promptVersion,
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
      fireAndForgetProfileRefresh(supabase, userId, builtinKey);

      const _domainEmoji = builtinKey === "sport" ? "🏃" : builtinKey === "sleep" ? "🌙" : builtinKey === "reading" ? "📚" : builtinKey === "food" ? "🍱" : "✓";
      const _domainDoneNotif = `${_domainEmoji} 已归档到${domainNameFromKey(builtinKey) ?? builtinKey}`;
      return respondWithExpressionShadow(withTraceMeta({
        status: "done",
        id: row.id,
        record_type: builtinKey,
        ai_ok: aiOk,
        message: `✓ ${domainNameFromKey(builtinKey) ?? "记录"}已归档`,
        notification: aiFeedback ? feedbackNotification(aiFeedback, _domainDoneNotif, { preserveFallbackAll: true }) : withCompanion(_domainDoneNotif),
        time_context: timeContext,
        companion_message: companionMessage,
        ai_feedback: aiFeedback,
        data: row,
      }, responseTraceMeta(aiLogId)), { mode: responseMode });
    }

    if (perceptualMatch && (recordType === "expense" || recordType === "income")) {
      if (companionSettings.enabled) {
        const baseDuplicateFeedback = recordType === "expense"
          ? buildExpenseAIFeedback(ai, normalizedAmount, timeContext, true)
          : buildIncomeAIFeedback(ai, normalizedAmount, timeContext);
        aiFeedback = baseDuplicateFeedback && recordType === "income"
          ? {
            ...baseDuplicateFeedback,
            badge: "疑似重复",
            band: "watch",
            tone: "verify_gently",
            utility_line: "轻确认：对照原图，确认这是另一笔收入再收下。",
            detail_reason: "图片与已有收入记录相似，需要人工确认是否重复。",
          }
          : baseDuplicateFeedback;
        if (aiFeedback) {
          companionFeedbackUsed = true;
          companionMessage = aiFeedback.emotion_line;
          ai.companion_message = companionMessage;
          aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
        }
      }
      const duplicateReview = {
        kind: "perceptual_hash" as const,
        distance: perceptualMatch.distance,
        referenceTable: perceptualMatch.referenceTable,
        referenceId: perceptualMatch.referenceId,
        recordType,
      };
      const staging = await createStagingRecord(supabase, {
        status: "pending_review",
        imagePath: path,
        imageHash: hash,
        perceptualHash,
        ai,
        occurredAt,
        orderFinishedAt,
        errorType: "POSSIBLE_DUPLICATE",
        errorMessage: "图片和已有记录相似，请确认是否为同一笔",
        dispatcher,
        userId,
        timeContext,
        testMeta,
        aiFeedback,
        companionMessage,
        duplicateReview,
      }, privacyConfig);
      if (!staging) throw new Error("Failed to create possible-duplicate review record");

      const aiLogId = await writeTraceAiLog({
        image_hash: hash,
        perceptual_hash: perceptualHash,
        perceptual_distance: perceptualMatch.distance,
        image_url: path,
        image_type: ai.image_type,
        record_type: recordType,
        occurred_at: occurredAt,
        order_finished_at: orderFinishedAt,
        duplicate_kind: "perceptual_hash",
        duplicate_ref_table: perceptualMatch.referenceTable,
        duplicate_ref_id: perceptualMatch.referenceId,
        target_table: "staging_records",
        target_id: staging.id,
        staging_record_id: staging.id,
        status: "pending",
        confidence: ai.confidence ?? 0,
        duration_ms: Date.now() - startedAt,
        ai_response: aiWithTimeContext,
        error_message: null,
        model_provider: aiProvider,
        model_name: aiModel,
        raw_response: rawDebug({ dispatcher }),
        prompt_version: promptVersion,
      });

      const retainedEvidenceMessage = privacyConfig.keepSourceImages
        ? "图片已保留并等待确认"
        : "文字事实已保留，原图会按你的设置删除";

      return respondWithExpressionShadow(withTraceMeta({
        status: "staging",
        staging_status: "pending_review",
        id: staging.id,
        record_type: recordType,
        ai_ok: aiOk,
        possible_duplicate: true,
        duplicate_ref_table: perceptualMatch.referenceTable,
        duplicate_ref_id: perceptualMatch.referenceId,
        message: `发现相似记录，${retainedEvidenceMessage}`,
        notification: withCompanion(`⚠️ 这张图可能和已有记录重复\n${retainedEvidenceMessage}`),
        time_context: timeContext,
        companion_message: companionMessage,
        ai_feedback: aiFeedback,
      }, responseTraceMeta(aiLogId)), { mode: responseMode });
    }

    if (recordType === "income" && normalizedAmount !== null && (ai.confidence ?? 0) >= 0.7) {
      const incomeCategory = ["salary", "bonus", "freelance", "investment", "reimbursement", "other"].includes(ai.income_category ?? "")
        ? ai.income_category
        : "other";
      const sourceName = ai.source_name ?? ai.merchant_name ?? "截图识别收入";

      if (companionSettings.enabled) {
        const _secondCallIncome = voiceSignalsEnabled
          ? await generateVoiceFeedback({
            ai,
            domainKey: "income",
            builtPayload: null,
            normalizedAmount,
            domainProfiles,
            timingSignal: timingSignalFor("income", timeContext),
            clientLocalTime,
            weekday: _weekdayCN,
            persona: companionSettings.persona,
            expressionStyle: companionSettings.expressionStyle,
            customNote: companionSettings.customNote,
            recentCompanionLines: [],
            textProvider,
          })
          : await regenerateFeedbackWithSecondCall({
            ai,
            domainKey: "income",
            builtPayload: null,
            timeContext,
            timingSignal: timingSignalFor("income", timeContext),
            promptCtx: {
              clientLocalTime,
              weekday: _weekdayCN,
              memoryEnabled: companionSettings.memoryEnabled,
              memoryStrength: companionSettings.memoryStrength,
              expressionStyle: companionSettings.expressionStyle,
              persona: companionSettings.persona,
              customNote: companionSettings.customNote,
              memory: companionContext.memory,
              recentCompanionLines: [],
            },
            textProvider,
          });
        if (_secondCallIncome.duration_ms > 0) {
          console.log(`[feedback] second_call income ok=${!_secondCallIncome.error} duration=${_secondCallIncome.duration_ms}ms`);
        }
        if (voiceSignalsEnabled) {
          const voiceCall = _secondCallIncome as VoiceCallResult;
          companionVoiceDebug = {
            enabled: true,
            error: voiceCall.error ?? null,
            signals: voiceCall.signals.map((signal) => signal.kind),
            number_violations: voiceCall.number_violations ?? [],
          };
        }
        if (_secondCallIncome.ai_feedback) {
          aiFeedback = _secondCallIncome.ai_feedback as AIFeedback;
          companionFeedbackUsed = true;
          companionMessage = _secondCallIncome.companion_message || aiFeedback.emotion_line;
          ai.companion_message = companionMessage;
          aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
        } else {
          if (_secondCallIncome.companion_message) {
            companionMessage = _secondCallIncome.companion_message;
            ai.companion_message = companionMessage;
          } else if (voiceSignalsEnabled) {
            companionMessage = null;
            ai.companion_message = null;
          }
          aiFeedback = buildIncomeAIFeedback(
            voiceSignalsEnabled ? { ...ai, companion_message: null } : ai,
            normalizedAmount,
            timeContext,
          );
          if (aiFeedback) {
            companionFeedbackUsed = true;
            companionMessage = companionMessage ?? aiFeedback.emotion_line;
            ai.companion_message = companionMessage;
            aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
          }
        }
      }

      const { data: rawIncomeRow, error: incErr } = await supabase.from("income_records").insert({
        amount: normalizedAmount,
        category: incomeCategory,
        source_name: sourceName,
        income_date: recordDate,
        image_url: path,
        image_hash: hash,
        ...(perceptualStorageAvailable ? { perceptual_hash: perceptualHash } : {}),
        user_id: userId || null,
        source: "ai_scan",
        account_id: autoBoundAccount?.id ?? null,
        note: ai.platform ? `来自${ai.platform}截图识别` : "截图识别收入",
        companion_message: companionMessage,
        ai_feedback: aiFeedback,
      }).select().single();
      timings.mark("db_insert");

      if (incErr) {
        await writeTraceAiLog({
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
          raw_response: rawDebug(),
          prompt_version: promptVersion,
        });
        if (uploadedNewObject) {
          await cleanupUploadedObjectOrQueue(supabase, userId, path);
        }
        throw new Error(`Income insert failed: ${incErr.message}`);
      }
      const row = rawIncomeRow as InsertedRecordRow;

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
          if (uploadedNewObject) await cleanupUploadedObjectOrQueue(supabase, userId, path);
          throw entryError;
        }
      }

      const aiLogId = await writeTraceAiLog({
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
        raw_response: rawDebug(),
        prompt_version: promptVersion,
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
      return respondWithExpressionShadow(withTraceMeta({
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
      }, responseTraceMeta(aiLogId)), { mode: responseMode });
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
        .eq("user_id", userId)
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
      const dup = ((candidates ?? []) as TransactionCandidateRow[]).find((item) => {
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
      // 第二次调用:信号驱动 Voice 层(事实→信号→语言);VOICE_SIGNALS_ENABLED=false 可回退旧链路
      const _secondCall = voiceSignalsEnabled
        ? await generateVoiceFeedback({
          ai,
          domainKey: "expense",
          builtPayload: null,
          normalizedAmount,
          domainProfiles,
          timingSignal: timingSignalFor("expense", timeContext),
          clientLocalTime,
          weekday: _weekdayCN,
          persona: companionSettings.persona,
          expressionStyle: companionSettings.expressionStyle,
          customNote: companionSettings.customNote,
          recentCompanionLines: [],
          textProvider,
        })
        : await regenerateFeedbackWithSecondCall({
          ai,
          domainKey: "expense",
          builtPayload: null,
          timeContext,
          timingSignal: timingSignalFor("expense", timeContext),
          promptCtx: {
            clientLocalTime,
            weekday: _weekdayCN,
            memoryEnabled: companionSettings.memoryEnabled,
            memoryStrength: companionSettings.memoryStrength,
            expressionStyle: companionSettings.expressionStyle,
            persona: companionSettings.persona,
            customNote: companionSettings.customNote,
            memory: companionContext.memory,
            recentCompanionLines: [],
          },
          textProvider,
        });
      if (_secondCall.duration_ms > 0) {
        console.log(`[feedback] second_call expense ok=${!_secondCall.error} duration=${_secondCall.duration_ms}ms`);
      }
      if (voiceSignalsEnabled) {
        const voiceCall = _secondCall as VoiceCallResult;
        companionVoiceDebug = {
          enabled: true,
          error: voiceCall.error ?? null,
          signals: voiceCall.signals.map((signal) => signal.kind),
          number_violations: voiceCall.number_violations ?? [],
        };
      }
      // 如果二次调用成功产出有效反馈，优先使用；否则回退到规则生成
      if (_secondCall.ai_feedback) {
        aiFeedback = _secondCall.ai_feedback as AIFeedback;
        companionFeedbackUsed = true;
        if (_secondCall.companion_message) {
          companionMessage = _secondCall.companion_message;
        } else {
          companionMessage = aiFeedback.emotion_line;
        }
        ai.companion_message = companionMessage;
        aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
      } else {
        // Voice 未产出 ai_feedback(完全失败或逐句抢救只存活 companion)
        // 先回收存活的 companion_message,防止视觉模型幻觉文案残留
        if (_secondCall.companion_message) {
          companionMessage = _secondCall.companion_message;
          ai.companion_message = companionMessage;
        } else if (voiceSignalsEnabled) {
          // Voice 完全失败,清除视觉模型文案防止幻觉数字泄漏
          companionMessage = null;
          ai.companion_message = null;
        }
        aiFeedback = voiceSignalsEnabled
          ? buildSignalFallbackAIFeedback(
            "expense",
            (_secondCall as VoiceCallResult).signals,
            timingSignalFor("expense", timeContext),
          )
          : null;
      }
      if (!aiFeedback) {
        aiFeedback = buildExpenseAIFeedback(
          voiceSignalsEnabled ? { ...ai, companion_message: null } : ai,
          normalizedAmount,
          timeContext,
          possibleDuplicate,
        );
      }
      // aiWithTimeContext 在上方已初始化(非 null),原 `if (!aiWithTimeContext)` 为死代码。
      // 改为:Voice 未产出 ai_feedback 时,确保规则兜底的 aiFeedback 写入上下文。
      if (!_secondCall.ai_feedback && aiFeedback) {
        companionFeedbackUsed = true;
        // companionMessage 未从 Voice 存活时,用规则兜底的 emotion_line
        if (!companionMessage) {
          companionMessage = aiFeedback.emotion_line;
          ai.companion_message = companionMessage;
        }
        aiWithTimeContext = { ...ai, time_context: timeContext, ai_feedback: aiFeedback };
      }
    }

    // 6. 写入数据库
    const { data: rawTransactionRow, error: insErr } = await supabase.from("transactions").insert({
      type: "expense",
      amount: normalizedAmount,
      merchant_name: ai.merchant_name,
      platform: ai.platform,
      category: ai.category,
      payment_method: ai.payment_method,
      status: normalizedAmount === null ? "pending" : status,
      image_url: path,
      image_hash: hash,
      ...(perceptualStorageAvailable ? { perceptual_hash: perceptualHash } : {}),
      user_id: userId || null,
      is_large_transport: isLargeTransport,
      transaction_date: recordDate,
      transaction_time: recordTime,
      source: "ai_scan",
      account_id: autoBoundAccount?.id ?? null,
      companion_message: companionMessage,
      ai_feedback: aiFeedback,
    }).select().single();
    timings.mark("db_insert");

    if (insErr) {
      await writeTraceAiLog({
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
        raw_response: rawDebug(),
        prompt_version: promptVersion,
      });
      if (uploadedNewObject) {
        await cleanupUploadedObjectOrQueue(supabase, userId, path);
      }
      throw new Error(`DB insert failed: ${insErr.message}`);
    }
    const row = rawTransactionRow as InsertedRecordRow;

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
        if (uploadedNewObject) await cleanupUploadedObjectOrQueue(supabase, userId, path);
        throw entryError;
      }
    }

    const aiLogId = await writeTraceAiLog({
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
      status: aiOk ? (row.status === "done" ? "success" : "pending") : "ai_error",
      confidence: ai.confidence ?? 0,
      duration_ms: Date.now() - startedAt,
      ai_response: aiWithTimeContext,
      error_message: aiErrorMessage,
      model_provider: aiProvider,
      model_name: aiModel,
      raw_response: rawDebug(),
      prompt_version: promptVersion,
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
    fireAndForgetProfileRefresh(supabase, userId, "expense");

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
    return respondWithExpressionShadow(withTraceMeta({
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
    }, responseTraceMeta(aiLogId)), { mode: responseMode });

  } catch (e) {
    console.error("Ingest request failed", {
      trace_id: requestTraceId,
      error_type: e instanceof Error ? e.name : typeof e,
    });
    return respondShortcut({
      trace_id: requestTraceId,
      ai_log_id: lastAiLogId,
      error: String(e),
    }, { mode: responseMode, status: 500 });
  } finally {
    if (temporaryImageCleanup) {
      const { userId, path } = temporaryImageCleanup;
      try {
        await enqueueImageCleanup(supabase, userId, [path], "immediate");
        const cleanup = await processImageCleanupQueue(supabase, {
          userId,
          bucketPath: path,
          limit: 1,
          force: true,
        });
        if (cleanup.failed > 0 || cleanup.remaining > 0) {
          console.error("Temporary source image cleanup incomplete", { cleanup });
        }
      } catch (cleanupError) {
        console.error("Temporary source image cleanup failed", {
          error_type: cleanupError instanceof Error ? cleanupError.name : typeof cleanupError,
        });
      }
    }
  }
});
