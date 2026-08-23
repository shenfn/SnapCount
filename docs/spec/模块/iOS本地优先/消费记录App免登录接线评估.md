# iOS 消费记录 App 接线与免登录边界评估

> 评估编号：LOCAL-002-APP-EVAL
>
> 状态：已完成只读评估，进入红灯规格
>
> 基线：`origin/main@e68a64d`

## 1. 结论

LOCAL-002-APP 可实施，但不能把现有 `AppState` 改成一组 `if localMode { ... } else { ... }`。当前 AppState 同时承载会话恢复、远端读取、页面投影和副作用；直接加入本地分支会把身份、网络、数据库和刷新策略重新耦合在一个文件中。

本片应建立一个窄的本地消费应用边界：

```text
SwiftUI View
  -> AppState 兼容门面
       -> LocalExpenseUseCase
            -> LocalExpenseRepositoryProtocol
                 -> LocalDatabase
```

本地写入不依赖 session、access token、Supabase client 或网络；云同步不在本片发送。AppState 只负责把结构化结果投影到现有 UI 状态，不能重新实现本地事务语义。

## 2. 当前事实

### 2.1 启动和身份

- `AppState.bootstrap()` 当前先执行 `restoreAuthentication()`，认证恢复失败后才继续进入应用状态。
- `AppState` 持有 `SupabaseAuthService`，大量公开动作通过 `validSession()` 获取 access token。
- `LocalDatabase()` 已能创建 Application Support 下的 GRDB 文件并执行 `local-v1` migration。
- `LocalExpenseRepository.createProfile` 只能显式创建 profile，当前没有“读取现有 profile/恢复默认 profile”的应用层生命周期入口。
- `local_profiles.cloud_user_id` 和 `sync_enabled` 已存在，但本片不把登录自动解释为绑定或同步。

### 2.2 消费读写

- `createManualRecord`、`saveRecordDetail`、`deleteRecord` 当前均通过远端 `RecordRepository`，保存前强制获取 session。
- `RecordsView` 和月度记录入口使用 `AppState.loadRecordMonth`；该方法直接调用远端 `recordRepository.fetchMonth`。
- `ManualRecordSheet` 使用 `NativeManualRecordDraft`，金额是 `Double` 解析后的 UI 值；不能直接作为本地数据库模型。
- `NativeAccount.currentBalance` 是云端读取字段；本地账户余额必须从 opening balance 和有效流水派生。
- `LocalExpenseRepository` 已实现新增、编辑、删除、流水冲销、tombstone、Outbox 和导入导出，但尚未提供页面所需的本地 profile/账户列表、消费列表和详情读模型。

## 3. 本片范围

### 包含

- 单设备默认本地 profile 的创建、恢复和隔离；
- 本地消费新增、读取、编辑、删除的 Use Case 边界；
- `NativeManualRecordDraft` 到 `LocalExpenseDraft/LocalExpenseUpdate` 的显式 mapper；
- 本地消费到 `NativeDayRecordGroup`、`NativeRecordDetail` 的只读投影；
- 本地模式下无业务网络请求的可测试闸门；
- 登录、退出和用户切换时不串用本地 profile 的生命周期规则；
- AppState 兼容门面和最小页面接线，保持现有 View API 不变。

### 不包含

- Supabase 同步发送、冲突合并和云端绑定迁移；
- 收入、运动、睡眠、饮食、阅读、钱包和图片本地化；
- Hosted AI、BYOK、图片上传和云端识别；
- PWA 本地数据库或 PWA 登录策略；
- 账户 CRUD、还款和余额快照页面的本地化；
- 生产迁移、部署、TestFlight 和既有云端用户迁移。

## 4. 目标边界

### 4.1 Profile 生命周期

1. 首次启动打开本地数据库，若不存在当前设备 profile，则在本地事务中创建一个稳定 UUID profile。
2. 再次启动按设备级稳定标识恢复同一 profile；不得每次启动创建新 profile。
3. profile 创建失败必须进入可恢复错误状态，不能静默创建 Supabase 匿名用户，也不能把业务数据写入云端。
4. 本片只支持一个活动本地 profile。多 profile 选择和设备迁移留到后续规格。
5. 登录只更新认证会话状态，不自动绑定 `cloud_user_id`，不自动上传本地记录。
6. 退出登录不删除本地 profile；清除会话后，活动 profile 仍是当前设备 profile。
7. 用户切换或 session 变化不能改变本地查询的 `profile_id`，旧异步请求不得把结果投影到当前 UI。

### 4.2 本地消费写入

- Use Case 接受本地消费命令和活动 profile 上下文，不接受 Supabase session 或 access token。
- 金额在 mapper 边界使用 Decimal/字符串转整数分；禁止用二进制浮点直接写 `amount_minor`。
- `accountId` 必须能解析为当前 profile 的本地 UUID，并由 repository 校验账户归属；远端账户 ID 不得静默当成本地账户 ID。
- 新增、编辑、删除继续复用已合并的 Local Repository 事务语义；Use Case 不复制流水冲销或 Outbox 逻辑。
- 本地写入成功即视为当前设备事实；Outbox 只表示未来可同步，不触发网络。

### 4.3 本地读取投影

- 本地查询必须按活动 `profile_id`、`deleted_at IS NULL` 和本地日期语义读取。
- 新增独立 `LocalExpenseReadModel`/Presenter，把 Local 模型转换成页面需要的 `NativeDayRecordGroup` 和 `NativeRecordDetail`。
- 该投影只覆盖 `expense`，不伪造收入或通用域记录；Dashboard 中未接入的域必须显示为空或不可用，而不是复用远端旧快照冒充本地事实。
- 详情引用使用稳定 UUID 的本地命名空间，不能与远端 `data/<id>` 引用混淆；mapper 必须可逆地识别本地引用。
- `DashboardSnapshotStore` 继续只是展示缓存，不升级为业务事实库。

### 4.4 AppState 接线

- AppState 保留 `createManualRecord`、`saveRecordDetail`、`deleteRecord`、`loadRecordMonth` 等现有公开入口，页面不改为直接持有 Repository。
- AppState 不新增按模式分支，不解析金额、不创建流水、不写 Outbox；它只负责 busy、消息、导航、generation/stale 检查和已有状态投影。
- 选择本地消费路径的策略放在 `ExpenseRecordCoordinator` 或等价 Feature Use Case 中。该对象对 AppState 暴露单一命令/查询接口，内部组合本地 provider；后续云同步由独立 Sync Engine 接入，不把远端 transport 塞回页面。
- 其他尚未本地化的域保持现有云端路径，本片不得宣称整个 App 已免登录可用。

## 5. 场景与测试映射

| 编号 | Given / When / Then | 首选验证层 |
|---|---|---|
| LOCAL-002A2 | 首次启动无 session；创建 profile 成功 | Local profile lifecycle XCTest |
| LOCAL-002A3 | 重启后已有 profile；再次启动 | lifecycle/integration XCTest |
| LOCAL-002A4 | profile 创建失败 | error-state XCTest；不产生网络请求 |
| LOCAL-002G1 | 无 session、网络 Stub 设为 fail；新增消费成功 | Use Case XCTest + network spy |
| LOCAL-002G2 | 本地编辑/删除；网络不可用 | Use Case/Repository XCTest |
| LOCAL-002H1 | AI provider disabled；手动消费仍成功 | Use Case XCTest |
| LOCAL-002I1 | 登录或退出发生在本地读写前后 | AppState lifecycle XCTest |
| LOCAL-002I2 | 旧请求完成于用户/session 切换之后 | stale/generation XCTest |
| LOCAL-002APP1 | UI 草稿金额、账户和日期映射到 Local 命令 | mapper XCTest |
| LOCAL-002APP2 | 本地 expense 投影到记录分组和详情 | read-model XCTest |
| LOCAL-002APP3 | 本地记录引用不被远端详情加载器误识别 | reference boundary/source check |

## 6. 红灯顺序

1. 先新增 profile lifecycle 和 network spy 的红灯，证明当前启动仍只认远端 session。
2. 再新增 `NativeManualRecordDraft` mapper、Local expense Use Case 和本地读取投影红灯；不修改 AppState。
3. 最后新增 AppState 兼容门面红灯，固定“页面入口不变、AppState 不持有事务细节、旧请求 stale 不投影”。
4. 最小实现顺序固定为：profile store/读取 API -> mapper/read model -> Use Case -> AppState 接线 -> 页面行为回归。

## 7. 风险和暂缓决定

- **默认账户交互未在本片自动决定**：本地消费必须有账户；如果首次启动没有账户，UI 应进入可解释的账户创建/选择状态，而不是隐式创建一个名称不明确的账户。是否提供“我的钱包”默认账户另立产品决策。
- **本地 profile 与云端账号绑定未实现**：`cloud_user_id` 仅保留 schema 字段；绑定、迁移、去重和回滚属于 L2。
- **现有 Dashboard 是多域云端快照**：LOCAL-002-APP 只接消费记录，不应把本地消费与远端其他域拼成不透明混合事实。混合 Dashboard 需要单独读模型契约。
- **Windows 无法证明 Swift 编译**：本地只能运行脚本和静态检查；最终 XCTest 与 iOS Build 以 GitHub macOS CI 为准。

## 8. 完成定义

- 规格场景全部有红灯/绿灯证据；
- 本地模式业务写入的 network spy 证明未调用 Supabase；
- profile、消费、流水、tombstone、Outbox 仍由 Local Repository 单一事务语义负责；
- AppState 和页面公开入口兼容，未引入第二套业务规则；
- `docs/spec/03-阶段与任务索引.md`、执行记录和交接快照同步更新；
- GitHub macOS XCTest、iOS Build、治理和适用发布门禁通过。
