# Jiezi Local-First Phase 1 Handoff

> 更新：2026-09-25（SL-01 文档口径收口）。依据：本轮已完成的产品决策、实现差距矩阵及 AI Popup 资产盘点；本文是接续快照，不是完整 PRD 或实施授权。
> 盘点基线：`D:\Business\count`，HEAD `7005e81`，分支 `codex/local-first-phase1-fact-reader`。工作区存在用户 WIP，必须保护。

## 1. 当前阶段目标

Phase 1 的目标是尽快完成一个可发布 App Store 的 Local-First Personal AI Memory iOS 版本：把已经探索和使用过的产品能力迁移到“本地正式事实”架构。当前主线是完整的本地核心体验，已有同步系统不再决定第一版发布进度。

**阶段口径：**旧任务索引仍记录 LOCAL-003 同步 RC，部分旧原型说明仍写 Expense + Account；这些历史范围不能覆盖本文记录的最新用户决策。实现情况仍以真实代码和验证证据为准。

## 2. 已经拍板的产品决策

- 本地数据是正式业务事实，不是云端缓存；本地数据库独立支撑核心记录体验。
- Phase 1 不做 Cloud Sync、多设备同步、云端换机恢复。已有同步代码冻结，不删除、不扩展，不作为第一版发布阻塞项。
- 登录、BYOK、Hosted AI、Cloud Sync 是独立能力。登录不自动代表开启同步；AI Provider 不决定业务数据存储位置。
- 不登录、不联网仍可创建和管理已落地的本地记录，包括查看、编辑、删除及基础账户、余额能力。此承诺不等于离线调用云端大模型。
- BYOK 暂缓，不纳入 Phase 1；联网并登录可使用 Hosted AI，登录主要服务于身份、额度、订阅和 Hosted AI。
- Phase 1 范围按拍板扩展为七个本地事实域：**消费、收入、钱包快照、饮食、睡眠、运动、阅读**。收入与钱包分别由 SL-A/SL-B 进入实现；不能因为 Expense 当前实现更成熟而缩减其他域。
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

- 饮食 / 睡眠 / 运动 / 阅读的未登录手动创建已走本地正式记录路径；完整候选、图片和用户闭环仍在后续 Slice。
- 图片仍主要依赖云端 URL + 磁盘缓存，正式本地图片生命周期未接通。
- 截图 / 快捷输入仍以登录凭据和云端上传链路为中心。
- BYOK 暂缓移出 Phase 1，保留为冻结登记，不作为当前发布阻塞。
- Today / Records / Account 等仍有云端依赖或混读；完整账户管理未统一到本地。
- 跨域 AI Analysis 当前读取 Supabase 汇总和历史明细。
- AI Popup 当前主要读取云端记录、历史、画像、曝光和反馈。
- 本地五域事实尚未完整接入 AI Popup 与 Analysis；AI 结果与反馈的本地生命周期也未形成闭环。
- 设置页导出仍查询云端；本地归档能力尚未接成五域和图片的用户导出闭环。

### 已验证与未验证的边界

- **已核实：**上述实现和调用边界来自本轮代码、文档、原型静态核查；“代码存在”不等于当前真机可发布。
- **已有验证依据：**本地消费、账户、数据库重开、归档，以及表达选择、校验和反馈存在自动化测试；仓库历史记录有 macOS 构建及 280 个 XCTest 通过。本轮未重跑这些测试。
- **历史使用 / 验证：**多域与跨域分析已有实际产品使用；表达文档记录过云端 owner Canary 的曝光和点评闭环。不能据此推断当前所有用户开关、五域候选质量或 Local-First 链路已验证。
- **未验证：**本次确定的五域及收入/钱包范围、图片、AI、离线、重启等完整 Phase 1 真机闭环。Windows 不能验证 Swift 编译，后续仍需 macOS CI 和真机验收。
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

- 五域及收入/钱包 Local-First（收入/钱包分别由 SL-A/SL-B 推进）。
- 本地图片生命周期。
- 截图 / 快捷输入本地闭环。
- Hosted AI 与云端业务存储解耦并基于本地正式事实工作；BYOK 暂缓，不作为 Phase 1 blocker。
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

## 13. 真机验收后的下一切片：LOCAL-P1-SPORT-001-G

2026-09-19，PR #199 对应的 TestFlight 构建已上传成功，用户已完成真机验收并确认无阻断问题。下一片固定为运动首片的离线真实图片入口：未登录时从 Today 的相机/相册入口取得图片，打开本地运动记录兜底表单；用户补齐运动事实并保存后，图片通过既有 `LocalRecordUseCase` 写入本地记录目录，沿用本地 hash、导出和删除生命周期。

本片只新增本地手动兜底入口和草稿图片传递，不接入云端 AI 识别、不改变登录态远端 Planner 路由、不修改 Cloud Sync、Outbox、Cursor、Conflict 或 AI Popup / Analysis 算法。行为编号为 `LOCAL-P1-SPORT-001-G`，测试层为 `NativeManualRecordDraft` 状态测试加既有本地图片保存/导出/删除 XCTest；iOS 编译和完整 XCTest 仍以 macOS CI 为准。

本片完成后仍未解决：截图图片直接进入本地候选/中转站、AI source 持久化、图片编辑替换、AI Popup/Analysis 本地读取以及饮食/睡眠/阅读用户闭环。

## 14. G 片与事实来源元数据收口

`LOCAL-P1-SPORT-001-G` 已实现并通过 CI：未登录图片入口转入本地运动兜底表单，保存时图片沿用 `LocalRecordUseCase` 的本地生命周期。随后继续完成 `DM-GAP-02` 的最小模型收敛：`local_records` 与 `local_staging_records` 增加 `source_kind`、`domain_version`，高置信度自动归档、低置信度候选和用户确认分别保留 `ai_auto_archive`、`ai_candidate`、`ai_confirmed` 来源；旧数据库通过 v6 本地迁移补默认值。

`8850c61` 的 G 片已由 macOS iOS workflow `35442948032` 通过 Build、完整 XCTest 和 iOS Build Gate；PWA/Edge、治理、Vercel、Cloudflare 门禁同步通过。来源元数据改动随后由 `f83c951` 加入，并在 `6e1bbc0` 修正中转站 INSERT 占位符后收口；最终 macOS iOS workflow `35444698473` 的 Build、完整 XCTest 和 iOS Build Gate 均通过，PR #199 的 PWA/Edge、治理、Vercel、Cloudflare 门禁也全部通过。未触发新的 TestFlight，当前提交尚未完成新的真机验证。后续仍应围绕本地候选/中转 UI 与 AI 输入适配，不把来源元数据误认为 AI 运行日志，也不扩展 Cloud Sync。

## 15. H 片：本地中转站收件箱闭环

`LOCAL-P1-SPORT-001-H` 将低置信度本地候选投影到既有 Inbox 收件箱：使用 `local-staging/<id>` 路由、本地图片目录 URL 和候选来源元数据；“确认”调用本地 `confirmStaging` 生成正式记录，“销毁”调用本地 `discardStaging` 并沿用图片清理生命周期。中转候选不会进入正式事实读取，且本片不接入远端重试、AI 适配、跨域分析或同步协议。

实现提交为 `9587898`，macOS iOS workflow `35445897681` 已通过模拟器编译、完整 XCTest 和 iOS Build Gate；PR #199 的 PWA/Edge、治理、Vercel、Cloudflare 门禁也全部通过。H 片当前仅在未登录本地路径投影候选；本地候选的编辑、重试和域重判仍明确延期，当前提交未触发新的 TestFlight，尚未完成新的真机验证。

## 16. I 片：确认后正式事实投影

`LOCAL-P1-SPORT-001-I` 补齐 H 片确认后的正式事实可见性：确认候选后，正式记录保留原本地图片引用，中转记录清空图片引用并保留 `archived` 关系；统一事实读取器可读取 `data/<uuid>`，详情读模型保留 `ai_confirmed` 和域版本元数据。`AppState` 在本地确认后刷新对应月份投影，确保 Today/Records 不需要重启即可看到新事实。

实现提交为 `80ff1a4`，macOS iOS workflow `35450693810` 已通过模拟器编译、完整 XCTest 和 iOS Build Gate；截至本记录，PR #199 的 PWA/Edge、治理、Vercel、Cloudflare 门禁也全部通过。随后从文档已固定的提交 `cf6b2e9` 触发 TestFlight workflow `35451820461`，实际 IPA build number 为 `35451820461`，App Store Connect 上传成功，IPA artifact `SnapCount-ipa` 已生成。当前仍需等待 Apple 处理完成后在 TestFlight 中出现，再进行真机验收。

## 17. J 片：真实图片输入与 Hosted AI 识别接入本地生命周期

`LOCAL-P1-SPORT-001-J` 已完成代码实现。Today 的相册/拍照入口和 `UploadScreenshotIntent` 现在先把图片交给本地 `LocalImageRecognitionUseCase`：先写入本地 `intake/`，再调用 Hosted AI 的显式 `operation=recognize_only`，返回 Provider-neutral 的 `local-recognition-candidate-v1` 候选。候选不直接成为云端业务事实，而是交由既有 `LocalRecordUseCase.ingest()` 沿用原阈值与字段完整性规则：高置信度且完整直接视为确认并写入本地正式记录，低置信度或缺关键字段写入本地 staging；完成后刷新 Today/Records/Inbox，数据库和图片目录可在 App 重启后恢复。

本片首先核实了旧 `ingest-receipt` 的边界：默认 `ingest` 会写 Storage，并写入 `transactions`、`income_records`、`data_records`、`staging_records`，还可能写 `ai_recognition_logs`，因此没有把它直接当成本地识别接口。新增的 `recognize_only` 分支只做必要的配置/域读取和 AI 识别，不上传源图到云端 Storage，不创建云端正式记录或云端 staging，不写 AI trace；未显式传 operation 的旧调用仍保持原有 ingest 行为。对 LocalRecordValidation 当前不支持的旧域，登录态仍保留旧 Hosted ingest 兼容回退，故 J 片完成不等于所有历史域都已本地化。

图片保存失败不会留下只有数据库的候选；AI 请求失败按既有本地图片生命周期清理 intake；成功候选按结果移动到 `records/` 或 `staging/`。候选和正式记录 ID 由图片 hash 派生，重试不会生成重复正式事实。新增 `LocalImageRecognitionProvider` / `LocalRecognitionCandidate` 保留 BYOK 复用边界，Hosted AI 返回结构不成为唯一 Provider 模型。J 片不修改 Cloud Sync、Outbox、Cursor、冲突协议、AI Popup、Expression Planner 或跨域 Analysis。

J 片提交为 `3c78b1e`、`37d010a`、`2db3640`、`77758ca`、`3731121`，分支为 `codex/local-first-phase1-fact-reader`，PR 为 [#199](https://github.com/shenfn/SnapCount/pull/199)。本地 `npm run test:local-recognition-boundary` 4/4、`npm run build`、`git diff --check` 均通过；macOS iOS workflow `35480060158` 的 simulator build、完整 XCTest（306 tests，0 failures）和 iOS Build Gate 全部通过。未执行生产迁移、Edge Function 部署或 TestFlight 上传。

J 片尚未验证真实 Hosted AI 网络样本、真机相机/相册/快捷指令权限与后台生命周期、重启后的图片展示、登录/未登录实际操作及旧域回退行为。下一次 TestFlight 需要固定验证：支持域在登录和未登录两态都只在本地生成正式事实；低置信度和字段缺失只进本地 Inbox；重试不重复；App 重启后 Today/Records/Inbox 与图片仍在；并通过 Supabase 侧核对 recognize-only 请求没有新增业务记录。

## 18. K 片：recognize_only 上线与真实 AI 链路验收

K 片完成了 J 片 `recognize_only` 的生产上线和生产 AI smoke，但把“生产候选边界已证明”和“真机本地事实链路已证明”明确区分。

- 生产部署前 version `198` 的 `ingest-receipt` 源码与 `ab6ed3f` 完全一致，尚未包含 `recognize_only`；其余 `generate-insights` version `26` 未变。
- J 片曾让无 JWT / `upload_token` 的 `recognize_only` 请求绕过认证。K 片先以 `LOCAL-P1-SPORT-001-K-001` 固定红灯，再在 `21644b5` 恢复既有 Hosted AI 认证边界：函数内部必须有 JWT 或 `upload_token`，没有开放匿名 Hosted AI；`verify_jwt=false` 配置保持原样。BYOK 本片未实现或验证。
- 生产仅部署 `ingest-receipt` version `199`（`2026-09-20T03:38:04Z`，`ezbr_sha256=c813a222797d61b0e380e17bf923b3afd6cfffcfe3bc748799acceb501151af4`），未执行数据库迁移、未修改 Cloud Sync、未部署其他 Edge Function。回滚点是 version `198` / `ab6ed3f`，从该提交重新部署同一函数即可回滚。
- 生产无认证 smoke 返回 `401`。使用 `docs/cases/cycling.jpg` 的认证 smoke 返回 `200` Provider-neutral candidate：`domain_key=sport`、`confidence=1`、`missing_fields=[]`，证据字段和 payload 完整。
- 该认证 smoke 前后针对测试账号的云端计数保持不变：`transactions 72→72`、`data_records 17→17`、`staging_records 31→31`、`ai_recognition_logs 70→70`；`receipt-images/recognize-only/910e13cf2c96` 对象数 `0→0`。1×1 PNG 的 AI 失败请求返回 `502 AI_PROVIDER_ERROR`，同样没有业务写入。
- PR #199 Release Validation `35486659827`、macOS iOS workflow `35486659801` 均通过；完整 XCTest 为 306 tests、0 failures。TestFlight workflow `35487465615` 从固定提交 `21644b595c264d9daff7eb6d008350cc6de0e9ad` 触发，IPA build number 为 `35487465615`，上传成功并生成 `SnapCount-ipa` artifact。
- 代码审计和 smoke 均支持：Hosted AI 只返回候选、域、置信度、证据、hash 和 provider metadata，不进入云端业务事实存储；旧 `ingest` 默认路径和认证策略未被改写。
- K 片当前停点：生产 Edge 的真实 AI 候选和零云端业务写入已经证明；TestFlight 真机相机/相册/快捷指令、置信度高低路由、Inbox 确认、重启、断网、登录/退出登录与本地图片展示仍待用户在 iPhone 上验证。未完成真机清单前，不将完整“真实 AI → 本地自动归档/staging → 本地正式事实”宣称为已闭环，也不开始饮食、睡眠、阅读扩展。
- 真机验收应使用 build `35487465615`：登录后分别测试相册、相机、快捷指令；高置信度完整运动候选检查 Today/Records，低置信度或缺字段检查 Inbox；再测同图重试、Inbox 确认、重启、断网编辑删除、登录/退出登录切换，并用同一生产测试时间窗口复核三张业务表和 Storage 无对应新增。

## 19. L 片：退出登录后的本地 Inbox 与详情投影恢复

用户真机验收发现：退出登录后选择相册会正确回到本地手动录入，但本地中转站显示为空，部分记录详情疑似回退到需要登录的远端路径。只读核查确认本地 staging 没有被删除；`resetUserScopedState()` 清空了内存 dashboard，而 Inbox 的 `.task` 只加载远端 repayment 候选，没有重新调用本地 staging 投影。这是本地读取缺口，不是产品规则，也不改变 Hosted AI 认证边界。

`LOCAL-P1-SPORT-001-L` 的最小修复为：

- `AppState.refreshInboxProjection()` 在未登录时重建本地正式事实与 staging 投影，登录时继续只加载既有远端 repayment 候选；
- Inbox 主页面、分类页面和下拉刷新统一使用该入口，未登录刷新不再请求远端 dashboard；
- `loadRecordDetail()` 在远端回退前查询本地通用记录和本地消费，避免退出登录后因内存缓存已清空而把本地事实误判为远端记录；
- 未修改登录认证、AI 置信度阈值、图片生命周期、Cloud Sync、Outbox、数据库迁移、Edge Function 或 Planner/Analysis。

新增 `LocalFirstLogoutProjectionTests`，场景覆盖 `LOCAL-P1-SPORT-001-L`：退出登录后本地 staging 重新出现在 Inbox；本地运动详情和本地消费详情在没有 session 的情况下直接从本地读取，且不触发远端 session 查询。Windows 仍无 `xcodebuild`/Swift 工具链；macOS iOS workflow `35510609001` 的 simulator build、完整 XCTest 和 iOS Build Gate 已通过，Release Validation `35510608995` 也已通过。真机验证待进行；修复完成后需要从固定提交 `27ab2c4` 重新生成 TestFlight，不能继续把旧 build `35487465615` 当作包含本修复的版本。

## 20. SL-01：文档口径收口（2026-09-25）

本片只修正文档基线，不修改业务代码、Spec 场景编号、同步协议或发布配置：

- §3 已反映事实：未登录四域手动创建已经走本地记录路径；完整候选、图片和用户闭环仍按后续 Slice 推进。
- Phase 1 产品范围按 Q-01 纳入收入与钱包快照，分别排入 SL-A/SL-B；BYOK 按 Q-06 暂缓移出 Phase 1。
- 共享事实引用以代码已验证的 `local-staging/<id>` 为准；`staging/<id>` 只保留为历史文档误写说明。
- Q-07（DM-GAP-10）维持“消费必须选账户”，Q-12 维持计数级绑定预览；两项不进入当前实现 Slice。

下一 Slice 为 SL-02：投影刷新收敛与特征测试加固。同步、迁移、PWA 结构、生产部署和 TestFlight 仍冻结。
