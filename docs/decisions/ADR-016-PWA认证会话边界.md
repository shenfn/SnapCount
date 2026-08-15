# ADR-016：PWA 认证会话边界

> 状态：接受
>
> 日期：2026-08-16

## 决策

将 PWA 认证拆为 Auth Repository、Session Feature 和 App 唯一 session 事件入口。`AuthPage` 不再直接写 Store 用户状态或触发全量数据加载；注册同意 metadata 仍随认证请求提交，版本、时间和敏感数据同意由服务端 trigger 判定。

## 原因

- App 和 AuthPage 当前都可能响应登录成功并调用 `loadData`，异步时序会造成重复加载和用户切换竞态。
- `user_configs` 默认行已经由 `auth.users` after-insert trigger 创建，客户端 upsert 不能成为第二个默认事实源。
- 旧用户查询的防写回必须覆盖主查询，而不是只覆盖图片和还款的补充加载。

## 禁止

- 不在组件中直接赋值 `currentUserId`、`currentUserEmail`、`isLoggedIn` 作为认证成功的第二入口。
- 不在 AuthPage、Settings Feature 或客户端代码复制 consent timestamp、terms/privacy 版本校验。
- 不接受组件传入任意 user id 作为登录、退出或 session 切换对象。
- 不以移除 `loadData` 调用为目标而丢失登录成功后的首次数据加载；加载必须由 Session Feature/App 编排一次。

## 后续

先完成 PWA-018 的红灯和最小实现，再分别评估中转生命周期、正式记录和账户还款；不要在认证切片内重写整个 Store。
