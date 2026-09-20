# LOCAL-P1-SPORT-001 运动域 Local-First 首片 TDD 执行记录

- 目标行为：运动记录作为第一个非 Expense Local-First 样板，完成本地正式记录、候选路由、中转确认、读取、编辑、删除、重启恢复和图片生命周期基础闭环。
- 当前行为：本地 GRDB 既有 Profile、Account、Expense、流水和 Outbox；本轮在不改变同步主线的前提下补充了通用本地记录、运动域读模型、中转状态和本地附件闭环。
- 权威来源：`docs/spec/LOCAL-FIRST-PHASE1-HANDOFF.md`、`docs/spec/LOCAL-FIRST-PHASE1-FIRST-SLICE.md`、用户确认的本轮开发范围。
- 场景编号：`LOCAL-P1-SPORT-001-A` 至 `LOCAL-P1-SPORT-001-F`；模型收敛补充 `LOCAL-P1-DM-001`、`003`、`006`、`008`、`009`。
- 本轮范围：本地通用生活数据记录基座先支持 `sport`；保留 `food`、`sleep`、`reading` 的 domain key 和 payload 扩展边界；接入本地记录读模型、版本删除语义、中转候选路由和本地图片存储。
- 非范围：Cloud Sync、Outbox/Cursor/Conflict 协议、生产迁移、PWA、AI Popup / Expression Planner 算法重设计、BYOK/Hosted AI provider 实现重写。
- 预计修改文件：`ios/SnapCount/LocalData/`、`ios/SnapCount/Features/Records/`、必要的 `AppState`/本地图片展示适配、`ios/SnapCountTests/`。
- 基线测试结果：Windows 无 `xcodebuild`、`xcodegen` 和 Swift toolchain；未运行 XCTest。macOS CI 是 iOS 编译与测试权威。
- 红灯测试及失败原因：专项测试先固定本地运动记录、候选路由、中转确认、版本删除、图片生命周期和导出图片；本轮新增模型红灯覆盖消费与通用表隔离、域阈值与事实完整性、睡眠分钟归一化、时间格式、中转确认幂等和过期版本。Windows 无 Swift toolchain，未能取得本地红灯输出。
- 最小实现：在既有 v4 基础上补充 `local_staging_records` v5 归档目标/解析字段；Repository 拒绝通用消费、确认中转站幂等；Use Case/Codec 采用域阈值、最小事实校验、睡眠分钟归一化和时间格式校验；新增 `LocalFactReader`、`LocalFactReadModel` 和 `LocalFactPortability`，把消费与四个非财务域合并为正式事实读取，接入本地 Today/Records 和离线通用导出，并排除中转与墓碑；未修改 Outbox、Cursor、Conflict 或同步协调器。
- 绿灯结果：macOS CI 已通过；新增 `LOCAL-P1-DM-*` 与 `LOCAL-P1-SPORT-001` 专项测试，以及完整既有 XCTest 均通过。
- PWA/iOS 差异：本轮只实现 iOS 本地事实；PWA 继续读取云端副本，不改 PWA。
- GitHub CI 结果：PR #199 的 iOS workflow `35431410842` 已通过应用编译、完整 XCTest 和 iOS Build Gate；PWA/迁移、治理、预览和部署检查同步通过。
- 未解决风险：本地文件删除与数据库 tombstone 不是同一物理事务；现有截图 AI / Hosted AI 结果尚未接入 `LocalRecordUseCase.ingest`；登录态仍会保留远端刷新并和本地事实合并展示，这是当前兼容策略而非 Cloud Sync；通用记录的 AI source 持久化、AI Popup/Analysis 本地读取、真实图片输入和完整真机链路仍需逐步实现。
- 本轮修改文件：上一轮列出的本地数据与 App 接线文件，以及本轮的 `AppState.swift`、`LocalFactReader.swift`、`LocalFactReadModel.swift`、`LocalFactPortability.swift`、`LocalPhase1DataModelTests.swift`。
- 本轮可执行验证：`git diff --check` 通过；已确认 `project.yml` 以目录方式收录 App/Test 源码；Windows 环境无 `xcodebuild`、`xcodegen` 和 Swift toolchain；macOS workflow `.github/workflows/ios-build.yml` 已远端验证编译与 XCTest，真机链路仍未验证。
- 保护边界：未修改同步协议、Outbox、Cursor、Conflict、`LocalSyncCoordinator`、AI Popup / Expression Planner 算法或生产配置；现有工作区其他 WIP 未清理、未归类、未提交。
- 对应分支：`codex/local-first-phase1-fact-reader`；PR：`https://github.com/shenfn/SnapCount/pull/199`；最终代码提交：`11a5518`。

## 后续切片：LOCAL-P1-SPORT-001-G

- 进入条件：PR #199 的 TestFlight 构建 `35432794401` 上传成功，用户已完成真机验收并确认无阻断问题。
- 目标行为：未登录时从 Today 的相机/相册入口取得图片，进入本地运动记录兜底表单；保存后图片与运动正式记录一起落入本地生命周期。
- 红灯：`testLOCALP1SPORT001GLocalCaptureDraftRetainsImageForLocalSave` 固定草稿必须保留图片数据、运动域和通用记录类型。
- 最小实现：`NativeManualRecordDraft` 增加图片数据承载；`TodayView` 在未登录图片入口转入 `ManualRecordSheet(initialImageData:)`；表单提供本地预览、拍照、相册选择、替换和移除；`AppState.createLocalDomainRecord` 将图片交给既有 `LocalRecordUseCase.create`。
- 保护边界：登录态仍走既有云端图片上传；不改变 AI 识别、中转协议、同步协议、Outbox/Cursor/Conflict、AI Popup 或 Analysis。
- 验证：Windows 只执行 `git diff --check` 和静态核对；必须由 macOS GitHub Actions 完成 Swift 编译与完整 XCTest，再安排下一次真机验收。

## DM-GAP-02 最小模型收敛

- 在 `local_records` 和 `local_staging_records` 增加 `source_kind` 与 `domain_version`；旧本地库由 `local-v6-phase1-fact-provenance` 补齐默认值。
- 高置信度自动归档记录为 `ai_auto_archive`，低置信度候选记录为 `ai_candidate`，中转站确认后的正式记录记录为 `ai_confirmed`；手动记录默认 `manual`。
- `LocalFactReader` 与本地导出读取并保留这两个元数据，不把 AI 原始响应、提示词或 token 写入正式事实。
- 新增 `testLOCALP1DM002IntakePreservesCandidateAndFormalSourceKinds`，固定候选、自动归档和确认后的来源边界。
- G 片的 macOS Build/XCTest workflow `35442948032`、iOS Build Gate、PWA/Edge、治理、Vercel 和 Cloudflare 均通过；来源元数据改动在 `f83c951` 加入，并由 `6e1bbc0` 修正中转站 INSERT 占位符后通过最终 workflow `35444698473` 的 Build、完整 XCTest、iOS Build Gate 及 PR 全部门禁。未触发新的 TestFlight，当前提交尚未完成新的真机验证。

## 后续切片：LOCAL-P1-SPORT-001-H

- 目标行为：将未登录本地低置信度候选投影到既有 Inbox，使用 `local-staging/<id>` 路由展示本地图片和候选元数据；确认进入本地正式记录，销毁走本地中转删除并清理图片。
- 红灯：`testLOCALP1SPORT001HLocalStagingProjectsToInboxWithLocalImageRoute` 固定本地候选到收件箱的路由、运动域、置信度、待确认状态、本地图片 URL 和本地 ID 往返映射。
- 最小实现：新增 `LocalStagingReadModel`；`AppState` 在离线本地加载后投影候选，并将本地 Inbox 确认/销毁路由到既有 `LocalRecordUseCase`；Inbox 隐藏本地候选不支持的远端重试、编辑和域重判入口。
- 保护边界：不改变远端中转站、不增加 AI provider 适配、不修改 Cloud Sync、Outbox/Cursor/Conflict、AI Popup 或 Analysis 算法；候选仍排除在 `LocalFactReader` 正式事实之外。
- 验证：macOS iOS workflow `35445897681` 已通过模拟器编译、完整 XCTest 和 iOS Build Gate；PR #199 的 PWA/Edge、治理、Vercel、Cloudflare 门禁全部通过。当前 H 代码未重新上传 TestFlight，真机验证仍未完成。

## 后续切片：LOCAL-P1-SPORT-001-I

- 目标行为：确认本地运动候选后，正式记录立即进入统一事实读取，保留原本地图片引用；中转行变为 `archived`、清空图片引用；详情继续显示 `ai_confirmed` 来源和域版本。
- 红灯：`testLOCALP1SPORT001IConfirmedCandidateBecomesFormalFactWithImageAndSource` 固定正式记录 ID、来源、图片路径、图片文件存在、中转归档状态、统一事实引用和详情来源元数据。
- 最小实现：本地确认后刷新对应月份的本地事实投影；`LocalRecordReadModel` 不再把所有通用本地记录伪装成 `manual`/`local-v1`，而是读取持久化来源与域版本。
- 保护边界：不改变远端中转站、不扩展 AI provider、不修改 Cloud Sync、Outbox/Cursor/Conflict、AI Popup 或 Analysis 算法。
- 验证：macOS iOS workflow `35450693810` 的模拟器编译、完整 XCTest 和 iOS Build Gate 已通过；PR #199 的 PWA/Edge、治理、Vercel、Cloudflare 门禁全部通过。随后从固定提交 `cf6b2e9` 触发 TestFlight workflow `35451820461`，IPA build number 为 `35451820461`，App Store Connect 上传成功，IPA artifact `SnapCount-ipa` 已生成；Apple 处理完成和真机验证待进行。

## 当前切片：LOCAL-P1-SPORT-001-J

- 目标行为：把 Today 的选择图片/拍照、相册入口和快捷输入接入本地图片生命周期；图片先保存到本地 `intake/`，再调用 Hosted AI 的 `operation=recognize_only`；结构化候选使用 Provider-neutral envelope 返回 iOS，由既有 `LocalRecordUseCase.ingest()` 沿用现有阈值与事实完整性口径路由。高置信度且字段完整直接作为已确认的本地正式事实，低置信度或关键字段缺失进入本地 staging；Today、Records、Inbox 在完成后刷新，重启后由本地数据库和图片目录恢复。
- 产品口径：沿用既有规则，不改变“高置信度且完整即直接确认/自动归档”的语义；AI Provider 不拥有存储决策，Hosted AI 返回值不是云端业务事实，用户确认后的本地修改仍优先于 AI 原始候选。Phase 1 不扩展 Cloud Sync、Outbox、冲突协议、AI Popup、Expression Planner 或跨域 Analysis。
- 风险核查结论：旧 `ingest-receipt` 默认 `ingest` 分支会写 Storage，并插入 `transactions`、`income_records`、`data_records`、`staging_records`，还可能写 `ai_recognition_logs`，不能直接作为本地识别接口。J 片新增显式 `operation=recognize_only` 分支：只读取必要的域/Provider 配置并调用既有 Prompt、字段映射和置信度语义，不上传源图到云端 Storage，不创建云端正式记录或云端 staging，不写 AI trace；旧调用未带 operation 时仍保持 legacy ingest 行为。
- 真实入口：Today 的相册/拍照上传路径和 `UploadScreenshotIntent` 均先走本地 Hosted AI 识别；支持本地通用记录域的候选由本地 use case 保存。对当前 LocalRecordValidation 不支持的旧域，登录态保留旧 Hosted ingest 兼容回退，因此这些旧域仍可能产生云端业务记录；这不是 J 片本地运动/通用记录路径的保存方式，后续应按域收敛而不是扩大 J 片范围。
- 图片生命周期：AI 请求前先写入本地 `intake/`；成功后由 `LocalRecordUseCase` 移动到 `records/` 或 `staging/`，失败时清理 intake，图片保存失败时不会创建数据库候选。正式记录保存本地图片引用，staging 保存本地图片引用；重试使用图片 hash 派生的候选/记录 ID 幂等，避免重复正式事实。
- Provider 边界：新增 `LocalImageRecognitionProvider` 与 `LocalRecognitionCandidate`；Hosted AI 仅负责把 `local-recognition-candidate-v1` 解码为中立候选，后续 BYOK 可复用同一候选结构，不把 Hosted AI 响应字段直接固化为唯一业务模型。
- 红灯/测试覆盖：新增 `LocalImageRecognitionTests` 覆盖高置信度完整运动直接正式归档、低置信度 staging、高置信度缺关键字段 staging、图片保存失败无半成品、AI 请求失败清理 intake、相同图片重试幂等；新增 `test:local-recognition-boundary` 静态契约测试覆盖显式 recognize-only、Provider-neutral envelope、无云端业务/源图写入和 legacy ingest 默认行为。H/I 片既有 XCTest 继续覆盖本地 Inbox/Today/Records 投影、确认/删除和重启恢复；完整回归共 306 tests。
- 实现提交：`3c78b1e`（J 片主体）、`37d010a`、`2db3640`、`77758ca`、`3731121`（编译与测试修复）；分支 `codex/local-first-phase1-fact-reader`。
- 验证结果：`npm run test:local-recognition-boundary` 通过 4/4；`npm run build` 通过；`git diff --check` 通过；macOS iOS workflow `35480060158` 的 simulator build、完整 XCTest（306 tests，0 failures）和 iOS Build Gate 全部通过。Windows 无 Swift/Xcode toolchain；未执行生产迁移、Edge Function 部署或 TestFlight 上传。
- 未验证：真实 Hosted AI 网络请求的线上返回样本、相机/相册/快捷指令在真机上的权限与后台生命周期、重启后的实机图片展示、登录/未登录两态实际操作、旧域兼容回退是否符合产品预期；下一次 TestFlight 应专门验证这些链路，并确认支持域不出现云端业务写入。
