# ADR-025：PWA 账户域按事务风险分片

> 日期：2026-08-16
>
> 状态：接受，PR #93 已合并

## 决策

1. 不建立一个同时容纳账户 CRUD、详情读取、还款、截图确认、wallet 快照和流水补偿的“大账户 Feature”。
2. 首片只收拢手动确认与撤销还款：数据库 RPC 保持事务权威，Account Repository 负责 transport/DTO，Repayment Feature 负责并发、generation、stale 和 accepted/refresh 分层。
3. 在客户端重构前先新增 PostgreSQL 特征 fixture，固定确认、重新确认、撤销、流水、余额和用户隔离现状；测试可以先绿，因为它保护的是已有数据库行为。
4. 账户列表/详情、账户 CRUD、截图还款、wallet 快照和旧流水 helper 按 PWA-065 至 PWA-069 分开评估或实现。
5. wallet 快照多步写入在获得原子数据库契约前不得被封装并宣称为事务；账户默认项多步更新也不得在普通 Repository 重构中被掩盖。
6. iOS `AccountRepositoryProtocol` 只作为 transport 形状参考；其 AppState 是否满足 generation 与 accepted/refresh 语义留到 A4 以同场景复核。

## 原因

手动还款已经有数据库原子 RPC，适合成为可控的首个垂直切片。wallet 快照与账户默认项仍是多次客户端写入，如果一起迁移，代码虽然会变小，却会把原有部分成功和跨表不一致风险藏到新抽象内部。按事务边界分片可以让每个 Feature 的返回状态、回滚能力和测试层与真实权威一致。

## 禁止事项

- 不在 Repository 中计算还款状态、溢缴、余额方向或候选账户。
- 不把 RPC accepted 后的刷新失败描述为还款失败，也不自动重试写入。
- 不让旧会话结果更新当前用户的 cycle、账户详情或提示。
- 不为统一命名直接搬迁或删除未完成调用审计的流水 helper。
- 不把 PWA-064 扩大到账户 CRUD、截图还款或 wallet 快照关联。
