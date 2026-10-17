# IOS-V2-POLISH 偏差修正与性能排查

日期：2026-10-17。工作区：`D:\Business\count\.worktrees\ios-v2-skeleton`。

## 范围与证据边界

- 起点：`b322642`，分支 `feature/IOS-V2-五域骨架`。
- 用户在分析后授权开始；随后明确授权本轮指定文件提交、推送及 macOS Build/XCTest 红绿验证。没有 TestFlight 或生产操作授权。
- 主原型 SHA256 已重新核实：`5C457E429AB9D524F18D7311C1C6CAAD8461946F7087103B70F1B1B171D4F6A5`。原型及素材未上传。
- 原有规格索引修改及五份未跟踪交接/规格/方案/执行记录不纳入本轮提交；不动根工作区 WIP。
- 沿用 `IOS-V2-POLISH-001～011`、D-01～D-09；不修改数据库、Edge、Planner、PWA 或生产配置。
- Windows 没有 Swift/Xcode。Node 边界检查不是 Swift 编译或 XCTest 通过证据；没有真机采样，不给流畅度结论。

## 已执行基线

- `git status --short --branch`、`git worktree list --porcelain` 已核查。
- iOS Token `--check` 通过。
- 九组现有边界检查 43/43 通过：详情、候选确认、staging 生命周期、详情图片、钱包动作、还款、账户管理、账户读取、补绑。

## 切片与测试层

| 切片 | 场景 | 改动/验收目标 | 测试层与状态 |
|---|---|---|---|
| 壳层和主值 | 001、002、009 | 顶底栏实际高度避让、品牌、日期入口、分页名称、主值与猫分层 | 本地源码修改；待 macOS 和截图/小屏/大字体验收 |
| 重复求值 | 003、004 | 每次页面求值一次创建展示模型，周图最大值一次求值；日历金额快照一次聚合 | 不改变日期/金额口径；待 macOS 回归与真机前后采样 |
| 日历 | 002-B | 滚动内容与固定底部操作，取消/提交门禁保留 | 六行月份、失败重试、大字体待运行 |
| 日期窗口 | 004 | 睡眠近七夜截止所选日，跨月周一不使用未来日期 | XCTest 已新增，红灯 CI 见下 |
| 逐屏引导 | 007、008 | 五屏组织、返回、跳过、模板打开、凭据检查 | 构图修改；真实测试回执仍需接线，身份/迁移回归待 CI |
| 字体与生成链 | 011-B | 系统正文、完整衬线和 Nunito、移除冗余 Sans、iOS/PWA 隔离 | Node 生成检查已有红绿；最终字体覆盖/Archive 待 macOS |
| 共享表单/卡片 | 006、010 | 原型内距、表面和阴影；表单标题不与操作叠放 | 保留提交、取消、busy 与确认门禁；待 CI 和页面对照 |

## 红绿记录

### 日期窗口：004

- 测试：`testIOSV2POLISH004SleepSevenNightsEndOnSelectedMondayAcrossMonth`。
- 输入：2026-10-05（周一）、空正式事实集合。
- 预期窗口：9/29～10/05，共七夜，所有缺失值保持 nil。
- 红灯固定提交：`76ebc14`（仅测试文件）。
- 红灯 CI：https://github.com/shenfn/SnapCount/actions/runs/39017679919 。Build 通过；333 项 XCTest 有 2 项失败。目标测试明确因实际 `10/05～10/11` 不等于预期 `9/29～10/05` 失败，业务红灯成立。
- 另一个失败为既有 `testA4IOS004DReusesSameCommandAndDoesNotDuplicateTransport`（archiveCallCount 实际 2、预期 1）；此提交只增加日期测试，没有账户实现变动。单列为基线问题，不冒充日期修正回归。
- 最小修正：睡眠/饮食按截止所选日近七日；记账/运动/阅读保留自然周。AppState 一次加载两种窗口涉及的月份，避免跨月切域窗口缺读；无全局缓存或持久化变更。
- 绿灯等待本轮固定提交的 macOS CI。

### 生成链：009、010、011-B

- 命令：`node --test scripts/test-ios-prototype-generation.mjs`。
- 系统正文与场景光晕：先失败 2 项，修改后通过。
- 原型 44/40pt 主值与衬线品牌：先失败“主值应为原型 44pt”，修改后通过。
- 共享卡片：先失败“原型卡片内边距为 16pt”，修改后通过。
- 当前 7/7 通过；覆盖重复生成确定性、修改 iOS 专属 Token 后实际 PWA CSS/JS/Tailwind 输出不变、字体注册和资源引用。
- Sans 源文件移除 17,772,300 字节；这不是最终 App Store 下载体积。完整衬线与 Nunito 保留，未对子集字库作假设。

## 页面覆盖清单

以下是入口与状态验收清单，不表示已还原完成。每页仍需正常、空、加载、失败、长文本、大字体和离线适用状态的运行证据。

| 页面/入口 | 文件 | 本轮状态/剩余验收 |
|---|---|---|
| 首页、五域、顶底栏 | Root/MainShellView、NativeDomainPageView | 壳层和主值已改；独立域内容继续实施 |
| 日历 | Root/DomainDatePickerView | 布局与金额快照已改；六行月份/取消/跨月待运行 |
| 单线猫、五域背景 | Root/DomainSceneView | 独立猫层与光晕 Token 已改；快速反向、取消、后台、减少动态效果待运行 |
| 全局新增 | Root/MainShellView → Records/UnifiedManualRecordEntry | 领域上下文待接线；已有四域保存链保留 |
| 本机消费与账户准备 | Records/LocalExpenseEntryView、LocalAccountPreparationView | 使用共享表单；账户门禁和本地保存回归待运行 |
| 通用新增/编辑/图片 | Records/ManualRecordSheet | 使用共享表单；默认今天、编辑保留原日、相册/相机/失败恢复待运行 |
| 候选总览、筛选、分类 | Inbox/InboxView | 导航表面已调整；分类/状态及页面构图继续核查 |
| 候选舞台、补字段、重复、失败、账户未匹配 | Inbox/InboxView 中各 Stage/ResolutionView | 既有动作和门禁保留；逐状态构图与恢复未验收 |
| 记录列表、月份与域筛选 | Records/RecordsView | 导航与共享卡片调整；上下文与筛选待运行 |
| 详情、消费编辑、删除确认 | Records/RecordsView | 使用共享表单/详情卡片；取消和事务回归待运行 |
| 图片预览与错误 | Records/RecordsView、Inbox/InboxView | 保留图片加载/错误恢复及专用深色查看背景；待运行 |
| 观察、月报、联动分析 | Insights/InsightsView、MonthlyReportContent | 导航表面已调整；真实数据范围、加载和错误未验收 |
| 钱包、资产/负债/归档账户 | Accounts/AccountsView | 图标表面调整；列表构图与账户门禁待运行 |
| 账户详情、还款、账户编辑 | Accounts/AccountsView | 共享表单调整；动作边界检查通过，Swift 行为待 CI |
| 未绑定记录、单条/批量补绑 | Accounts/UnboundRecordsView | 图标表面调整；返回上下文与补绑回归待运行 |
| 设置、识别、陪伴、观察、隐私 | Settings/SettingsView | 导航表面调整；不是逐页验收通过 |
| 导出与系统分享 | Settings/SettingsView | 保留真实导出与系统分享；文件生成/失败待运行 |
| 快捷指令帮助与凭据 | Settings/SettingsView | 导航/图标表面调整；模板安装和真实回执待验收 |
| 同步预览、账号绑定 | Settings/LocalBindingPreviewView | 保留授权和取消；构图/身份隔离待验收 |
| 登录、注册、法律文档 | Auth/LoginView、配套法律页面 | 登录品牌调整，校验/同意/敏感数据门禁保留；子页待运行 |
| 五步引导与设置重看 | Onboarding/OnboardingFlowView | 已改逐屏；旧完成迁移、身份隔离、真实识别反馈待验证 |

## 未完成与风险

- 商户排行、时间线选择、前日比较、四域完整独立区块、下钻、全局领域新增和引导真实回执继续实施，不能用当前视觉修改算完成。
- 本地收入读取、睡眠个人基线、阅读总页数/当前页仍受交接中已说明的真实字段能力约束，不编造事实。
- 当前没有新截图对照、手势、VoiceOver 或真机性能采样，不宣称像素还原、无障碍或流畅度通过。
- 最终 Build/XCTest、提交清单和剩余差异在本文件续记。
