# PWA-065 PWA 账户读取边界评估记录

> 日期：2026-08-16
>
> 基线：`2c5b205`
>
> 分支：`docs/PWA账户读取边界评估`
>
> 结果：PR #96 全门禁通过并合并，merge commit `955ef35`

## 本轮范围

- 只读核对账户列表、流水、还款周期、还款记录、来源快照和余额修复的调用链。
- 核对 PWA 列表/详情的用户切换、账户切换、失败与刷新出口。
- 参考 iOS Account Repository/AppState 的职责形状，但不修改或宣称完成 iOS 边界。
- 产出 PWA-065A 至 PWA-065E 的实现切片，不修改业务代码。

## 证据摘要

- `loadData` 与 `refreshAccountsFromDB` 都直接查询 `accounts`，且成功后调用会写余额的 `repairEmptyAccountSnapshotBalances`。
- `loadData` 失败清空账户，`refreshAccountsFromDB` 失败保留旧值，列表失败语义不一致。
- `openAccountDetail`/`refreshAccountDetail` 并行调用三个 loader，但没有统一 user/account/generation guard。
- entries/payments/source failure 被压成 `[]` 或 `null`，页面不能区分空数据、服务失败、兼容性 unavailable 与图片签名失败。
- `ensure_liability_repayment_cycles` 是写命令，却与周期查询一起藏在加载流程中。
- iOS 已有聚合详情和 `loadErrors`，来源快照也使用独立 Repository；这只作为边界参考，PWA 仍需独立特征与竞态测试。

## 评估结论

- 建立纯 Account Repository 与 Account Detail State/Feature 两层，不继续扩充大账户 Feature。
- Repository 不接收 `user_id`，不拥有 Vue、选中状态、来源快照、图片签名、余额写入或修复。
- 详情 State 固定同请求复用、account/user/generation stale、section partial error 和 accepted/partial/failed/stale 刷新结果。
- 来源快照保持 Record/Wallet Snapshot 边界；repair 副作用移出读取路径，实际重构留到 wallet 后续切片。

## 验证

| 命令 | 结果 |
|---|---|
| `npm run governance:check` | 通过 |
| `git diff --check` | 通过，仅 Git 行尾转换提示 |

## 未验证与剩余风险

- 尚未编写 PWA-065A 至 PWA-065E 正式 Spec、红灯或业务实现。
- 尚未用浏览器复现快速切换账户时的旧详情覆盖；风险由现有无 guard 调用链静态确认。
- 尚未裁决 wallet 余额修复的最终触发入口、幂等键与数据库事务边界。
- 未连接真实服务；未执行生产查询、迁移、部署、真实数据写入或 TestFlight。
