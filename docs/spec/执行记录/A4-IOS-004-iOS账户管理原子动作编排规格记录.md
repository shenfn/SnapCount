# A4-IOS-004 TDD 执行记录：iOS 账户管理原子动作编排

## 当前状态

- 任务：A4-IOS-004 账户管理原子动作编排。
- 阶段：A4 iOS 业务编排收拢。
- 基线：`d5dc62f`，A4-IOS-004 评估 PR #123 合并提交。
- 当前 worktree：`D:\Business\count\.worktrees\A4-IOS-004账户管理红灯`。
- 当前分支：`test/A4-IOS-004账户管理红灯`。
- 当前阶段：红灯已确认，最小实现已在同一分支完成，等待 macOS CI 转绿。

## 权威来源

- `docs/spec/模块/iOS业务边界/账户管理原子动作编排边界评估.md`
- `docs/spec/模块/iOS业务边界/账户管理原子动作编排规格说明.md`
- `docs/decisions/ADR-031-iOS账户管理接入数据库原子契约.md`
- PWA-066 账户管理规格与 `20260816160000_account_management_atomic_contract.sql`

## 本轮范围

本轮先提交正式 Spec，随后仅添加 A4-IOS-004A-H 的 XCTest/源边界红灯。不得在红灯提交中修改 `AccountRepository`、`AppState`、数据库或页面实现。

## 红灯证据

2026-08-20 已添加 `AccountManagementActionUseCaseTests.swift` 的 A4-IOS-004A-H 场景和 `test:ios-account-management-action-boundary` 源边界检查。

本地 Node 红灯结果：5 个子测试中 1 个通过、4 个按预期失败：

- `save_account` 尚未出现在 iOS `AccountRepository`；
- `set_account_archived` 尚未出现在 iOS `AccountRepository`；
- `AccountManagementActionUseCase.swift` 尚不存在；
- AppState 尚未委托账户管理 Use Case。

同时 A4-IOS-004A-H 场景追踪检查通过，`node --check`、`npm run governance:check` 和 `git diff --check` 通过。Windows 无 Swift/Xcode，XCTest 编译红灯需由 GitHub macOS runner 复核，不能把本地工具缺失写成业务结论。

## 最小实现进展

已新增纯 Swift `AccountManagementActionUseCase`，实现同命令复用、跨命令冲突、reset/user stale 和 accepted/refresh 分层；`AccountRepository` 已实现 `AccountManagementRepositoryProtocol`，保存/归档分别调用 `save_account` / `set_account_archived`；AppState 保留公开入口并通过 Use Case 投影 canonical account。

本地 `npm run test:ios-account-management-action-boundary` 已 5/5 通过；新增 Repository XCTest 固定 RPC 名称、参数、无 `user_id` 旁路和 malformed response 失败。

第三轮 macOS workflow `32381458280` 在 runner 长时间无终态日志后由本任务主动取消，属于环境级未验证；不计入业务通过或失败。取消前未出现新的编译错误输出。

## 未验证与下一步

- 尚未运行 Swift XCTest；实现提交等待 GitHub macOS Build/XCTest 验证。
- 下一步：若 macOS 编译通过，运行完整 PWA/Edge、治理和架构回归；若失败，只修当前账户管理切片，不扩大到账户读取或截图还款。
- 红灯合并后，从同一分支开始最小实现；不新增数据库迁移或生产部署。
