# A4-IOS-008 iOS 中转生命周期动作编排执行记录

> 状态：A4-IOS-008A-H 红灯已建立，尚未进入最小实现
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

## 红灯验证

- `npm run test:ios-staging-lifecycle-boundary`：A4-IOS-008A-H 场景登记通过；Use Case 文件缺失、Repository 仍返回旧 `Void`/`ShortcutUploadResult`/`String`、AppState 仍直调 transport 等 4 项边界断言按预期失败。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过；仅保留既有人工清单警告。
- `git diff --check`：通过。
- Windows 未运行 Swift/XCTest；后续以 GitHub macOS iOS Build/XCTest 为编译和业务测试权威。

## 进入最小实现的顺序

1. 先让 `InboxRepository` 返回丢弃、重试、归档的结构化事实，不改变 RPC/Edge 参数。
2. 建立不依赖 SwiftUI、Supabase 或 HTTP 的 `StagingLifecycleUseCase`，实现认证、并发、reset/generation stale 和 accepted/refresh 分层。
3. 最后把 `AppState` 三个公开入口改成兼容投影，保留页面导航和已有消息出口。
4. macOS 门禁通过前不进入下一片，不执行生产迁移、部署、真实数据写入或 TestFlight。

## 冻结范围

- 根工作区和其他 worktree 的 WIP 不在本任务中处理。
- 不修改 PWA、Edge、数据库 migration、Planner、页面视觉、导航结构或生产配置。
