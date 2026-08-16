# ADR-026：PWA 账户读取分离纯查询与详情状态

> 日期：2026-08-16
>
> 状态：接受，待文档 PR 合并

## 决策

1. Account Repository 只拥有账户、流水、还款周期和还款记录的 transport/DTO，不拥有当前账户选择、Vue 状态、图片签名或余额修复。
2. 账户详情由独立 Account Detail State/Feature 编排，以 user identity、account id 和 generation 作为请求身份，保留 section partial error 与 stale 结果。
3. 来源快照继续由 Record/Wallet Snapshot 读取边界负责；Account Detail State 可以编排该边界，但 Account Repository 不查询 `data_records`。
4. `ensure_liability_repayment_cycles` 与周期查询保持两个显式方法；写命令不得隐藏在 `listRepaymentCycles` 中。
5. `repairEmptyAccountSnapshotBalances` 从纯账户读取成功路径中移出。PWA-065 不重写该规则，后续由 wallet 快照修复/对账切片决定触发、幂等和会话隔离。
6. Store 继续提供兼容 API，页面逐步消费结构化 loading/error/refresh 状态，不一次性重写 wallet 页面。

## 原因

当前详情 loader 会把旧账户或旧用户的异步结果写入共享 selected 状态，并把查询失败压成空数组或 `null`。同时，列表读取成功后会触发余额更新。仅抽取 Supabase 查询会把这些行为缺陷固化进 Repository。纯 transport 与详情状态分离后，Repository 可以保持可测试的读契约，Feature 则显式承担会话身份、并发和部分失败语义。

## 禁止事项

- 不让 `listAccounts`、`listRepaymentCycles` 或其他读取方法暗中写数据库。
- 不让 Repository 接收或发送 `user_id` 绕过 RLS 会话边界。
- 不在一个 section 失败时清空其他已成功 section。
- 不让旧 account/user/generation 的结果更新当前详情或当前用户错误提示。
- 不以 Account Repository 统一命名为理由吸收 `data_records`、图片签名、wallet 快照写入或修复逻辑。
