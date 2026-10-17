# 五域 Shell 空态与收件箱恢复回归记录

日期：2026-10-17（Asia/Shanghai）。

## 范围与确认

- Worktree：`D:\Business\count\.worktrees\ios-v2-skeleton`。
- 分支：`feature/IOS-V2-五域骨架`；基点：`5a844cb`。
- 用户确认：修复真实四域空态及收件箱恢复入口；钱包沿用 10 月 17 日拍板，保留入口与现有能力。
- 不包含：消费账户解耦、日期、领域内容、识别入口、引导改版、场景视觉、数据库迁移和生产发布。
- 本轮新增/修改范围：Shell View、域页展示模型、真实本地链路 XCTest、源边界检查与本规格/执行记录。

## IOS-V2-SHELL-003A

- 问题：候选读取失败时现有投影会归零，新 Shell 据此禁用收件箱，阻断进入页面查看错误和重试。
- 测试边界：Shell 收件箱入口始终可用，仅在候选数大于零时显示徽章。该检查是源码门禁，不代替 SwiftUI 交互验收。
- 红灯：`node --test scripts/test-ios-v2-shell-recovery-boundary.mjs`，1 项按预期失败，原因是入口存在 `.disabled(appState.dashboard.pendingCount == 0)`。
- 最小修改：删除计数禁用条件，补充入口无障碍名称“收件箱”；零条时继续隐藏徽章。
- 绿灯与回归：该检查及 `test-ios-local-record-detail-boundary.mjs`、`test-ios-record-detail-image-boundary.mjs` 共 9 项通过。
- 未验证：候选读取失败注入下的真实点击、错误显示、下拉重试及覆盖层关闭。

## IOS-V2-SHELL-005A

- 问题：域页依赖 `dashboard.domains[].recordCount`，但当前本地事实刷新不更新该元数据，造成真实记录已存在时仍显示空态。
- 测试边界：真实 SQLite → `AppState.createManualRecord`/`loadRecordMonth`/`deleteRecord` → `NativeDomainPageModel.make`。
- 已编写：`LocalFirstSL02ProjectionTests.testIOSV2SHELL005ALocalDomainPagesFollowCreateReopenAndDelete`，覆盖睡眠、饮食、运动、阅读的新增、数据库重开与删除最后一条。
- 当前状态：Windows 未安装 Swift/Xcode；Swift 测试尚未执行，不将环境不可用当作业务红灯。产品实现等待 macOS 红灯确认。
- 计划：复用当月正式记录的现有查询口径，排除其他月份和候选，不增加持久化计数或远端请求。

## 验证与发布边界

- `node scripts/check-project-governance.mjs`、`node scripts/check-architecture-boundaries.mjs` 和 `git diff --check` 通过；架构检查保留既有人工清单警告。
- 本轮尚未确认 macOS Build/XCTest 结果，不能宣布 iOS 骨架验收完成。
- 用户已授权本轮逐文件提交、推送独立分支及后续修复推送，运行 GitHub macOS CI；未授权合并主线、生产部署或 TestFlight。
