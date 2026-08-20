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

待添加并运行 A4-IOS-004A-H 测试后填写。Windows 无 Swift/Xcode 时，需区分“测试代码已建立但本地环境无法编译”和“业务断言失败”，最终以 GitHub macOS Build/XCTest 为准。

## 未验证与下一步

- 尚未运行 Swift XCTest；当前只完成规格文件建立。
- 下一步：添加专项 XCTest 和 Repository 源边界检查，提交可复现红灯。
- 红灯合并后，从同一分支开始最小实现；不新增数据库迁移或生产部署。
