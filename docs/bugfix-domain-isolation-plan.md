# 执行计划：系统域 user_id 隔离修复

> 日期：2026-06-27
> 状态：待确认
> 前置条件：已通过只读分析确认全部问题根因

## 一、问题总结

| 序号 | 问题 | 类型 | 严重程度 |
|---|---|---|---|
| P1 | 5 个系统域的 user_id 被错误绑定到 602a1568 | 数据问题 | 高 |
| P2 | getDomainByKey 查询不按 is_system + user_id 过滤 | 代码问题 | 高 |
| P3 | runLowCostDispatcher 查询所有 active 域不按 user_id 过滤 | 代码问题 | 中 |
| P4 | Edge Function 不校验 user_id 有效性 | 代码问题 | 中 |
| P5 | 测试脚本默认 user_id 用了 upload_token 值 | 工具问题 | 低 |

## 二、改动范围

| 文件 | 改动内容 | 风险 |
|---|---|---|
| `supabase/migrations/XXX_fix_system_domain_user_id.sql` | 新建 migration，修正系统域 user_id | 低，精确 WHERE 条件 |
| `supabase/functions/ingest-receipt/index.ts` | 修改 getDomainByKey + dispatcher 查询 + user_id 校验 | 中，核心链路 |
| `scripts/test-ingest-receipt.mjs` | 修正默认测试 user_id | 低 |

## 三、详细任务拆解

### 任务 1：修复系统域 user_id（数据修复 SQL）

**目标**：把 5 个 is_system=true 但 user_id 不为 null 的系统域，user_id 清回 null

**SQL 逻辑**：
```sql
-- 修正系统域 user_id：is_system=true 的域应为共享域，user_id 必须为 null
UPDATE public.data_domains
   SET user_id = NULL,
       updated_at = now()
 WHERE is_system = true
   AND user_id IS NOT NULL;
```

**验证 SQL**（修复后执行，应返回 0 行）：
```sql
SELECT id, key, name, user_id, is_system
  FROM public.data_domains
 WHERE is_system = true AND user_id IS NOT NULL;
```

**风险控制**：
- WHERE 条件 `is_system = true AND user_id IS NOT NULL` 精确锁定，不会误伤私有域
- 修复后 food/wallet 不受影响（本来就是 null）
- expense/income/sport/sleep/reading 的 user_id 从 602a1568 改为 null

**影响范围**：
- `data_records` 里已有记录的 domain_id 不变（它们指向的还是同一个域 ID）
- RLS 策略 `domains_user_select` 的 `is_system = true` 条件本来就让所有人可读，不受影响
- 前端 `domains` 从 `getSystemDomainDefinitions()` 硬编码返回，不依赖 DB 的 user_id

### 任务 2：修复 getDomainByKey（Edge Function 代码）

**当前代码**（index.ts:1244-1260）：
```typescript
async function getDomainByKey(supabase, key) {
  const { data, error } = await supabase
    .from("data_domains")
    .select("id,key,version")
    .eq("key", key)
    .eq("status", "active")
    .limit(1)
    .maybeSingle();
  // ...
}
```

**问题**：只按 key 查，取 limit(1) 第一条。多个用户创建同名域时会取到任意一条。

**修复方案**：优先查系统共享域（is_system=true AND user_id IS NULL），查不到再查当前用户的私有域

```typescript
async function getDomainByKey(
  supabase: ReturnType<typeof createClient>,
  key: BuiltinDomainKey,
  userId?: string | null,
): Promise<{ id: string; key: string; version?: string | null } | null> {
  // 1. 优先查系统共享域（is_system=true AND user_id IS NULL）
  const { data: systemDomain, error: sysErr } = await supabase
    .from("data_domains")
    .select("id,key,version")
    .eq("key", key)
    .eq("status", "active")
    .eq("is_system", true)
    .is("user_id", null)
    .maybeSingle();
  if (sysErr) console.error("Domain lookup (system) failed:", sysErr);
  if (systemDomain) return systemDomain;

  // 2. 系统域没有，查当前用户的私有域
  if (userId) {
    const { data: userDomain, error: userErr } = await supabase
      .from("data_domains")
      .select("id,key,version")
      .eq("key", key)
      .eq("status", "active")
      .eq("user_id", userId)
      .maybeSingle();
    if (userErr) console.error("Domain lookup (user) failed:", userErr);
    if (userDomain) return userDomain;
  }

  return null;
}
```

**调用方修改**：
- index.ts:3460 `getDomainByKey(supabase, builtinKey)` → `getDomainByKey(supabase, builtinKey, userId)`
- index.ts:3673 同上

### 任务 3：修复 dispatcher 查询（Edge Function 代码）

**当前代码**（index.ts:1271-1274）：
```typescript
const { data: domains, error } = await supabase
  .from("data_domains")
  .select("key,name,routing_json,status")
  .eq("status", "active");
```

**问题**：查所有 active 域，不区分系统域和私有域，会取到别人的私有域

**修复方案**：查系统域 + 当前用户的私有域

```typescript
// 查系统共享域 + 当前用户私有域
const { data: systemDomains, error: sysErr } = await supabase
  .from("data_domains")
  .select("key,name,routing_json,status")
  .eq("status", "active")
  .eq("is_system", true)
  .is("user_id", null);

let userDomains: typeof systemDomains = [];
if (userId) {
  const { data: uDomains, error: uErr } = await supabase
    .from("data_domains")
    .select("key,name,routing_json,status")
    .eq("status", "active")
    .eq("user_id", userId);
  if (uErr) console.error("Dispatcher user domain load failed:", uErr);
  userDomains = uDomains || [];
}

if (sysErr) console.error("Dispatcher system domain load failed:", sysErr);
const domains = [...(systemDomains || []), ...userDomains];
```

### 任务 4：user_id 校验（Edge Function 代码）

**当前代码**（index.ts:3000-3010）：
```typescript
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
```

**问题**：原代码只检查 user_id 是否存在，不能证明请求者有权使用该 user_id。任何人知道一个有效的 user_id 就可以冒充。

**修复方案**：三级身份校验，JWT > upload_token > 401。

```typescript
let userId: string | null = null;
const authHeader = req.headers.get("Authorization") || "";
const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";

// 1. JWT 优先：从 Authorization 头解析真实 user_id
if (bearerToken) {
  const anonKey = getEnvOptional("ANON_PUBLIC_KEY");
  if (anonKey && bearerToken !== anonKey) {
    const userClient = createClient(getEnv("SUPABASE_URL"), anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: jwtUser }, error: jwtErr } = await userClient.auth.getUser();
    if (!jwtErr && jwtUser) userId = jwtUser.id;
  }
}

// JWT 成功：form.user_id 必须和 JWT 一致
if (userId) {
  const formUserId = normalizeString(form.get("user_id"));
  if (formUserId && formUserId !== userId) {
    return respondShortcut({ error: "user_id 与登录身份不匹配" }, { status: 401 });
  }
} else {
  // 2. 没有 JWT，尝试 upload_token 反查
  const uploadToken = normalizeString(form.get("upload_token"));
  if (uploadToken) {
    const { data: cfg } = await supabase.from("user_configs")
      .select("user_id").eq("upload_token", uploadToken).eq("is_active", true).maybeSingle();
    if (cfg) userId = cfg.user_id;
  }
  // 3. 都没有：401
  if (!userId) {
    return respondShortcut({ error: "缺少有效身份信息" }, { status: 401 });
  }
}
```

**设计决策**：
- JWT 最优先（Web App 场景）：从 Authorization 头解析，form.user_id 必须匹配
- upload_token 次之（快捷指令/测试脚本场景）：通过 user_configs 反查
- form.user_id 不再单独作为身份凭证（仅 JWT 场景下校验一致性）
- 无任何有效身份信息返回 401，不产生 user_id=null 脏数据
- 匿名上传作为独立需求完成设计后，再开放匿名入口

### 任务 5：修正测试脚本默认 user_id（工具修复）

**旧问题**：测试脚本曾把一个真实 `upload_token` 硬编码为默认 user_id。该令牌必须撤销，源码和文档不得保留明文。

**修复**：测试身份必须显式使用临时 JWT 或本地 upload_token，不再提供默认身份，也不单独信任 user_id。

```javascript
// 不提供默认身份；只读取被 Git 忽略的本地环境变量。
const uploadToken = process.env.TEST_RECEIPT_UPLOAD_TOKEN
```

同时修改 `executeCase` 的认证逻辑：优先使用临时测试账号 JWT，也可显式传 upload_token；user_id 只能与 JWT 配合做一致性校验，不能单独作为身份凭据。

```javascript
// user_id 只和 JWT 一起用于一致性校验。
if (context.userId) {
  form.append('user_id', context.userId)
}
if (!context.accessToken && context.uploadToken) {
  form.append('upload_token', context.uploadToken)
}

const authorization = `Bearer ${context.accessToken || context.anonKey}`
```

### 任务 6：设置页面显示 user_id（前端修复）

**当前**：`PageSettings.vue` 只显示 upload_token，不显示 user_id

**修复**：在"账户"区域增加 user_id 显示项

```vue
<!-- PageSettings.vue 账户区域 -->
<div class="settings-item" v-if="store.currentUserId.value">
  <div class="settings-item-icon">号</div>
  <div class="settings-item-content">
    <div class="settings-item-title">用户 ID</div>
    <div class="settings-item-sub" style="word-break:break-all;font-size:11px;">
      {{ store.currentUserId.value }}
    </div>
  </div>
</div>
```

**影响范围**：只读显示，不涉及任何逻辑变更。`store.currentUserId` 在登录后已有值，无需额外接口调用。

## 四、验证标准

### 4.1 数据修复验证
- [ ] 执行修复 SQL 后，`SELECT * FROM data_domains WHERE is_system=true AND user_id IS NOT NULL` 返回 0 行
- [ ] 所有 7 个系统域的 user_id 均为 null

### 4.2 Edge Function 验证（dry-run）
- [ ] 用正确的 upload_token 上传 sport 图片，在 App 里能看到记录
- [ ] 用错误的 user_id 上传，返回 401 错误（报错拒绝）
- [ ] 用无效的 upload_token 上传，返回 401 错误（报错拒绝）
- [ ] 不传 user_id 和 upload_token，返回 401 错误（拒绝无身份请求）

### 4.3 回归验证
- [ ] expense 类型上传仍正常写入 transactions（不依赖域）
- [ ] income 类型上传仍正常写入 income_records

## 五、Git 策略

- 多 commit、少 push
- 拆分方式：
  1. `fix: 修正系统域 user_id 错误绑定`（SQL migration）
  2. `fix: Edge Function 域查询按 is_system 和 user_id 隔离`（index.ts 改动）
  3. `fix: Edge Function 校验 user_id 有效性`（index.ts 改动）
  4. `fix: 测试脚本使用 upload_token 替代 user_id`（脚本改动）
  5. `feat: 设置页面显示 user_id`（前端改动）
- **不 push，不 deploy**，等你确认后再操作

## 六、风险控制

| 风险 | 应对 |
|---|---|
| SQL 误伤私有域 | WHERE 条件精确锁定 is_system=true AND user_id IS NOT NULL |
| Edge Function 改动引入新 bug | 先本地 dry-run 验证，再用单张图真实上传测试 |
| 线上已有数据受影响 | data_records 里的 domain_id 不变，只改 data_domains 的 user_id |
| 部署后发现问题 | migration 可写反向 SQL 恢复；Edge Function 可回退代码 |

## 七、已确认事项

1. ~~**任务 4 的降级策略**~~：已确认采用"报错拒绝"方案，传无效身份信息或无身份信息均返回 401。
2. ~~**任务 5 的测试脚本改动**~~：已确认保留 --user-id 参数但标记"仅限调试"，默认走 upload_token。
3. ~~**执行顺序**~~：已确认如下：
   1. 改 Edge Function 代码（任务 2+3+4：域查询隔离 + user_id 校验）
   2. 准备 SQL migration（任务 1：系统域 user_id 清回 null）
   3. 改测试脚本（任务 5：默认走 upload_token）
   4. 改设置页面（任务 6：显示 user_id）
   5. 本地 build / 静态检查 / 脚本 dry-run
   6. 经用户确认后，push main 触发部署
   7. 部署后用单张 sport 图真实验证
   8. 验证通过后清理之前写错的测试数据
4. ~~**何时 push/deploy**~~：本地验证通过后，经用户确认再 push main。
