# D-REMOTE-003 TDD 执行记录

- 目标行为：将 DREMOTE-001、DREMOTE-002、DREMOTE-003、DREMOTE-007、DREMOTE-009 从红灯转为可执行的服务端合同。
- 权威来源：`docs/spec/模块/iOS本地优先/D-REMOTE-001服务端同步协议规格.md`、`docs/spec/执行记录/D-REMOTE-002迁移与RPC红灯.md`、`ADR-039`。
- 本轮实现：`sync_entity_versions`、`sync_change_log`、`sync_operations`、`sync_cursor_state`，以及 `sync_expense_batch(uuid, integer, text, jsonb)`。
- 已实现边界：用户级 operation/idempotency 唯一约束、base_version 冲突结果、跨用户账户拒绝、空批次不写 operation、首次 expense 写入账户流水并按有效流水重算余额。
- 明确未实现：删除 tombstone、金额/账户替换时旧流水作废、批次中间失败专用故障注入、cursor retention/过期边界、完整 pull 快照和其他数据域；这些保持在 DREMOTE-004/005/006/008。
- 测试入口：`scripts/test-remote-sync-contract-fixture.sql`、`supabase/migrations/20260826090000_remote_sync_expense_contract.sql`、`scripts/test-remote-sync-contract.sql`，由 `.github/workflows/release-validation.yml` 的 `remote_sync_contract` job 执行。
- 本地验证：`npm run governance:check`、`node scripts/check-migration-versions.mjs`、`git diff --check` 已通过；Windows 无 `psql`，数据库行为以 GitHub PostgreSQL job 为准。
- 下一步：保持 iOS adapter 未接线，补齐 DREMOTE-004/005/006/008 后再评估 D-REMOTE-004 首次真实同步 adapter。
