# PWA-068A 至 PWA-068J PWA 钱包快照原子边界实现记录

> 日期：2026-08-16
>
> 基线：`c082541`
>
> 分支：`feature/PWA钱包快照原子边界`
>
> 状态：本地最小实现与客户端回归已绿，待 PostgreSQL 17 远程验证

## 当前范围

- 按 `钱包快照原子边界规格说明.md` 建立数据库原子命令、Account Repository、Wallet Snapshot Feature 和最小 Store/Page 接线。
- 先写 PostgreSQL/static/Node 红灯，再开始 migration 或业务实现。
- 不修改 iOS、Edge、Planner、生产配置、PWA-069 或其他 worktree WIP。

## 已完成

- PR #107 全门禁通过并合并为 `c082541`。
- 从该 merge commit 建立干净 worktree `D:\Business\count\.worktrees\PWA钱包快照原子边界`。
- 建立 PWA-068A 至 PWA-068J 场景、事实模型、数据库事务、Repository/Feature/Page 契约和完成定义。
- 先建立有效红灯：目标 migration 缺失；客户端 7 项中 6 项因 Repository、Feature 和 Store/Page 边界缺失而失败，历史 repair 未接线特征测试保持通过。
- 新增 `apply_wallet_snapshot` 原子命令、脱敏 PostgreSQL fixture/assertions 和 migration 双次执行 job。
- Account Repository 只发送 record/account ID；Wallet Snapshot Feature 负责同命令复用、异目标冲突、会话 stale、accepted 收敛和刷新分层。
- Store 已删除 wallet 快照账户、账期、流水和余额的客户端多步写入；页面只在 accepted 后关闭选择器，并过滤归档或账户家族不兼容的目标。

## 本地验证

- `npm run test:wallet-snapshot-contract`：通过。
- `npm run test:wallet-snapshot`：10/10 通过。
- `npm run test:repayment`：18/18 通过。
- `npm run test:screenshot-repayment`：30/30 通过。
- `npm run test:account-read`：20/20 通过。
- `npm run test:account-management`：19/19 通过。
- `npm run build`：通过；仅保留既有 `vconsole eval` 与 chunk size 警告。
- `npm run governance:check`、`npm run governance:arch`：通过。
- `git diff --check`：通过；工作区换行符提示不属于业务失败。

## 未验证

- 本机没有 `psql`，Docker Desktop daemon 不可用；PostgreSQL fixture、真实函数编译、事务回滚和 migration 双次执行尚待 GitHub PostgreSQL 17 job。
- 尚未运行远程 Release Validation，不能把 SQL 行为写成已验证。
- 未执行任何生产或发布操作。

## 下一步

1. 逐文件暂存并提交本地实现与证据。
2. 推送 PR，运行 Release Validation 的 PostgreSQL 17 wallet snapshot job。
3. 根据真实 SQL 日志修复后更新最终 CI 证据；全绿前不合并。
