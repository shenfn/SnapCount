# LOCAL-FIRST-SL-A Income TDD 执行记录

- Slice：SL-A / LF-032 收入本地域
- 基线：`origin/main@7c64bae`；工作分支：`feature/local-first-sl-a-sl-b-grooming`
- 范围：独立 `local_incomes`、账户分录联动、严格金额解析、FactReader/Today/Records/导出扩展、迁移 v8。
- 已确认决策：方案 B；`amount_minor` 使用货币最小单位；当前输入默认 CNY，表结构不封死未来 currency；日期真实合法性校验单列公共能力 Slice；Wallet 延至 SL-B 新会话 Grooming；登录态新建 Income 保留 Cloud 是同步冻结期 Transitional 行为。

## 红灯

先新增 `ios/SnapCountTests/LocalIncomeTests.swift`，具名覆盖 LF-032 的金额精度、独立迁移表、创建与账户入账、编辑替换、删除作废、FactReader/导出、Today/Records 聚合与 Income 详情路由。由于当前 Windows 没有 Swift/Xcode，红灯未能在本机运行；没有把环境失败伪装成业务失败。

## 最小实现

- `local-v8-phase1-income` 只新增 `local_incomes` 和索引，不重建 `local_records`/`local_staging_records`。
- `LocalIncomeRepository` 持有 Income 行与可选账户分录的事务边界；创建/编辑/删除分别实现入账、作废替换、tombstone。
- `LocalAccountEntryWriter` 只抽取账户归属校验、活跃分录作废、分录插入原语；Expense 和 Income 的事务仍由各自 Repository 管理。
- `LocalIncomeMoney` 严格按当前 CNY 两位小数解析到 `amount_minor`，拒绝超出最小单位的精度。
- `LocalFactReader` 使用 `income/<uuid>`；`LocalFactArchive` schema 升为 2；未登录 Income 写入 Local，登录态新建继续 Cloud。

## 验证

- 已验证：`git diff --check` 无输出；静态检查确认无旧 Expense helper 引用，Income 月份/发生时间插值已修正，Wallet/Sync/AI 新路由未改。
- 未验证：Windows 无 `swift`/`xcodebuild`，未运行 XCTest、iOS 编译、真机或 macOS CI；本分支未推送。
- 风险：日期真实合法性、Income 导入/Sync/Outbox、登录态路由收敛、生产迁移和 Wallet 均未在本 Slice 处理；macOS CI 仍是合入前必要证据。
