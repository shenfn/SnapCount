# A4-IOS-002 TDD 执行记录：AppState 钱包快照动作编排

- 目标行为：把钱包快照动作的 session、busy、in-flight、generation stale、accepted/refresh 分层从 AppState 抽到纯 Swift Use Case/Coordinator。
- 当前行为：`WalletSnapshotActionUseCase` 已承接 create/link 的输入校验、同命令 Task 复用、异目标冲突、generation stale 和 accepted/refresh 分层；AppState 只保留公开入口、busy/message 投影和三个既有读模型刷新。
- 权威来源：A4-IOS-002 只读评估、A4-IOS-001 钱包快照原子边界规格、ADR-029。
- 本轮范围：A4-IOS-002A-F XCTest、纯 Swift Use Case、AppState 兼容门面、本地源边界和交接证据。
- 非范围：Repository RPC、数据库/PWA/Edge/Planner、页面视觉、生产发布和其他 AppState 动作。
- 修改文件：`WalletSnapshotActionUseCase.swift`、`AppState.swift`、`WalletSnapshotActionUseCaseTests.swift`、本地源边界脚本、package script 和本任务文档。
- 基线测试结果：A4-IOS-001 Repository 源边界 4/4 通过；PWA production build 通过；治理和架构 ratchet 通过。
- 红灯测试及失败原因：A4-IOS-002A-F 已写入 XCTest；Windows 无 Swift/Xcode，无法在本地执行编译红灯，不能把环境缺失写成业务失败。
- 最小实现：新增 `WalletSnapshotActionUseCase`，动作身份为 `userId + recordId`，签名包含 operation/accountId；同签名复用 Task，异签名返回 conflict；reset 与 user/generation 变化使旧任务 stale；accepted 后刷新失败保持 accepted。
- 绿灯结果：Node 源边界 4/4、A4-IOS-001 源边界 4/4、`npm run build`、`governance:check`、`governance:arch` 均通过；GitHub macOS SwiftUI Build 与完整 XCTest 通过。
- PWA/iOS 差异：共享 accepted/stale/refresh 业务语义；Use Case 与 AppState 为 iOS 平台编排，不迁移 PWA Feature。
- GitHub CI 结果：PR #118 首轮发现 `Task` 弱引用早退的 `.stale` 类型推断错误；提交 `6074e81` 显式返回 `WalletSnapshotActionResult.stale` 后，SwiftUI Build、完整 XCTest、iOS Build Gate、PWA/Edge 综合门禁、治理和 Cloudflare 全部通过。
- 未解决风险：读模型刷新仍复用现有 loader，并通过其 message 暴露失败；本片不推广到其他 AppState 动作，后续切片需重新评估边界。
- 对应提交：`8222a06`、`6074e81`；PR #118 待合并。
