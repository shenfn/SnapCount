# PWA-067A 至 PWA-067G PWA 截图还款边界实现记录

> 日期：2026-08-16
>
> 基线：`5386d6e`（PWA-067 评估 PR #104 合并提交）
>
> 分支：`feature/PWA截图还款边界实现`
>
> 状态：正式 Spec 已建立，待红灯

## 当前范围

- PWA-067A：候选纯规则。
- PWA-067B：数据库原子确认、状态推导与 `repayment_cycle` 目标。
- PWA-067C：Account Repository transport。
- PWA-067D：Feature 并发与 stale。
- PWA-067E：accepted 收敛与 refresh 分层。
- PWA-067F：已处理目标出口。
- PWA-067G：PagePending 取消、失败与推进语义。

## 基线

- `test:repayment`：17 项通过。
- `test:staging-read`：10 项通过。
- `check:security-contracts`、Vite build、治理与架构检查通过，仅既有警告。

## 冻结范围

- PWA-068 wallet snapshot 创建/关联/repair、`evidence_record_id` 正式关联。
- iOS、Edge、Planner、流水 helper、生产配置、生产 migration、部署与 TestFlight。

## 下一步

1. 为候选、Repository、Feature、Store/Page 和 migration 契约建立有效红灯。
2. 记录红灯失败原因后写最小实现。

## 发布边界

- 尚未执行生产查询、migration、部署、真实数据写入或 TestFlight。
