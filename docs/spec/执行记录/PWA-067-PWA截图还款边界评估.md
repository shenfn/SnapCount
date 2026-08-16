# PWA-067 PWA 截图还款边界评估记录

> 日期：2026-08-16
>
> 基线：`b2e5644`
>
> 分支：`docs/PWA截图还款边界评估`
>
> 状态：只读评估完成，待文档 PR 验证

## 本轮范围

- 只读追踪 PWA 候选生成、页面确认、RPC、还款事务和已处理中转目标。
- 对照 iOS 候选/确认实现，确认共享业务含义是否漂移。
- 运行现有还款、中转读取、安全、构建和治理基线。
- 只新增评估、ADR、执行记录、交接和索引文档。

## 已确认

- PWA 候选规则仍在 `useStore`，没有专项测试；iOS 有独立实现且已在归档账户过滤上与 PWA 不同。
- PWA 直接调用 `confirm_staging_repayment`，忽略 canonical cycle 返回，并依赖不具备 generation stale 的 `runLockedAction`。
- RPC 事务会更新 payment/entry/balance/cycle 并归档 staging，但当前客户端 `p_status='paid'` 可以让部分金额强制清零剩余。
- 截图还款 archived staging 指向账期 UUID，却没有 `repayment_cycle` 目标类型；已处理页面会显示一个无法成功打开的“查看并编辑”入口。
- 现有 PostgreSQL 还款 fixture 不执行截图确认 RPC；安全 fixture 只检查 anon 权限。
- `evidence_record_id` 外键指向 `data_records`，PWA-067 不能直接写 staging UUID，也不能因此进入 PWA-068。

## 评估结论

- 采用 ADR-028：纯候选函数 + Account Repository transport + 独立 Screenshot Repayment Feature + 数据库原子权威。
- 后续实现拆为 PWA-067A 至 PWA-067G，先 PostgreSQL/纯逻辑/Feature 红灯，再最小实现。
- 数据库保留旧 RPC 参数签名，但最终状态由金额规则推导；新增 `repayment_cycle/wallet` 目标元数据和保守回填。
- PWA-068 wallet 快照创建、关联、cycle 和余额校准继续冻结。

## 基线验证

- `npm run test:repayment`：17 项通过。
- `npm run test:staging-read`：10 项通过。
- `npm run check:security-contracts`：通过。
- `npm run build`：通过；仅既有 `vconsole eval` 与 bundle size 警告。
- `npm run governance:check`、`npm run governance:arch`：通过；仅既有人工清单警告。
- 本机 `psql` 缺失，未执行 PostgreSQL 行为测试。

## 下一步

1. 提交并推送本轮纯文档评估，等待 PR 全部门禁通过并合并。
2. 从合并后的 main 建立 `feature/PWA截图还款边界实现`。
3. 先提交 PWA-067A 至 PWA-067G 正式 Spec，再建立 PostgreSQL 和 Node 红灯。

## 发布边界

- 未修改 PWA/iOS/数据库/Edge/Planner 业务代码。
- 未执行生产查询、migration、部署、真实数据写入或 TestFlight。
