# LOCAL-003D 远端同步契约评估

> 状态：只读评估，阻断真实 adapter 接线
>
> 基线：`origin/main@cfbedc3`

## 结论

当前仓库可以验证 iOS 本地同步编排，但**不能安全地把 `LocalSyncTransport` 接到现有 Supabase REST/RPC**。现有云端写入接口能完成单笔消费和账户流水原子写入，却没有同步所需的幂等操作键、实体版本、变更游标和批量失败语义。直接从 iOS 依次写 `accounts`、`transactions`、`account_entries` 会把本地事务拆成多个云端事务，无法满足余额和重试不变量。

因此 `LOCAL-003D` 需要拆成两条明确边界：

1. **本地编排片**：PR #167 已完成，transport 保持注入，不宣称云端互通。
2. **远端契约片**：先补服务端同步协议和脱敏 fixture，再实现 iOS adapter；未满足进入条件前不得调用生产 REST 写路径。

## 已确认的云端能力

| 能力 | 现状 | 可否直接复用 |
|---|---|---|
| 读取当前用户账户 | `GET /rest/v1/accounts`，RLS 按 `auth.uid()` | 只读预览可复用 |
| 读取当前用户消费 | `GET /rest/v1/transactions`，可按用户读取 | 只读 fixture 可复用，不能当同步流 |
| 单笔消费 + 账户流水 | `save_transaction_with_account` 在数据库事务内完成 | 可作为未来批量 RPC 的内部 primitive |
| 单笔账户创建/编辑 | `save_account` RPC | 不能替代同步批量和幂等协议 |
| 账户余额 | 由云端流水触发器/函数维护 | 不得从 iOS 上传余额覆盖 |
| 用户隔离 | `accounts`/`account_entries` 有 `auth.uid()` RLS | 必须保留 |

## 阻断项

### 1. 没有稳定的同步版本和变更流

本地实体有 `localVersion`、tombstone 和 `updatedAt`，云端 `transactions` 没有对应的实体版本/删除 tombstone/同步 cursor；`accounts` 也没有与本地版本对应的字段。只靠 `created_at` 不能区分编辑、删除和同秒并发，也不能安全恢复 pull cursor。

### 2. 没有幂等操作语义

云端表没有 `operation_id`/`idempotency_key`。把本地 UUID 当作云端记录 ID 只能解决重复插入，不能解决“同一实体的第 2 次编辑重试”或服务端已提交、客户端超时的确认问题。

### 3. 本地账户写入没有 Outbox

历史版本的 `LocalExpenseRepository.createAccount` 只写 `local_accounts`，不会追加账户 Outbox。即使消费 Outbox 可以上传，首次同步也无法知道新建账户或账户初始余额，消费的 `account_id` 可能在云端不存在。修复后账户与账户 Outbox 必须在同一数据库事务中提交；对于历史本地账户，如果仍有待上传消费引用且不存在任何账户操作，协调器必须以幂等方式补偿一条 `account/upsert`。

### 4. REST 多步写不满足原子性

账户、消费和流水分开请求时，任一步失败都会留下半同步状态；重试还可能重复流水。现有单笔 RPC 只能保证一次消费写入内部的原子性，不能接收 workspace 的批次、顺序和幂等键。

### 5. 当前 iOS archive 不是远端同步协议

`LocalExpenseArchive` 是本地导出/恢复格式，明确排除 cloud binding、凭据和源 Outbox。它可以作为脱敏 fixture 的载体，但不能直接作为服务端 API 的权威 wire format；尤其不能让服务端接受客户端传来的余额快照。

## 远端契约的最小进入条件

服务端实现前先固定以下契约，所有字段必须有数据库/RPC 测试：

```text
sync_expense_batch(
  workspace_id,
  client_generation,
  pull_cursor,
  operations: [{ operation_id, idempotency_key, aggregate_id,
                 operation_kind, aggregate_version, base_version, payload }]
) -> {
  accepted_operation_ids,
  conflicts,
  remote_accounts,
  remote_expenses,
  remote_account_entries,
  next_pull_cursor
}
```

硬约束：

- `workspace_id` 只作为客户端相关性字段，服务端归属仍以 `auth.uid()` 为准；客户端不能指定另一个用户。
- 同一 `idempotency_key` 重试必须返回同一结果，不重复创建记录或流水。
- `aggregate_version`/`base_version` 偏离时返回 conflict，不静默覆盖。
- 账户余额只由服务端有效流水派生；响应不得要求客户端写 `current_balance`。
- 批次内账户、消费和流水在一个数据库事务中提交；失败整体回滚。
- pull cursor 必须是服务端同步流的 opaque cursor，不能复用某个数据域的 `updated_at`。
- 删除以 tombstone 或等价 change event 进入同步流，不能物理删除后让另一台设备“猜不到”。
- 返回结果必须按 `accepted / conflict / rejected` 分层，客户端可以安全重试未确认操作。
- 当前 iOS adapter 对含账户依赖的批次按账户 `upsert`、消费 `upsert` 的顺序发送；服务端批次处理仍按数组顺序执行。其他客户端接入前，必须将“服务端不依赖调用方排序”单独提升为协议增强，不能把当前 iOS 排序误认为跨客户端保证。

## 推荐实施顺序

1. **D-REMOTE-001：服务端契约 Spec 与脱敏 fixture**。先定 operation、版本、cursor、冲突和账户不变量，不改 iOS 页面。
2. **D-REMOTE-002：数据库迁移与批量 RPC**。补同步元数据/change log/幂等记录和 RLS/RPC 测试；复用现有单笔账户流水 primitive。
3. **D-REMOTE-003：iOS `SupabaseLocalSyncTransport`**。仅调用已通过 fixture 的 RPC，将结果映射到现有 `LocalSyncCoordinator`。
4. **D-REMOTE-004：双设备与故障注入验证**。覆盖超时重试、重复 operation、退出登录、账号错绑、余额派生和 cursor 恢复。

## 当前不做

- 不把普通 PostgREST `upsert` 当同步协议；
- 不在 iOS 端直接写 `accounts.current_balance`；
- 不把本地 archive 原样暴露为生产 API；
- 不在没有服务端版本/幂等 fixture 前接入真实用户账号；
- 不扩展到 income、sport、sleep、food、reading 等其他域。
