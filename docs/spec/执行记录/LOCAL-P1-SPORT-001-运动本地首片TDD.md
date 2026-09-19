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
- 绿灯结果：待 macOS CI 验证，不能据此声称已通过。
- PWA/iOS 差异：本轮只实现 iOS 本地事实；PWA 继续读取云端副本，不改 PWA。
- GitHub CI 结果：待验证。
- 未解决风险：本地文件删除与数据库 tombstone 不是同一物理事务；现有截图 AI / Hosted AI 结果尚未接入 `LocalRecordUseCase.ingest`；登录态仍会保留远端刷新并和本地事实合并展示，这是当前兼容策略而非 Cloud Sync；通用记录的 AI source 持久化、AI Popup/Analysis 本地读取、真实图片输入和完整真机链路仍需逐步实现。
- 本轮修改文件：上一轮列出的本地数据与 App 接线文件，以及本轮的 `AppState.swift`、`LocalFactReader.swift`、`LocalFactReadModel.swift`、`LocalFactPortability.swift`、`LocalPhase1DataModelTests.swift`。
- 本轮可执行验证：`git diff --check` 通过；已确认 `project.yml` 以目录方式收录 App/Test 源码；已确认 Windows 环境无 `xcodebuild`、`xcodegen` 和 Swift toolchain，因此 XCTest、iOS 编译和真机链路未验证；对应 macOS 工作流为 `.github/workflows/ios-build.yml`，当前未对未提交工作区触发远端运行。
- 保护边界：未修改同步协议、Outbox、Cursor、Conflict、`LocalSyncCoordinator`、AI Popup / Expression Planner 算法或生产配置；现有工作区其他 WIP 未清理、未归类、未提交。
- 对应提交：未提交。
