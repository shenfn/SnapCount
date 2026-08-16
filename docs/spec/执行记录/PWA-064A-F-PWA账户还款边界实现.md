# PWA-064A 至 PWA-064F PWA 账户还款边界实现记录

> 日期：2026-08-16
>
> 基线：`d47fa5b`
>
> 分支：`feature/PWA账户还款边界实现`

## 目标行为

- 数据库特征测试固定手动确认、重新确认和撤销的事务事实。
- Account Repository 独占两个还款 RPC 的 transport 与 canonical cycle DTO。
- Repayment Feature 独立持有并发、冲突、generation、stale 和刷新结果。
- Store/Page 保留用户预览和兼容 API，不再直接组装还款 RPC。

## 本轮范围

- PWA-064A 至 PWA-064F 的正式 Spec、数据库 fixture、Repository/Feature/Store 测试、最小实现、Release Validation 和文档。

## 非范围

- 生产 migration、账户读写/CRUD、周期生成、截图还款、wallet 快照、流水 helper、iOS、Edge、Planner、生产配置和部署。

## 基线验证

沿用评估 PR #93 的已登记结果；实现前重新确认 wallet、财务保存、账户补绑、正式记录、构建与治理基线。

## 特征测试与红灯证据

待执行后补充。

## 最小实现

待红灯成立后补充。

## 绿灯与回归

待实现后补充。

## 未解决风险

- 网络超时后没有 operation ID，不能承诺客户端端到端 exactly-once。
- PWA/iOS 还款预览规则的共享 fixture 留到 A4 对账；本片保持既有页面计算不变。
- 账户详情刷新仍依赖 PWA-065 后续读取边界；本片只要求刷新失败可被 Feature 看见。

## 发布边界

- 不执行生产查询、迁移、部署、真实数据写入或 TestFlight。
