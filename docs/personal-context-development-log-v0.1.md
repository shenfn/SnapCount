# Personal Context 开发计划与交接日志 v0.1

> 对应设计：[personal-context-architecture-v0.1.md](./personal-context-architecture-v0.1.md)
> 状态：开发中
> 范围：Supabase Edge Function、Planner/Signals 上下文边界、语义 Memory 读取与测试
> 发布边界：本轮已获用户授权；仍须先通过 CI，按迁移→Edge→PWA→TestFlight 顺序发布

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
| Phase 4 | 本地收口，待 CI/发布 | 时间事实与 Planner/Voice 统一出口已在同一工作树完成；生产发布按固定顺序进行 |

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

## 13. 2026-08-07 Planner 与 Voice 统一出口

> 历史中间状态：本节记录了“coverage 后选择下一候选”的第一版实现。该做法会让用户看到的 Voice 首候选无法获得曝光和候选级点评，已由第 15 节的正式 delivery 契约替代。

范围：保持五因子评分与一次表达调用不变，把插入前 Planner 主候选、Context Packet、Voice、Surface 组合及现有 ACK/点评闭环接成同一条可追溯链路。

### 13.1 契约升级

- Context Packet 升级到 `context-packet-v2`，候选携带 `candidate_id`、`semantic_key`、`dimension`、来源 Surface、Planner 版本与严格的 `count/measure` 数字角色；
- Planner 升级到 `expression-shadow-auto-v0.6`，新增正式的 `expense_merchant_first_occurrence` 候选；新别名不等于新商户，历史待补全记录也会阻止误报“第一次记录”；
- 支出、收入、睡眠、饮食、运动、阅读和钱包在落库前运行只读 Planner brief，仍只调用一次 Voice；synthetic ID 不产生曝光；
- Voice 通过 `expression-coverage-v1` 声明实际表达的稳定 `semantic_key`。声明必须匹配首条候选且主陪伴语真实存在；Provider/解析失败时才由代码事实兜底。旧版本、缺失指纹或 Surface 不符的 coverage 一律 fail-open；
- 落库后的正式 Planner 按 coverage 重组详情和通知，已表达候选不进入详情 `action_set`，下一条不同角度仍按原评分和门禁选择。

### 13.2 客户端组合

- PWA 与 iOS 都隐藏陪伴语旁边的纯当前事实兜底，但保留首次出现、历史比较、对象和情境候选；
- 隐藏的 PWA 卡不 ACK；iOS 会丢弃被组合策略隐藏的未曝光预览，避免旧 token 卡住后续计划；
- coverage 解析统一校验版本、Planner 版本、来源 Surface 和 Packet 指纹，过期客户端宁可重新展示，也不静默丢候选。

### 13.3 当前验证与边界

- Planner `163/163`、Edge/Deno `45/45`、PWA Surface 组合与候选身份 `9/9`、PWA production build、安全契约和重复记录契约均已通过；
- `regenerateFeedbackWithSecondCall` 已有直接契约测试覆盖无 Provider、HTTP 失败和坏 JSON，三条路径均保留已核实 Planner 事实与完整 coverage；
- iOS 已完成静态契约复审，并覆盖真实 `JSONDecoder -> AnyCodable` 解码、coverage 规范化和隐藏预览状态；Windows 没有 Swift 或 Xcode，iOS Build/单测仍必须由 GitHub Actions 的 macOS 环境验证；
- 已使用生产只读聚合生成本地等价脱敏回放。一条真实低价茶饮记录此前同名和同品牌计数均为 0；生产 v0.5 重复呈现商户和金额，本地 v0.6 新增并选择 `expense_merchant_first_occurrence`，当前事实退回兜底。精确商户、金额和时间不进入 Git；
- 回放输入、结果和新旧对照保存在 Git 忽略的 `local-only/expression-planner/`，不含用户 ID、生产记录 ID、图片、路径和其他原始商户名，不进入提交或 CI artifact；
- 当前尚未推送、部署生产 Edge 或触发 TestFlight；真实模型措辞、macOS iOS Build/单测和发布仍属于下一门禁。

## 14. 2026-08-08 统一出口阻断项收口

> 历史中间状态：本节完成了 coverage 事实校验，但“隐藏首候选、交付下一候选”的生命周期仍未闭环。最终行为以第 15 节为准。

完成：

- coverage 不再信任模型自报的 `semantic_key`；只有文案实际包含对应对象、语义锚点以及来自候选的准确数字和单位时，才会隐藏同角度 Planner 卡片；
- coverage 与正式详情候选增加稳定 `claim_fingerprint`。记录编辑后旧 coverage 自动 fail-open，ACK 前重新规划并以 `plan_claim_stale` 拒绝已经变化的 claim；
- 支出、收入和数据域历史读取改为 500 条一页的完整分页，避免第 501 条之外的历史导致“第一次记录”误报；
- 插入前与落库后的数据域 Planner 使用同一画像来源。回归确认饮食餐次基线会进入正式 `decision.action_set`；快照 `candidates` 仍按安全契约只冻结实际下发的主候选；
- PWA 在预览和 ACK 两个阶段校验 `feedback.source` 与顶层 `candidate_id`，避免展示与曝光串候选；iOS 现有 Repository 已保持同类候选身份校验；
- 回放器按账号隔离支出和数据域历史，输出递归移除用户 ID，避免多账号历史污染首次出现或个人基线。

测试：

- Planner：`163/163`；Edge/Deno：`45/45`；PWA 表达组合：`9/9`；
- `ingest-receipt`、`generate-insights` Deno 类型检查通过，PWA production build 通过；
- 安全契约、重复记录、待处理队列、财务选项、钱包快照金额、注册元数据、migration version 和 `git diff --check` 通过；
- Windows 不能验证 Swift/Xcode；iOS 编译与单测仍必须由 GitHub Actions macOS runner 完成。

已知边界：

- 本轮没有新增 migration，也没有执行生产迁移、Edge 部署、push 或 TestFlight；
- migration version 检查把 `20260806100000_personal_context_memory_contract.sql` 列为超出仓库记录基线 `20260726121000` 的 active migration；本日志此前已记录其生产应用结果，因此需要由发布流程单独核对并更新 baseline 元数据，本轮不重复执行迁移；
- 真实模型的最终措辞质量只能在 owner-only 发布后用自然记录验证，本地不把规则兜底示例当成模型实测。

下一轮：

- 进入独立 PR 和 GitHub CI，先取得 macOS iOS Build/单测结果；
- CI 通过后再决定是否部署 owner-only Edge Canary，不扩大到其他账号，不启用在线 Bandit；
- 发布后观察“陪伴语保留 + 新角度候选不重复 + 点评绑定正确候选”三项闭环。

是否允许进入下一阶段：允许提交并进入 CI；生产部署和 TestFlight 仍需单独授权。

## 15. 2026-08-08 Voice 首候选正式 delivery 闭环

范围：不增加模型调用、不修改五因子评分、不新增 migration，把用户实际看到的陪伴语与正式 Planner 候选、曝光和点评绑定为同一份交付。

### 15.1 根因与修正

第一版统一出口把 Voice 已表达的首候选从正式详情计划中排除，再为第二候选创建 snapshot。结果是用户看到首候选，但疲劳计数、ACK 和点评都绑定第二候选。现在改为：

- 插入前 Planner 仍只读，不创建快照或曝光；
- 最终 `companion_message` 通过候选事实验证后写入 coverage；
- 落库后的正式 Planner 必须再次选中同一 claim，才能创建 `presentation_target=companion_message` 的 delivery snapshot；
- 客户端不重复绘制正文，只在原“AI 陪伴”容器中承载可见性 ACK 和点评控件；
- ACK 后曝光的 `rendered_payload` 就是实际陪伴语，点评使用同一候选的 `exposure_event_id`；
- coverage、文本指纹、持久文案、候选依赖或 claim 任一变化时，回退到普通 Planner 卡，不静默丢内容。

### 15.2 数字与通知

- 统计数字改为同候选的 `value + meaning + unit + scope` 绑定，拒绝把“本周第 4 次”和“近 90 天均价 9.54 元”交换口径；
- 通知改为 `slot + semantic_key + claim_fingerprint` 组合，同 claim 的不同说法只出现一次，固定记账结果始终保留；
- Voice 首候选只有通过快捷通知准入时才进入通知，并为实际展示的陪伴语写 `returned_to_shortcut` 曝光；不满足准入时由真正选中的快捷通知候选负责展示和曝光。

### 15.3 首次记录与回放

- “第一次记录某商户”统一解释为“芥子第一次见到”，按 `known_at/created_at` 判断；补录更早事件不会把已经见过的商户误报为第一次；
- 回放器修复 `--baseline` 变量错误，并覆盖无变化、候选变化、选择变化及非零候选变零候选；
- 真实素材仍只保存在 Git 忽略的 `local-only/`，测试和文档只使用合成或脱敏事实。

### 15.4 当前门槛

- 服务端 delivery、fingerprint、编辑失效、快捷通知曝光和通用文案无 coverage 的定向测试已通过；
- Edge 全量测试、PWA 组合测试、Planner 全量、PWA build、安全与业务契约仍需在本轮最终状态统一复跑；
- iOS 只完成本地源码和静态测试，必须由 GitHub Actions macOS runner 验证编译与单测；
- 本轮未提交、未 push、未部署 Edge、未执行生产迁移，也未触发 TestFlight。

是否允许进入下一阶段：等待最终全量回归；通过后只允许进入 PR/CI，生产发布仍需当前任务中的单独授权。

## 16. 2026-08-08 表达出口客户端最终收口

本轮补齐了最后一层客户端活性与身份约束：

- PWA 详情页和待补充弹窗现在依赖陪伴文案身份。文案异步刷新会废弃旧计划、取消旧 in-flight 请求并重取；ACK 前会再次校验可见文案。
- `feedback_card` 和 `companion_message` 都使用候选、claim、target 与渲染文本指纹进行确认；旧响应仅在没有显式 target 时走兼容规则。
- iOS 在废弃 stale pending 时同时清理 ACK token，避免旧请求完成后新计划没有点评入口。

最终本地验证：Planner `170/170`、Edge/Deno `59/59`、PWA 表达展示 `16/16`、PWA exposure 契约 `10/10`、PWA production build、Deno 类型检查、安全/重复/待处理/财务/钱包/注册/migration 契约和 `git diff --check` 全部通过。Windows 不能运行 Swift/Xcode，未执行 iOS Build。

本轮未提交、未 push、未部署 Edge、未执行 migration、未触发 TestFlight。

## 17. 2026-08-08 时间与统一出口发布批次

完成：

- 将 `occurred_at` 作为财务业务发生时间的 canonical 字段，保留旧日期/时分字段作为兼容展示；历史只从 staging/AI 日志的明确证据回填。
- Voice、Feedback、PWA 和 iOS 详情统一消费冻结 Context Packet 与 Planner delivery；陪伴语已表达的候选复用同一点评曝光，不再绘制重复卡片。
- PWA/iOS 详情同时展示上传时间与发生时间；发生时间缺失时显示未知或日期，不把上传时间伪装成发生时间。
- 当前阶段固定 `Asia/Shanghai`；海外时区、用户时区设置和 DST 作为后续独立项目，不混入本批次。
- 未知发生时间的时段词清洗为无时段表达，保留可验证的句子主体。

修改文件：

- Edge：`supabase/functions/ingest-receipt/{index.ts,time.ts,time-language.ts,prompts.ts,expression-delivery.ts,...}`
- 数据库：`supabase/migrations/20260808120000_finance_occurred_at_contract.sql`
- PWA：`src/utils/{financeOccurrence.js,expressionPresentation.js,helpers.js}` 及详情/状态适配器
- iOS：记录查询、详情展示、Planner feedback envelope 与时间单测
- Planner/测试：候选、去重、曝光、回放和时间契约测试

测试：

- Planner 171/171；PWA 表达 16/16；PWA 时间辅助函数 13/13；业务契约、安全/重复/待处理/财务选项、生产构建和 `git diff --check` 通过。
- 本机缺少 Deno 与 Swift/Xcode，Edge 类型检查、PostgreSQL/RLS 和 iOS Build 留给 GitHub CI。

已知风险：

- migration 必须先于包含 `occurred_at` 查询的客户端和 Edge 发布；否则旧生产 schema 会导致查询失败。
- 历史记录没有明确发生时间证据时保持 null，不能自动猜测；线上 Canary 需确认 UI 对该空值的文案可接受。
- 海外时区暂缓，不把当前 Shanghai 契约误称为国际化完成。

最终收口补充：

- PWA 仅允许明确的手动旧记录回退展示 `transaction_time`；`ai_scan` 等旧 AI 记录缺少 canonical `occurred_at` 时不再显示可能错位的时分。
- iOS 手动/中转记录未选择具体时分时，`occurred_at` 保持 `null`，不再自动补成 `12:00`。
- 修正时间文案清洗器的替换回调参数，补录场景可以保留明确描述“上传/补录时刻”的措辞，同时仍以发生时段约束主句。
- `test:expression-presentation` 已纳入 Release Validation；当前本地没有 Deno、PostgreSQL 或 Xcode，相关结果必须由 PR CI 给出。

下一步：

- 逐路径暂存并提交，推送 Draft PR；等待 Edge/Postgres/macOS CI。
- CI 固定提交通过后执行生产 migration、Edge、PWA，再手动触发 TestFlight。
- 用一条真实 06:xx 记录验收时间、去重和点评闭环。

是否允许进入下一阶段：是，进入 CI 和固定提交发布门禁。

### 17.1 首轮 CI 失败与修复

PR #28 首轮 CI 暴露了三处收口问题，均未改变既定产品范围：

- Voice 时间测试误把识别 Prompt 的 `client_captured_at` 约束断言放在 Voice Prompt 上；断言已移回识别阶段测试，识别与表达边界保持不变。
- 时间文案清洗的普通时段正则含捕获组，导致 JavaScript `replace` 回调把捕获文本误当字符下标；改为非捕获组后，“早上才补录”可以保留上传时段，而记录主体仍服从代码计算的发生时段。
- iOS 将带默认参数的 `NativeLocalDate.dateKey` 直接传给 `Optional.map`，Swift 类型推断要求两个参数；改为显式闭包调用，不改变日期语义。

修复后本地验证：Edge safeguards `71/71`、Planner `171/171`、PWA 表达 `16/16`，财务发生时间、待处理队列、财务选项、重复记录和安全契约均通过。Windows 仍不能替代 macOS Swift 编译，修复后的 iOS Build 与单测必须由 PR CI 再验证。

第二轮 Release Validation 继续执行到 PostgreSQL 实际迁移演练后，发现测试夹具的 `data_records` 缺少生产 schema 自 007 migration 起就存在的 `created_at`。归档 RPC 的同图幂等查询长期按该列排序，因此本轮仅补齐夹具字段，不修改生产 RPC 或时间契约。
