# ADR-034：iOS 账户补绑独立编排

> 状态：已接受
>
> 关联任务：A4-IOS-007、PWA-063、ADR-024

## 决策

将 iOS 未绑定记录的单笔和批量账户补绑收拢到独立 Use Case。`AppState` 保留公开入口和页面兼容状态；`UnboundRecordRepository` 保留 RPC transport，但返回结构化绑定结果；`NativeAccountRecommendationEngine` 继续作为纯函数，不并入动作编排。

## 原因

当前 `AppState` 同时管理 session、全局 busy、逐项 RPC、数组删除、批量计数和三处刷新。单笔刷新失败仍可能返回成功，批量部分成功被压缩成布尔值，用户切换后也没有统一的 stale/停止剩余项语义。PWA-063 已证明这些边界需要独立 Feature，iOS 应保持相同业务含义。

## 约束

- 批量补绑是多个独立数据库事务，不得声称为原子批处理。
- accepted 与 refresh failure 必须分开表达；不得因刷新失败重发补绑 RPC。
- 服务端数据库 RPC、账户余额和流水规则是唯一权威；iOS 不计算或补写账户影响。
- 不以“清理重复”为由合并补绑、收件箱生命周期、正式记录保存或 AI 洞察。
- 新 Use Case 不依赖 SwiftUI、HTTP 或 Supabase client。

## 验收

实现必须提供 A4-IOS-007A-G 场景测试、Repository 参数/identity 测试、批量部分成功和 stale 测试、macOS XCTest、治理/架构门禁及执行记录更新。
