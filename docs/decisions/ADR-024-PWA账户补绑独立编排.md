# ADR-024：PWA 账户补绑独立编排

> 日期：2026-08-16
>
> 状态：已实施，PR #91 已合并

## 决策

1. 账户补绑继续调用 `save_transaction_with_account` / `save_income_with_account`，复用 Record Repository 已有的 `saveExpense` / `saveIncome` transport 和 canonical DTO。
2. 新建独立 Account Binding Feature，负责单笔 inflight、冲突账户、generation、用户切换、批量停止与逐项结果；不复用 Finance Save Feature。
3. Store 保留推荐账户计算、用户确认、canonical DTO 页面收敛、表达计划失效和文案；Feature 只接收已确认的 `accountId`。
4. 单笔和批量都必须区分数据库 accepted 与写后 refresh；刷新失败不得降级为补绑失败。
5. 批量补绑按独立事务顺序执行，返回逐项结果并在写入结束后最多刷新一次；用户切换时停止后续项。
6. PWA-063 不修改 RPC、迁移、账户流水、余额方向、推荐策略或默认账户规则。

## 原因

Record Repository 已经提供正确的参数映射和正式记录 DTO，重复 transport 没有价值。Finance Save Feature 的请求键和 modal 回调语义面向新建/编辑；若直接复用，同一记录的编辑与不同账户补绑可能错误共享请求，批量部分失败也没有表达空间。独立 Feature 能复用同一数据库权威，同时保持账户补绑自己的状态机和用户出口。

## 禁止事项

- 不新增第二套保存 RPC 参数映射，不在 Store 保留 `sb.rpc('save_*_with_account')`。
- 不把推荐算法或默认账户选择放进 Repository 或 Account Binding Feature。
- 不把批量多事务描述成原子操作，也不把客户端请求合并描述成数据库幂等。
- 不因刷新失败重试已 accepted 的补绑请求。
- 不让 stale 结果修改当前用户页面、关闭当前预览或显示旧任务提示。
