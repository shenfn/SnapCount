# PWA-064 PWA 账户还款边界评估记录

> 日期：2026-08-16
>
> 基线：`85882db`
>
> 分支：`docs/PWA账户还款边界评估`

## 本轮范围

- 只读核对账户 CRUD、详情读取、还款周期、手动确认/撤销、截图还款、wallet 快照关联与流水 helper。
- 核对数据库事务权威、PWA 用户切换/刷新出口与 iOS 现有 Repository 形状。
- 产出职责矩阵、ADR-025、PWA-064A 至 PWA-064F 场景和后续分片顺序。

## 证据摘要

- PWA 的账户与还款职责仍集中在 `useStore.js`；手动还款和撤销直接组装 RPC，只有页面 action lock，没有 generation。
- 两个手动还款 RPC 已在数据库内维护 payment、cycle、账户流水和余额，但 Release Validation 没有对应 PostgreSQL 行为 fixture。
- `loadData` 会调用生成周期 RPC，`refreshAccountsFromDB` 可能写回快照余额，证明账户读取与写副作用尚未分开。
- 账户默认项由“保存当前账户 + 清理其他默认项”两次客户端写入组成；第二步失败仅 warning。
- wallet 快照创建/关联横跨 account、data record、cycle、adjustment 与 refresh，多处显式部分成功，不能靠抽 Repository 获得原子性。
- `upsertAccountEntry` 仅用于 wallet 负债快照校准；`voidAccountEntries` 未发现产品调用，但仍由 Store 公开。
- iOS 已有 `AccountRepositoryProtocol` 与 `NativeRepaymentCalculator`，可作为 transport 和共享语义参考；其 AppState 还款编排不替代 PWA 的 stale/refresh 契约测试。

## 基线验证

| 命令 | 结果 |
|---|---|
| `npm run test:wallet-snapshot-amount` | 通过 |
| `npm run test:finance-save` | 16 项通过 |
| `npm run test:account-binding` | 11 项通过 |
| `npm run test:record-read` | 14 项通过 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过，仅既有人工清单警告 |
| `npm run build` | 通过，仅既有 `eval` 与 bundle size 警告 |

## 结论

- 后续第一片先增加数据库还款特征 fixture，再实现 Account Repository 的 confirm/revoke transport 与独立 Repayment Feature。
- PWA-064A 至 PWA-064F 固定数据库事务、Repository、并发、会话隔离、accepted/refresh 与页面兼容边界。
- 账户读取、CRUD、截图还款、wallet 快照和流水 helper 分别转入 PWA-065 至 PWA-069。

## 未验证与剩余风险

- 未启动本地 PostgreSQL 执行还款事务；当前判断来自迁移源码，数据库行为测试是下一片首要交付物。
- 未连接真实服务执行确认、撤销或 wallet 关联。
- PWA 与 iOS 的还款状态/溢缴规则仍由两端代码分别表达，共享 fixture 尚未落地。
- 生产迁移版本和线上数据不在本轮范围；未执行生产查询、迁移、部署、真实数据写入或 TestFlight。
