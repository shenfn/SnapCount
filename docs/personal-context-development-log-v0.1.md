# Personal Context 开发计划与交接日志 v0.1

> 对应设计：[personal-context-architecture-v0.1.md](./personal-context-architecture-v0.1.md)
> 状态：开发中
> 范围：Supabase Edge Function、Planner/Signals 上下文边界、语义 Memory 读取与测试
> 发布边界：本轮不自动 push、部署或触发 TestFlight；需通过本日志的发布门槛后单独授权

## 1. 目标

把现有“事实/信号/旧 Memory/模型表达”并行链路收敛为：

```text
源记录 → 域画像/当前事实 → Signals/Planner → Context Packet → 表达模型
                         ↘ 语义 Memory（只提供已授权的用户语义）
```

代码负责计算事实、口径、候选和权限；模型只负责在冻结 Packet 内自然表达。

## 2. 不在本轮做的事情

- 不修改原始记录识别字段、交易状态机或账户逻辑；
- 不建立巨型 `personal_profile` JSON 表；
- 不把所有域的候选规则一次性重写；
- 不批量删除现有 `user_companion_memories` 数据；
- 不在未通过回归、Shadow 和单用户 Canary 前做全量生产发布。

## 3. 开发阶段与交付物

### Phase 0：表达链路止血与入口盘点

目标：先消除已知的统计口径误杀和旧入口混用。

任务：

- 明确识别调用、Voice 调用和旧反馈调用的边界；
- 识别调用不得接收短期统计或未经匹配的语义 Memory；
- Voice Prompt 允许引用已选信号事实，但禁止自行计算；
- 数字校验按来源白名单工作，保留对无来源统计的拦截；
- 为三类调用分别增加回归样本和日志字段。

产出：调用入口矩阵、Prompt/Guard 回归测试、已知“第 11 次/第 4 次”样本通过。

### Phase 1：Context Packet 与 Memory 标准化

目标：所有表达入口只消费一个冻结的、带来源的 Packet。

任务：

- 实现 Memory 标准化读取器，不改变数据库表结构；
- 实现实体/域匹配、状态和 claimability 过滤；
- 实现 Packet 版本、内容指纹和 trace；
- 将 `buildPrompt`、`buildVoicePrompt`、`buildFeedbackPrompt` 接到明确的兼容适配层；
- 禁止完整 `get_companion_context` JSON 继续进入模型。

产出：Packet 构造器、旧链路兼容适配、三入口一致性测试。

### Phase 2：语义 Memory 收敛与删除契约

目标：保留用户确认的语义资产，停止统计型 Memory 增长。

任务：

- 停止 `rememberCompanionSignals` 写入可重算的商户/分类统计模式；
- 旧数据按 `user_explicit`、`record_derived`、来源不明分类；
- 加入删除语义的存储、缓存、Packet 和 Surface 失效；
- 提供“芥子对我的理解”只读列表和删除入口；
- 删除不影响原始记录，不恢复旧记忆。

产出：Memory 迁移报告、删除回归测试、最小用户理解页面契约。

### Phase 3：六域契约与学习接入

目标：框架一次性覆盖所有域，生产切换按风险分批进行。

任务：

- 为 expense、sleep、food、sport、reading、wallet 准备正例/拒绝例；
- 统一候选、语义 Memory 和偏好的来源优先级；
- 保留 Planner Shadow，比较旧链路、新 Packet 和规则兜底；
- 记录候选、Memory 命中、表达违规、反馈和删除后再召回指标。

产出：六域契约测试、Shadow 报告、单用户 Canary 清单。

### Phase 4：发布候选与上线

目标：在可回滚的前提下完成闭环。

任务：

- 本地测试、Edge bundle 检查和 GitHub CI；
- 单用户 Canary，至少覆盖 20-30 条真实跨域记录；
- 确认删除理解后所有 Surface 不再命中；
- 确认旧 Memory 统计不会进入任一 Prompt；
- 通过发布评审后再部署生产。

## 4. 每轮交接格式

每轮完成后更新本文件：

```text
日期：YYYY-MM-DD
完成：
修改文件：
测试：
真实样本/回放：
已知风险：
下一轮：
是否允许进入下一阶段：是/否
```

每轮不得把用户素材、凭据、生产导出或无关 WIP 纳入提交。

## 5. 开发前门槛

- [ ] 三类模型入口和 fallback 条件已在代码中定位并有测试；
- [ ] Context Packet 字段、空值、最大规模和来源 trace 已冻结；
- [ ] Memory 删除不会级联删除原始记录；
- [ ] 未确认推断没有 `expressible` 权限；
- [ ] 六域至少各有一条 Packet 契约样本；
- [ ] Shadow、Canary、回滚开关和指标已定义；
- [ ] 未通过以上门槛前不做生产部署。

## 6. 进度

| 阶段 | 状态 | 备注 |
| --- | --- | --- |
| Phase 0 | 已完成 | Edge 入口、数字来源校验和最终 Guard 已通过 CI 并部署 |
| Phase 1 | 已部署观察 | Context Packet、Memory 标准化读取器和 RLS 契约已上线；用户可见表达仍由旧链路承载 |
| Phase 2 | 未开始 | 不批量删除旧数据 |
| Phase 3 | Canary 观察中 | Shadow 已覆盖真实跨域记录，待完成可见输出切换门槛 |
| Phase 4 | 部署完成，未闭环 | migration 与 Edge 已部署；需先修复 Canary 暴露的旧链路问题再全量切换 |

## 7. 2026-08-06 开发记录

完成：

- 新增 `context-packet.ts`：标准化语义 Memory、实体匹配、claimability 过滤和 Packet trace；
- 识别阶段 `buildPrompt` 不再序列化原始 Memory，并明确识别/表达边界；
- Voice Prompt 改为允许忠实转述已核实信号，同时禁止改写时间范围和统计口径；
- Voice 层校验改为传入 signals，允许信号白名单数字，拒绝错误时间窗口；
- 新增 Signals、Context Packet、Prompt 入口契约测试样本。

修改文件：

- `supabase/functions/ingest-receipt/context-packet.ts`
- `supabase/functions/ingest-receipt/context-packet_test.ts`
- `supabase/functions/ingest-receipt/prompts.ts`
- `supabase/functions/ingest-receipt/prompts_test.ts`
- `supabase/functions/ingest-receipt/signals.ts`
- `supabase/functions/ingest-receipt/signals_test.ts`
- `supabase/functions/ingest-receipt/index.ts`

测试：

- `git diff --check` 通过；
- Windows 本机未安装 Deno，Edge `deno test` 未能运行；
- GitHub Actions 的 `deno check` 与 Edge 测试仍是下一验证门槛。

已知风险：

- 旧反馈 fallback 已停止原始 Memory JSON 注入，但尚未在 fallback 分支构造完整 Context Packet；
- `rememberCompanionSignals` 仍会写入派生统计型 Memory，Phase 2 处理；
- 识别阶段目前只切断了 Memory 注入，首轮返回的 companion_message 仍需在后续统一收敛。

下一轮：

- 将 fallback 分支接入 Context Packet；
- 补全三入口的静态契约检查；
- 在 CI 上运行 Deno 类型检查和 Edge 单测。

是否允许进入下一阶段：否，等待 Edge CI 验证和 fallback 接入。

## 8. 2026-08-07 收口记录

完成：

- 修正安全契约门禁：`hasModelOwnedStatisticalClaim` 由 `signals.ts` 负责，门禁不再要求它错误地出现在 `index.ts`；仍检查所有表达入口使用 `validateModelTone`。
- 用 `npx deno` 本机执行与 CI 同口径的 Edge `check` 和 23 项 Signals/Packet/Prompt 测试；识别、Voice、兼容 Feedback 三个入口均通过。
- 将 `get_companion_semantic_memories` 迁移加入 release validation，并扩充安全夹具字段；明确 authenticated 只能 SELECT/DELETE，不能 INSERT/UPDATE，RPC 仅 service role 可执行。
- Context Packet 增加同步内容指纹，trace 保留 Packet 创建时间、候选类型、Memory 加载/过滤数量和选中 Memory ID。
- 保持识别模型的 companion 只进入 debug，不进入用户可见或归档字段；最终文案统一由 Voice/规则链路生成。
- 将内容 Guard 和补录时间 Guard 放到 Voice/兼容表达的最终出口，避免二次调用绕过“禁用套话”和睡眠补录相对日期校正。

修改文件：

- `scripts/check-security-contracts.mjs`
- `scripts/security-migration-fixture.sql`
- `scripts/test-security-migration.sql`
- `.github/workflows/release-validation.yml`
- `supabase/migrations/20260806100000_personal_context_memory_contract.sql`
- `supabase/functions/ingest-receipt/context-packet.ts`
- `supabase/functions/ingest-receipt/context-packet_test.ts`
- `docs/personal-context-architecture-v0.1.md`
- `docs/personal-context-development-log-v0.1.md`

测试：

- `npx deno check --no-lock --node-modules-dir=auto supabase/functions/ingest-receipt/index.ts` 通过；
- `npx deno test --no-lock .../signals_test.ts .../context-packet_test.ts .../prompts_test.ts`：23 passed；
- CI 完整 Edge 测试集合（重复识别、Signals、Packet、Prompt、Shadow、通知）：35 passed；
- `npm run check:security-contracts` 通过；
- `git diff --check` 通过；
- `npm run build`、`npm run test:pending-queue`、`npm run check:receipt-dedup`、迁移版本检查均通过；
- 迁移版本检查、PWA 待处理队列和重复记录契约仍待本轮最终复跑；Windows 尚未直接执行 PostgreSQL 迁移演练，GitHub Actions 仍是数据库门禁权威。

已知风险：

- 新迁移已加入 CI，但当前工作区没有本地 `psql`；需在 GitHub Actions 的 PostgreSQL service 中确认夹具和 RLS 权限行为。
- Planner 仍有部分候选停留在 Shadow/owner-only，Context Packet 已提供统一入口，但未宣称六域候选已全部补齐。
- 本轮未提交、未 push、未部署；根工作区中的用户素材和其他 WIP 未纳入本任务范围。

下一轮：

- 运行完整 release-validation；通过后再做单用户真实回放，重点观察“当前记录主体 + 一个准确候选 + 人格语气”是否同时保留。
- 对删除后的语义 Memory 做线上回放，确认所有 Surface 不再命中，且历史已持久化文案不被误删。

是否允许进入下一阶段：否，等待 GitHub Edge/Postgres CI 和单用户 Canary 结果。

## 9. 2026-08-07 本轮复核

完成：

- 复跑 Edge `deno check` 与完整收件箱/信号/Packet/Prompt/Shadow/通知测试：35 passed；
- 复跑 PWA 构建、安全契约、待处理队列、重复记录契约、财务审核选项、迁移版本和注册同意元数据检查：全部通过；
- 只读复审识别、Voice、兼容 Feedback 三个入口：识别模型的 companion 只保留调试值，表达入口均通过 Context Packet 组装；
- 只读复审语义 Memory RPC 和 RLS：service role 才能读取聚合语义 Memory，authenticated 只能查看/删除，不能 INSERT/UPDATE。

未完成/环境差异：

- Windows 本机没有可被 Planner 测试直接解析的 `esbuild` 包，PowerShell 运行 Planner 测试时有 4 个测试加载失败；其余 84 个 Planner 测试通过。该依赖以 GitHub Actions 的 Linux 安装结果为准，本轮没有修改依赖或绕过测试；
- Windows 没有 `psql`，Docker daemon 未运行，PostgreSQL 迁移与 RLS 演练仍需 CI service；
- 尚未提交、push、部署或执行生产迁移。

Git 阻塞：

- 根工作区仍包含本任务改动和用户无关素材；4 个旧共享 worktree 的 HEAD 指向已消失的分支引用，`git worktree list --porcelain` 显示全零；
- `fsck` 进程已结束，但按 AGENTS.md 规则，在 Git owner 恢复这些异常 worktree 前不执行 `add`、`commit`、`push`、`worktree repair` 或引用清理。

下一轮：

- Git owner 从干净 `origin/main` 建立中文独立 worktree，逐文件转移本轮源码、迁移、测试和文档；
- 在新 worktree 复跑完整 release-validation，重点确认 PostgreSQL 迁移和 RLS；
- CI 通过后再做单用户 20–30 条真实记录 Canary，并决定是否进入生产发布。

是否允许进入下一阶段：否，等待 Git owner 修复 worktree 并通过 CI/Postgres 门槛。

## 10. 2026-08-07 生产单用户 Canary

范围：对生产项目 `igbghrhsdaolxljgiisf` 中最近 30 天的现有记录做只读核对。未上传素材、未创建新记录、未修改用户数据。当前高活跃单用户按最近 30 天记录量识别；本节不记录用户 ID。

### 10.1 生产链路与 Shadow 状态

- 生产 Edge 部署已生效：最近识别日志仍使用 `platform-v3-builtins`，最新食物、睡眠和支出记录均成功落库；本轮未发现新的 Edge 错误。
- 最近 30 天共观察到 96 次 Expression Shadow：89 次文本响应、7 次 JSON 响应；全部为 `rollout_mode=shadow`、`lifecycle_state=returned_to_shortcut`，错误 0、改变用户输出 0。
- 这说明新 Planner 已经运行并写入 Shadow/Exposure，但**没有接管用户可见内容**。当前用户看到的仍是旧 `legacy_voice`/兼容反馈结果，不应把 Shadow 候选误认为已上线。

### 10.2 真实数据覆盖

- 交易支出 197 条；其中 104 条有 `companion_message`，86 条有结构化 `ai_feedback`，93 条仍没有陪伴文案，111 条没有反馈对象。
- 新域记录 47 条：睡眠 32、饮食 12、钱包 2、阅读 1。
- 睡眠记录中 18/32 有陪伴文案，12 条为 `signal_fallback`，14 条没有反馈对象；饮食 11/12 有文案，其中 7 条为 `ai_generated`；钱包 2/2、阅读 1/1 有文案。
- 支出文案主体聚焦仍不足：按商户全名精确命中仅 27/197；这只是保守下界，但足以说明旧链路仍会产出大量泛化句式。当前 67 条 `companion_message` 与 `emotion_line` 完全相同，需在可见链路切换后继续观察是否造成事实重复，而不是在 Shadow 阶段直接改写历史记录。

### 10.3 Planner 实际候选维度

Shadow 不是只生成一个中位数候选。最近真实记录的候选维度包括：

- 支出：`record_context`、`category_period_comparison`、`repeat_interval`、`personal_baseline`、`amount_structure`、`daily_aggregation`、`period_comparison`；
- 睡眠：`current_fact`、`personal_baseline`、`quality`、`sleep_structure`、`temporal_rhythm`；
- 饮食：`current_fact`、`meal_baseline`、`record_context`、`record_composition`、`recurrence`；
- 阅读/钱包：当前事实候选已生成。

因此本轮确认的根因不是“候选没有计算”，而是“候选计算与用户可见表达之间仍隔着 Shadow/旧 Voice 回退层”。

### 10.4 Memory 读取结论

- 语义 Memory RPC 当前返回 111 条仍有效记录；其中绝大多数带有源记录的旧派生模式，只有极少数明确用户反馈来源。
- Context Packet 会把 `record_derived` 记忆标为 `ranking_only`，不会直接进入陪伴文案；只有用户明确确认的语义才具备 `expressible` 权限。
- 最新饮食记录的时间为 `04:11 UTC`，而本次 Edge 部署在 `04:39 UTC` 完成；它与 `food:lunch` Memory 的同步更新属于旧链路，不能用来判断新版本是否仍在写派生 Memory。当前生产 secret 列表未发现 `COMPANION_DERIVED_MEMORY_WRITES_ENABLED`，新代码默认关闭；由于本轮约束不创建新记录，运行时关闭状态留待下一次自然请求继续观察。

### 10.5 Canary 结论与发布门槛

结论：**生产基础设施发布成功，个人上下文契约生效，用户可见闭环尚未完成。** 不能用本轮结果宣称“AI 陪伴已经切换到新框架”。

在允许单用户可见 Canary 前必须完成：

1. 为单用户设置明确的 `canary` 入口/开关，确保只影响该用户和指定 Surface；
2. 将 `record_context` 作为每条表达的保底维度，再从候选中选择一个不重复的事实维度；
3. 让 Voice/兼容反馈消费冻结 Packet，而不是继续返回 `legacy_voice`；
4. 记录候选 ID、Packet 指纹、Memory 命中和最终文案来源，验证 20-30 条跨域记录；
5. 验证失败时可回退到旧链路，且不修改历史已持久化文案。

是否允许进入下一阶段：否。当前只完成“契约上线 + Shadow 观察”；下一轮应先做单用户可见 Canary 接入，再决定是否扩大 rollout。

## 11. 2026-08-07 owner-only 可见 Canary

范围：继续使用同一生产项目和既有真实记录，只对服务端配置的单一 owner 账号开放记录详情候选。未创建测试记录，未上传新素材，未修改其他用户数据；本节不记录 owner 用户 ID、记录 ID 或商户原文。

### 11.1 发布与门禁

- `20260806100000_personal_context_memory_contract.sql` 已应用；`ingest-receipt` v178 与 `generate-insights` v22 为 ACTIVE。
- `EXPRESSION_PLANNER_OWNER_ENABLED=true` 且 owner JWT 用户匹配；普通用户、开关关闭和 owner 不匹配路径仍返回不可用，不会接管用户可见输出。
- `EXPRESSION_PLANNER_MODE` 继续保持 `shadow`；owner 的记录详情可见门禁是独立路径，不代表快捷通知、周报或其他用户已经切换。
- Planner 141/141、Edge 35/35、`deno check`、PWA build、安全契约、迁移版本、RLS 夹具及 iOS Build Gate 均已通过。

### 11.2 真实可见闭环

- 部署后 owner 客户端先生成 10 个 `expression_delivery_snapshots`，覆盖 5 条真实记录；GET 只创建一小时有效的预览快照，不计曝光。
- 第一轮没有 `client_rendered`，同期 Edge 请求无 4xx。PWA 和 iOS 都要求候选卡真正进入视口后才 ACK；记录详情中的候选位于图片、字段和陪伴语之后，因此“打开详情但未滚到候选”只产生快照，属于预期行为。
- owner 随后打开一条已完成记录并将“AI 即时反馈”卡片滑入视口。生产新增 1 条 `record_detail` 真实曝光，并成功绑定确定性 `decision_id`、候选 ID、策略版本和可见字段。
- 同一曝光随后成功提交点评，生命周期从 `client_rendered` 更新为 `user_reviewed`。这证明 `GET -> 真实可见 -> ACK -> 点评` 已在生产自然记录上闭环，且点评没有绑定预览快照或旧 `legacy_voice` 替代物。
- 当前快照和曝光没有 `client_platform`/User-Agent 字段，生产侧无法仅凭数据库区分本次来自 PWA 还是 iOS；后续观测字段需要补齐，但不影响本次闭环真实性。

### 11.3 首批候选质量

部署后的 6 条不同记录预览已出现以下主候选：

- 支出：`record_context`、`repeat_interval`、`daily_aggregation`、`personal_baseline`；
- 饮食：`current_fact`。

首批结果同时证明了框架价值和当前选择质量的缺口：

- 同名记录间隔和饮食当前事实能够补充旧陪伴语没有表达的信息，方向正确；
- 一条商户活跃日基线只有约 3.27% 的金额差异，仍以较高分入选，说明 `personal_baseline` 缺少最小实质差异 Gate；
- 首条真实点评绑定的 `record_context` 与旧陪伴语都在复述当前金额，虽然字段和事实准确，但新增信息价值不足；
- 当前详情页保留旧陪伴语在前、Planner 事实候选在后，Planner 不会覆盖已持久化的陪伴文案。问题是候选语义重复，不是客户端异步覆盖复发。

### 11.4 客户端状态机复审

- 当前零 ACK 已由真实可见冒烟排除为链路故障；无需为了计数放宽“真实可见后 ACK”的原则。
- PWA 仍有两个非阻断的恢复风险：快速离开又返回同一记录时可能复用已取消的 in-flight 请求；预览快照超过一小时后，手动重试会继续使用旧 token，而不是重新 GET。
- iOS/PWA 的可见性、过期 token 和快速切换仍需页面级回归；现有定向测试以模型、请求和源码契约为主，不能替代真机/真实浏览器生命周期测试。

### 11.5 当前结论与下一轮

结论：**owner-only 用户可见链路已经跑通，Personal Context/Planner 不再只是 Shadow；但首批样本仍不足以扩大灰度。**

下一轮按以下顺序推进：

1. 保持 owner-only，继续积累 20-30 条自然跨域可见样本，不制造记录；
2. 为个人基线候选增加最小实质差异 Gate，避免几乎相同的中位数比较占据详情主位；
3. 在 Surface 组合层加入“已由陪伴语覆盖”的语义去重，避免 `record_context` 与陪伴语复述同一事实；
4. 补 PWA 快速切换、过期 token 自动重新 GET，以及 iOS 对应恢复路径的页面级回归；
5. 补 `client_platform` 观测字段后，再比较 PWA 与 iOS 的 ACK、点评和失败率。

是否允许进入下一阶段：允许继续 owner-only Canary 和定向质量修复；不允许扩大到其他用户，也不允许把在线选择权交给 Bandit。

## 12. 2026-08-07 个人基线最小实质差异门禁

范围：只调整 `merchant_daily_vs_active_day_median` 的 Surface 可见资格，不修改候选生成、事实口径、评分公式，也不影响睡眠、饮食、运动和阅读等其他域的个人基线。

### 12.1 设计与口径

生产 Canary 暴露出一条金额仅比个人活跃日中位数高约 3.27% 的候选仍占据详情主位。该事实虽然准确，但没有足够新增价值，因此门禁放在 `surfaceDecision`，而不是候选生成或 claim 事实门禁：

- 笔数绝对差至少 `1`，通过；
- 或金额绝对差至少 `20` 元，通过；
- 或金额绝对差至少 `5` 元且相对差至少 `15%`，通过；
- 基线金额为 `0` 时不计算百分比，只使用笔数差或 `20` 元绝对差；
- 指标缺失或非有限值使用独立原因 `missing_materiality_metrics`，不误报成“差异太小”。

增加和减少使用相同阈值。金额先转换为整数“分”再计算差异和比例，避免 `8.04 - 3.04` 一类浮点误差破坏边界。金额阈值当前是人民币口径；多币种接入前必须先统一币种，不能直接复用本规则。

### 12.2 行为边界

- 低差异候选仍保留在 `plan.candidates`，claim 仍为有效，供 Shadow、审计和离线调参使用；
- 所有用户可见 Surface 以 `difference_below_materiality_threshold` 拒绝该候选，Surface 分数为 `null`；
- 被拒候选不能进入 `decision.action_set`，不会参与详情页确定性选择或未来 Bandit 动作空间；
- Planner 版本从 `expression-shadow-auto-v0.4` 升至 `v0.5`，用于区分新旧资格策略；候选结构和评分公式未变化，因此不升级 candidate/scoring version。

### 12.3 验证结果

- Planner 完整测试 `148/148` 通过，覆盖正负方向、阈值边界、零基线、缺失/`NaN`、冗余 delta 不一致、非目标候选、Shadow 保留、详情选择、旧版本快照失效和 `action_set` 排除；
- 防御性修正前 Edge TypeScript 检查和 Edge 测试 `35/35` 已通过；当前 Windows 环境没有 Deno，最终提交必须由 GitHub CI 复验 Edge；
- PWA production build、安全契约、重复记录、财务选项和 migration version 检查通过；
- `git diff --check` 通过。`npm ci` 报告的 4 个依赖漏洞与本轮修改无关，本轮未执行自动 breaking upgrade。

### 12.4 当前结论与下一轮

结论：**首个真实 Canary 质量缺口已在正确的 Surface 边界上修复。** 本轮代码尚未推送、未部署，生产仍运行旧 Planner 资格策略。

下一轮应先进入 PR/CI，再保持 owner-only 观察自然样本。随后处理“Planner 候选与旧陪伴语语义重复”，该问题属于 Surface 组合去重，不应继续扩大本门禁的职责。

是否允许进入下一阶段：允许提交并进入 CI；生产部署仍需单独授权。
