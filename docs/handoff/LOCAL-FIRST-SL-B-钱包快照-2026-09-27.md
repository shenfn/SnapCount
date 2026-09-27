# LOCAL-FIRST SL-B Wallet 快照交接

日期：2026-09-27

## 当前分支与基线

- 基线：`7e3933c`（SL-A Income 合并提交）
- 当前分支：`feature/SL-B-钱包快照本地域`
- 本次临时 worktree 初始分支名曾为 `codex/sl-b-wallet-grooming-next`，已重命名。
- 后续分支命名使用 `feature/`、`test/`、`fix/`、`docs/` 等既有前缀，并使用中文任务名；不要使用 `codex/` 前缀。

## TDD seam

已确认并开始覆盖以下公共边界：

1. `LocalWalletSnapshotUseCase`：创建、更新、删除、金额和账户类型校验。
2. `LocalFactReader`：Wallet 事实读取、引用格式和 tombstone 排除。
3. `LocalFactReadModel`：Today/Records 日分组、详情金额和 `wallet/<uuid>` 引用。
4. `LocalFactPortability`：沿用 schema v2 导出 Wallet 事实。

## 已实现的最小垂直切片

- 新增 `local-v9-phase1-wallet-snapshots` migration。
- 新增独立 `LocalWalletSnapshotRepository` 和 `LocalWalletSnapshotUseCase`。
- `amount_minor` 使用整数分；当前只接受 CNY；快照金额允许 0。
- 快照不写 `local_account_entries`，不写 outbox，不修改账户余额。
- `account_id` 可为空；只允许绑定同 profile 且资产/负债类型兼容的既有账户。
- FactReader 使用 `wallet/<uuid>`，domain 为 `wallet`，domain version 为 `wallet-v1`。
- Wallet 不计入收入/支出汇总；domain presentation 使用快照数量、最近账户、最近金额和最近类型，不对快照求和或平均。
- AppState 已接入未登录 Local、新建登录 Cloud、已有本地 Wallet 编辑/删除的路由。

## 明确未实现

- 本地还款周期、还款流水、自动扣款、截图还款、补绑。
- 自动创建账户、账户流水、当前余额和净资产推演。
- 云端 Wallet 历史迁移、Sync/Outbox/Edge/PWA/生产/TestFlight。
- Wallet 通用导入；导入仍留给 `LF-021 / SL-09`。
- 本地负债账户创建、汇率换算、AI staging/candidate 路径。

## 验证状态

- 已完成：红灯测试文件、最小实现、`git diff --check`。
- macOS CI 已通过：workflow `ios-build.yml` run `36303877470`，`Build for simulator` 和 `Run unit tests` 均成功。
- CI 期间修复了静态校验调用和异步断言问题，最终代码提交为 `54065da`。
- Windows 无 Swift/Xcode 工具链；未执行本地 Swift 编译、真机验收、TestFlight 或生产验证。
