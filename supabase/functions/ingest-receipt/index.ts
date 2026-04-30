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

const PROMPT = `你是移动支付截图与账单记录识别助手。图片可能是以下几种类型，请先判断类型再提取信息：

【图片类型识别】
- payment_confirm：支付成功确认页（有“支付成功”“付款成功”等字样）
- income_confirm：收款成功/已收款确认页（有“你已收款”“收款成功”“资金已存入零钱”“到账成功”等字样）
- wechat_bill：微信账单详情页（有“记录时间”“来源”“备注”字段，灰色背景卡片风格）
- alipay_bill：支付宝账单详情页（有“交易时间”“交易状态”“商家订单号”等字段）
- bank_bill：银行账单/流水页（有银行标志、“账户余额”等）
- other：其他

【通用字段提取规则】

amount（金额）：
- 数字，不带货币符号，无法识别返回 null
- 若显示为负数（如 -16.00），取绝对值（返回 16.00）
- 若是支出页面，同时有“优惠”或“实付”，以实际支付金额为准
- 若是收入页面，以收款/到账/入账金额为准，不要把余额识别为本次收入

merchant_name（商家）：
- 优先从商家名称/收款方/收款账号字段提取
- 若备注/摘要格式为“扫二维码付款-给X”或“转账给X”或“付款给X”，则 X 为商家名
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

只返回如下结构的纯 JSON（不要 markdown 包裹）：
{"image_type":"other","record_type":"uncertain","amount":null,"merchant_name":null,"platform":null,"category":null,"payment_method":null,"income_category":null,"source_name":null,"confidence":0}`;

interface AIResult {
  image_type: string;
  record_type?: "expense" | "income" | "uncertain";
  amount: number | null;
  merchant_name: string | null;
  platform: string | null;
  category: string | null;
  payment_method: string | null;
  income_category?: string | null;
  source_name?: string | null;
  confidence: number;
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
    const { data: txDup } = await supabase
      .from("transactions").select("id").eq("image_hash", hash).maybeSingle();
    if (txDup) {
      return new Response(JSON.stringify({ status: "duplicate", id: txDup.id, record_type: "expense", message: "该截图已记账" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { data: incDup } = await supabase
      .from("income_records").select("id").eq("image_hash", hash).maybeSingle();
    if (incDup) {
      return new Response(JSON.stringify({ status: "duplicate", id: incDup.id, record_type: "income", message: "该收入截图已记录" }), {
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
    try {
      ai = await callKimiVision(bytes, mime, moonshot_key);
    } catch (e) {
      aiOk = false;
      ai = { image_type: "other", record_type: "uncertain", amount: null, merchant_name: null, platform: null, category: null, payment_method: null, income_category: null, source_name: null, confidence: 0 };
      console.error("Kimi Vision failed:", e);
    }

    const normalizedAmount = normalizeAmount(ai.amount);
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    const nowTime = now.toTimeString().slice(0, 8);
    const recordType = ai.record_type ?? "expense";

    if (recordType === "income" && normalizedAmount !== null && (ai.confidence ?? 0) >= 0.7) {
      const incomeCategory = ["salary", "bonus", "freelance", "investment", "reimbursement", "other"].includes(ai.income_category ?? "")
        ? ai.income_category
        : "other";
      const { data: row, error: incErr } = await supabase.from("income_records").insert({
        amount: normalizedAmount,
        category: incomeCategory,
        source_name: ai.source_name ?? ai.merchant_name ?? "截图识别收入",
        income_date: today,
        image_url: path,
        image_hash: hash,
        source: "ai_scan",
        note: ai.platform ? `来自${ai.platform}截图识别` : "截图识别收入",
      }).select().single();

      if (incErr) {
        if (uploadedNewObject) {
          const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
          if (removeErr) console.error("Cleanup uploaded income image failed:", removeErr);
        }
        throw new Error(`Income insert failed: ${incErr.message}`);
      }

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
      let dupQuery = supabase.from("transactions")
        .select("id")
        .eq("transaction_date", today)
        .eq("payment_method", ai.payment_method)
        .gte("amount", (normalizedAmount - 0.01).toFixed(2))
        .lte("amount", (normalizedAmount + 0.01).toFixed(2))
        .gte("created_at", threeMinAgo);
      // 商家名已识别时额外过滤，减少误判；未识别时仅靠金额+支付方式兜底
      if (ai.merchant_name !== null) {
        dupQuery = dupQuery.eq("merchant_name", ai.merchant_name);
      }
      const { data: dup } = await dupQuery.limit(1).maybeSingle();
      if (dup) {
        possibleDuplicate = true;
        dupRefId = dup.id;
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
      transaction_date: today,
      transaction_time: nowTime,
      source: "ai_scan",
    }).select().single();

    if (insErr) {
      if (uploadedNewObject) {
        const { error: removeErr } = await supabase.storage.from(BUCKET_NAME).remove([path]);
        if (removeErr) console.error("Cleanup uploaded image failed:", removeErr);
      }
      throw new Error(`DB insert failed: ${insErr.message}`);
    }

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
