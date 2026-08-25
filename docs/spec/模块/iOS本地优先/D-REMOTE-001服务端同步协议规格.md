# D-REMOTE-001 服务端同步协议规格

> 关联任务：LOCAL-003D
>
> 状态：提议，进入数据库/RPC 红灯阶段
>
> 上游：`LOCAL-003`、`LOCAL-003D远端同步契约评估`、`ADR-036`、`ADR-039`

## 1. 目标与范围

为 `expense/accounts` 首片定义一个服务端权威的批量同步协议，使 iOS `LocalSyncCoordinator` 可以安全地上传 Outbox、拉取云端变更并恢复 cursor。

本片只定义：

- 当前登录用户的账户、消费和账户流水；
- 批量操作的幂等、顺序、版本和冲突结果；
- 删除 tombstone 和跨域 opaque cursor；
- 账户余额由有效流水派生；
- PostgreSQL fixture、RPC 契约测试和 RLS 边界。

本片不实现：

- income、运动、睡眠、饮食、阅读、图片和 AI；
- CRDT、字段级自动合并或静默 last-write-wins；
- 生产部署、真实用户回填和 iOS adapter 接线。

## 2. 权威原则

1. `auth.uid()` 是唯一用户归属来源，客户端传入的 `workspace_id` 只用于相关性和日志，不得改变用户边界。
2. 云端账户余额不接受客户端覆盖；账户余额由账户初始余额和未作废流水在服务端派生。
3. 同一 `operation_id` 或 `idempotency_key` 重试返回第一次结果，不重复创建消费或账户流水。
4. `base_version` 不匹配时返回冲突，不修改云端实体，不接受客户端强制覆盖。
5. 批次中账户、消费、流水和同步元数据必须在同一数据库事务中提交；任一业务校验失败，批次整体回滚。
6. pull cursor 是全局同步流的 opaque 位置，不是 `updated_at`、某张表的版本或某个域的计数。
7. 删除通过 tombstone/change event 同步；物理删除不能从同步流中消失。

## 3. 服务端元数据模型

迁移新增三类表，具体命名可在 SQL 实现阶段调整，但语义不可改变：

### 3.1 `sync_entity_versions`

| 字段 | 约束 | 含义 |
|---|---|---|
| `user_id` | `auth.users` 外键 | 数据归属 |
| `aggregate_kind` | `account` / `expense` | 同步实体类型 |
| `aggregate_id` | UUID | 现有云端实体 ID；本地稳定 UUID 首次上传时可作为 ID |
| `version` | 正整数 | 每次接受的实体变更递增 |
| `deleted_at` | 可空 | tombstone 时间 |
| `updated_at` | 非空 | 服务端变更时间 |
| `payload_hash` | 非空 | 规范化实体快照指纹，仅用于审计/冲突诊断 |

主键为 `(user_id, aggregate_kind, aggregate_id)`。所有读写必须带 `user_id`。

### 3.2 `sync_change_log`

| 字段 | 约束 | 含义 |
|---|---|---|
| `cursor` | 用户范围内单调递增 | 全局拉取位置 |
| `user_id` | 外键 | 数据归属 |
| `aggregate_kind/id` | 非空 | 变更实体 |
| `version` | 非空 | 该实体版本 |
| `change_kind` | `upsert` / `delete` | 变更类型 |
| `created_at` | 非空 | 服务端记录时间 |

`cursor` 只能由服务端分配。清理旧 change log 前必须有 retention 约束；cursor 过期返回可恢复的 `cursor_expired`，不能静默从最新位置开始。

### 3.3 `sync_operations`

| 字段 | 约束 | 含义 |
|---|---|---|
| `user_id` | 外键 | 数据归属 |
| `operation_id` | 用户范围唯一 | 本地 Outbox 稳定 ID |
| `idempotency_key` | 用户范围唯一 | 网络重试幂等键 |
| `aggregate_kind/id` | 非空 | 操作对象 |
| `aggregate_version` | 正整数 | 客户端期望写入版本 |
| `base_version` | 非负整数 | 客户端读取到的远端版本 |
| `result_kind` | `accepted` / `conflict` / `rejected` | 首次处理结果 |
| `result_json` | 非空 | 可重复返回的结果 |
| `created_at` | 非空 | 首次处理时间 |

唯一索引至少覆盖 `(user_id, operation_id)` 和 `(user_id, idempotency_key)`。

## 4. RPC 契约

建议 RPC 名称：`sync_expense_batch`。函数使用 `security definer`，固定 `search_path = public`，开始时拒绝 `auth.uid() is null`。

### 4.1 请求

```json
{
  "p_workspace_id": "local-workspace-uuid",
  "p_client_generation": 3,
  "p_pull_cursor": "opaque-or-null",
  "p_operations": [
    {
      "operation_id": "stable-operation-uuid",
      "idempotency_key": "stable-retry-key",
      "aggregate_kind": "account",
      "aggregate_id": "stable-account-uuid",
      "operation_kind": "upsert",
      "aggregate_version": 1,
      "base_version": 0,
      "payload": {
        "name": "现金",
        "kind": "cash",
        "currency": "CNY",
        "opening_balance_minor": 1000000
      }
    }
  ]
}
```

请求限制：批次大小、payload 字节数、版本范围和 aggregate 类型必须有服务端上限；客户端不得传 `user_id`、`current_balance`、`created_at` 或服务端 cursor。

### 4.2 响应

```json
{
  "accepted_operation_ids": ["stable-operation-uuid"],
  "conflicts": [
    {
      "operation_id": "stale-operation-uuid",
      "aggregate_kind": "expense",
      "aggregate_id": "expense-uuid",
      "expected_base_version": 2,
      "actual_version": 3,
      "reason": "version_conflict"
    }
  ],
  "rejected": [],
  "remote_accounts": [],
  "remote_expenses": [],
  "remote_account_entries": [],
  "next_pull_cursor": "opaque-next-cursor"
}
```

响应不能返回客户端写入的 `current_balance` 作为待写字段；余额只作为读取投影或服务端 fixture 的断言。

### 4.3 批次处理顺序

1. 锁定当前用户相关的 `sync_operations` 幂等键和受影响实体；
2. 先处理账户 upsert，使消费的 `account_id` 有效；
3. 按 `sequence`/请求顺序处理消费 upsert/delete；
4. 由现有账户流水 primitive 创建、作废或替换流水；
5. 写入 `sync_entity_versions` 和 `sync_change_log`；
6. 固化每个 operation 的结果到 `sync_operations`；
7. 生成响应并提交事务。

任一步骤失败，除可重复识别的已存在幂等结果外，整个事务回滚。

## 5. Pull 语义

- `p_pull_cursor = null` 表示首次拉取当前用户的完整同步集合；
- 非空 cursor 只返回 cursor 之后的 `sync_change_log`，并带实体完整快照或 tombstone；
- 返回结果必须包含账户、消费和账户流水的关联关系；
- 同一实体多次变更可在响应中折叠，但不能跳过最新版本或 tombstone；
- cursor 只在事务成功后前进；客户端收到传输错误时不得持久化新 cursor；
- `workspace_id` 不参与数据过滤，不能用来读取其他用户的数据。

## 6. Fixture 与测试矩阵

首批 PostgreSQL fixture 必须覆盖：

| 编号 | 场景 | 预期 |
|---|---|---|
| DREMOTE-001 | 同一 operation 首次提交 + 重试 | 只产生一条消费和一条有效流水，返回同一结果 |
| DREMOTE-002 | 两个 operation 使用同一 idempotency key | 第二个返回第一次结果或明确 rejected，不产生第二条事实 |
| DREMOTE-003 | `base_version` 过期 | 返回 conflict，云端实体/流水不变 |
| DREMOTE-004 | 消费金额/账户替换 | 旧流水作废、新流水生成，余额只由有效流水派生 |
| DREMOTE-005 | 删除 tombstone | 删除进入 change log，另一端可恢复删除事实 |
| DREMOTE-006 | 批次中间失败 | 账户、消费、流水、版本、change log、operation 结果全部回滚 |
| DREMOTE-007 | 用户 A 读取/写入用户 B UUID | RLS/RPC 拒绝，不泄露实体是否存在 |
| DREMOTE-008 | 旧 cursor | 返回 `cursor_expired`，不静默返回最新集合 |
| DREMOTE-009 | 空批次只 pull | 不写 operation，不改变实体，只返回 cursor 后的变更 |

## 7. 进入 D-REMOTE-002 的门禁

- 本 Spec 合并并登记到规格索引；
- PostgreSQL fixture 能在空库重复执行；
- DREMOTE-001 至 DREMOTE-009 均有数据库测试入口；
- 明确迁移版本、RPC 参数和返回 JSON schema；
- 不使用普通 REST 多步写替代 RPC；
- iOS adapter 继续保持未接线，直到服务端 fixture 全绿。
