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
- 第一轮实现提交 `fec47ca`：https://github.com/shenfn/SnapCount/actions/runs/39018186972 。Build 通过，近七夜目标测试通过；仅旧重试用例的两个“单月次数”断言失败，后续已改为精确双月断言。
- 原重试场景的 `2000-01-05` 在近七日口径下涉及 `1999-12` 和 `2000-01`，后续加强为断言双月明确顺序、force 后两个月都重读、两个错误均清除；不删除重试断言。
- 既有账户复用测试的时序修正：不再用可能晚于首请求完成才启动的 `async let duplicate`；在当前 MainActor 任务中进入重复调用，释放由另一个 MainActor 任务执行。保留一次 transport 的断言，不修改账户业务实现。

### 生成链：009、010、011-B

- 命令：`node --test scripts/test-ios-prototype-generation.mjs`。
- 系统正文与场景光晕：先失败 2 项，修改后通过。
- 原型 44/40pt 主值与衬线品牌：先失败“主值应为原型 44pt”，修改后通过。
- 共享卡片：先失败“原型卡片内边距为 16pt”，修改后通过。
- 当前 7/7 通过；覆盖重复生成确定性、修改 iOS 专属 Token 后实际 PWA CSS/JS/Tailwind 输出不变、字体注册和资源引用。
- 后续阅读 10pt 色带/暗色覆盖、领域数据色与动作色分离分别经历 Node 红绿；当前 9/9 通过。
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

## 商户切片：003

- 红灯接口与测试提交 `7c3293a`；该次 CI 因截图测试只读环境值注入导致编译失败，不算业务红灯。
- 修正截图测试提交 `8dc48b5`；有效红灯：https://github.com/shenfn/SnapCount/actions/runs/39019327211 。Build 通过，338 项测试中仅新增商户用例失败（空汇总与预期两商户不符，6 个断言/解包失败），其余 337 项通过；包括双月重试、账户时序和 4 项原生渲染测试。
- 最小实现：同日正式支出按真实商户名/消费标题聚合，收入与候选排除；缺金额不当零或部分合计；商户明细保留稳定引用。已补缺金额特征用例，待绿灯 CI。
- UI：商户排名、商户记录下钻、当天全部记录，复用既有详情/编辑/删除链。选中商户只存标识，展示从当前模型查找，删除最后一条后显示空态。
- 全局加号与域内空态统一传领域参数给既有表单；非财务域优先走通用记录表单，不进入财务账户准备。未传浏览日期，默认今天的既有规则保留。
- 待确认总览默认全部范围、单列事实卡；分类、单/双列、原图、状态处理、还款候选和归档门禁保留。大字体强制单列。
- 旧 `test-ios-local-shell-boundary.mjs` 本轮仍 0/4：断言旧双 Tab、LocalSettingsView 和隐藏未登录新增。核实基线 `b322642` 已不存在 LocalSettingsView，RootView 与该脚本本轮未改，RecordsView 仅导航表面变更。未回退产品或删除检查伪造全绿；九组现行业务边界仍 43/43。

## 原生截图与性能采样准备

- `IOSPrototypeRenderingTests` 使用独立临时数据库、虚构事实和固定业务日期。导出五域内容普通/无障碍字号、390×844 空壳、六行月份的 390×422 日历、引导欢迎页；内容截面为 390×720。
- CI 使用 XCTest attachment 和 xcresulttool 导出 PNG；只上传合成图和附件映射，不上传私有原型、原型素材或完整 xcresult/构建日志。
- 截图导出测试不包含像素正确性断言，生成成功不能替代视觉对照。实际图片仍需下载审查。
- 五域内容已按领域分开组织；当前睡眠区间、饮食餐次、运动分布、阅读书目复用现有真实字段。商户排行、前日比较、区间图、平均/累计等剩余区块继续实施。
- Instruments 可采样 `com.jiezi.app` 的 `DomainScene / BuildDomainPresentation` 与 `DomainCalendar / AggregateCalendarExpense`。只记录区间，不记录金额、书名、商户或凭据。没有真机采样前不给帧率/操作延迟结论。
- 首批合成图已下载审查，路径：`C:\Users\yinli\.codex\visualizations\2026\10\17\01a148ef-70cd-7092-bd7f-4da990bb014b\ios-8dc48b5`，对应 `8dc48b5`，不是后续修改的视觉通过证明。
- 首轮发现并合并修正：时长主值将数字与单位分级，实际 ISO 区间格式化为时钟；日历图例移到网格后，底部操作短标签；去掉顶底栏独立渐变色带，场景背景统一绘制；阅读按原型色带加暗色覆盖；猫用前景墨色/纸色。中英文域名按原型 Spending/Exercise 等校正。
- 深色分页采用场景内可读的浅色数据强调色，保留选中形态与朗读状态；不直接套深紫/深蓝造成低对比。最终仍需完整无障碍验收。
- 已从实际 TTF name 表核实 PostScript 名称为 `NotoSerifSC-ExtraLight`、`Nunito-ExtraLight`。另补 UIFont 注册与代表性字形覆盖检查，待 macOS 执行，不宣称所有 Unicode 字形均已验证。

## 003/004 独立数据区块切片

- 上一实现固定提交 `cf07bb6`，绿灯候选 CI：https://github.com/shenfn/SnapCount/actions/runs/39021140342 ，结果待查询。
- 本轮只扩展现有 iOS 展示模型与领域页面，不改持久化、账户金额、同步或 PWA 契约。
- 003：同日真实业务时间线，未知/上传时间不入图但保留全部记录；等时记录保持独立引用；前一天比较跨月且缺金额不作零。
- 004：饮食近七日有效记录日平均（显式零计入，缺指标/无记录不计入分母）、最大已知餐次；运动/阅读自然周正式记录的次数、完整累计和运动类型；睡眠完整 ISO 区间跨午夜、倒置/缺失不倒造。
- 测试层：`IOSDomainBlocksTests` → `NativeDomainScenePresentation.make`；现有正式事实过滤/缺字段测试继续回归。新增接口先为空结果，待 macOS 业务红灯后实施。

## 008 引导真实回执切片

- 输入：已授权的五步引导缺少真实试运行回执；现有 `UploadScreenshotIntent` 已区分本机归档/候选，云端回退只得到上传服务返回。
- 输出：跳转只显示等待；实际 Intent 开始时认领本次试运行，持久化成功后才显示归档/待确认；云端返回单独标记，不推断已正式归档；失败不保存错误原文、图片或凭据。
- 最小回执模型按当前设备/账号、随机请求标识及 30 分钟有效期隔离。二次运行不能覆盖已完成结果，旧请求/过期/取消/账号切换均无效。
- 预计范围：新增 `ShortcutTrialStore` 与 XCTest，连接现有引导、AppState 身份范围和上传 Intent，不改变归档规则、凭据存储、引导完成版本与旧进度迁移。
- 测试层：`ShortcutTrialStoreTests` 验证真实结果前等待、单次认领、旧标识、账号切换、过期与取消；模板安装/系统跳转/真实服务仍需设备验收。接口先为空实现，待 macOS 业务红灯。
