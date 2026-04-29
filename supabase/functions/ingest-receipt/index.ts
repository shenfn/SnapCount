// 随手账 · Edge Function: ingest-receipt
// 部署: supabase functions deploy ingest-receipt --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

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

const PROMPT = `你是移动支付截图识别助手。识别截图中的支付信息，严格返回纯 JSON（不要 markdown 包裹）。

字段要求：
- amount: 数字，不带货币符号，无法识别返回 null
- merchant_name: 商家名称字符串，无法识别返回 null（不要猜测）
- platform: 从中选一个 [美团,微信,京东,拼多多,淘宝,抖音,支付宝,滴滴,饿了么,其他]，无法判断返回 null
  平台识别规则（优先级高于外观判断）：
  * 页面含"先用后付"文字 且 订单号以 PO 开头 → 拼多多
  * 页面含"先用后付"文字 且 订单号以 OD 开头 → 淘宝
- category: 从中选一个 [food,shopping,transport,entertainment,life,health,education,other]
- payment_method: 从中选一个 [微信支付,支付宝,花呗,京东白条,美团月付,拼多多先用后付,银行卡,其他]
  支付方式识别规则：
  * 页面含"先用后付"且平台为拼多多 → 拼多多先用后付
  * 页面含"先用后付"且平台为淘宝/天猫 → 花呗（花呗先用后付）
- confidence: 0-1 浮点数，识别整体置信度

只返回如下结构的 JSON：
{"amount":null,"merchant_name":null,"platform":null,"category":null,"payment_method":null,"confidence":0}`;

interface AIResult {
  amount: number | null;
  merchant_name: string | null;
  platform: string | null;
  category: string | null;
  payment_method: string | null;
  confidence: number;
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
    const { data: dup } = await supabase
      .from("transactions").select("id").eq("image_hash", hash).maybeSingle();
    if (dup) {
      return new Response(JSON.stringify({ status: "duplicate", id: dup.id, message: "该截图已记账" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 3. 上传到 Storage
    const ext  = mime.includes("png") ? "png" : "jpg";
    const path = `${new Date().toISOString().slice(0,10)}/${hash.slice(0,12)}.${ext}`;
    const { error: upErr } = await supabase.storage.from(BUCKET_NAME)
      .upload(path, bytes, { contentType: mime, upsert: false });
    if (upErr && !upErr.message.includes("already exists")) {
      throw new Error(`Upload failed: ${upErr.message}`);
    }
    const { data: signed } = await supabase.storage.from(BUCKET_NAME)
      .createSignedUrl(path, 60 * 60 * 24 * 365); // 1 年有效

    // 4. 调用 Kimi Vision 识别
    let ai: AIResult;
    let aiOk = true;
    try {
      ai = await callKimiVision(bytes, mime, moonshot_key);
    } catch (e) {
      aiOk = false;
      ai = { amount: null, merchant_name: null, platform: null, category: null, payment_method: null, confidence: 0 };
      console.error("Kimi Vision failed:", e);
    }

    // 5. 业务层疑似重复检测：3 分钟内同金额+同支付+同商家 → 标记 possible_duplicate
    //    不阻断入库，允许用户真实的重复消费，仅在响应中提示
    let possibleDuplicate = false;
    let dupRefId: string | null = null;
    if (aiOk && ai.amount !== null && ai.payment_method !== null && ai.merchant_name !== null) {
      const threeMinAgo = new Date(Date.now() - 3 * 60 * 1000).toISOString();
      const today = new Date().toISOString().slice(0, 10);
      const { data: dup } = await supabase.from("transactions")
        .select("id")
        .eq("transaction_date", today)
        .eq("payment_method", ai.payment_method)
        .eq("merchant_name", ai.merchant_name)
        .gte("amount", (ai.amount - 0.01).toFixed(2))
        .lte("amount", (ai.amount + 0.01).toFixed(2))
        .gte("created_at", threeMinAgo)
        .limit(1)
        .maybeSingle();
      if (dup) {
        possibleDuplicate = true;
        dupRefId = dup.id;
      }
    }

    // 6. 判断是否完整
    const isComplete = ai.amount !== null && ai.platform !== null && ai.category !== null && ai.payment_method !== null;
    const status = isComplete && (ai.confidence ?? 0) >= 0.7 ? "done" : "pending";
    const isLargeTransport = ai.category === "transport" && (ai.amount ?? 0) >= 200;

    // 6. 写入数据库
    const now = new Date();
    const { data: row, error: insErr } = await supabase.from("transactions").insert({
      type: "expense",
      amount: ai.amount ?? 0.01,            // 金额识别失败时占位 0.01，由用户改
      merchant_name: ai.merchant_name,
      platform: ai.platform,
      category: ai.category,
      payment_method: ai.payment_method,
      status: ai.amount === null ? "pending" : status,
      image_url: signed?.signedUrl ?? null,
      image_hash: hash,
      is_large_transport: isLargeTransport,
      transaction_date: now.toISOString().slice(0, 10),
      transaction_time: now.toTimeString().slice(0, 8),
      source: "ai_scan",
    }).select().single();

    if (insErr) throw new Error(`DB insert failed: ${insErr.message}`);

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
