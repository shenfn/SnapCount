# D-REMOTE-004 TDD 执行记录

- 目标行为：在 D-REMOTE-003 首批同步 RPC 上补齐流水替换、删除 tombstone、批次事务回滚和 cursor 过期出口。
- 权威来源：`docs/spec/模块/iOS本地优先/D-REMOTE-001服务端同步协议规格.md`、`docs/spec/执行记录/D-REMOTE-003最小同步RPC.md`、`ADR-039`。
- 实现方式：继续复用 `sync_expense_batch`，不新增第二套写入口；更新时作废旧 `account_entries` 后生成新流水，删除写入 `sync_entity_versions.deleted_at` 和 `sync_change_log.change_kind=delete`。
- 故障边界：fixture 通过 `payload.force_failure=true` 注入中间失败，断言同一数据库事务内事实、operation 和版本记录全部回滚。
- cursor 边界：`sync_cursor_state.minimum_cursor` 是用户范围的保留下界；请求游标低于下界返回 `cursor_expired`，不静默跳到最新。
- 测试入口：`scripts/test-remote-sync-contract.sql` 的 DREMOTE-004/005/006/008 场景，由 `.github/workflows/release-validation.yml` 的 `remote_sync_contract` job 执行。
- 未包含：完整远端 pull 快照、跨域 cursor 迁移策略、其他数据域、iOS adapter、生产部署。
- 本地验证：Windows 无 `psql`，提交前运行 `npm run governance:check`、`node scripts/check-migration-versions.mjs`、`git diff --check`；数据库行为以 GitHub PostgreSQL job 为准。
