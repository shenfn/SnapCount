# LOCAL-002-APP 免登录接线红灯记录

> 日期：2026-08-23
>
> 分支：`test/LOCAL-002-APP免登录红灯`
>
> 基线：`6415f13`

## 红灯目标

固定 `LOCAL-002-APP` 的四个缺口：本地 profile 生命周期、本地消费 Use Case、表单 mapper、本地读模型，以及 AppState 不再直接以远端 session 作为本地消费保存前置。

## 新增测试

- `ios/SnapCountTests/LocalExpenseAppUseCaseTests.swift`
- `scripts/test-ios-local-expense-app-boundary.mjs`
- `npm run test:ios-local-expense-app-boundary`

## 预期红灯

- `LocalProfileStoreProtocol`、`LocalProfileStore`、`LocalExpenseUseCaseProtocol` 尚不存在，macOS XCTest 编译应失败；
- 本地 profile 没有恢复入口；
- AppState 的 `createManualRecord` 仍先调用 `validSession()` 再调用远端 `RecordRepository`；
- mapper 和本地 expense read model 文件尚不存在。

这些失败是业务缺口，不是环境失败。Windows 不运行 Swift 编译；最终红灯/绿灯以 GitHub macOS iOS Build 和 XCTest 为准。

## 最小实现顺序

1. `LocalProfileStore`：单 profile 创建/恢复，不调用 Supabase；
2. `LocalExpenseMapper` 与 `LocalExpenseReadModel`：Decimal/minor、账户归属、日期和本地引用；
3. `LocalExpenseUseCase`：只编排已有 Local Repository，不复制事务；
4. AppState 兼容门面和本地记录查询接线；
5. 完整 XCTest、macOS Build、治理和源边界回归。
