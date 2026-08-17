# iOS 钱包快照动作编排边界评估

> 模块编号：A4-IOS-002
>
> 所属计划：CLEAN-001/A4、ADR-029
>
> 状态：只读评估完成，待 Spec/TDD 实现
>
> 基线：`61874ba`（PR #115 合并提交）

## 开工前必读

- `AGENTS.md`
- `docs/spec/规格文档索引.md`
- `docs/spec/03-阶段与任务索引.md`
- `docs/spec/05-仓库清洗与架构收拢实施计划.md`
- `docs/spec/02-TDD实施与交接规范.md`
- `docs/spec/模块/iOS业务边界/钱包快照原子边界规格说明.md`
- `docs/decisions/ADR-029-PWA钱包快照采用数据库原子命令.md`

## 1. 结论

A4-IOS-001 已将跨表写入收回 `WalletSnapshotRepository` 和数据库原子 RPC，但 `AppState` 仍直接编排钱包快照动作：读取 session、设置 busy、调用 Repository、刷新三个读模型、生成用户消息并处理异常。下一最小切片应只抽离这段动作编排，保留 AppState 的公开入口和 `@Published` 兼容状态，不扩大到全量 AppState 重构。

建议建立 `WalletSnapshotActionUseCase`（或等价的纯 Swift Feature/Coordinator），由 AppState 作为兼容门面调用。Use Case 不拥有 SwiftUI，不直接访问 HTTP；它接收 session、Repository、刷新回调和用户状态 generation，返回结构化动作结果。

## 2. 当前证据

| 位置 | 当前职责 | 风险 |
|---|---|---|
| `AppState.swift:73-76` | `walletSnapshots`、加载状态、单一 `walletSnapshotActionId`、消息均由 AppState 保存 | 状态和动作编排耦合，后续每个动作继续堆入巨型对象 |
| `AppState.swift:1075-1125` | create/link 两个入口重复 validSession、busy guard、Repository 调用、刷新和文案分支 | create/link 语义容易漂移；`needs_confirmation`/replayed 需要重复处理 |
| `AppState.swift:1127-1131` | 一个动作刷新 accounts、wallet snapshots、dashboard 三个读模型 | 刷新失败与事务成功没有结构化分层；动作编排无法单测隔离 |
| `AppState.swift:userStateGeneration` | 其他 load 方法在请求前后使用 generation guard | 钱包快照动作本身没有捕获并检查 generation，旧请求仍可能写入 `walletSnapshotMessage` 或触发刷新 |
| `WalletSnapshotRepository` | 已只负责 canonical RPC transport/DTO 映射 | 可作为 Use Case 的唯一写依赖，不应再次向下扩展业务规则 |

## 3. 目标依赖方向

```text
DomainsView / AppState 兼容门面
  -> WalletSnapshotActionUseCase
    -> WalletSnapshotRepositoryProtocol
    -> SessionProvider
    -> RefreshWalletSnapshotReadModels
```

- Use Case 负责命令身份、busy/冲突、generation stale、accepted 与 refresh 分层、结构化结果。
- Repository 负责 RPC transport 和 canonical DTO；不感知 AppState、页面文案或刷新。
- AppState 负责把 Use Case 结果投影到既有 `walletSnapshotActionId`、`walletSnapshotMessage` 和数组状态；页面 API 不变。
- 读模型刷新仍复用已有 `loadAccounts`、`loadWalletSnapshots`、`refreshDashboard`，本轮不重写这些 loader。

## 4. 场景矩阵

| 场景 | 行为不变量 | 测试层 |
|---|---|---|
| A4-IOS-002A | 未认证、session 无效或输入缺失在 Repository 前 rejected；不改变账户或快照数组 | Use Case XCTest |
| A4-IOS-002B | 同一 record 的 create/link 动作进行中时，重复同命令复用或被 busy guard 拒绝；不同目标不发第二个写请求 | Use Case XCTest |
| A4-IOS-002C | Repository 返回 created/linked/replayed/needs-confirmation 都保留结构化 outcome；不由 AppState 重新猜测状态 | Use Case XCTest |
| A4-IOS-002D | canonical RPC 已 accepted 后，刷新失败只标记 refresh failure，不重复写事务或把 accepted 改成 failed | Use Case/AppState XCTest |
| A4-IOS-002E | 用户切换/reset 提升 generation 后，旧请求结果为 stale，不更新当前用户 message/数组、不执行 accepted refresh hook | Use Case XCTest |
| A4-IOS-002F | 成功动作只触发既有三个读模型刷新一次；不会因 create/link 双重包装重复刷新 | AppState 特征测试 |

## 5. 非目标

- 不修改 `WalletSnapshotRepository` 的 RPC 契约、数据库 migration、PWA、Edge、Planner 或生产配置。
- 不一次性拆解 AppState 的 dashboard、records、settings、inbox 等其他编排。
- 不引入 SwiftUI/Combine 以外的新生产依赖，不把 Use Case 变成第二个 HTTP Service。
- 不改变页面视觉、导航、确认门禁或用户可见的既有入口名称。
- 不在普通读模型加载中加入 repair 或钱包快照写入。

## 6. 推荐实现顺序

1. 先写 A4-IOS-002A 至 A4-IOS-002F XCTest，使用 Repository/Session/Refresh stub 固定 outcome、stale 和 refresh 分层。
2. 提取最小 `WalletSnapshotActionUseCase`，仅承载一对 create/link command；先保持 AppState 方法签名不变。
3. 将 `userStateGeneration` 以只读 generation provider/closure 注入，动作完成前后检查，不复制另一套用户状态。
4. AppState 只做结果投影和兼容刷新；删除 create/link 中重复的 session/busy/message 编排。
5. 运行 XCTest、macOS iOS Build、治理和源边界检查；再评估是否把同一 Use Case 模式推广到其他 AppState 事务。

## 7. 进入实现门禁

- 本评估和后续正式 Spec 合并前，不修改 AppState。
- 实现片不得同时拆其他业务动作；超出钱包快照编排范围必须另开任务。
- Windows 只运行文档/静态检查，Swift 编译和 XCTest 以 GitHub macOS 为准。
- 完成后必须更新 A4 交接快照，记录 stale、refresh failure 和未验证项。
