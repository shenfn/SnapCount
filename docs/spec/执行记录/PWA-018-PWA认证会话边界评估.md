# PWA-018 认证会话边界评估执行记录

> 日期：2026-08-16
>
> 基线：`21e011b`（PR #68 合并提交）
>
> 分支：`docs/PWA认证会话边界评估`

## 目标与范围

- 只读评估 App、AuthPage、useStore、注册同意 trigger 和 RLS 的职责边界。
- 为下一轮认证会话实现建立范围、非目标、风险和红灯门禁。
- 不修改认证业务代码、数据库迁移、Edge、iOS 或部署。

## 已核对证据

- App 同步 `getSession` 并订阅 `onAuthStateChange`；AuthPage 登录/注册成功后仍手动写 Store 并调用 `loadData`。
- 注册同意由 AuthPage 提交 metadata，服务端迁移校验版本并写服务端时间；`user_configs` 由 auth user trigger 创建默认行。
- Store 的 `loadDataRunId` 只在补充加载阶段检查当前 run，主查询结果在用户切换后缺少统一 guard。
- 页面直连基线在 PR #68 后为 AuthPage、PageSettings Supabase/fetch 三项；本评估不扩大架构 ratchet。

## 结论

- 下一片编号为 PWA-018，先收拢认证会话生命周期，不迁移正式记录和中转查询。
- App 是唯一 session event 入口；AuthPage 只负责认证动作和 UI 状态。
- 注册同意和数据库默认配置行不在客户端重新实现。

## 验证分类

| 类型 | 结果 |
|---|---|
| 只读源码/迁移核对 | 完成 |
| 业务测试/实现 | 未开始，按本评估范围不执行 |
| 生产迁移/部署 | 未执行 |
| 下一片门禁 | 需先写 PWA-018 红灯测试 |

## 下一步

1. 合并本评估文档，更新当前索引入口。
2. 从最新 main 建 `feature/PWA认证会话边界`，先写 session 竞态和 consent 透传红灯。
3. 通过红绿与回归后再评估 PWA 中转生命周期。
