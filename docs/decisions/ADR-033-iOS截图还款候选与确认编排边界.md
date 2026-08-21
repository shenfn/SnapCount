# ADR-033：iOS 截图还款候选与确认编排边界

> 状态：已接受（评估决策）
>
> 日期：2026-08-21
>
> 关联任务：A4-IOS-006、A4-IOS-005、PWA-067

## 决策

iOS 截图还款拆成“候选纯规则 + RPC transport + 确认编排”三层：

- 候选继续由 `NativeRepaymentCandidateEngine` 负责，输入为快照，零 I/O；
- `InboxRepository.confirmStagingRepayment` 继续是 `confirm_staging_repayment` 的唯一 transport；
- 新增窄的纯 Swift Screenshot Repayment Use Case/Feature State，负责命令并发、用户/generation stale、accepted 投影和 refresh 分层；
- `AppState` 保留公开入口，只负责把结构化结果投影到现有 iOS UI 状态。

## 原因

现有 iOS 架构骨架已经正确，问题集中在 `AppState.confirmStagingRepayment` 同时承担跨域编排：确认框、账户/账期候选、RPC、staging 数组、processed 状态、导航和 dashboard 刷新。继续把这些职责留在 AppState 会让 accepted、refresh failed 和 stale 继续不可区分；把它们塞入 Repository 又会让 Repository 反向依赖页面状态。

## 禁止事项

- 不以“清理重复”为由删除候选纯函数或把 PWA Store 代码复制到 Swift。
- 不在 iOS 侧重新推导账期状态、余额方向或还款金额规则。
- 不把截图确认与账户读取 prepare、钱包快照或手动还款 Feature 合并。
- 不把 `staging_records` UUID 写入 `evidence_record_id`，不创建 wallet data record。

## 验证要求

实现必须证明同命令复用、冲突、未登录/非法输入、reset/user stale、accepted 先投影、refresh failed 可观察，以及失败时不推进当前页面。Windows 只做静态/脚本检查；Swift 行为以 macOS GitHub Build/XCTest 为准。
