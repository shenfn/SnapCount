# iOS AppState 钱包快照动作编排规格

> 模块编号：A4-IOS-002
>
> 所属计划：CLEAN-001/A4、ADR-029
>
> 状态：规格评审中
>
> 基线：`128352a`（A4-IOS-002 评估 PR #116 合并提交）

## 开工前必读

- `AGENTS.md`
- `docs/spec/规格文档索引.md`
- `docs/spec/03-阶段与任务索引.md`
- `docs/spec/05-仓库清洗与架构收拢实施计划.md`
- `docs/spec/02-TDD实施与交接规范.md`
- `docs/spec/模块/iOS业务边界/AppState钱包快照动作编排边界评估.md`
- `docs/spec/模块/iOS业务边界/钱包快照原子边界规格说明.md`
- `docs/decisions/ADR-029-PWA钱包快照采用数据库原子命令.md`

## 1. 用户价值与目标

把 iOS 钱包快照动作从 `AppState` 的重复编排中收拢出来，使用户切换、重复点击、事务 accepted、读模型刷新失败和旧请求回写都有稳定出口；保持现有页面入口、导航和 `AppState` 公开方法兼容。

本片只抽离 Wallet Snapshot Action Use Case/Coordinator，不拆解 AppState 的其他领域动作。

## 2. 输入与依赖

Use Case 接收以下能力，不直接依赖 SwiftUI、HTTP 或 Supabase client：

- 当前 session provider：返回 user ID 和 access token；
- `WalletSnapshotRepositoryProtocol`：执行 create/link canonical command；
- 当前 generation/user provider：读取用户切换代数和当前 user ID；
- accepted 后的 refresh callback：复用 AppState 现有 `loadAccounts`、`loadWalletSnapshots`、`refreshDashboard`；
- reset 能力：用户切换时使 in-flight action 失效。

命令字段：

```text
operation: create | link
recordId: non-empty String
accountId: String?  // create 必须为空，link 必须非空
```

Use Case 不接收金额、账户类型、账期、还款状态或 `userId` 作为业务事实；这些由记录和数据库 RPC 权威决定。

## 3. 结果契约

```text
transaction: accepted(created|linked|replayed|needs_confirmation)
           | rejected(unauthenticated|invalid_input)
           | conflict(wallet_snapshot_busy|wallet_snapshot_conflict)
           | failed(stable RPC/protocol error)
           | stale(session_changed)
refresh: not_started | succeeded | failed(error)
```

- `transaction=accepted` 表示数据库事务已成功提交；`needs_confirmation` 仍是 accepted，只需产品确认出口。
- `refresh=failed` 不得把 accepted 变成 failed，也不得重复写 RPC；用户可重试读取刷新。
- `stale` 不执行 accepted 投影、消息更新或 refresh callback。
- AppState 兼容门面可以把 accepted 映射为既有 `Bool=true`，但必须依据 outcome 生成不同 message；stale/failed/conflict/rejected 返回 `false`。

## 4. 并发与用户切换

1. 动作身份为 `userId + recordId`；签名包含 operation 和 accountId。
2. 同一身份和签名的 in-flight 调用复用同一个 Task，不向 Repository 发第二次 RPC。
3. 同一 record 的不同 operation/目标账户返回 `wallet_snapshot_conflict`，不发第二次写入。
4. `reset()` 提升 generation 并清理本地 in-flight 索引；旧 Task 完成后只能返回 stale。
5. RPC 前后和 refresh 前均检查 generation 与当前 user ID；旧用户结果不能更新当前用户 message/数组。
6. `walletSnapshotActionId` 继续作为 AppState 兼容展示状态，但不再作为唯一并发/用户切换权威。

## 5. 场景矩阵

| 场景 | Given / When / Then 不变量 | 测试层 |
|---|---|---|
| A4-IOS-002A | 未认证、空 recordId、create 带 accountId、link 缺 accountId 在 transport 前 rejected | Use Case XCTest |
| A4-IOS-002B | 同身份同签名重复调用复用 Task；同 record 异目标返回 conflict；Repository 只收到一次调用 | Use Case XCTest |
| A4-IOS-002C | Repository accepted 的四种 outcome 原样保留；needs-confirmation 不被转成 failed 或普通 warning | Use Case XCTest |
| A4-IOS-002D | accepted 后 refresh callback 失败时 transaction 仍 accepted，refresh=failed，不重发 RPC | Use Case/AppState XCTest |
| A4-IOS-002E | reset/user switch 后旧 Task 返回 stale，不调用 accepted projection、message 更新或 refresh | Use Case XCTest |
| A4-IOS-002F | AppState 兼容入口只投影 Use Case 结果，保持 action busy、message、刷新和页面公开入口 | AppState XCTest |

## 6. AppState 兼容边界

实现片必须保留：

- `createAccountFromWalletSnapshot(_:) async -> Bool`；
- `linkWalletSnapshot(_:to:) async -> Bool`；
- `walletSnapshotActionId`、`walletSnapshotMessage`、`walletSnapshots` 的现有页面可观察含义；
- accepted 后的账户、钱包快照、dashboard 刷新顺序。

实现片必须移出 AppState：

- create/link 的重复 session、busy、in-flight、generation 判定；
- outcome 到 transaction/refresh 结果的分类；
- accepted/refresh failure/stale 的控制流判断。

AppState 不负责：RPC 参数、金额/账期推导、流水写入、数据库错误猜测或补偿写入。

## 7. TDD 顺序与预计文件

1. 在 `ios/SnapCountTests` 添加 A4-IOS-002A-F XCTest，先证明当前缺失的 Task 复用、冲突、stale 和 refresh 分层。
2. 新增纯 Swift `WalletSnapshotActionUseCase`/Coordinator 和结果类型；不引入 UI 或网络依赖。
3. 最小改 AppState 注入 Use Case、投影结果并保留公开入口。
4. 运行已有钱包快照 XCTest、A4-IOS-002 专项、macOS Build、治理和源边界检查。

预计文件：

- `ios/SnapCount/Features/Accounts/WalletSnapshotActionUseCase.swift`（或同职责目录）；
- `ios/SnapCount/App/AppState.swift`；
- `ios/SnapCountTests/WalletSnapshotActionUseCaseTests.swift`；
- 执行记录和交接快照。

非预计文件：数据库 migration、PWA、Edge、Planner、设计 Token、页面视觉和生产配置。

## 8. 完成定义

- A4-IOS-002A-F 由 XCTest 固定并通过；删除 AppState 中重复的动作编排而不改变公开入口。
- 同命令只发一次 RPC；异目标冲突、用户切换 stale、refresh failure 均有稳定结果。
- transaction accepted 与 refresh failed 分层可观察；needs-confirmation 不被误报成功或失败。
- GitHub macOS iOS Build/XCTest、治理和架构门禁通过；未执行生产迁移、部署或 TestFlight。
