# D-REMOTE-007 iOS 同步入口接线

## 范围

- 将已验证的 `LocalSyncCoordinator + SupabaseSyncTransport` 注入 `AppState`。
- 用户确认“合并并开启同步”后执行首次同步；设置页提供同一入口的手动重试。
- 同步成功后刷新本地账户和当前月份消费读模型。
- 不增加后台调度，不接其他数据域，不执行生产迁移、部署或 TestFlight。

## TDD 场景

| 编号 | 行为 | 测试层 |
|---|---|---|
| DREMOTE-010 | 确认绑定后调用 runner，使用预览中的 workspace 与 cloud user | AppState XCTest |
| DREMOTE-011 | 同步成功发布 synced 状态并刷新本地读模型 | AppState XCTest |
| DREMOTE-012 | 同步失败保留本地数据并展示可重试错误，不伪报成功 | AppState XCTest |
| DREMOTE-013 | 设置页 ready/failed 状态提供手动同步入口 | SwiftUI 编译 + AppState XCTest |

## 验证边界

- Windows 运行治理、迁移命名和 diff 检查。
- Swift 编译与 XCTest 以 GitHub macOS iOS Build 为准。

## 当前实现

- `AppState` 注入 `LocalSyncRunner`，默认由本地 GRDB 仓库、`LocalSyncCoordinator` 和 `SupabaseSyncTransport` 组成。
- 绑定确认后自动触发首次同步；设置页在 `ready`、`failed`、`synced` 状态提供立即同步/重试入口，并防止并发重复执行。
- 同步成功后刷新本地账户余额和当前月份消费读模型；失败只更新状态与提示，保留本地事实和 Outbox。
- XCTest 已覆盖 DREMOTE-010 至 DREMOTE-013；Swift 编译、测试和源边界检查待 GitHub macOS 门禁确认。

## 本地验证记录

- `node scripts/check-project-governance.mjs`：通过。
- `node scripts/check-migration-versions.mjs`：通过（当前生产基线 `20260726121000`，本分支迁移未执行）。
- `git diff --check`：通过；换行符提示为 Windows 工作区的既有 Git 属性提示。
