# D-REMOTE-008 同步失败出口

> 关联阶段：`LOCAL-003` / `D-REMOTE`
>
> 状态：代码完成，待 macOS 门禁
>
> 上游：`D-REMOTE-001服务端同步协议规格.md`、`D-REMOTE-006-iOS同步Adapter.md`、`D-REMOTE-007-iOS同步入口接线.md`

## 1. 目标与范围

为 `expense/accounts` 的 iOS Local-First 同步补齐服务端批量响应的失败出口，避免把部分成功或可恢复错误显示为“同步完成”。本片只修改 iOS 同步模型、transport、coordinator 及其 XCTest，不处理其他数据域、后台调度、冲突人工解决 UI、生产迁移或 TestFlight。

## 2. 行为不变量

| 编号 | 不变量 | 验证 |
|---|---|---|
| DREMOTE-014 | `rejected` 中的 operation 保持 Outbox `failed`，已 accepted 的 operation 才能标记 `sent`；同步状态为 `failed`，不得推进成功 checkpoint | Coordinator XCTest |
| DREMOTE-015 | `cursor_expired` 映射为明确的可重试错误，清除本地旧 cursor，保留本地事实和 Outbox | Transport + Coordinator XCTest |
| DREMOTE-016 | `conflicts` 使同步进入 `unresolved/failed`，冲突实体不被远端投影覆盖 | Coordinator XCTest |
| DREMOTE-017 | 绑定不匹配/旧 attempt 的结果不能写入新 workspace；失败状态必须有重试或重新绑定出口 | Coordinator/状态仓储 XCTest |

## 3. 状态流转

```text
ready/synced
   -> syncing
   -> synced                         (全部 accepted，pull 成功)
   -> failed                         (rejected / 网络 / 其他可重试错误)
   -> unresolved + failed             (conflict，等待后续人工出口)
   -> failed + cursor = nil           (cursor_expired，下一次全量 pull)
```

任何失败出口都不得清除本地事实；只有明确出现在 `accepted_operation_ids` 的操作可以标记为 `sent`。游标只在完整成功时推进，`cursor_expired` 时回退到 `nil` 以便受控重建。

## 4. 完成条件

- XCTest 覆盖 014-017，固定状态、Outbox、cursor 和远端投影不变量。
- macOS iOS Build 与完整 XCTest 由 GitHub 门禁验证；Windows 只做静态检查。
- 更新阶段索引和本执行记录，明确未验证的生产迁移、真机和双设备场景。

## 5. 本轮实现

- `SupabaseSyncTransport` 将 `rejected` 解码为带 operation ID 的失败结果；只把明确的 `accepted_operation_ids` 标记为 sent。
- `cursor_expired` 映射为 `LocalSyncError.cursorExpired`，清除本地旧 cursor 并保留 Outbox 供下一次全量 pull 重试。
- `conflicts` 同时携带 aggregate ID；账户冲突不应用远端账户投影，消费冲突沿用现有排除逻辑，并进入 `unresolved/failed`。
- 部分拒绝进入 `failed`，不推进 checkpoint；本地事实始终保留。

## 6. 验证记录

- `node scripts/check-project-governance.mjs`：通过。
- `node scripts/check-migration-versions.mjs`：通过；`20260826090000_remote_sync_expense_contract.sql` 仍为 pending，未执行生产迁移。
- `git diff --check`：通过；仅有 Windows 工作区既有 LF/CRLF 属性提示。
- Swift 编译、XCTest 和 iOS 源边界：待 GitHub macOS iOS Build 门禁。

## 7. 未验证与下一步

- 未在真实 Supabase、真实账号、真机或双设备环境验证；不触发 TestFlight。
- 合并 D-REMOTE-007（PR #176）与本片后，进入 `Expense + Account Sync Release Candidate Gate`，不继续拆分新的失败切片。
- `LOCAL-003E` 仍负责冲突列表和人工解决 UI，本片不宣称该能力完成。
