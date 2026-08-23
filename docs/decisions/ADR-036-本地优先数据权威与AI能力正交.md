# ADR-036：本地优先数据权威与 AI 能力正交

> 状态：已接受
>
> 日期：2026-08-23
>
> 关联任务：LOCAL-001、LOCAL-002、LOCAL-AI-001

## 决策

iOS 采用 Local-First + Sync，而不是 Local-Then-Cloud：

```text
Use Case
  -> Local-first Repository
       -> 本地数据库 + Outbox
       -> Sync Engine -> Supabase
```

本地写入成功即构成当前设备的可见业务结果；同步是独立、可重试的后续过程。业务 Use Case 不同时操作“本地模式 Repository”和“云端模式 Repository”，也不根据套餐分支业务流程。

数据位置与 AI 来源是两个正交能力：

- 数据：本地保存；用户主动开启后增加云同步。
- AI：关闭、应用托管 AI、用户自带 API Key（BYOK）。

## 背景

当前架构由 Supabase Auth、数据库、Storage、RPC 和 Edge Function 共同提供业务权威。要支持免登录、断网记录和“项目方不保存业务隐私数据”，必须把本地存储从缓存提升为正式基础设施，同时保留现有云端能力作为可选同步和 Hosted AI 后端。

## 备选方案

- 方案 A：Supabase 继续为唯一权威，本地仅缓存。无法满足免登录和断网写入目标。
- 方案 B：按 Local/Cloud/BYOK/Pro 建立多套模式类。容易把权限和套餐判断扩散进业务层。
- 方案 C：本地写入与同步分离，AI Provider 独立抽象，商业套餐只组合能力。

## 选择原因

选择方案 C。它使离线写入、同步失败和 AI 失败互不阻塞，并允许未来调整套餐、供应商和同步策略而不重写核心 Use Case。

## 影响与边界

- 开启多设备同步后，本地数据库是当前设备即时事实，Sync Protocol 是跨设备协调权威，Supabase 是中继、备份和协调中心，不是可被任一设备覆盖的普通镜像。
- 账户余额不得采用最后写入覆盖；优先同步不可变流水或等价操作日志，并由确定性规则派生余额。
- BYOK Key 只允许保存在 iOS Keychain；不得进入业务数据库、Supabase、日志、分析、崩溃报告或交接文档。
- Hosted AI 可经过项目 Edge；BYOK 只有在供应商允许安全直连时才承诺不经过项目服务器。
- 本 ADR 不锁定 SwiftData 或 GRDB；正式选型必须经过 LOCAL-SPIKE-001。

## 验证证据

- `docs/spec/模块/iOS本地优先/本地优先数据生命周期规格说明.md`。
- `docs/spec/模块/iOS本地优先/AI供应方与BYOK安全契约.md`。
- 后续 LOCAL-002 垂直切片的离线、重启、导出恢复、同步和网络闸门测试。
