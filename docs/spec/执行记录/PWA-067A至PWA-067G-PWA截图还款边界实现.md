# PWA-067A 至 PWA-067G PWA 截图还款边界实现记录

> 日期：2026-08-16
>
> 基线：`5386d6e`（PWA-067 评估 PR #104 合并提交）
>
> 分支：`feature/PWA截图还款边界实现`
>
> 状态：实现与 PostgreSQL 17 远程事务验证通过，待 PR #105 合并

## 当前范围

- PWA-067A：候选纯规则。
- PWA-067B：数据库原子确认、状态推导与 `repayment_cycle` 目标。
- PWA-067C：Account Repository transport。
- PWA-067D：Feature 并发与 stale。
- PWA-067E：accepted 收敛与 refresh 分层。
- PWA-067F：已处理目标出口。
- PWA-067G：PagePending 取消、失败与推进语义。

## 基线

- `test:repayment`：17 项通过。
- `test:staging-read`：10 项通过。
- `check:security-contracts`、Vite build、治理与架构检查通过，仅既有警告。

## 冻结范围

- PWA-068 wallet snapshot 创建/关联/repair、`evidence_record_id` 正式关联。
- iOS、Edge、Planner、流水 helper、生产配置、生产 migration、部署与 TestFlight。

## 有效红灯

- 客户端测试先因候选函数和 Screenshot Repayment Feature 不存在、Account Repository 缺少 `confirmStagingRepayment`、Store 仍直连 RPC、Staging Repository 不认识 `repayment_cycle`、页面无 accepted 推进门禁而失败。
- migration 静态契约先因 `20260816190000_screenshot_repayment_atomic_contract.sql` 不存在而以 `ENOENT` 失败。
- 本机 Docker CLI 可用但 Docker Desktop daemon 未运行；这属于 PostgreSQL 行为测试的环境失败，不冒充业务红灯，也不以静态正则替代事务证据。

## 最小实现

- 新增候选纯函数，排除归档/非负债账户，保留账户、金额和日期评分，并使用 due date、cycle month、cycle id 稳定排序。
- Account Repository 独占 `confirm_staging_repayment` transport，发送 `p_status: null` 并复用 canonical cycle mapper。
- 新增独立 Screenshot Repayment Feature，覆盖 Promise 复用、冲突、generation/user stale、accepted 后本地收敛和独立刷新结果。
- Store 不再直连截图还款 RPC；accepted 后收敛 cycle、开放/已处理中转 DTO，PagePending 只在 accepted 后推进。
- Staging Repository 与页面支持 `repayment_cycle` 目标；目标缺失时返回明确失败出口。
- migration 保留旧七参数签名，服务端推导账期状态，原子写 payment/entry/balance/cycle/staging，并保守回填历史目标类型。
- Release Validation 新增独立 PostgreSQL 17 数据库，连续执行 migration 两次后运行行为断言。

## 本地绿灯

- `npm run test:screenshot-repayment`：30 项通过。
- `npm run test:screenshot-repayment-contract`：静态 migration/workflow 契约通过。
- `npm run test:repayment`：18 项通过。
- `npm run test:staging-read`：11 项通过。
- `npm run test:account-read`：20 项通过。
- `npm run test:account-management`：19 项通过。
- `npm run test:finance-save`：16 项通过。
- `npm run check:security-contracts`、`npm run governance:check`、`npm run governance:arch`、`npm run build` 与 `git diff --check` 均通过；构建只有既有 `vconsole eval` 和 bundle size 警告。

## 未验证与剩余风险

- PR #105 首轮 8 项成功、1 项按路径跳过、0 失败；Release Validation run `31943619573` 对应提交 `7d99247`。
- run 第 68 步 `Execute screenshot repayment transaction contract` 已在 PostgreSQL 17 实际成功，migration 语法、权限、触发器余额、幂等和双次执行均有远程证据。
- 当前补证提交仍需第二轮 PR 门禁；在 PR 合并前不把 PWA-067 标记为已完成。
- 未执行生产 migration、生产查询、部署、真实数据写入或 TestFlight。

## 下一步

1. 推送远程证据提交并等待 PR #105 第二轮全部门禁。
2. PR 合并后建立纯文档收口；在此之前不开始 PWA-068。

## 发布边界

- 尚未执行生产查询、migration、部署、真实数据写入或 TestFlight。
