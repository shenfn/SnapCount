---
tags:
  - handoff
  - local-first
  - tdd
scope: SL-A Income 独立本地域实施与后续 SL-B 交接
---

# Local-First SL-A Income 交接

## 当前状态

- 基线：`origin/main@7c64bae`；本分支：`feature/local-first-sl-a-sl-b-grooming`。
- SL-02 交接回填已 cherry-pick，03-索引/BDD 已更新。
- SL-A 采用方案 B：Income 独立 `local_incomes`；实现已落地并通过 macOS CI。
- 本 Slice 对应 PR #201，最终实现提交为 `cf138d9`；CI 运行记录：[36290165757](https://github.com/shenfn/SnapCount/actions/runs/36290165757)。
- Wallet 不在本 Slice 决定，SL-A 完成后新开会话单独 Grooming；不预设 `local_records` 或独立表。

## 已实现

- v8 新增 `local_incomes`，不重建 `local_records`/`local_staging_records`。
- Income CRUD、expectedVersion、tombstone、可选账户入账；编辑涉及账户/金额/日期/时间时作废旧分录并插入新分录。
- `LocalAccountEntryWriter` 统一 Expense/Income 的分录原语，避免重复 account entry SQL；事务边界仍在两个财务 Repository。
- 严格 CNY 金额解析到 `amount_minor`；currency 列保持开放；日期真实合法性不在本 Slice。
- FactReader、详情、Today/Records 聚合、JSON/CSV 事实导出接入 Income；归档 schema v2。
- 路由明确标注为 Transitional：未登录新建 Income 走 Local；登录态新建继续现有 Cloud，已有本地 Income 编辑可走 Local。Sync/AI 新路由后续处理。

## CI 验证记录

- 首轮 CI：[36289758483](https://github.com/shenfn/SnapCount/actions/runs/36289758483) 在 `Run unit tests` 编译阶段失败；问题只出在新增 `LocalIncomeTests.swift`：测试引用了 fileprivate 的 `JSONDecoder.iso8601`，并在非 MainActor 上创建/访问 `AppState`。
- 修复提交：`cf138d9 test(local-first): fix income test actor isolation`。测试类改为 `@MainActor`，导出归档测试改用测试内配置的 ISO-8601 decoder；未改变生产代码和业务边界。
- 第二轮 CI：[36290165757](https://github.com/shenfn/SnapCount/actions/runs/36290165757) 全绿：XcodeGen、模拟器 Build、完整 `SnapCountTests`、iOS Build Gate、Governance Validation、Release Validation 均通过。

## 明确未实现项

- Wallet（SL-B）：本轮不决定复用 `local_records` 还是独立表；下一个会话单独 Grooming。
- 日期真实合法性公共校验：当前只要求日期非空，另列共享能力 Slice。
- Income 导入、Sync/Outbox 新路由、登录态新建 Cloud 路由收敛、AI 新路由。
- Expense 全量重构；仅抽取 `LocalAccountEntryWriter` 复用账户分录原语，事务边界仍由各财务 Repository 持有。
- 迁移失败回滚、低存储恢复、真机验收、生产迁移、部署和 TestFlight。

## 主要文件

- `ios/SnapCount/LocalData/LocalDatabase.swift`
- `ios/SnapCount/LocalData/LocalModels.swift`
- `ios/SnapCount/LocalData/LocalIncomeRepository.swift`
- `ios/SnapCount/Features/Records/LocalIncomeUseCase.swift`
- `ios/SnapCount/LocalData/LocalAccountEntryWriter.swift`
- `ios/SnapCount/LocalData/LocalFactReader.swift`
- `ios/SnapCount/LocalData/LocalFactPortability.swift`
- `ios/SnapCount/Features/Records/LocalFactReadModel.swift`
- `ios/SnapCount/App/AppState.swift`
- `ios/SnapCountTests/LocalIncomeTests.swift`

## 验证与限制

- `git diff --check` 已通过。
- Windows 没有 Swift/Xcode；本地无法运行 Swift/XCTest，编译与测试证据以 macOS CI 为准。真机验收仍未执行。
- 不执行生产迁移、部署或 TestFlight。
- LF-024 迁移失败回滚、日期公共合法性、Income 导入/Sync/Outbox 仍是后续 Slice；登录态新建 Cloud 是同步冻结期迁移策略，不是最终 Local-First 架构。

## 下一步

1. 合并 PR #201，使 `cf138d9` 的实现和本交接进入 `main`。
2. 新会话单独对 SL-B Wallet 做切片级 Grooming，再决定存储形态。
3. SL-B Grooming 确认后再按 TDD 开工；继续保持 Sync/AI/生产发布边界冻结。
