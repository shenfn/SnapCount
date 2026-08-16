# ADR-029：PWA 钱包快照采用数据库原子命令

> 状态：接受
>
> 日期：2026-08-16
>
> 关联：CLEAN-001/A3、PWA-068、ADR-025、ADR-028

## 决策

1. wallet 快照创建账户和关联既有账户由一个数据库原子命令承接；记录、账户、账期、payment、流水、余额和校准时间不得由客户端分步提交。
2. 资产余额、负债账单、当前总欠款和已还金额是不同事实。legacy liability snapshot 默认只证明 statement；没有 current-total 证据时不得校准账户总欠款。
3. `status=paid` 的正式 wallet record 是还款 evidence，必须经过 canonical repayment 金额/状态规则生成幂等 payment/entry；不得只把 cycle 标成 paid。
4. Account Repository 独占 RPC transport 和 account/cycle DTO；独立 Wallet Snapshot Feature 负责命令身份、并发冲突、会话 stale 和 accepted/refresh 分层。
5. repair 不得成为普通读取副作用。存量修复只能通过可审计 migration 或显式命令处理可证明集合。
6. iOS 在 A4 接入同一数据库契约；A3 不修改 Swift，也不保留第二套跨表事务语义。

## 原因

- 当前一次动作跨越多张表，任一后续失败都会留下孤儿账户、半关联记录、错误账期或虚假校准水位。
- RLS 保护单表行访问，但不会自动证明跨表 UUID 属于同一用户；事务入口必须显式校验所有权。
- 无条件 cycle upsert 会覆盖已有还款事实，`status=paid` 又没有 payment/entry 证据，违反已落地的还款权威。
- 将现状包装进 Repository 只能隐藏部分成功，不能提供原子性或可靠重试。

## 禁止

- 不得把现有 `createAccountFromWalletSnapshot` / `linkWalletSnapshotToAccount` 原样搬进 Repository 后宣称边界已完成。
- 不得用一份截图金额同时覆盖账户 current balance、cycle statement 和 paid amount。
- 不得在流水失败后更新 `last_reconciled_at`，也不得让旧快照回退校准时间。
- 不得重新把 `repairEmptyAccountSnapshotBalances` 接入 `loadData` 或账户刷新。
- 不得直接吸收 `codex/账户快照关联修复` 的过期 WIP，或在 PWA-068 顺手修改 iOS/PWA-069。

## 后果

- 实现片必须包含 migration、PostgreSQL fixture、Repository、独立 Feature 和最小 Store/Page 接线，范围大于普通前端重构。
- legacy liability snapshot 的保守默认会减少自动余额改写；证据不足时产品需要显示 `needs_confirmation`，而不是猜测成功。
- 后续可让 PWA 与 iOS 共用同一事务权威，但两端仍分别负责自己的会话 stale 和页面状态。
