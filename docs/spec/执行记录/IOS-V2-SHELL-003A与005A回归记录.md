# 五域 Shell 空态与收件箱恢复回归记录

日期：2026-10-17（Asia/Shanghai）。

## 范围与确认

- Worktree：`D:\Business\count\.worktrees\ios-v2-skeleton`。
- 分支：`feature/IOS-V2-五域骨架`；基点：`5a844cb`。
- 用户确认：修复真实四域空态及收件箱恢复入口；钱包沿用 10 月 17 日拍板，保留入口与现有能力。
- 不包含：消费账户解耦、日期、领域内容、识别入口、引导改版、场景视觉、数据库迁移和生产发布。
- 本轮新增/修改范围：Shell View、域页展示模型、AppState 共享月份读取投影、真实本地链路 XCTest、源边界检查与本规格/执行记录。

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
- 红灯提交：`bb95b5b7f2b60b4c0fcc9b8eb306a45bac0cf36a`；[macOS CI 39000867759](https://github.com/shenfn/SnapCount/actions/runs/39000867759)。模拟器 Build 通过，320 个 XCTest 中，新增生命周期测试在四域新增后、重开数据库后的空态/计数断言共出现预期的 16 条失败（期望 1，实际 0），其他测试无失败。
- 最小实现：`NativeDomainPageModel.make` 复用 `NativeRecordQuery` 按当月筛选正式记录，再按域统计；不增加持久化计数、AppState 计数维护或远端请求。
- 原模型测试补充实际记录分组；既有查询测试继续保护跨月过滤与候选排除。
- 第二轮提交：`1058e0486ae9e9ddbf7e9c3bf1f79e63bdcde10d`；[macOS CI 39001385651](https://github.com/shenfn/SnapCount/actions/runs/39001385651)。Build 通过，新增与重开断言已通过；仍有 8 条删除后空态/计数断言失败，其余测试无失败。
- 继续定位：数据库删除成功，但 `recordGroups` 将旧的本地 Dashboard 投影作为远端数据合入，重新带回已删除记录。修复共享读取函数：未登录且月份成功加载后，使用本地结果（含空月）；登录态合并规则保持。
- 回归增加公共 `recordGroups` 的删除后断言，保证列表与域页同时移除记录；不是只隐藏域页数字。
- 绿灯提交：`b3bce8f3ba4ff7d5348ae3109becd3bcc888169b`；[macOS CI 39001958079](https://github.com/shenfn/SnapCount/actions/runs/39001958079) 已完成且结论为 `success`，模拟器 Build 和完整 320 个 XCTest 全部通过（0 failures），新增生命周期测试通过。
- 此后仅回填验证文档，代码验证基线固定为上述提交。

## 验证与发布边界

- `node scripts/check-project-governance.mjs`、`node scripts/check-architecture-boundaries.mjs` 和 `git diff --check` 通过；架构检查保留既有人工清单警告。
- 已验证：上述固定提交的 macOS 模拟器 Build、320 个 XCTest，以及本地 9 项源码门禁/回归、治理和架构检查。
- 未验证：下列模拟器/真机交互与视觉；CI 通过不等于骨架全部验收完成。
- 用户已授权本轮逐文件提交、推送独立分支及后续修复推送，运行 GitHub macOS CI；未授权合并主线、生产部署或 TestFlight。

## 尚待模拟器/真机的骨架交互验收

- 未登录下四域分别无记录时显示空态；通过域页入口新增后退出表单，概要变为 1 条。
- 杀进程重启后仍显示已有记录；删除最后一条后回到空态。
- 零候选时收件箱仍可打开；模拟候选读取失败后可进入查看错误并重试，零条不显示徽章数字。
- 记录、收件箱、观察、钱包、设置覆盖层可关闭；关闭后返回原领域，详情导航仍正常。
- 首次启动时记录覆盖层与引导的呈现顺序，以及动态字体下顶底栏避让，尚未实测。
- 猫、背景、转场、领域明细和日历不在本轮验收结论内。

## 骨架 TestFlight 预览（后续单独授权）

- 用户在两项修复验证完成后明确要求上传，授权仅用于本版效果预览。
- 固定代码提交：`b3bce8f3ba4ff7d5348ae3109becd3bcc888169b`，对应上方已通过的 macOS Build/320 个 XCTest。
- 固定标签：`codex/ios-v2-shell-preview-20261017`；未使用根工作区 WIP 或未验证的新代码。
- 手动触发：[TestFlight workflow 39003054063](https://github.com/shenfn/SnapCount/actions/runs/39003054063)，已核对 `head_sha`；工作流 `run_number = 121`。
- 最终状态：工作流 `completed / success`，真机 Release 归档、IPA 导出、TestFlight 上传和 IPA artifact 步骤全部通过；上传日志明确返回 `UPLOAD SUCCEEDED with no errors`。
- 实际 IPA `CFBundleVersion = 39003054063`，已从 Upload 步骤解包读取的 Info.plist 日志核对；`121` 仅为 GitHub 工作流序号，不是实际安装包构建号。
- 上传完成时间：2026-10-17 12:40:18（Asia/Shanghai）；来源提交与固定标签再次核对一致。
- Apple 处理完成及 iPhone 安装、视觉/交互体验仍需独立确认；未执行主线合并或后端生产部署。
