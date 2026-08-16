# PWA-063A 至 PWA-063F PWA 账户补绑边界实现记录

> 日期：2026-08-16
>
> 基线：`30aed05`
>
> 分支：`feature/PWA账户补绑边界实现`

## 目标行为

- Account Binding Feature 独立持有单笔/批量补绑的并发、冲突、generation、stale 和刷新结果。
- Store 只提供推荐、确认和页面收敛，不直接组装保存 RPC。
- Record Repository 的 canonical DTO 是成功补绑的唯一事实输入。

## 本轮范围

- PWA-063A 至 PWA-063F 的 Spec、Feature、Store 接线、reset 接线、专项测试和发布门禁。

## 非范围

- RPC、迁移、账户流水、余额方向、推荐算法、默认账户、manual/edit、staging、待补全、wallet、删除、图片签名、iOS、Edge、Planner 和部署。

## 基线验证

沿用评估 PR #90 已登记结果；实现前将重新运行专项相关基线。

## 红灯证据

待补充。

## 最小实现

待补充。

## 绿灯与回归

待补充。

## 未解决风险

- 批量补绑是多次数据库事务，允许部分成功。
- 网络超时后的重复请求没有 operation ID，不能承诺端到端幂等。
- 推荐默认账户的产品策略保持现状，未在本任务重新评审。
- Account Binding Feature 与 Finance Save Feature 之间不提供全局串行化。

## 发布边界

- 不执行生产查询、迁移、部署、真实数据写入或 TestFlight。
