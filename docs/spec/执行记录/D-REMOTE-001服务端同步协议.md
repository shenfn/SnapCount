# D-REMOTE-001 TDD 执行记录

- 目标行为：服务端为 iOS 本地优先同步提供用户隔离、批量事务、幂等重试、实体版本冲突、删除 tombstone 和跨域 opaque cursor 契约。
- 当前行为：云端已有 `save_transaction_with_account`、`save_account` 等单笔 RPC，但没有批量同步元数据、operation 幂等记录或 change log。
- 权威来源：`docs/spec/模块/iOS本地优先/LOCAL-003D远端同步契约评估.md`、`docs/spec/模块/iOS本地优先/D-REMOTE-001服务端同步协议规格.md`、`ADR-036`、`ADR-039`。
- 本轮范围：服务端协议、元数据语义、RPC 请求/响应、数据库 fixture 场景和进入 D-REMOTE-002 的门禁。
- 非范围：本轮不改 SQL、不新增 RPC、不执行生产迁移、不接 iOS adapter、不扩展其他数据域。
- 基线测试结果：只读审计；`npm run governance:check` 待提交前运行；Windows 不执行 PostgreSQL 生产 fixture。
- 红灯测试及失败原因：DREMOTE-001 至 DREMOTE-009 已固定为下一片数据库红灯入口；当前服务端对象不存在，不能提前伪造绿灯。
- 最小实现：本轮只有规格和测试矩阵；所有金额、流水、RLS、幂等和 cursor 规则进入 D-REMOTE-002 SQL/fixture。
- 绿灯结果：待 D-REMOTE-002。
- 未解决风险：元数据表最终命名、change log retention、批次上限和 RPC JSON schema 需要在 SQL fixture 中落地验证。
- 下一步：创建 `docs/D-REMOTE-002迁移与RPC红灯`，先建立可重复执行迁移和 DREMOTE-001 至 DREMOTE-009 失败测试。
