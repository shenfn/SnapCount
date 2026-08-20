# A4-IOS-004 TDD 执行记录：iOS 账户管理原子动作编排

## 当前状态

- 任务：A4-IOS-004 账户管理原子动作编排。
- 阶段：A4 iOS 业务编排收拢。
- 基线：`d5dc62f`，A4-IOS-004 评估 PR #123 合并提交。
- 当前 worktree：`D:\Business\count\.worktrees\A4-IOS-004账户管理红灯`。
- 当前分支：`test/A4-IOS-004账户管理红灯`。
- 当前阶段：正式 Spec 已建立，准备提交 XCTest 红灯。

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

## 未验证与下一步

- 尚未运行 Swift XCTest；当前红灯提交包含测试代码但缺少预期的业务类型/实现。
- 下一步：推送红灯提交并取得 macOS Build/XCTest 失败证据；随后在同一任务下按最小实现顺序补 Repository、Use Case 和 AppState。
- 红灯合并后，从同一分支开始最小实现；不新增数据库迁移或生产部署。
