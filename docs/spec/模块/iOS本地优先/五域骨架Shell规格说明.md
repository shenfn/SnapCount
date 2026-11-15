# 五域骨架 Shell 规格说明

> 状态：骨架期执行中（2026-10-17 拍板确认单驱动）
> 来源：`docs/前端设计理念/iOS与新原型能力对照及取舍分析-2026-10-16.md` 第十节拍板确认单 + 新原型（Mobile app design request (1)）
> 关系：局部替代 `LOCAL-003A 统一 App Shell` 的导航拓扑（单树、本地权威、Repository 边界全部继承不变）；旧 5 Tab 结构在骨架验收后移除。

## 1. 范围

骨架期只做导航壳与域页占位：五域横滑、顶部栏、底部栏、「…」菜单覆盖层、真·空态。观察行、时间线、日历热度、猫/场景背景/转场、引导改版、截图暂存接线不在本期（后续阶段）。

## 2. 场景编号

| 场景 | 名称 | 内容 | 测试层 |
|---|---|---|---|
| IOS-V2-SHELL-001 | 五域主场景 | 主场景为五域横滑：记账（收+支）、睡眠、饮食、运动、阅读；无底部 Tab 栏；横滑切换域，分页圆点指示 | iOS XCTest（域枚举特征）+ macOS Build + 用户验收 |
| IOS-V2-SHELL-002 | 顶部栏 | logo + 同步状态 + 日历入口（占位）+「…」菜单；菜单四项：观察、记录、钱包、设置 | 用户验收（占位）+ XCTest（菜单路由映射） |
| IOS-V2-SHELL-003 | 底部栏 | 待确认入口（徽章数 = dashboard.pendingCount，0 时仅隐藏数字，入口始终可用）+ 分页圆点 + 右下「＋」按钮（弹 UnifiedManualRecordEntry） | 源边界检查（入口恢复）+ XCTest（路由）+ 用户验收 |
| IOS-V2-SHELL-004 | 覆盖层路由 | 菜单四项与待确认以全屏覆盖层呈现，关闭后回到原域页；内含 NavigationStack，recordsPath/inboxPath 继续生效 | XCTest（openInbox 等路由函数特征） |
| IOS-V2-SHELL-005 | 域页空态 | 每个域页在无数据时显示 JieziEmptyState 空态 +「＋记一笔」入口；记账域 hero 显示本月收支两行（支出主值 + 收入次值），月度为零时整体空态 | XCTest（空态判定纯函数 + hero 口径）+ 用户验收（真空态） |
| IOS-V2-SHELL-006 | 外部路由兼容 | deep link `jiezi://inbox|records|record|settings`、快捷指令通知路由、免登录 bootstrap 落点（记录）、引导完成跳转（主场景）映射到新壳，路由字符串契约不变 | XCTest（deep link 与快捷指令路由映射） |
| IOS-V2-SHELL-003A | 收件箱恢复入口 | 候选为零或读取失败使计数归零时，仍可打开收件箱查看空态/错误并重试；不能用候选计数控制入口可用性 | Node 源边界检查 + 模拟器验收 |
| IOS-V2-SHELL-005A | 本地事实驱动四域空态 | 四域计数取当月正式记录，不依赖可能缺失或陈旧的领域定义计数；新增后非空、重开数据库后不丢失、删除最后一条后为空；其他月份和候选不计入。未登录且本地月份已成功读取时，以本地结果为准，包括空月；禁止将已删除的旧 Dashboard 投影重新合入列表。登录态既有合并规则保持 | 真实 SQLite → AppState → 域页模型 XCTest + 查询口径/登录态合并 XCTest |

## 3. 路由映射表（旧 → 新）

| 旧（AppTab.selectedTab） | 新（AppState.presentedOverlay / selectedDomain） |
|---|---|
| `.today`（主场景） | `presentedOverlay = .none`（五域横滑） |
| `.inbox` | `presentedOverlay = .inbox` |
| `.records` | `presentedOverlay = .records` |
| `.insights` | `presentedOverlay = .insights` |
| `.settings` | `presentedOverlay = .settings` |

`AppTab` 枚举与 `selectedTab` 属性随骨架移除；`AppDomain`（expense/sleep/food/sport/reading）与 `AppOverlay`（none/inbox/records/insights/wallet/settings）新增。

## 4. 已知边界（ponytail: 上限与升级路径）

- 非记账域页骨架期只有域头 + 记录数概要/空态，不展示记录列表（列表 = 下一阶段域页内容工程；复用现有正式记录月查询口径判空，不引入远端查询或持久化计数）。
- 「＋」按钮骨架期不接本地截图暂存（pendingLocalImageData 属于识别链路接线阶段）。
- 日历入口、同步状态为占位/沿用现有组件最小接线，热力图与日历弹层为后续阶段。
- 旧今日页（TodayView）骨架期脱离导航但保留编译；物理删除在骨架验收后独立提交。

## 5. 验收标准

即拍板确认单 C 节：结构一致、覆盖层进出正确、每域真·空态过验、视觉（猫/背景/转场）不算骨架期验收项。编译门禁 = GitHub Actions macOS iOS Build。

## 6. 2026-10-17 接续确认

- 钱包沿用 10 月 17 日确认单：首版保留钱包入口及现有账户、还款、补绑能力；本轮不做消费账户解耦。
- 本轮仅修复 SHELL-003A、SHELL-005A；日期、领域内容、识别入口、引导与视觉集成继续按后续阶段处理。
