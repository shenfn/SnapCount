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
- SL-A 采用方案 B：Income 独立 `local_incomes`；实现已落地，等待 macOS XCTest/Build 证据后收口。
- Wallet 不在本 Slice 决定，SL-A 完成后新开会话单独 Grooming；不预设 `local_records` 或独立表。

## 已实现

- v8 新增 `local_incomes`，不重建 `local_records`/`local_staging_records`。
- Income CRUD、expectedVersion、tombstone、可选账户入账；编辑涉及账户/金额/日期/时间时作废旧分录并插入新分录。
- `LocalAccountEntryWriter` 统一 Expense/Income 的分录原语，避免重复 account entry SQL；事务边界仍在两个财务 Repository。
- 严格 CNY 金额解析到 `amount_minor`；currency 列保持开放；日期真实合法性不在本 Slice。
- FactReader、详情、Today/Records 聚合、JSON/CSV 事实导出接入 Income；归档 schema v2。
- 路由明确标注为 Transitional：未登录新建 Income 走 Local；登录态新建继续现有 Cloud，已有本地 Income 编辑可走 Local。Sync/AI 新路由后续处理。

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
- Windows 没有 Swift/Xcode，XCTest、iOS 编译、真机验收和 macOS CI 尚未验证；本分支未推送。
- 不执行生产迁移、部署或 TestFlight。
- LF-024 迁移失败回滚、日期公共合法性、Income 导入/Sync/Outbox 仍是后续 Slice；登录态新建 Cloud 是同步冻结期迁移策略，不是最终 Local-First 架构。

## 下一步

1. 在 macOS CI 运行 `LocalIncomeTests` 与完整 iOS Build/XCTest，修复真实编译或测试失败。
2. CI 通过后完成 SL-A 收口提交与用户验收。
3. 新会话单独对 SL-B Wallet 做切片级 Grooming，再决定存储形态。
