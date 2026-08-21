# A4-IOS-006 iOS 截图还款候选与确认红灯执行记录

> 状态：实现完成，macOS Swift/XCTest 与全部适用门禁通过
>
> 日期：2026-08-21
>
> 基线：`a3ff6ed`（A4-IOS-006 评估 PR #129 合并提交）

## 本次目标

只固定截图还款确认的纯 Swift 编排缺口，不修改生产实现、数据库、PWA、Edge 或 Planner。

## 红灯内容

- `ios/SnapCountTests/ScreenshotRepaymentUseCaseTests.swift`
  - A4-IOS-006B：同命令 Task 复用、不同命令冲突；
  - A4-IOS-006C：未登录/非法输入在 transport 前拒绝；
  - A4-IOS-006D：reset 后旧 transport 结果为 stale，不执行 hooks；
  - A4-IOS-006E：accepted 先投影 canonical cycle，再刷新；
  - A4-IOS-006F：刷新失败仍保留 accepted 事实。
- `scripts/test-ios-screenshot-repayment-boundary.mjs`
  - Use Case 不得依赖 SwiftUI、Supabase 或 HTTP；
  - AppState 不得直接调用截图还款 RPC；
  - Inbox Repository 必须返回 canonical `NativeRepaymentCycle`；
  - XCTest 场景必须存在。

## 红灯转绿与最小实现

已完成窄 Use Case、Repository canonical cycle transport 和 AppState 兼容投影：

- `ScreenshotRepaymentUseCase` 负责同命令复用、冲突、用户/generation stale、accepted 与 refresh 分层；
- `InboxRepository` 只负责 RPC transport，并返回服务端 canonical `NativeRepaymentCycle`；
- `AppState` 只保留兼容入口、状态投影和账户/dashboard 刷新协调；
- 服务端 `p_status` 传 `null`，状态继续由数据库规则计算，不由客户端写死 `paid`。

## 当前失败证据

初始 `npm run test:ios-screenshot-repayment-boundary`：

- 失败：`ScreenshotRepaymentUseCase.swift` 尚不存在；
- 失败：AppState 尚未接入 `ScreenshotRepaymentUseCase`，仍直接调用 `inboxRepository.confirmStagingRepayment`；
- 通过：场景 XCTest 文件已包含 006B 至 006F。

这些失败是预期的 TDD 红灯，已由最小实现转绿。

## 当前验证证据

Windows 静态与跨模块回归已通过：

- `npm run test:ios-screenshot-repayment-boundary`
- `npm run test:ios-repayment-action-boundary`
- `npm run test:ios-account-read-boundary`
- `npm run governance:check`
- `npm run governance:arch`
- `npm run build`
- `git diff --check`

macOS GitHub Actions 已通过：

- Run `32501880601`：模拟器构建、全部 `SnapCountTests` XCTest 和 iOS Build Gate 通过；
- Release Validation、两组 Governance Validation 和部署预览检查通过。

架构检查仅保留既有人工基线警告；Windows 无法运行 Swift/XCTest，需以 GitHub macOS iOS Build/XCTest 为最终依据。

## 验证限制

- Windows 无 Swift/Xcode；XCTest 已由 GitHub macOS Build 权威验证。
- 尚未执行生产查询、migration、部署、真实账户写入或 TestFlight。
