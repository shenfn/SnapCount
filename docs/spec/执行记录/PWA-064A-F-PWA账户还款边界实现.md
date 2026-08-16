# PWA-064A 至 PWA-064F PWA 账户还款边界实现记录

> 日期：2026-08-16
>
> 基线：`d47fa5b`
>
> 分支：`feature/PWA账户还款边界实现`

## 目标行为

- 数据库特征测试固定手动确认、重新确认和撤销的事务事实。
- Account Repository 独占两个还款 RPC 的 transport 与 canonical cycle DTO。
- Repayment Feature 独立持有并发、冲突、generation、stale 和刷新结果。
- Store/Page 保留用户预览和兼容 API，不再直接组装还款 RPC。

## 本轮范围

- PWA-064A 至 PWA-064F 的正式 Spec、数据库 fixture、Repository/Feature/Store 测试、最小实现、Release Validation 和文档。

## 非范围

- 生产 migration、账户读写/CRUD、周期生成、截图还款、wallet 快照、流水 helper、iOS、Edge、Planner、生产配置和部署。

## 基线验证

沿用评估 PR #93 的已登记结果。实现后重新执行并通过：

- `npm run test:wallet-snapshot-amount`：通过。
- `npm run test:finance-save`：16 项通过。
- `npm run test:account-binding`：11 项通过。
- `npm run test:record-read`：14 项通过。
- `npm run build`：通过；保留既有 VConsole `eval` 与大 chunk 警告。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过；未新增架构违规，RPC 与重复规则仍沿用人工清单警告。

## 特征测试与红灯证据

- PWA-064A 新增隔离 PostgreSQL fixture 与断言脚本，覆盖部分还款、重新确认、撤销、重复撤销、负债/扣款余额和跨用户拒绝，并接入 Release Validation 的 PostgreSQL 17 service。
- 本机无 `psql`，Docker CLI 存在但 Docker Desktop daemon 未运行，因此数据库契约未在本地执行；PR #94 的 PostgreSQL 17 `Release Validation` 已通过，成为本片数据库事务的最终验证证据。
- `npm run test:repayment` 首次运行失败：`accountRepository.js` 与 `createRepaymentFeature.js` 不存在，Store 边界断言同时证明两个 RPC 仍由 `useStore.js` 直接组装。
- 页面特征项在同次红灯运行中通过，证明金额模式、最低还款、溢缴、扣款账户预览与撤销确认没有被本片误删。

## 最小实现

- 新增 Account Repository，独占确认/撤销 RPC 参数与 canonical cycle DTO mapper，不接收或发送 `user_id`。
- 新增 Repayment Feature，以用户与 cycle 为并发键：相同命令共享 Promise，不同确认或确认/撤销交叉操作返回 `repayment_conflict`。
- Feature 在 reset 或用户切换后返回 `stale`，不执行 canonical 收敛、刷新或旧会话提示。
- Store 保留兼容方法、按钮 pending 状态和撤销确认，只负责提交已确认 command、收敛 canonical cycle、刷新和提示；两个手动还款 RPC 名称与 `p_*` 参数已移出 Store。
- RPC accepted 后先收敛 cycle；刷新失败仍返回成功，并显示“已完成但列表刷新失败”，不诱导重复写入。

## 绿灯与回归

- `npm run test:repayment`：11 项通过。
- Repository/Feature/Store/Page 新增文件均通过 `node --check`，`package.json` 可解析，`git diff --check` 通过。
- 相关 PWA 回归、构建、治理和架构结果见“基线验证”。
- PostgreSQL 事务契约：PR #94 两轮 `Release Validation` 均通过，最终一轮耗时 1 分 14 秒；PR 共 8 项检查成功、1 项按路径跳过、0 失败。

## 未解决风险

- 网络超时后没有 operation ID，不能承诺客户端端到端 exactly-once。
- PWA/iOS 还款预览规则的共享 fixture 留到 A4 对账；本片保持既有页面计算不变。
- 账户详情刷新仍依赖 PWA-065 后续读取边界；本片只要求刷新失败可被 Feature 看见。
- `refreshAccountDetail` 内部的各读取函数仍会自行记录部分读取错误；本片只将账户列表刷新失败提升为 Feature 可见结果，详情读取失败分层留给 PWA-065。

## 发布边界

- 不执行生产查询、迁移、部署、真实数据写入或 TestFlight。
- 对应提交：`d4dcb5b`（规格）、`73a0e3b`（实现、测试、CI 与本地证据）、`64661eb`（远程验证证据）；PR #94 merge commit `09d9ff8`。
- 下一步：PWA-064A 至 PWA-064F 已完成；按 ADR-025 对 PWA-065 账户列表/详情读取边界做只读评估，不直接开始实现。
