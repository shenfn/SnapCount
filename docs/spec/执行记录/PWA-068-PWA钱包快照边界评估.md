# PWA-068 PWA 钱包快照边界评估记录

> 日期：2026-08-16
>
> 基线：`c66e0a3`
>
> 分支：`docs/PWA钱包快照边界评估`
>
> 状态：只读评估完成，待文档 PR 验证

## 本轮范围

- 只读追踪 PWA wallet 快照创建、关联、opening balance、cycle、reconciliation 和页面出口。
- 核对账户、流水、账期、payment、正式记录的 RLS、外键、唯一约束、trigger 和 RPC。
- 对照 iOS 同类实现和历史 `codex/账户快照关联修复` WIP，不修改或吸收它们。
- 只新增评估、ADR、执行记录、交接和索引文档。

## 已确认

- PWA 和 iOS 都用客户端多步写入模拟一次跨表事务，无法保证全成或全败。
- PWA cycle 直接 upsert 可以覆盖已有 payment/终态；`status=paid` 不会生成 payment/entry 证据。
- `upsertAccountEntry` 吞掉失败后，调用方仍可能写 `last_reconciled_at`，造成虚假校准完成。
- legacy liability snapshot 的 amount 只能稳定证明待还/账单金额，不能同时作为当前总欠款和已还金额。
- 单表 RLS 已存在，但跨表外键没有同用户一致性约束，必须由 canonical RPC 显式验证。
- `repairEmptyAccountSnapshotBalances` 当前无调用者；历史 WIP 的读取时 repair 不能回到主线。

## 评估结论

- 接受 ADR-029：数据库原子命令 + Account Repository transport + 独立 Wallet Snapshot Feature。
- 后续实现拆为 PWA-068A 至 PWA-068J，优先建立 PostgreSQL 原子性、权限、幂等、证据优先级和时间顺序 fixture。
- paid 快照必须形成正式 payment/entry；证据不足时返回 `needs_confirmation`，不伪造已还清。
- PWA-069、iOS、Edge、Planner 和生产操作继续冻结。

## 基线验证

- `npm run test:wallet-snapshot-amount`：通过。
- `npm run test:account-read`：20 项通过。
- `npm run test:account-management`：19 项通过。
- `npm run test:repayment`：18 项通过。
- `npm run governance:check`、`npm run governance:arch`：通过；只有既有人工清单警告。
- `npm run build`：通过；只有既有 `vconsole eval` 与 bundle size 警告。
- 未执行 PostgreSQL 行为测试、生产查询、migration、部署、真实数据写入或 TestFlight。

## 下一步

1. 复核纯文档 diff，提交并推送评估 PR。
2. PR 合并后从最新 main 建立 `feature/PWA钱包快照原子边界`。
3. 先提交正式 Spec 与 PostgreSQL/Node 红灯，再写 migration、Repository、Feature 和接线。

## 发布边界

- 未修改 PWA/iOS/数据库/Edge/Planner 业务代码。
- 未修改历史 WIP，未执行生产或发布操作。
