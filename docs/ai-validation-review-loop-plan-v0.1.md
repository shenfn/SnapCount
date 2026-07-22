# AI 验证正反馈闭环 — 实施计划书 v0.1

> 状态：已与用户对齐方向，待执行。
> 范围：第 1 步（快回路 + 点评面板一次到位）。第 2-4 步为后续阶段，仅列要点。
> 配套：本文件与 `docs/ai-validation-handoff.md`、`docs/ai-validation-prompt-evaluation-plan-v0.4.md` 一起读。

---

## 1. 背景与动机

SnapCount 当前调 AI 截图识别 prompt 的回路是「改 prompt → 推 main → GitHub Action 部署 EF → 肉眼看结果」，反馈慢、不可累积、改坏了不知道。已有零件（`local-simulate.mjs` 直连 qwen、`test-ingest-receipt.mjs` 过真实 EF、追踪台 UI、`/api/local-simulate` 与 `/api/upload-test` 雏形）大部分就绪，**缺的是闭环的后半段：人工点评 → 问题聚合 → 新旧对比 → 回退兜底**。

实测关键发现（两次跑 `test-cases/food/2026-06-27/001-meal-tray.png`）：
- 视觉识别稳定 **~97 秒**（97157ms / 96970ms），第二次还出现 JSON 解析失败（record_type undefined）。
- 文案生成 < 1.5 秒。
- 瓶颈 100% 是视觉调用的 `enable_thinking=true`（completion_tokens ~3000），**不是"两次调用"**。
- 推论：用户「6-8 秒」诉求的真正杠杆是 **分域关 thinking + 精简 prompt**，不是合并调用。

本计划聚焦先把「快回路 + 当场点评 + 持久化」打通，让调试越多越能定位问题。

---

## 2. 架构总览

```
                  追踪台 UI（操作台）
   ┌──────────────┼──────────────────────┐
   ▼              ▼                       ▼
① 快回路调试   ② 看结果+点评(review)   ③ 版本对比/回退
local-simulate  打分+评论+标签           prompt-history + git tag
本地直连秒级        │
   │                ▼
   │           ④ 问题聚合（第 2 步）
   │      哪些 case 反复被吐槽→改哪段 prompt
   │                │
   └─── 改 prompts.ts ┘
            │
            ▼
   ⑤ 准回路验证（上线前，第 4 步）
   批量 15 张过真实 EF → 确认 → 才部署
```

- **快回路**（日常）：`local-simulate` 直连 qwen，秒级，疯狂试。
- **准回路**（上线前）：`test-ingest-receipt` 过真实 EF，确认没把线上调坏。
- **点评**把"我觉得这个不行"变成可累积、可统计的数据。
- **git 是终极兜底**：`prompts.ts` 在 git 里，打 tag 即可 100% 回退。

---

## 3. 第 1 步：快回路接入 UI + 点评面板

### 3.1 总目标

选图 → 本地秒级出识别 + 文案 + 耗时 → 当场点评 → 存盘可累积 → 列表显示已点评徽标。

### 3.2 数据契约：review.json

**落盘位置**：
- 走 trace 的 run（线上验证或批量）：`test-results/<run-id>/<domain>/<date>/<file>.review.json`（与 `.trace.json` 同目录同名）。
- 单图本地模拟 run（无 trace）：`test-results/<run-id>/single/no-date/<file>.review.json`。
  - `<run-id>` 由 UI 在本地模拟模式下也收集（默认 `manual-sim-YYYYMMDD`）。
  - `<file>` 取上传文件名（去扩展名），粘贴图用 `sim_<timestamp>`。

**结构**（review-v1，覆盖识别 + 文案两维度）：
```json
{
  "schema_version": "review-v1",
  "case_key": "food/2026-06-27/001-meal-tray",
  "run_id": "manual-sim-20260630",
  "reviewed_at": "2026-06-30T12:34:56.000Z",
  "mode": "local-simulate",
  "ratings": {
    "recognition_accuracy": 4,
    "feedback_quality": 3
  },
  "issue_tags": ["ai_feedback_too_generic"],
  "notes": "文案太套话，没有提到具体菜名",
  "suggested_action": "希望文案引用 extracted_json 里的 merchant 字段",
  "sim_snapshot": {
    "elapsed_ms": 97157,
    "vision_model": "qwen3.6-flash",
    "vision_parse_ok": true,
    "feedback_model": "qwen3.6-flash",
    "vision_parsed": { "record_type": "...", "domain_key": "..." },
    "feedback_parsed": { "companion_message": "...", "ai_feedback": "..." }
  }
}
```

- `sim_snapshot` 仅在 `mode=local-simulate` 时填，把当场结果快照进 review，**让 review 自解释**，不依赖 trace 文件存在。
- 走 trace 的 run 不填 `sim_snapshot`，靠同目录 `.trace.json` 提供细节。

**issue_tags 枚举**（复用 V0.4 §4.4，前端做 chip 多选）：

| tag | 含义 |
|---|---|
| `wrong_domain` | 域识别错（如把转账识别成收入） |
| `wrong_amount` | 金额错 |
| `wrong_date` | 日期错 |
| `wrong_category` | 分类错（如餐饮分成购物） |
| `missing_key_field` | 漏关键字段（如缺 merchant / amount） |
| `ai_feedback_too_generic` | AI 文案套话、不具体 |
| `ai_feedback_too_exaggerated` | AI 文案过度夸张 |
| `ai_feedback_wrong_tone` | 文案语气不对 |
| `hallucination` | 模型幻觉（编造不存在的字段） |
| `model_timeout` | 调用超时 |
| `parse_failure` | 模型输出 JSON 解析失败 |
| `other` | 其他（notes 里说明） |

### 3.3 后端改动（`tools/ai-validation/server/index.mjs`）

复用现有 `safeJoinPath`（76-85）、`safeReadJson`（118-125）、runId 正则 `/^[a-zA-Z0-9_-]+$/`（244）、`:caseKey(*)` 通配路由模式（334-352）。

**新增三段路由**（建议插在 `/api/runs/:runId/traces/:caseKey(*)` 之后、`/api/images` 之前，约 368 行处）：

1. `POST /api/runs/:runId/reviews/:caseKey(*)`
   - 请求体：review-v1 对象（不含 `reviewed_at` / `case_key` / `run_id`，由服务端补）。
   - 校验：runId 正则；caseKey 安全校验照搬 342-352；ratings 两个值 1-5 整数；issue_tags 必须在枚举内。
   - 路径：`<runDir>/<caseKey>.review.json`，写前 `mkdir -p` 父目录（复用 `mkdir`，已在 import 列表 29 行）。
   - 用 `writeFile` 写入（已 import 29 行），原子性靠"写临时文件再 rename"可选；初版直接覆盖。
   - 返回 `{ ok: true, path: "<relative>", reviewed_at: "..." }`。

2. `GET /api/runs/:runId/reviews/:caseKey(*)`
   - 读 `<runDir>/<caseKey>.review.json`，不存在返回 404。
   - 返回 review-v1 对象。

3. `GET /api/runs/:runId/reviews`
   - 递归扫描 `<runDir>` 下所有 `.review.json`（复用 `findFilesRecursive`，93-111，传入 `.review.json`）。
   - 返回 `{ reviews: [{ case_key, reviewed_at, ratings, issue_tags, mode, file }] }`（不带 sim_snapshot，省流量）。

**安全约束（沿用）**：
- 只 127.0.0.1。
- runId 正则白名单。
- caseKey 拒绝 `..` / 绝对路径，最终路径必须在 runDir 内。
- 不读 .env，不需要密钥。
- review.json 属测试结果，不提交 GitHub（.gitignore 已忽略 test-results/）。

**list traces 接口增强**（268-325）：
- 在 `/api/runs/:runId/traces` 返回的每个 trace 摘要里，新增 `has_review: boolean` 和 `review_ratings: {recognition_accuracy, feedback_quality} | null`。
- 实现：扫描时同步检查同目录是否存在 `.review.json`，存在就读 ratings 字段（小开销，初版可接受；后续若慢再缓存）。
- 用途：SampleList 列表能直接拿到徽标数据，无需 N+1 请求。

### 3.4 前端 API 封装（`tools/ai-validation/ui/trace-console/src/lib/api.js`）

照搬现有 POST 内联写法（参考 `localSimulate` 89-105、`uploadTest` 155-171）。

新增三个函数：

```js
export async function saveReview(runId, caseKey, payload) {
  // POST /api/runs/:runId/reviews/:caseKey
  // body: { ratings, issue_tags, notes, suggested_action, mode, sim_snapshot? }
  // 返回 { data, error }
}

export function fetchReview(runId, caseKey) {
  // GET，复用 request()
}

export function fetchReviews(runId) {
  // GET /api/runs/:runId/reviews，复用 request()
}
```

注意 `caseKey` 含 `/`，必须 `encodeURIComponent`（参考 62-63 行 `fetchTrace`）。

### 3.5 新建 ReviewPanel.vue（`tools/ai-validation/ui/trace-console/src/components/ReviewPanel.vue`）

**Props**：
- `runId: String`
- `caseKey: String`
- `mode: String`（`'local-simulate'` | `'trace'`）
- `simSnapshot: Object | null`（仅 local-simulate 模式传入，用于快照到 review）

**Emits**：`saved(review)` / `cancel`

**UI 结构**（scoped style + CSS 变量，与现有组件一致）：
1. 两个 1-5 星评分组件（识别准度 / 文案质量），用简单的 5 个按钮 + hover 态，不引第三方库。
2. issue_tags 多选 chip 区（枚举映射成中文 label，复用 formatters.js 风格）。
3. notes 多行文本框（textarea，3-5 行）。
4. suggested_action 单行输入（可选）。
5. 保存 / 取消按钮。

**逻辑**：
- 挂载时调 `fetchReview(runId, caseKey)`，有则回填（实现"刷新还在"）。
- 保存调 `saveReview`，成功后 emit `saved`。
- 状态机：`idle` → `loading`（拉旧）→ `dirty` → `saving` → `saved`。

### 3.6 改 UploadPanel.vue（`tools/ai-validation/ui/trace-console/src/components/UploadPanel.vue`）

**当前问题**：本地模拟结果区（109-142）是裸 `<pre>` JSON，无点评入口；run_id 输入仅线上模式显示（62-70）。

**改动**：

1. **本地模拟模式也显示 run_id 输入**（默认 `manual-sim-YYYYMMDD`），让 review 有地方落盘。
   - 把 62-70 行的 `v-if="!simulateMode"` 改成始终显示，label 区分「批次 ID（线上）/ 模拟批次 ID（本地）」。
   - 默认值在 191-192 行的 `runId.value` 处根据 `simulateMode` 切换。

2. **本地模拟结果区结构化展示**（替换 109-142）：
   - 顶部一行：耗时 / 视觉模型 / 视觉是否解析成功（`parse_ok` 徽标）/ 文案模型。
   - 识别字段卡片：从 `vision_output.parsed` 提取关键字段（record_type / domain_key / amount / merchant / date 等），用键值对展示，而非裸 JSON。
   - 文案卡片：从 `feedback_output.parsed` 提取 `companion_message` / `ai_feedback`，纯文本展示。
   - 折叠的「原始 JSON」区（默认收起，点击展开），保留调试能力。
   - 解析失败时显式标红 `parse_ok: false` + 显示 raw_text 片段。

3. **嵌入 ReviewPanel**：
   - 在结果区底部加 `<ReviewPanel :runId="runId" :caseKey="simCaseKey" mode="local-simulate" :simSnapshot="simSnapshot" @saved="onReviewSaved" />`。
   - `simCaseKey` 计算：`single/no-date/<文件名去扩展名>`。
   - `simSnapshot` 从 `simResult` 提取（耗时、模型、parsed、parse_ok）。
   - 保存成功后不强制刷新，但可 emit 一个事件给父组件（App.vue）用于刷新 SampleList。

### 3.7 改 SampleList.vue（`tools/ai-validation/ui/trace-console/src/components/SampleList.vue`）

**当前**：trace 摘要里有 `has_ai_feedback`（53 行）/ `parse_error`（54 行）两个徽标。

**改动**：
- 在 53-54 行后追加 `<span v-if="t.has_review" class="review-dot" :title="reviewTitle(t)">评 {{ reviewScore(t) }}</span>`。
- `reviewScore(t)` 返回 `t.review_ratings.recognition_accuracy + '/' + t.review_ratings.feedback_quality`。
- 新增 `.review-dot` 样式（仿 `.feedback-dot` 270-277，用绿色 `--accent-green` 或蓝色区分）。
- 这要求 `/api/runs/:runId/traces` 返回的 trace 摘要带 `has_review` / `review_ratings`（见 3.3 末尾）。

### 3.8 改 local-simulate.mjs（`tools/ai-validation/server/local-simulate.mjs`）

**问题一：JSON 解析鲁棒性**（112-127 行 `extractJsonFromText`）
- 当前：先试代码块 → 直接 parse → 首 `{` 到末 `}`。
- 改进：
  1. 先剥除 `<think>...</think>` 标签（thinking 模式输出可能含此标签）。
  2. 代码块 / 直接 parse / 首尾花括号三段式保留。
  3. 全部失败时返回 `{ parse_ok: false, raw_text: text }` 而非 `null`。
- `callVision` / `callFeedback`（133-207）拿到 `parsed` 后，结果对象里显式加 `parse_ok` 字段，让 UI 能直接读到。

**问题二：thinking 开关**（133-169 `callVision`）
- 新增命令行参数 `--no-vision-thinking`（在 35-44 行的参数解析里加）。
- `callVision` 内 `enable_thinking: !noVisionThinking`。
- 输出 JSON 里加 `vision_thinking_enabled: !noVisionThinking`，让 UI 能显示当前是开还是关。
- 这是后续第 4 步提速实验的入口，第 1 步只把开关打好，不默认关。

**问题三：UI 透传开关**
- `/api/local-simulate` POST body 增加 `noVisionThinking?: boolean`（563-612 路由）。
- `runLocalSimulate`（637-684）spawn 时追加 `--no-vision-thinking` 参数（644 行 args 数组）。
- UploadPanel 在本地模拟模式加一个 checkbox「关视觉 thinking（提速实验）」，绑定到 payload。

---

## 4. 第 1 步验收清单

执行人按此逐项打勾：

- [ ] `local-simulate.mjs`：`extractJsonFromText` 处理 `<think>` 标签，失败返回 `{parse_ok:false}`。
- [ ] `local-simulate.mjs`：`--no-vision-thinking` 开关生效，输出含 `vision_thinking_enabled`。
- [ ] `index.mjs`：`POST /api/runs/:runId/reviews/:caseKey` 写盘成功，路径校验通过。
- [ ] `index.mjs`：`GET /api/runs/:runId/reviews/:caseKey` 能读回。
- [ ] `index.mjs`：`GET /api/runs/:runId/reviews` 列出全部 review 摘要。
- [ ] `index.mjs`：`/api/runs/:runId/traces` 摘要带 `has_review` / `review_ratings`。
- [ ] `api.js`：`saveReview` / `fetchReview` / `fetchReviews` 三个函数。
- [ ] `ReviewPanel.vue`：两个星评分 + tag chip + notes + 保存按钮，挂载时回填。
- [ ] `UploadPanel.vue`：本地模拟模式也显示 run_id 输入。
- [ ] `UploadPanel.vue`：结果区结构化展示（耗时 / 模型 / parse_ok / 关键字段 / 文案）。
- [ ] `UploadPanel.vue`：嵌入 ReviewPanel，simSnapshot 正确传入。
- [ ] `UploadPanel.vue`：关 thinking checkbox 透传到后端。
- [ ] `SampleList.vue`：已点评样本显示「评 X/Y」徽标。
- [ ] **端到端**：选 food 图 → 本地模拟 → 出结果 → 点评打分写 notes → 保存 → 刷新页面 → 点评还在 + 列表显示徽标。
- [ ] **提速实验入口**：关 thinking 跑一次，对比耗时（预期大幅下降）。
- [ ] **安全**：review.json 落在 test-results/，不进 git（.gitignore 已忽略）。
- [ ] **不破坏现有**：线上验证模式（非模拟）流程不受影响。

---

## 5. 第 2-4 步要点（后续阶段，本次不实施）

### 第 2 步：问题聚合 + 新旧对比
- 新建 `ReviewSummary.vue`：读 `GET /api/runs/:runId/reviews`，按 issue_tags 统计 TopN，按评分排最差样本。
- 新旧对比：选 baseline / candidate 两个 run，对同 case_key 比 ratings 变化 + 文案 diff。复用 PromptViewer 双栏布局思路。

### 第 3 步：版本对比 + git tag 兜底规范
- `refresh-prompt` 已有历史快照机制（508-545）。补齐 PromptViewer 下拉切历史 diff。
- **git tag 规范**写进 `docs/ai-validation-handoff.md`：满意版本 `git tag prompt-vN`，回退 `git checkout <tag> -- supabase/functions/ingest-receipt/prompts.ts`。

### 第 4 步：用闭环验证提速实验
按实测，提速杠杆排序（大→小）：
1. 分域关 thinking（最大）：用 3.8 的开关在快回路 A/B 出数据。
2. 精简 prompt：现 ~11500 字压到 ~8000。
3. 合并调用：实测只省 <1 秒，**默认不做**。
4. food 域 Observation：实测 food 已 97s，加 thinking 风险极高，用数据再定。

---

## 6. 关键文件清单

| 文件 | 动作 | 说明 |
|---|---|---|
| `tools/ai-validation/server/local-simulate.mjs` | 改 | 鲁棒解析 + `--no-vision-thinking` + 输出 `parse_ok` / `vision_thinking_enabled` |
| `tools/ai-validation/server/index.mjs` | 改 | 新增 3 个 reviews 端点 + traces 摘要带 review 字段 + local-simulate 透传 thinking 开关 |
| `tools/ai-validation/ui/trace-console/src/lib/api.js` | 改 | 新增 `saveReview` / `fetchReview` / `fetchReviews` |
| `tools/ai-validation/ui/trace-console/src/components/ReviewPanel.vue` | 新建 | 点评面板 |
| `tools/ai-validation/ui/trace-console/src/components/UploadPanel.vue` | 改 | run_id 模式切换、结果区结构化、嵌入 ReviewPanel、thinking 开关 checkbox |
| `tools/ai-validation/ui/trace-console/src/components/SampleList.vue` | 改 | 加已点评徽标 |
| `docs/ai-validation-handoff.md` | 改（第 3 步） | 补 git tag 回退规范 |
| `supabase/functions/ingest-receipt/prompts.ts` | 改（第 4 步） | 提速实验，需用户确认才动 |

**复用的现有零件**：
- `safeJoinPath` / `safeReadJson` / `findFilesRecursive` / `sendError`（index.mjs）
- runId 正则 `/^[a-zA-Z0-9_-]+$/`、`:caseKey(*)` 通配路由（index.mjs 244, 334）
- `request()` GET 封装、POST 内联写法（api.js 15-27, 89-105）
- `.feedback-dot` 徽标样式（SampleList.vue 270-277）
- UploadPanel 状态机与轮询逻辑（261-339）

---

## 7. 边界与规则（严格遵守）

- 不提交 `test-cases/`、`test-results/`、`.env*`、密钥、service role key、隐私截图。
- **review.json 属测试结果，不提交 GitHub**（.gitignore 已忽略 test-results/）。
- server 只监听 127.0.0.1，图片接口只允许 test-cases/，不读 .env。
- 准回路真实上传前先 `--dry-run`，只用临时测试账号 JWT 或 `.env.local` 中已轮换的测试上传令牌。
- 改 EF / 推 main / 部署前必须经用户确认。**多 commit，少 push**。
- 第 4 步改 `prompts.ts` 后，线上生效需重新部署 EF（用户确认），且 `npm run trace:extract-prompt` 刷新快照。
- 测试账号不混入日常真实账号。

---

## 8. 端到端验证流程

1. 启动追踪台：项目根 `npm run trace:console`（拉起 server 5181 + UI 5180）。
2. **快回路**：UploadPanel 选「本地模拟」→ 传一张 food 图 → 看识别 JSON + 文案 + 耗时 + parse_ok。
3. **点评**：结果区打两个评分 + 选标签 + 写 notes → 保存 → 刷新页面验证持久化 → SampleList 显示徽标。
4. **提速实验**：勾「关视觉 thinking」再跑一次，对比耗时（预期大幅下降）和识别质量是否退化。
5. **准回路**（用户确认后）：`npm run test:receipt -- --dir test-cases --domain food --run-id <id>` 过真实 EF。
6. **回退**（第 3 步后）：`git tag prompt-vN` + `git checkout <tag> -- prompts.ts` 验证能还原。
