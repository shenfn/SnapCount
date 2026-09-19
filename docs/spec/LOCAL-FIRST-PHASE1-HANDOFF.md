# Jiezi Local-First Phase 1 Handoff

> 更新：2026-09-19。依据：本轮已完成的产品决策、实现差距矩阵及 AI Popup 资产盘点；本文是接续快照，不是完整 PRD 或实施授权。
> 盘点基线：`D:\Business\count`，HEAD `f24bfd4`，分支 `feature/LOCAL-003E同步错误恢复与分批上传`。工作区存在用户 WIP，必须保护。

## 1. 当前阶段目标

Phase 1 的目标是尽快完成一个可发布 App Store 的 Local-First Personal AI Memory iOS 版本：把已经探索和使用过的产品能力迁移到“本地正式事实”架构。当前主线是完整的本地核心体验，已有同步系统不再决定第一版发布进度。

**阶段口径：**旧任务索引仍记录 LOCAL-003 同步 RC，部分旧原型说明仍写 Expense + Account；这些历史范围不能覆盖本文记录的最新用户决策。实现情况仍以真实代码和验证证据为准。

## 2. 已经拍板的产品决策

- 本地数据是正式业务事实，不是云端缓存；本地数据库独立支撑核心记录体验。
- Phase 1 不做 Cloud Sync、多设备同步、云端换机恢复。已有同步代码冻结，不删除、不扩展，不作为第一版发布阻塞项。
- 登录、BYOK、Hosted AI、Cloud Sync 是独立能力。登录不自动代表开启同步；AI Provider 不决定业务数据存储位置。
- 不登录、不联网仍可创建和管理本地记录，包括查看、编辑、删除及基础账户、余额能力。此承诺不等于离线调用云端大模型。
- 联网但不登录可使用 BYOK；联网并登录可使用 Hosted AI，登录主要服务于身份、额度、订阅和 Hosted AI。
- 第一版继续覆盖五域：**消费、饮食、睡眠、运动、阅读**。不能因为 Expense 当前实现更成熟而缩减其他域。
- 截图 / 快捷输入、选择图片 / 拍照是核心入口；手动创建和编辑是兜底；语音暂不进入 Phase 1。
- AI 将输入转换为结构化候选，用户最终确认后的正式记录保存到本地。
- 图片需要真正本地保存，并具备与记录相对应的生命周期，不能只依赖远端 URL + Cache。
- 跨域 AI Analysis 是已有产品能力，需要保留。
- AI Popup / 即时反馈是已有核心产品能力，需要保留。
- 不重新设计这两套 AI 能力，优先解决 Local-First 数据边界适配；二者都不以 Cloud Sync 为前提。

## 3. 当前已经确认的真实实现状态

### 已经比较成熟

- GRDB / SQLite 文件数据库、Local Profile、本地 Expense 与基础 Account 已有实现。
- Expense CRUD、本地账户创建、本地流水及余额计算已有数据层、Use Case 和部分页面接线。
- 本地消费 / 账户归档能力及相关测试已有，尚不等于用户可操作的五域导出。
- 已有多域云端产品逻辑、Hosted AI、跨域 AI Analysis。
- 已有 AI Popup / Expression Planner、Prompt、校验、展示、曝光和用户反馈资产。

### 主要缺口

- 饮食 / 睡眠 / 运动 / 阅读尚未形成完整本地正式数据闭环；未登录手动入口目前主要覆盖消费。
- 图片仍主要依赖云端 URL + 磁盘缓存，正式本地图片生命周期未接通。
- 截图 / 快捷输入仍以登录凭据和云端上传链路为中心。
- BYOK 尚未形成完整 iOS 闭环。
- Today / Records / Account 等仍有云端依赖或混读；完整账户管理未统一到本地。
- 跨域 AI Analysis 当前读取 Supabase 汇总和历史明细。
- AI Popup 当前主要读取云端记录、历史、画像、曝光和反馈。
- 本地五域事实尚未完整接入 AI Popup 与 Analysis；AI 结果与反馈的本地生命周期也未形成闭环。
- 设置页导出仍查询云端；本地归档能力尚未接成五域和图片的用户导出闭环。

### 已验证与未验证的边界

- **已核实：**上述实现和调用边界来自本轮代码、文档、原型静态核查；“代码存在”不等于当前真机可发布。
- **已有验证依据：**本地消费、账户、数据库重开、归档，以及表达选择、校验和反馈存在自动化测试；仓库历史记录有 macOS 构建及 280 个 XCTest 通过。本轮未重跑这些测试。
- **历史使用 / 验证：**多域与跨域分析已有实际产品使用；表达文档记录过云端 owner Canary 的曝光和点评闭环。不能据此推断当前所有用户开关、五域候选质量或 Local-First 链路已验证。
- **未验证：**本次确定的五域、图片、AI、离线、重启等完整 Phase 1 真机闭环。Windows 不能验证 Swift 编译，后续仍需 macOS CI 和真机验收。
- 原型用于体验参考；当前原型使用模拟数据，部分操作尚是占位，不能计为业务完成。

关键证据入口（按需阅读，不要求重新扫描全仓库）：

- 本地能力：`ios/SnapCount/LocalData/`、`ios/SnapCount/Features/Records/LocalExpenseUseCase.swift`。
- 页面与数据分支：`ios/SnapCount/App/AppState.swift`。
- 分析：`ios/SnapCount/Repositories/InsightsRepository.swift`、`supabase/functions/generate-insights/`。
- 历史验证：`docs/spec/执行记录/LOCAL-003-Expense-Account-Sync-RC-Gate.md`。仅引用验证证据，不继承其旧同步发布范围。

## 4. AI Popup 核心资产

当前主链可概括为：

**记录事实 → 候选洞察 → 筛选 / 评分 → 选择最值得说的一件事 → LLM 表达 → 校验 → 用户看到 → 用户反馈。**

核心原则：**代码负责算，大模型负责说。** 事实、统计和可信候选尽量由代码决定，模型在约束内自然表达；这是一条已有设计原则，不代表所有历史分支和模型输出都已完全符合。

- Candidate、评分、Gate、Selection、Prompt 约束、校验、规则降级、Feedback 等能力已经存在。
- 已有候选去重、表达覆盖校验和真实可见后确认曝光的机制；用户点评可绑定实际展示内容。
- “最值得说的一件事”是表达价值原则。当前实现也允许 Voice 与提供不同信息的 Planner 卡片共存，不能误写成所有界面严格只显示一句话。
- 反馈采集和规则偏好资产已存在；在线 Bandit、自动探索或自动修改 Prompt 的完整学习闭环不能视为已完成。
- Local-First 不是重新发明这套算法。当前主要问题是数据来源、生成调用、结果及反馈持久化仍以云端为中心。
- AI Popup 回答“刚记录这件事，此刻最值得说什么”；Analysis 回答“一段时间的多域数据有什么变化或关系”。两者分别保留，不合并为一个功能。

资产入口：

- 算法：`supabase/functions/_shared/expression-core/`。
- 表达与交付：`supabase/functions/ingest-receipt/` 中的 `prompts.ts`、`expression-delivery.ts`、`expression-feedback.ts`、`voice-output.ts`。
- iOS 展示：`ios/SnapCount/Models/NativeAIFeedback.swift`、`ios/SnapCount/Shared/NativeAIFeedbackCard.swift`。
- 规格与历史：`docs/spec/20-陪伴表达事实契约.md`、`docs/expression-planner-grounded-voice-development-v0.1.md`、`docs/expression-planner-feedback-learning-rollout-v0.1.md`。历史文档中的部署状态需按时间区分。

## 5. 当前明确不是 Phase 1 主线的内容

- Cloud Sync、Multi-device、云端换机恢复。
- Outbox 扩展、大批量同步、Cursor 优化、Sync Conflict、CRDT。
- 在线 Bandit、Shadow 自动改变真实用户结果。
- 语音输入，以及其他未经明确纳入 Phase 1 的未来能力。

已有实现保持冻结；不能因为仓库中存在相关代码，就将其重新列为当前发布前提。

## 6. 当前 Release Blocker

以下均为**待实施或待完成验收**的一级能力清单，不是依赖排序或实施授权：

- 五域 Local-First。
- 本地图片生命周期。
- 截图 / 快捷输入本地闭环。
- BYOK。
- Hosted AI 与云端业务存储解耦，可基于本地正式事实工作。
- AI Popup Local-First 适配。
- 跨域 AI Analysis Local-First 适配。
- Today / Records / Account 本地事实统一。
- 本地导出。
- 最终真机验收。

## 7. 新会话 Agent 的行为约束

- 不重新讨论已经拍板的产品范围，不把五域缩减为 Expense + Account。
- 不重新把 Cloud Sync 提升为当前主线，也不将 AI 的云端数据依赖解释成必须先完成同步。
- 不因为现有代码采用某个架构，就默认该架构一定正确；区分事实、设计假设和历史状态。
- 不直接开始修改代码。先读本文及仓库 AGENTS.md，检查工作区状态，确认用户指定的当前阶段任务，保护现有 WIP。
- 先以现有产品行为和真实代码为基准核查：已有产品规则且代码已有实现的，不重新询问；已有云端实现但本地未接通的，记录为迁移差距；只有代码与既定行为冲突、行为未覆盖或证据不足时，才向用户提出产品问题。不要把本地数据库当前尚未覆盖的部分反过来当成产品范围问题。
- **待理解：**后续仍需对 AI Popup / Planner 等关键技术概念及真实数据边界做技术认知对齐；本轮未完成 Release Blocker 依赖分析，也未批准具体实现方案。
- 如涉及重大技术决策，先解释真实用户问题、已有资产、方案及取舍，再由用户拍板；不要把技术名词堆叠成默认路线。
- 根据下一轮用户指令进入认知对齐或依赖分析；本交接文档生成后停止，不自行开始下一阶段。

下一阶段工作范围已记录在：`docs/spec/LOCAL-FIRST-PHASE1-DATA-MODEL-GROOMING.md`。执行 Agent 应使用 Supabase 的长期业务实体和行为作为参考，设计 Phase 1 本地正式事实边界；不要求本地 schema 复制 Supabase，也不得把同步设计重新带回主线。

**当前停点：产品范围与现状盘点完成，AI Popup 资产盘点完成。**

## 8. 架构方法论适配状态

2026-09-19 已确认：`docs/arch-design-methodology` 是从公司项目带出的参考快照，不能直接作为 Count 的执行规范。已新增 `docs/spec/LOCAL-FIRST-ARCHITECTURE-ADAPTER.md` 作为 Count 项目适配层，原目录保持不变。

本轮已完成：

- 明确 Count 的 Local-First、五域、图片、AI、离线和同步冻结边界；
- 将多租户、租户分片调度、SPI 启动校验和服务端消息管道改为按需知识，不作为默认架构前提；
- 排除公司项目路径、内网安装协议、雁游回填流程和旧方法论仓库进度记录；
- 将适配层登记到 `docs/spec/规格文档索引.md`。

未验证项：适配层尚未用于 AI Popup / Planner 的真实代码依赖审计；五域本地事实、图片生命周期、BYOK、AI 结果与反馈的完整闭环仍未验证。

下一步：依据适配层对 AI Popup / Planner 做只读数据边界与依赖分析，产出依赖矩阵和最小完整切片建议；在方案获批准前不修改业务代码。

## 9. L0-L3 设计分层审计状态

2026-09-19 用户确认采用 L0/L1/L2/L3 作为 Count 的架构设计分层，不直接沿用公司项目的实施顺序或项目专属内容。已新增 `docs/spec/LOCAL-FIRST-ARCHITECTURE-LAYER-MAP.md`，完成现有架构文档的只读覆盖映射。

本轮判断：L0 有系统总览和 Local-First 决策材料，L1 缺少当前主领域清单与依赖图，L2/L3 有消费、账户、同步、BYOK 和表达核心片段，但五域、图片、AI Local-First、本地导出和完整技术详设仍未收敛。

后续按设计层级推进：先补当前有效的 L0/L1 架构总览，再按主领域补 L2，最后为获准的垂直切片补 L3。现有文档中的 L0-L5 继续作为历史实施路线记录，不与设计层级混用。

## 10. 数据模型 Grooming 接续结果

2026-09-19 已完成下一阶段的只读数据模型 Grooming。结论固定了五域正式事实归属、消费与通用记录不重叠、候选/中转站/正式记录生命周期、图片所有权、AI 与正式事实边界、统一本地事实读取边界，以及 `LOCAL-P1-DM-001` 至 `LOCAL-P1-DM-014` 验收场景。

详细结果见：`docs/spec/LOCAL-FIRST-PHASE1-DATA-MODEL-GROOMING-RESULT.md`。实现前应先依据该结果补行为红灯和模型缺口，不扩展同步主线。

## 11. 当前执行接续

2026-09-19 已在当前根工作区开始实现，保护既有用户 WIP，未新建隔离 worktree。已完成并待 macOS 验证的最小模型收敛包括：通用记录禁止写入 `expense`、域阈值与事实完整性路由、睡眠分钟归一化、时间格式边界、中转确认幂等、版本保护、只读 `LocalFactReader`，以及到 Today/Records 和离线通用导出的接线。`LocalFactReader` 以 `expense/<uuid>` 和 `data/<uuid>` 输出正式事实，排除中转记录与删除墓碑。

当前仍未完成：AI Popup/Analysis 本地读取适配、真实图片输入、AI source 持久化和真机验收。Windows 无 Swift/Xcode 工具链，本轮仅完成静态检查；iOS 编译与 XCTest 以 macOS CI 为准。同步协议、Outbox、Cursor、冲突机制和 Cloud Sync 主线保持冻结。

## 12. 本轮分支与 CI 收口

2026-09-19 已将本轮实现整理到分支 `codex/local-first-phase1-fact-reader`，通过 PR [#199](https://github.com/shenfn/SnapCount/pull/199) 提交。实现提交为 `196a6f1`，随后补充了数据库写入返回、异步 XCTest 断言和登录态 Planner 路由兼容修复，最终提交为 `11a5518`。

macOS iOS workflow `35431410842` 已通过：应用编译、完整 XCTest、iOS Build Gate 均为成功；同一 PR 的 PWA/迁移、治理、预览和部署检查也已通过。Windows 本地仍无法执行 Swift/Xcode 或真机测试，因此真机链路保持未验证。

本轮保留的剩余风险不变：AI Popup/Analysis 本地读取、真实图片输入、AI source 持久化、图片与数据库删除的原子性，以及最终真机验收。未提交的根工作区素材、视觉改动、规格原文和其他 WIP 未进入本分支提交。
