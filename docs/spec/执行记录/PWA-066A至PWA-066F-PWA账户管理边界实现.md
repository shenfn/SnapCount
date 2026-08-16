# PWA-066A 至 PWA-066F PWA 账户管理边界实现记录

> 日期：2026-08-16
>
> 基线：`d42fcba`（PWA-066 收口 PR #101 合并提交）
>
> 分支：`feature/PWA账户管理边界实现`
>
> 状态：实现完成，PostgreSQL 17 行为验证通过，PR #102 待合并

## 当前范围

- PWA-066A：存量规范化、旧客户端兼容 trigger、默认约束和迁移幂等。
- PWA-066B：canonical save/archive RPC 与数据库业务不变量。
- PWA-066C：Account Repository 写 transport 与 DTO。
- PWA-066D：Account Management Feature 并发与 stale。
- PWA-066E：canonical 收敛与 accepted/refresh 分层。
- PWA-066F：Store/Page 兼容、归档列表和恢复出口。

## 已完成

- 已读取 TDD 规范、账户管理边界评估、ADR-027 和收口交接。
- 已建立正式 Spec、文件范围、非目标、数据库契约、测试层与完成定义。
- 已新增 PostgreSQL fixture/assertion、静态 migration 契约和 Release Validation PostgreSQL 17 job 接线。
- `npm run test:account-management-contract` 已确认有效红灯：仅因目标文件 `supabase/migrations/20260816160000_account_management_atomic_contract.sql` 不存在而以 `ENOENT` 失败。
- 已实现存量默认规范化、旧客户端兼容 trigger、partial unique/check、`save_account`、`set_account_archived`、权限和迁移幂等脚本。
- Account Repository 已独占两个 RPC transport；Account Management Feature 已实现同命令 Promise 复用、冲突、reset/用户切换 stale 和 accepted/refresh 分层。
- Store 已移除账户管理直写与 `unsetOtherDefaults`，canonical account 同步列表和当前详情；modal 不再混合归档，wallet/详情新增已归档列表和恢复出口。
- PWA-066F 源边界测试曾因 modal 仍含归档复选框而有效红灯，最小页面接线后转绿。

## 基线

- `test:account-read`：17 项通过。
- `test:repayment`：15 项通过。
- `test:account-binding`：11 项通过。
- Vite build 和架构检查通过，仅既有警告。

## 下一步

1. 推送远程验证证据并等待 PR #102 第二轮门禁。
2. 全部门禁通过后合并，再建立独立收口任务；不在本分支进入 iOS A4。

## 未验证与风险

- 本机没有可用 PostgreSQL/Docker 行为环境；SQL 真实执行已由 PR #102 的 GitHub PostgreSQL 17 job 验证通过。
- 生产数据现状未知，未执行生产查询或写入。

## 本地验证

- `npm run test:account-management-contract`：通过。
- `npm run test:account-management`：18 项通过。
- `npm run test:account-read`：19 项通过。
- `npm run test:repayment`：17 项通过。
- `npm run test:account-binding`：11 项通过。
- `npm run test:finance-save`：16 项通过。
- `npm run build`：通过；仅既有 `vconsole eval` 与 bundle size 警告。
- `npm run governance:check`、`npm run governance:arch`：通过；架构检查仅既有人工清单警告。
- `git diff --check`：通过；仅工作区行尾转换提示。
- PR #102 首轮全部适用门禁通过；综合 job 在 PostgreSQL 17 中连续执行 migration 两次并通过完整行为 assertions（GitHub Actions run `31941675852`）。
