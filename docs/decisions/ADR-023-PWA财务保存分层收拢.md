# ADR-023：PWA 财务保存分层收拢

> 日期：2026-08-16
>
> 状态：已决定，待 PWA-058 至 PWA-062 实现

## 决策

1. `save_transaction_with_account` 与 `save_income_with_account` 继续作为正式记录和账户流水的数据库原子权威，首片不修改函数。
2. `recordRepository` 只增加这两个保存 transport，并复用既有 `mapTransaction` / `mapIncomeRow`；不得拥有账户选择、余额算法或页面状态。
3. 新增 Finance Save Feature，复用 Staging Feature 已验证的 inflight、generation、用户隔离和 `refreshStatus` 模式。
4. Store 保留表单校验、时间/账户选择和页面收敛，但 manual/edit 分支不得再直接调用两个保存 RPC或手工构造正式记录 DTO。
5. staging 归档、待补全确认和账户补绑保持独立用例；PWA-063 再处理账户补绑 transport。
6. 并发请求合并不等于数据库幂等；没有 operation ID 前，不承诺网络超时后的安全重试。

## 原因

数据库事务已经正确解决“记录与账户流水是否一起成功”，当前缺口在客户端异步边界：旧用户请求可能污染新会话，刷新失败可能掩盖已成功写入，手工 DTO 会丢失账户和时间字段。单纯移动 RPC 不能解决这些问题，因此 Repository 和 Feature 必须分层，同时保留 Store 的交互编排职责。

## 禁止事项

- 不把账户余额计算或流水补偿搬到客户端。
- 不因刷新失败重复提交已 accepted 的保存请求。
- 不用 `detected_domain_key`、页面数组或按钮状态推断数据库写入结果。
- 不把 staging、待补全、补绑和 manual/edit 合成一个万能 save 方法。
- 不把 concurrent dedupe 宣称为端到端幂等。

