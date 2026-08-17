# A4-IOS-001 TDD 执行记录：iOS 钱包快照原子边界规格

- 目标行为：iOS 钱包快照创建/关联复用 `apply_wallet_snapshot`，不再由客户端分步提交跨表写入。
- 当前行为：`WalletSnapshotRepository` 直接写账户、记录、账期并单独校准流水；AppState 只收到 `accountId/warnings`。
- 权威来源：`supabase/migrations/20260816210000_wallet_snapshot_atomic_contract.sql`；PWA-068 Spec；ADR-029。
- 本轮范围：建立 A4-IOS-001 Spec、场景矩阵、阶段追踪和接续指针。
- 非范围：Swift 实现、XCTest 红灯、数据库/PWA/Edge/Planner、生产迁移部署和 TestFlight。
- 预计修改文件：iOS 钱包快照模块 Spec、规格索引、阶段索引、清洗计划、执行记录、交接快照。
- 基线测试结果：未运行业务测试；本轮为文档规格片。远程主线基线为 `54cc313`。
- 红灯测试及失败原因：尚未建立；下一片先添加 A4-IOS-001 至 A4-IOS-006 Repository XCTest/源边界测试。
- 最小实现：未开始。
- 绿灯结果：未验证。
- PWA/iOS 差异：共享数据库事务和结果语义；iOS 保留 Swift Repository/AppState 入口，PWA Feature 不迁移到 iOS。
- GitHub CI 结果：本轮文档 PR 尚未创建。
- 未解决风险：Windows 无法编译 Swift；`NativeWalletSnapshotLinkResult` 需要扩展为显式 outcome/DTO；完整 AppState stale/use-case 拆分留待后续切片。
- 对应提交：待提交。
