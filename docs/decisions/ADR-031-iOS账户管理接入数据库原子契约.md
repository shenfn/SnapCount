# ADR-031：iOS 账户管理接入数据库原子契约

> 状态：已接受（评估决策）
>
> 日期：2026-08-19
>
> 关联任务：A4-IOS-004、PWA-066、ADR-027

## 决策

iOS 下一片业务编排切片选择账户管理原子动作接线。`AccountRepository.save` 和 `AccountRepository.setArchived` 必须改为调用已合并的 `save_account` 与 `set_account_archived`；其上新增纯 Swift `AccountManagementActionUseCase`，负责命令 identity、并发冲突、generation/user stale、accepted 收敛和 refresh 分层。`AppState` 保留公开入口，只承担兼容状态投影。

## 背景

当前 iOS 账户保存是 REST 写入后再多步清理默认项，归档是单独 REST patch。即使数据库兼容 trigger 能降低部分多默认风险，这两条路径仍绕过 canonical RPC 的完整语义：跨资产/负债类型迁移阻断、归档默认清除、未来自动扣款账户和开放周期引用清理、以及稳定的 canonical row 返回。

主线已有 `20260816160000_account_management_atomic_contract.sql`，并由 PWA-066A 至 PWA-066F 验证。继续让 iOS 走旧 transport 会使同一账户在不同客户端得到不同的业务结果。

## 备选方案

- 方案 A：先做截图还款候选与确认。确认 RPC 已是原子命令，但 AppState 还混合候选读取和收件箱刷新；跨 staging、cycle、account 的范围更宽，不能解决账户管理旁路。
- 方案 B：先拆账户列表/详情读取副作用。`fetchDetail` 已有分区错误模型，但 `loadAccountDetail` 的 `ensureRepaymentCycles` 仍需要单独设计写副作用结果，不能与账户写动作合并。
- 方案 C：接入账户管理 canonical RPC 并抽动作编排。数据库权威已经存在，能够独立验证并直接消除 iOS/PWA 语义分叉。选择此方案。

## 边界与约束

- 不新增或修改数据库 migration/RPC，不执行生产迁移。
- 不修改余额、流水、周期或还款状态规则。
- 不把账户管理与截图还款、账户详情读取合并为一个大 Feature。
- Repository 不复制默认互斥、类型迁移和归档引用清理规则；这些只由数据库 canonical 契约负责。
- accepted 与 refresh failure 必须可观察；刷新失败不得触发第二次写命令。
- reset/user switch 后的旧请求不得更新当前用户状态。

## 后果

正面后果：iOS 与 PWA 使用同一数据库事实；默认项、归档、自动扣款和类型迁移不再由各端复制；实现可以用纯 Swift XCTest 固定并发和 stale 行为。

代价与剩余风险：需要新增一个 iOS Use Case 和结果模型；Repository 的 RPC 错误映射必须与 Swift DTO 保持兼容；Windows 无法本地验证 Swift，必须依赖 macOS CI。账户读取中的 `ensureRepaymentCycles` 仍暂时存在，后续必须独立收拢。

## 验证要求

实现阶段必须提供：专项 XCTest、Repository 源边界检查、完整 macOS simulator Build、相关 PWA/Edge 回归、治理与架构门禁，以及交接快照。未完成这些证据前，A4-IOS-004 不得标记完成。
