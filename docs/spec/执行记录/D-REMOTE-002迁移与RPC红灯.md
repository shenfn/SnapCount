# D-REMOTE-002 TDD 执行记录

- 目标行为：为 `expense/accounts` 建立可重复的服务端同步数据库门禁，覆盖 DREMOTE-001 至 DREMOTE-009。
- 当前行为：`origin/main` 只有单笔账户/消费 RPC，没有同步 operation、实体版本、change log 或批量同步 RPC。
- 权威来源：`docs/spec/模块/iOS本地优先/D-REMOTE-001服务端同步协议规格.md`、`docs/spec/执行记录/D-REMOTE-001服务端同步协议.md`、`ADR-039`。
- 本轮范围：脱敏 PostgreSQL fixture、9 个场景的红灯入口、延后迁移模板；不执行生产迁移、不接 iOS adapter、不扩展其他数据域。
- 红灯入口：`scripts/test-remote-sync-contract-fixture.sql` + `scripts/test-remote-sync-contract.sql`。
- 预期红灯：在 fixture 后执行测试脚本时，因 `sync_entity_versions`、`sync_change_log`、`sync_operations` 和 `sync_expense_batch` 尚不存在而失败；这不是业务失败，而是待实现对象缺失。
- 已覆盖场景：DREMOTE-001 幂等重试、DREMOTE-002 重复幂等键、DREMOTE-003 版本冲突、DREMOTE-004 流水替换、DREMOTE-005 tombstone、DREMOTE-006 批次回滚、DREMOTE-007 用户隔离、DREMOTE-008 cursor 过期、DREMOTE-009 空批次 pull。
- 最小实现：下一片新增 timestamped migration/RPC，并将同一测试文件中的注释清单逐项替换为实际调用和不变量断言。
- 验证限制：Windows 本机没有 PostgreSQL 客户端/服务时只能做 SQL 静态检查；GitHub PostgreSQL job 需在实现迁移后接入，当前不应伪造绿灯。
- 下一步：D-REMOTE-003 服务端迁移与批量 RPC 最小实现，先让 DREMOTE-001、002、003、005、007、009 转绿，再补 004、006、008 的失败路径。
