# Local-First Phase 1 RC 收口交接

> 日期：2026-09-27
> 基线：`origin/main@7af5070`（SL-B Wallet 已合入）
> 当前分支：`codex/phase1-closure-sl03`
> 当前提交：`72da3fc fix(local-first): confirm edited local candidates`
> 根工作区：`D:\Business\count` 的 WIP 未触碰

## 1. 本次目标

本交接把“Phase 1 完整 Local-First”收缩为可以上架验收的 **Phase 1 RC**。RC 只承诺用户在本机完成核心记录闭环，并对登录态仍走 Cloud 的过渡路径明确标注；不把旧规划中尚未验证的功能默认为发布阻塞。

## 2. Phase 1 RC Closure Matrix

| 项目 | 当前状态 | 证据/缺口 | 是否阻塞 RC Done |
|---|---|---|---|
| 五域本地 CRUD（food/sleep/sport/reading + expense） | 已实现 | `LocalRecordRepository`、`LocalExpenseRepository`；既有 XCTest 与 macOS CI 证据 | 否，待总回归确认 |
| 本地图片创建、候选引用、确认后移交、删除/失败清理 | 已实现 | `LocalImageStore`、`LocalImageRecognition`；编辑换图不在 RC | 否，待 M1 |
| 候选高/低置信度路由 | 已实现 | 分域阈值与候选状态已有测试 | 否，待 M1 真实流程 |
| SL-03 本地候选编辑确认 | 已实现 | `72da3fc`；确认命令现在写入用户编辑后的 title/summary/payload/date/time/note；重复确认保持同一正式记录 | **是：本分支 macOS CI 未验证** |
| 候选重复丢弃幂等 | 已实现 | `72da3fc`；重复 discard 不改变终态 | **是：本分支 macOS CI 未验证** |
| Income 最小本地事实 | 已实现 | `local_incomes`；macOS CI `36290165757` | 否，待 M1 |
| Wallet 最小本地快照事实 | 已实现 | `local_wallet_snapshots`；macOS CI `36303877470` | 否，待 M1 |
| Income/Wallet 登录态新建 | 迁移期 Cloud | 代码仍走既有 Cloud 写入；本地未登录创建/编辑已支持 | 否，前提是发布说明明确为 Transitional |
| 低存储错误保护 | 已实现但缺测试 | 写入链路抛错/失败清理存在；缺主动低存储注入测试 | **是：稳定版需有 CI 证据或明确风险签字** |
| migration failure 保护 | 已实现但缺测试 | GRDB migration 错误向上传递；缺失败恢复/旧库保留测试 | **是：稳定版需有 CI 证据或明确风险签字** |
| M1 真机验收 | 待验证 | 相机/照片/快捷指令、在线/离线、重启、候选确认/丢弃、图片、Income/Wallet 未形成设备记录 | **是** |
| 全量 macOS CI（Build + XCTest + gate） | 待验证 | 当前提交尚未推送，不能把本地静态检查当 CI | **是** |

## 3. 明确延期到 Phase 1.1

| 项目 | 决定 | 原因 |
|---|---|---|
| AI Popup / Analysis 本地化 | 延期 | 当前仍是云端权威；RC 目标是本地记录事实闭环，表达计划和跨域分析不是上架稳定性前置条件 |
| SL-04 候选重试 / 域重判 | 延期 | 当前本地候选可确认/丢弃；重试需要重新识别与域重判状态机，不能在 RC 中半实现 |
| SL-05 编辑替换图片 | 延期 | 当前编辑已有记录不开放换图入口；不向 RC 用户承诺换图能力 |
| SL-09 四域导入恢复 | 延期 | 当前只有 expense 导入；导出可用，完整恢复包另开切片 |
| 设置 19 项本地镜像 | 延期 | 设置仍为云端权威，不影响本机核心记录生命周期 |

延期项不计入 RC Done；如果产品页面或上架说明声称这些能力“完全离线可用”，则必须重新打开对应阻塞。

## 4. 明确冻结

- Cloud Sync、Outbox 扩展、Cursor、冲突协议、多设备和 L2 老用户迁移。
- 还款、撤销、补绑、截图还款、周期账务推演。
- BYOK、账户轮换归属重构、PWA 结构重构、生产迁移、生产部署和 TestFlight 上传。

这些项目保留历史证据，不作为本 RC 的隐含验收项。

## 5. RC Definition of Done

Phase 1 RC 只有同时满足以下条件才可宣布完成：

1. 基于 `origin/main@7af5070` 的固定提交通过 macOS Build、全量 XCTest 和现有 gate。
2. SL-03 编辑确认和重复丢弃测试在 macOS CI 通过；不存在只在 Windows 静态检查通过的替代说法。
3. 低存储与 migration failure 的失败保护有可运行测试，或由发布负责人明确接受并记录风险；在没有这两者之一前不标记“稳定版”。
4. M1 真机记录通过：首次启动/本地 profile、相机或照片识别、快捷指令、低/高置信度、候选编辑确认、重复丢弃、正式记录编辑/删除、离线、杀进程重启、图片生命周期、Income、Wallet、登录/退出登录。
5. 上架说明明确两个过渡行为：登录态 Income/Wallet 新建仍走 Cloud；AI Popup/Analysis、完整导入和换图不属于本 RC。
6. CI 与 M1 证据回填本交接，才可以进入 TestFlight/上架流程。

## 6. 当前未做的发布动作

本轮没有推送分支、没有触发 CI、没有上传 TestFlight，也没有修改根工作区 WIP。Windows 无 Swift/Xcode，当前仅完成代码静态检查与 Git diff 检查；最终编译、测试和真机结论必须来自 macOS CI 与 M1。
