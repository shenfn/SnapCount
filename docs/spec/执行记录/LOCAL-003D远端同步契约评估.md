# LOCAL-003D 远端同步契约评估记录

- 目标行为：在实现真实同步 adapter 前，证明现有云端接口能否满足本地优先同步的原子性、幂等、版本、游标、冲突和余额不变量。
- 当前行为：iOS 已有 `LocalSyncCoordinator` 和可注入 `LocalSyncTransport`；云端已有单笔账户/消费 RPC，但没有 workspace 批量同步协议。
- 权威来源：`LOCAL-003` 统一页面与云端同步规格、`ADR-036`、`ADR-039`、`supabase/migrations/022_wallet_accounts_v1a.sql`、`027_wallet_atomic_record_rpcs.sql`、`ios/SnapCount/Services/SupabaseRemoteClient.swift`。
- 本轮范围：只读检查 Supabase 表、RLS、单笔 RPC、iOS 本地 Outbox/账户写入和同步进入条件。
- 非范围：不新增迁移、不新增 RPC、不接真实远端、不上传测试账号数据、不改 PWA。
- 实测结论：现有云端可复用单笔消费+流水原子 primitive 和用户范围读取，但缺少实体版本、删除 tombstone、操作幂等键、跨域 cursor、批量事务和账户 Outbox。
- 业务风险：直接 REST 多步上传会留下账户/消费/流水半同步；重复请求可能重复流水；云端返回余额不能覆盖本地派生余额；本地新建账户目前不会进入 Outbox。
- 推荐下一步：D-REMOTE-001 先写服务端同步契约与脱敏 PostgreSQL fixture；服务端契约通过后再做迁移/RPC，最后实现 iOS adapter。
- 验证结果：本轮为只读审计；未执行生产查询、迁移、部署或 TestFlight。
