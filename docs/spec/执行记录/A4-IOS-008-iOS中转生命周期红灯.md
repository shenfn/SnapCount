# A4-IOS-008 iOS 中转生命周期动作编排执行记录

> 状态：最小实现已接入，等待 macOS XCTest/门禁验证
>
> 日期：2026-08-22
>
> 基线：`590deca8`（A4-IOS-008 边界评估合并提交）

## 本次范围

本片固定 iOS 中转丢弃、重试、归档三个写动作的 Use Case 边界。待补全确认、截图还款、图片签名、正式记录保存/删除、记录详情读取和表达反馈继续冻结。

## 红灯产物

- 新增 `ios/SnapCountTests/StagingLifecycleUseCaseTests.swift`，登记 A4-IOS-008A-H：输入拒绝、同命令复用/冲突、丢弃清理事实、重试 route、归档 target/idempotent、accepted/refresh 分层、reset stale 和边界隔离。
- 新增 `scripts/test-ios-staging-lifecycle-boundary.mjs`，固定 Use Case 不依赖 UI/transport、Repository 返回结构化结果、AppState 仅做兼容投影和非目标隔离。
- 新增 `npm run test:ios-staging-lifecycle-boundary`。
- 阶段索引切换到 A4-IOS-008A-H 红灯，当前工作分支为 `test/A4-IOS-008中转生命周期红灯`。

## 最小实现进展

- `InboxRepository` 和 `NativeDataService` 现在返回丢弃清理状态、重试 route/提示和归档 target/idempotent 的结构化结果；RPC、Edge endpoint 和归档 payload 参数未改变。
- 新增纯编排 `StagingLifecycleUseCase`，统一认证、同记录命令复用/冲突、reset stale、accepted/refresh 分层和一次写后刷新。
- `AppState` 保留三个中转公开入口，只负责 busy、导航、消息和本地读模型兼容投影；用户 reset 会重置 Use Case。
- 更新既有 `InboxRepositoryProtocol` 测试 stub，避免结构化返回变更污染其他测试。

## 红灯验证

- `npm run test:ios-staging-lifecycle-boundary`：A4-IOS-008A-H 场景登记通过；Use Case 文件缺失、Repository 仍返回旧 `Void`/`ShortcutUploadResult`/`String`、AppState 仍直调 transport 等 4 项边界断言按预期失败。
- 最小实现接入后再次运行 `npm run test:ios-staging-lifecycle-boundary`：5 项源边界检查全部通过。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过；仅保留既有人工清单警告。
- `git diff --check`：通过。
- Windows 未运行 Swift/XCTest；后续以 GitHub macOS iOS Build/XCTest 为编译和业务测试权威。

## 后续验证顺序

1. 以 GitHub macOS XCTest 验证 A4-IOS-008A-H 的运行时行为和编译。
2. 若出现失败，按业务失败、环境失败和测试契约错误分层处理，不把门禁红灯直接视为实现完成。
3. macOS、Release、治理、源边界全部通过后，更新阶段索引和交接快照并进入下一片只读评估。
4. 验证完成前不执行生产迁移、部署、真实数据写入或 TestFlight。

## 冻结范围

- 根工作区和其他 worktree 的 WIP 不在本任务中处理。
- 不修改 PWA、Edge、数据库 migration、Planner、页面视觉、导航结构或生产配置。
