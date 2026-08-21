# A4-IOS-007 iOS 账户补绑边界评估执行记录

> 状态：只读评估完成，等待评估 PR 合并
>
> 日期：2026-08-22
>
> 基线：`ebd1ad8`（A4-IOS-006 收口合并提交）

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

## 未验证项

- Windows 无法运行 Swift/XCTest；
- 未执行生产查询、迁移、部署、真实账户写入或 TestFlight；
- 服务端绑定 RPC 的事务语义继续以现有 migration/RPC 和 PWA-063 证据为权威。
