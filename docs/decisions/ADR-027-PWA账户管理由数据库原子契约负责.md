# ADR-027：PWA 账户管理由数据库原子契约负责

> 日期：2026-08-16
>
> 状态：提议，待 PWA-066 评估 PR 合并

## 决策

1. 默认支出/收入互斥、归档账户非默认和跨用户隔离由数据库 trigger、约束与 canonical RPC 共同负责，不由 PWA/iOS 多步客户端更新负责。
2. 数据库 trigger 必须兼容仍在直写 `accounts` 的存量客户端；不能只加唯一索引导致当前 iOS 在设置新默认时先失败。
3. 新 PWA 使用 `save_account` 与 `set_account_archived` canonical RPC。Account Repository 只负责 transport/DTO，Account Management Feature 负责命令并发、user/generation stale、canonical 收敛和 accepted/refresh 分层。
4. 归档清除默认标记与未来自动扣款引用，不改变余额和历史记录；恢复不恢复这些关系，也不自动指定替代默认账户。
5. 产品只提供软归档，不新增单账户物理删除。已有历史或引用的账户不得通过普通编辑跨资产/负债家族迁移。
6. iOS 在 A4 迁移到相同 RPC 与 stale 语义；在此之前，数据库 trigger 保证旧版 iOS/PWA 直写不能破坏默认互斥。

## 原因

PWA 与 iOS 当前都先保存目标账户，再清除其他默认项。任一步失败或并发写入都会制造部分成功；只抽 Repository 不会改变事务事实。数据库兼容层既能为新客户端提供单一 canonical 命令，也能保护尚未升级的存量客户端，避免 PWA 修复后被 iOS 再次写坏。

## 禁止事项

- 不在 Account Management Feature 中用多个 REST 请求模拟事务。
- 不把默认清理失败降级为 warning 或成功提示。
- 不让归档账户继续作为默认或未来自动扣款来源。
- 不在恢复账户时静默恢复默认标记、自动扣款关系或选择替代默认。
- 不为“完整 CRUD”新增单账户 delete，也不改写历史流水、余额或还款记录。
- 不把 PWA-066 扩大到 wallet repair、截图还款、流水补偿或 iOS AppState 重构。
