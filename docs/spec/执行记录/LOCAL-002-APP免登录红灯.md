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

## 首轮红灯结果

- 初始红灯已证明 `LocalProfileStore`、`LocalExpenseUseCase`、mapper/read model 和 AppState 接线均缺失。
- 已完成最小基础实现：profile 单例恢复、Local Repository profile/account/month 查询、Use Case、Decimal/minor mapper 和 expense read model。
- 当前 Node 边界仍保留 1 项有效红灯：AppState 的 `createManualRecord` 仍先调用 `validSession()` 再调用远端 `RecordRepository`。

这些失败是业务缺口，不是环境失败。Windows 不运行 Swift 编译；最终红灯/绿灯以 GitHub macOS iOS Build 和 XCTest 为准。

## 下一步实现顺序

1. 取得 macOS CI 对当前基础实现的编译证据；
2. 建立不复制 local/cloud 事务语义的 AppState 兼容门面；
3. 接入本地记录查询投影和无 session 网络闸门；
4. 完整 XCTest、macOS Build、治理和源边界回归。

## 当前绿灯证据

- Run `32622637600`：模拟器 Build、完整 iOS XCTest `240/240`、iOS Build Gate 通过；PWA/Edge、治理、Cloudflare/Vercel 门禁全绿。
- `npm run test:ios-local-expense-app-boundary`：2/2 通过。
- `npm run governance:arch`：未增加架构基线违规。

## 未完成的产品出口

- `RootView` 未登录时仍只展示 `LoginView`，用户尚不能进入主 Tab；
- 本地消费要求当前 profile 下存在账户，首次使用尚无账户准备/选择出口；
- 因此本批只证明应用层基础和 AppState 兼容接线，不能标记“免登录可发布”。
