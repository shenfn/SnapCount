# iOS 消费记录 App 接线规格说明

> 规格编号：LOCAL-002-APP
>
> 状态：部分实施；应用层与 AppState 兼容接线绿灯，产品入口待后续切片
>
> 上游：`LOCAL-002-APP-EVAL`、`LOCAL-DATA-001`、`LOCAL-002`

## 1. 目标

让 iOS 在没有 Supabase session、没有网络和 AI 关闭时，仍能创建本地 profile、记录消费、读取记录、编辑和删除；同时保持现有页面入口、云端路径和后续同步边界可演进。

本片只接消费垂直切片，不把“免登录”扩大成所有域都已本地化。

## 2. 依赖方向

```text
RecordsView / ManualRecordSheet
  -> AppState 兼容门面
       -> LocalExpenseUseCaseProtocol
            -> LocalExpenseRepositoryProtocol
                 -> LocalDatabase
```

- Use Case 不依赖 SwiftUI、Supabase、HTTP、Keychain 或 GRDB 具体 API。
- Repository 负责本地事务和查询；Use Case 负责命令校验、profile/account 上下文和结果分类。
- `NativeManualRecordDraft`、`NativeDayRecordGroup`、`NativeRecordDetail` 只在 mapper/presenter 边界出现。
- AppState 只能依赖一个消费应用边界，不新增 local/cloud 双实现的业务条件分支。

## 3. 最小接口形状

以下是行为契约，不要求首个实现使用完全相同的类型名：

```swift
protocol LocalProfileStoreProtocol {
    func activeProfile() throws -> LocalProfile
}

protocol LocalExpenseUseCaseProtocol {
    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome
    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome
    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome
    func month(_ monthKey: String) async throws -> LocalExpenseMonth
}
```

接口不得暴露 access token、Supabase session、`Double` 金额或 GRDB `Row`。本地查询必须隐含活动 profile，不能由页面随意传入其他 profile ID。

## 4. 场景矩阵

| 编号 | 场景 | 行为不变量 | 测试层 |
|---|---|---|---|
| LOCAL-002A2 | 首次启动创建 profile | 稳定 UUID、本地完成、不访问 Supabase | profile lifecycle XCTest |
| LOCAL-002A3 | 重启恢复 profile | 不重复创建，消费仍归属原 profile | integration XCTest |
| LOCAL-002A4 | profile 创建失败 | 可恢复错误，不进入已保存状态 | lifecycle XCTest |
| LOCAL-002G1 | 无 session/断网新增消费 | 本地事务成功即返回 saved；network spy 调用数为 0 | Use Case XCTest |
| LOCAL-002G2 | 断网编辑/删除 | 复用 DB2 版本、冲销、tombstone 和 Outbox 语义 | Use Case/Repository XCTest |
| LOCAL-002H1 | AI disabled 新增消费 | AI provider 不可用不影响本地保存 | Use Case XCTest |
| LOCAL-002I1 | 登录/退出不改变本地 profile | 不自动绑定、上传或删除本地数据 | AppState XCTest |
| LOCAL-002I2 | 用户切换后的旧请求 | stale 结果不得更新当前 UI 或当前 profile | AppState XCTest |
| LOCAL-002APP1 | 表单 mapper | 金额按 Decimal 转 minor；账户和日期边界明确 | mapper XCTest |
| LOCAL-002APP2 | 月度读取投影 | 仅投影本地 expense；删除记录不可见；引用可识别 | presenter XCTest |
| LOCAL-002APP3 | 远端/本地引用隔离 | 本地引用不触发远端详情、签名 URL 或网络加载 | source boundary + XCTest |

## 5. Profile 规则

1. `activeProfile()` 是设备本地唯一入口；首次没有 profile 时创建一次。
2. profile 创建和恢复不调用 `SupabaseAuthService`，不创建匿名云账号。
3. `cloud_user_id` 和 `sync_enabled` 在本片保持 `nil/false`；登录不改变它们。
4. 退出登录保留本地 profile 和业务事实；只停止当前 session 相关的远端任务。
5. 所有本地查询和写入都必须带 profile 归属校验；跨 profile ID 返回显式错误。

## 6. Mapper 与读模型规则

- 金额输入先经过十进制定点解析，再写入 `Int64 amount_minor`；非法金额或超过范围必须在 Use Case 返回验证错误。
- 本地账户 ID 必须是 UUID 且属于活动 profile；远端字符串 ID 不得静默转换。
- 本地记录日期保持 `transaction_date` 的用户本地日语义；`transaction_time` 只在用户提供时投影。
- 详情引用使用 `local-expense/<uuid>` 命名空间；只有本地 presenter 能解析该引用。
- 本地月度读模型不混入远端 Dashboard 快照；未本地化的域显示为未提供，而不是旧缓存冒充当前事实。

## 7. AppState 兼容边界

AppState 保留现有公开方法和页面状态字段，负责 busy、错误消息、导航、generation/stale 检查，以及把 Use Case outcome 投影为现有状态。

AppState 不负责解析金额、组装 Local 模型、创建/冲销流水、写 Outbox、计算余额或直接调用 LocalDatabase/GRDB/网络。不得在同一方法内复制一套本地/云端保存语义。

## 8. 实施顺序与 DoD

1. 红灯：profile lifecycle、network spy、mapper、read model 和 AppState source-boundary 检查。
2. 最小实现：`LocalProfileStore` -> mapper/read model -> `LocalExpenseUseCase` -> AppState 兼容接线。
3. 回归：Local Repository 专项测试、完整 XCTest、macOS iOS Build 和治理/架构门禁。
4. DoD：所有场景绿灯；本地模式 network spy 为 0；无 session 可新增/读取/编辑/删除；登录退出不串 profile；文档与交接快照更新。

本片完成后仍不得宣称同步、老用户迁移、其他域或 AI Provider 已完成。

## 9. 当前实施边界

- 已完成：本地 profile 创建/恢复、消费 Use Case、Decimal/minor mapper、月度读模型，以及 AppState 未登录消费兼容入口。
- 已验证：Run `32623778871` 的模拟器 Build、242 项 XCTest 和 iOS Build Gate 通过；本地边界、治理与架构检查通过。
- 未完成：`RootView` 仍以登录状态决定是否进入主界面；首次本地账户准备/选择尚无产品出口。
- 因此当前成果是可复用的本地应用层基础，不是可直接发布的完整免登录体验。
