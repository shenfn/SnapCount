# D-REMOTE-006 iOS 同步 Adapter

## 范围

- 将 `LocalOutboxUpload` 映射为 `sync_expense_batch` 的 `p_operations`。
- 解码 accepted/conflict/rejected、opaque `next_pull_cursor` 及账户、消费、账户流水投影。
- 通过本地仓储按实体版本合并；不把云端 `current_balance` 写入本地余额，也不为远端导入创建 Outbox。
- 只覆盖 `expense/accounts`，不接入其他数据域、生产部署或 TestFlight。

## 验收不变量

1. 请求始终携带 workspace/profile、client generation、pull cursor 和用户范围 operation 元数据。
2. 远端版本低于本地版本时保留本地事实；远端 tombstone 不重新创建记录。
3. 传输失败由既有 `LocalSyncCoordinator` 保留本地事实与 Outbox。
4. 账户余额继续由有效本地流水派生，远端 `current_balance` 仅作为未使用投影。
5. 冲突实体不接受同一批次的远端投影覆盖，保留本地事实等待后续人工出口。
6. 同步批次存在冲突时，已 accepted 的 Outbox 可标记 sent；同步状态进入 unresolved/failed，不推进成功 checkpoint。

## 验证

- `SupabaseSyncTransportTests` 覆盖 RPC 名称、请求字段、金额 minor 转换和投影解码。
- Windows 无 Xcode/Swift 编译环境；最终编译与 XCTest 以 GitHub macOS iOS Build 为准。
