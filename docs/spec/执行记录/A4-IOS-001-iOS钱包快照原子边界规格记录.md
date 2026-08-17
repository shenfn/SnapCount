# A4-IOS-001 TDD 执行记录：iOS 钱包快照原子边界规格

- 目标行为：iOS 钱包快照创建/关联复用 `apply_wallet_snapshot`，不再由客户端分步提交跨表写入。
- 当前行为：Repository 已改为共享 canonical RPC；AppState 仍通过兼容入口接收既有结果模型。
- 权威来源：`supabase/migrations/20260816210000_wallet_snapshot_atomic_contract.sql`；PWA-068 Spec；ADR-029。
- 本轮范围：建立 A4-IOS-001 Spec，添加 Node 源边界红灯并完成 Repository/Model 最小实现。
- 非范围：数据库/PWA/Edge/Planner、生产迁移部署和 TestFlight；Swift XCTest 仅建立契约，最终由 macOS 验证。
- 预计修改文件：`WalletSnapshotRepository.swift`、`NativeWalletSnapshot.swift`、iOS 源边界测试、package script 及追踪文档。
- 基线测试结果：远程主线基线为 `132a0a7`；Windows 无法运行 Swift 编译。
- 红灯测试及失败原因：`npm run test:ios-wallet-snapshot-boundary` 初次 4 项全部失败，证明缺少 canonical RPC、旧多步写入和结果契约。
- 最小实现：create/link 共用 `apply_wallet_snapshot`；新增 outcome、account/cycle/payment DTO 和稳定错误/畸形响应映射。
- 绿灯结果：`npm run test:ios-wallet-snapshot-boundary` 4/4 通过。
- PWA/iOS 差异：共享数据库事务和结果语义；iOS 保留 Swift Repository/AppState 入口，PWA Feature 不迁移到 iOS。
- GitHub CI 结果：PR #115 的 GitHub macOS Build/XCTest、PWA/Edge、治理和 iOS Build Gate 全部通过。
- 未解决风险：完整 AppState stale/use-case 拆分留待 A4-IOS-002；本片未改数据库/PWA/Edge/Planner。
- 对应提交：`58dc167`；合并提交 `61874ba`。
