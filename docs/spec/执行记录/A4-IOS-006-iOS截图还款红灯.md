# A4-IOS-006 iOS 截图还款候选与确认红灯执行记录

> 状态：红灯已建立
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

## 当前失败证据

`npm run test:ios-screenshot-repayment-boundary`：

- 失败：`ScreenshotRepaymentUseCase.swift` 尚不存在；
- 失败：AppState 尚未接入 `ScreenshotRepaymentUseCase`，仍直接调用 `inboxRepository.confirmStagingRepayment`；
- 通过：场景 XCTest 文件已包含 006B 至 006F。

这些失败是预期的 TDD 红灯，下一步只实现窄 Use Case、Repository canonical cycle transport 和 AppState 兼容投影。

## 验证限制

- Windows 无 Swift/Xcode，尚未运行 XCTest；以 GitHub macOS Build 为权威。
- 尚未执行生产查询、migration、部署、真实账户写入或 TestFlight。
