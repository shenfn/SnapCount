# ADR-030：iOS 账户还款动作编排边界

> 状态：提议
>
> 日期：2026-08-19
>
> 关联任务：A4-IOS-003、PWA-064、ADR-025

## 决策

iOS 手动账户还款确认与撤销作为一个独立动作编排切片，新增纯业务 `RepaymentActionUseCase`。`AppState` 保留现有公开入口和消息/忙碌状态投影；`AccountRepository` 继续独占 `set_repayment_cycle_paid_amount` 与 `revoke_liability_payment` 的 transport、参数和 canonical cycle 解码。

## 背景

当前 `AppState.confirmRepayment` 与 `revokeLiabilityPayment` 同时处理 session、并发锁、RPC、三处读模型刷新和用户消息。这样会把“事务已 accepted”和“accepted 后刷新失败”混为一个布尔结果，也无法可靠表达用户切换后的 stale 结果。PWA-064 已为相同业务建立了 accepted/refresh/stale/conflict 行为基线。

## 备选方案

- 方案 A：继续在 AppState 内增加更多分支。改动小，但会延续业务编排与 SwiftUI 状态的耦合。
- 方案 B：把整个 AccountRepository、账户详情读取和截图还款一次性重写。边界过大，难以定位回归。
- 方案 C：只抽取手动确认/撤销 Use Case，保留兼容入口和现有读取路径。选择此方案。

## 选择原因

方案 C 的事务边界已经由数据库 RPC 固定，切片可独立验证；同时把最容易造成数据污染的 accepted/refresh/stale 语义先固定，再决定读取和截图还款的后续拆分。它不要求修改数据库或页面展示，风险和回滚面可控。

## 影响与边界

- Use Case 不得依赖 SwiftUI、HTTP、Supabase client 或页面类型。
- Repository 不得计算还款状态、余额方向、扣款推荐或用户文案。
- 截图还款、账户 CRUD、账户读取整体重构、钱包快照和数据库 migration/RPC 不属于本 ADR。
- 不得以“减少重复”为由合并手动还款与截图还款两条命令；二者的 staging 事务边界不同。
- accepted 后的刷新失败必须可观察，但不得触发第二次写 RPC。

## 验证证据

- 当前只读证据：`ios/SnapCount/App/AppState.swift`、`ios/SnapCount/Repositories/AccountRepository.swift`。
- 跨端行为基线：`docs/spec/模块/PWA业务边界/账户还款规格说明.md`。
- 实现阶段必须补充专项 XCTest、完整 macOS iOS Build、治理和架构门禁结果。
