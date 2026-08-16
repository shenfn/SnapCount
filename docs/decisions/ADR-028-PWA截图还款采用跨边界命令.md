# ADR-028：PWA 截图还款采用跨边界命令

> 状态：已接受
>
> 日期：2026-08-16
>
> 关联：CLEAN-001/A3、PWA-067、ADR-025、ADR-027

## 决策

1. 截图还款候选是账户域纯规则：输入 staging DTO、账户和账期，输出建议或拒绝，不执行 I/O、不自动确认。
2. `confirm_staging_repayment` transport 归 Account Repository，因为事务返回 canonical repayment cycle，必须复用唯一 cycle DTO；Staging Repository 不复制该映射。
3. 新建独立 Screenshot Repayment Feature，显式协调 staging 与 accounts 状态；不把截图命令塞进手动 Repayment Feature，也不让两个 Repository 互相依赖。
4. 数据库 RPC 是 staging、cycle、payment、entry 和 balance 的单事务权威。旧参数签名继续兼容，但客户端 `p_status` 不再决定最终账单状态。
5. 已处理目标新增 `repayment_cycle`，`resolved_domain_key` 为 `wallet`；既有截图还款行只在目标账期能被同用户唯一证明时保守回填。
6. PWA-067 不创建 wallet data record，也不伪造 `evidence_record_id`；正式快照证据关联留给 PWA-068。

## 原因

- transport 放入 Staging Repository 会复制 Account Repository 的账期 DTO；放在 Store 又会继续绕过边界。
- 复用手动 Repayment Feature 会把“一个账期的人工确认/撤销”和“消费一个 staging 并归档证据”混成同一种命令身份。
- 数据库必须根据金额规则保持 `paid_amount`、`remaining_amount` 和 `status` 一致，不能信任客户端字符串。
- `target_record_id` 指向账期但没有类型会制造已处理历史死出口，违反中转目标显式化契约。

## 禁止

- 不得只移动 `sb.rpc` 而保留 Store 内候选、并发和刷新语义。
- 不得以 `p_status='paid'` 强制清零与金额不一致的账单剩余。
- 不得把 staging UUID 写入指向 `data_records` 的 `evidence_record_id`。
- 不得在 PWA-067 顺手实现 wallet snapshot 关联、iOS AppState 重构或自动确认。

## 后果

- 实现片需要数据库 migration/fixture、纯候选测试、Repository、Feature 和少量 Store/Page 接线，范围大于单一 transport 迁移但仍是一个完整事务切片。
- PWA 与 iOS 的候选规则在 A4 完成前仍可能存在实现差异；PWA-067 场景与脱敏 fixture 将成为后续对账基线。
- 已处理列表需要理解新的 `repayment_cycle` 目标类型，并为目标已不存在提供显式失败出口。
