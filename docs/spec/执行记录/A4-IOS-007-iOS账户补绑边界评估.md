# A4-IOS-007 iOS 账户补绑边界评估执行记录

> 状态：已完成，PR #133 已合并
>
> 日期：2026-08-22
>
> 基线：`11f79ad6`（PR #133 合并提交）

> 最终门禁：A4-IOS-007A-G XCTest、macOS iOS Build、Release Validation、Governance Validation 和源边界检查全部通过。

## 本次结论

下一片选择 iOS 账户补绑动作编排。当前缺口集中在 `AppState.bindUnboundRecord` 与 `batchBindUnboundRecords`：单笔/批量直接管理 transport、局部投影和刷新，缺少统一的逐项结果、refresh failure、generation stale 和批量停止语义。

## 只读证据

- `UnboundRecordRepository.bind` 已按 expense/income 调用 `save_transaction_with_account` / `save_income_with_account`，但丢弃服务端 response，只返回 `Void`。
- 单笔绑定成功后立即移除本地记录并刷新账户、未绑定记录和 dashboard；刷新错误没有形成独立结果。
- 批量绑定顺序执行，每项只累计成功/失败计数，不保留逐项 record identity 和错误原因；用户切换不会统一停止后续项。
- `NativeAccountRecommendationEngine` 已是纯函数，本片不迁移、不复制。
- 没有修改 iOS、PWA、数据库、Edge、Planner 或生产配置。

## 计划门禁

1. 评估 PR 合并后，从最新 main 建立 A4-IOS-007 红灯 worktree。
2. 先添加 A4-IOS-007A-G XCTest/源边界检查，再做 Repository 结构化结果和 Use Case 最小实现。
3. Windows 验证静态/脚本门禁；GitHub macOS 验证 Swift/XCTest。
4. 实现收口时更新阶段索引、交接快照和本执行记录；未通过全部门禁不进入下一片。

## 红灯工作区进展

- 分支：`test/A4-IOS-007账户补绑红灯`。
- 新增 `ios/SnapCountTests/AccountBindingUseCaseTests.swift`，覆盖 A4-IOS-007A-G 的输入拒绝、并发复用/冲突、accepted 与刷新失败分层、批量部分成功、stale 停止、identity 保留和纯推荐边界。
- 新增 `scripts/test-ios-account-binding-boundary.mjs`，固定 Use Case、Repository、AppState 和推荐算法的依赖方向。
- 新增 npm 命令 `npm run test:ios-account-binding-boundary`。
- 预期红灯：`AccountBindingUseCase.swift` 尚不存在；Repository 仍返回 `Void`；AppState 仍直接调用 Repository 并循环批量动作。

## 红灯验证

- `npm run test:ios-account-binding-boundary`：1 项场景登记通过，4 项边界断言按预期失败；失败均属于本片尚未实现的业务边界，不是环境错误。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过；仅保留既有人工清单警告。
- `git diff --check`：通过（仅有 Windows 换行提示）。
- Windows 未运行 Swift/XCTest；后续以 GitHub macOS iOS Build 为编译和 XCTest 权威。

## 实现收口

- `AccountBindingUseCase` 已接管单笔/批量补绑编排：相同命令复用、不同账户冲突、逐项结果、stale、批量停止和一次刷新。
- `UnboundRecordRepository` 返回 `NativeAccountBindingResult`，保留服务端 accepted 的记录 kind/id/账户 identity；expense/income RPC 参数未改写。
- `AppState` 保留原公开入口，只做结果投影、同记录移除和消息转换；用户作用域 reset 会使旧补绑 stale。
- A4-IOS-007A-G XCTest 全部通过；PR #133 的 macOS Build、iOS Build Gate、Release Validation、治理门禁和源边界检查全部通过。
- 未执行生产查询、迁移、部署、真实账户写入或 TestFlight。

## 未验证项

- Windows 无法运行 Swift/XCTest；
- 未执行生产查询、迁移、部署、真实账户写入或 TestFlight；
- 服务端绑定 RPC 的事务语义继续以现有 migration/RPC 和 PWA-063 证据为权威。
