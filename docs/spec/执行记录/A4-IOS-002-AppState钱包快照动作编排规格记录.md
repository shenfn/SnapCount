# A4-IOS-002 TDD 执行记录：AppState 钱包快照动作编排规格

- 目标行为：把钱包快照动作的 session、busy、in-flight、generation stale、accepted/refresh 分层从 AppState 抽到纯 Swift Use Case/Coordinator。
- 当前行为：AppState 直接编排 create/link、刷新三个读模型和消息；Repository 已在 A4-IOS-001 收拢为 canonical RPC。
- 权威来源：A4-IOS-002 只读评估、A4-IOS-001 钱包快照原子边界规格、ADR-029。
- 本轮范围：正式 Spec、场景矩阵、输入/输出契约、兼容门面边界和 TDD 顺序。
- 非范围：AppState Swift 实现、XCTest 红灯、Repository、数据库/PWA/Edge/Planner、生产发布。
- 预计修改文件：AppState Use Case Spec、规格索引、阶段索引、执行记录、交接快照。
- 基线测试结果：未运行业务测试；本轮为 Spec 文档片。主线基线为 `128352a`。
- 红灯测试及失败原因：尚未建立；下一片先添加 A4-IOS-002A-F XCTest。
- 最小实现：未开始。
- 绿灯结果：未验证。
- PWA/iOS 差异：共享 accepted/stale/refresh 业务语义；Use Case 与 AppState 为 iOS 平台编排，不迁移 PWA Feature。
- GitHub CI 结果：本 Spec PR 尚未创建。
- 未解决风险：Swift Task 去重和 generation provider 的具体类型待测试驱动确认；不能在未评审前扩大到其他 AppState 动作。
- 对应提交：待提交。
