# D-REMOTE-005 TDD 执行记录

- 目标行为：让 `sync_expense_batch` 的 pull 部分返回账户、消费和账户流水的完整快照投影，并遵守 opaque cursor。
- 权威来源：`docs/spec/模块/iOS本地优先/D-REMOTE-001服务端同步协议规格.md`、`docs/spec/执行记录/D-REMOTE-004同步完整性.md`、`ADR-039`。
- 实现方式：`p_pull_cursor = null` 返回当前用户 change log 涉及实体的最新版本；非空 `c:<cursor>` 只返回 cursor 之后每个实体的最新变更，删除实体带 `change_kind=delete` 和 `deleted_at`。
- 账户流水投影：按消费实体关联 source entry 返回，保留 `is_voided/voided_reason`，客户端不得把云端 `current_balance` 当作本地可覆盖事实。
- 测试入口：`scripts/test-remote-sync-contract.sql` 的空批次首次 pull 与已消费 cursor 场景，由 `remote_sync_contract` PostgreSQL job 执行。
- 未包含：真实 iOS adapter、跨域同步、cursor retention 清理任务、生产迁移和部署。
- 本地验证：Windows 无 `psql`；以 GitHub PostgreSQL job 为数据库验证来源，提交前仍运行治理、迁移命名和 diff 检查。
