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
