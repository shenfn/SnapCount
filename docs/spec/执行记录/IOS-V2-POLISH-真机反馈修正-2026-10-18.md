# IOS-V2-POLISH 真机反馈修正执行记录

日期：2026-10-18（Asia/Shanghai）。基线：`ddf30a281cb47ffbea6634dabe7dcc53de6785b3`。

## 范围与事实

- 唯一工作区：`D:\Business\count\.worktrees\ios-v2-skeleton`；保护根工作区及现有文档 WIP。
- 用户已授权分析交接并开始开发；随后明确授权白名单提交、推送及 GitHub iOS Build。没有发布授权。
- 最新产品决定以 [真机反馈交接](../../handoff/iOS原型真机反馈与下一轮交互修正交接-2026-10-17.md) Q1～Q11 为准；原 Spec 中不补猫眼睛、没有个人基准等旧口径不能覆盖新决定。
- 不改 Edge、迁移、Planner、生产配置或历史事实。识别阶段睡眠归日涉及 Edge 的静态分支单列待扩展范围，不能仅在页面改标签后宣称已修复。
- 当前设备构建和真实三笔支出的时间字段仍未取得；不把静态发现写成设备复现。

## 首个切片：F03 / IOS-V2-POLISH-002-A、004

目标：可读正式事实不被云端刷新遮挡；无可展示事实时仍明确加载或失败；后续同月切日取消不丢失请求或留下普通取消报错。

权威来源：AppState 月读取与合并接口、NativeDomainScenePresentation 展示接口；正式/候选边界沿用 NativeRecordQuery.isFormal。服务端不参与本切片变更。

预计文件：`ios/SnapCountTests/IOSDomainBlocksTests.swift`、`ios/SnapCountTests/SnapCountTests.swift`、`ios/SnapCount/Models/NativeDomainScenePresentation.swift`、`ios/SnapCount/App/AppState.swift`、`ios/SnapCount/Features/Root/NativeDomainPageView.swift`；本记录。按逐片红绿顺序进入，未到对应测试前不先改业务代码。

测试层映射：

| 子场景 | 输入、动作与预期 | 层与入口 |
|---|---|---|
| 004-F03-本地可读 | 正式饮食 450 kcal，远端加载或失败；页面不进入整页遮挡态，记录及已知数值保留；刷新提示另行展示，不声称数据完整 | XCTest / NativeDomainScenePresentation.make |
| 004-F03-无事实（特征） | 无正式记录，加载或失败；保留明确加载/错误，不能伪装空记录或零 | XCTest / 同上 |
| 002-A-F03-取消重入（后续） | 可控慢远端、同月取消重入/跨月；活跃调用得到终态，旧身份不污染当前状态 | XCTest / AppState.loadRecordMonth、loadRecordDateWindow |

已静态确认：展示模型无条件将 isLoading/errorMessage 赋给 stateMessage，页面据此隐藏全部内容；loadRemoteRecordMonth 同月正在加载直接返回，捕获取消后写普通错误。前者为明确代码路径，后者的竞态仍需可控测试执行证明。

## 基线与本轮证据

- `git status --short --branch`、`git worktree list --porcelain`：已核实；产品代码起点无 WIP。
- `node trae-design-system/scripts/generate-ios.mjs --check`：通过。
- `node --test scripts/test-ios-prototype-generation.mjs`：9/9 通过。仅代表生成链，不代表 Swift 或设备验收。
- 新增 `testIOSV2POLISH004F03RemoteRefreshDoesNotHideReadableFormalRecords`：待 macOS 执行，不冒充已获得红灯。
- 新增 `testIOSV2POLISH004F03WithoutReadableRecordsLoadingAndFailureRemainExplicit`：特征测试，待 macOS 执行。
- Windows 未执行 Swift 编译或 XCTest；设备交互与发布未执行。

测试提交：`2125fa81fba8e0ba9b0a6f8fb2108cdcac498168`。[macOS 红灯 CI 39052519085](https://github.com/shenfn/SnapCount/actions/runs/39052519085)：Build 通过，355 项 XCTest 中目标场景两条 XCTAssertNil 失败，实际分别为“正在读取本机与云端记录…”和“记录读取失败：网络不可用”；无事实的特征测试通过，其余测试通过。业务红灯成立。

最小实现：展示模型拆分整页 stateMessage 与非阻断 refreshMessage。窗口内本域存在正式事实时继续展示，明确提示“以下为已读取记录，统计可能尚不完整”，保留失败重试；无本域事实时沿用整页加载/错误。周内其他日期的事实同样不被遮挡。前日比较在读取不完整时仍不计算。没有修改数据或吞掉真实错误。

新增普通/辅助字号合成截图入口 `testIOSV2POLISH004F03ExportReadableFoodDuringRemoteFailure`，仅使用虚构记录。绿灯、截图及真机结果待后续填入。

展示绿灯固定提交 `6fe6aac8f62b0d31bbc9a8c79222c6545f261926`：[CI 39053517966](https://github.com/shenfn/SnapCount/actions/runs/39053517966)。macOS Build 通过，356 项 XCTest 全通过，包括展示红灯回归、无事实特征场景及新增截图入口。随后把刷新提示移至主指标下方，保留指标/猫原位置，并将截图 fixture 补入猫层，等待下一固定提交复核。

第二片测试：`testIOSV2POLISH002AF03CancelledPageAndSameMonthReentryAwaitReadableRecords`。通过网络边界 stub 挂起月请求，取消第一个页面 Task 后直接进入同月新调用；释放 transport 后，新调用须拿到正式记录、无普通取消错误、无残留 loading，并复用一次网络读取。采用 continuation 控制顺序，避免真实网络和固定延时；失败原因及运行证据待 macOS 执行后填写。业务实现尚未修改。

第二片固定提交 `6170e18`：[CI 39054204953](https://github.com/shenfn/SnapCount/actions/runs/39054204953)。attempt 1 的 App Build 成功，XCTest 步骤长等待后取消；普通取消后状态仍在运行，随后 force-cancel 完成。取消后的日志未包含 XCTest 阶段结果，不能判定为业务红灯或证明测试编排错误。相同提交已启动 attempt 2，等待结果；不据长等待修改业务实现。

本地已查看 `6fe6aac` 的普通/辅助字号刷新失败截图：提示、重试、450 kcal 虚构事实及餐次可同时展示。主指标位置和猫层补充仍待 `6170e18` 的新截图复核；图片来自 iPhone 17 Pro Simulator 合成渲染，不是用户真机、真实餐食或手势证据。

测试编排纠正：静态复查发现 `Task.yield()` 释放任务可能早于新调用到达远端门禁，使新请求另起一次挂起且无人释放；这是测试可能悬挂的路径，不能冒充运行日志已证实的根因。attempt 2 已请求取消。`58e969c` 改为仅首个 transport 挂起，显式等待第二调用进入，通过 0.1 秒有界反向 expectation 检查不得过早返回，随后手动统一释放并等待两调用结束。时间窗只验证“仍应等待”的测试状态，不模拟业务成功。[新红灯 CI 39056080492](https://github.com/shenfn/SnapCount/actions/runs/39056080492) 待结果；产品请求实现依旧未改。

第二片有效红灯：`58e969c` 的 CI 39056080492 App Build 通过，357 项 XCTest 中仅目标测试有三条断言失败：提前返回（fulfilled inverted expectation）、缺目标记录（XCTAssertTrue）、普通 CancellationError 留在 recordMonthMessages（XCTAssertNil）。其余测试通过。两次长等待不计入此证据。

最小实现：历史月在 AppState 内按月份共享在途 Task，重入等待同一结果，页面取消不取消会话所属读取；账户重置统一取消并清空任务。保留用户/代次检查并在导入远端支出后再次核对身份。加载状态改为远端月份集合，首页、日历、记录页、月报复用 isLoadingRecordMonth，避免并行月份互相覆盖；本地读取原路径保持。任务完成清理同代状态，取消不写普通业务错误。当前月 Dashboard 独立刷新链不在本片内，不以历史月测试代表当前月全部取消/刷新场景。绿灯及设备结果待验证。

实现固定提交 `61c630f863a3a1ab6f68592de9ea0ada1b6ea47e`：[CI 39056994419](https://github.com/shenfn/SnapCount/actions/runs/39056994419)。App Build 成功，取消重入目标测试通过；357 项测试中，仅未修改的图片用例 `testA4IOS011BReusesSameIdentityAndSkipsExistingURL` 两条次数断言失败（2而非1）。该测试直接构造图片 UseCase，不经过本片 AppState；原 async let duplicate 与 gate.release 无“重复调用已进入”的顺序保证。修正测试为当前 MainActor 中直接进入 perform，让释放 Task 在其等待共享任务时执行；保留 hydrated、缓存跳过和一次 transport 的全部断言，不修改图片 UseCase。完整绿灯仍待新提交验证，不将本次失败归为已通过。

最终布局第二次复核：已查看 `58e969c` 的普通/辅助字号图片，主指标/猫位于原处，刷新失败及重试在指标下方，已有餐次可滚动查看。后续历史月请求实现没有布局变化，不额外重复视觉打磨。猫眼睛属于 F09 尚未开发，截图中的缺眼不作为本次全量原型验收。

本地九组业务边界检查：43/43 通过。第一次使用不存在的 test-ios-record-detail-boundary.mjs 路径未执行成功；通过 rg 查得现有 test-ios-local-record-detail-boundary.mjs 后运行，无产品修改用于绕过检查。

F06 / 003 纯视觉：前一天、当天各占一行，金额使用等宽数字并允许大字号换行；算法未变，截图与真机待验证。

## 尚未关闭

F01～F18 及交接 10.2 的刷新/候选保存问题仍按原清单追踪。首片未通过前，不把整个交接标为完成。热量个人目标历史生效范围未定，不擅自实现当前目标覆盖历史。真机手势、视觉、离线和实际故障样本仍需独立验收。

## 交接分析与接续范围

以下“待开发”只说明现状，不代表已有验收证据。原型决定按最新交接，不恢复旧 Spec 已被覆盖的决定。

| 反馈 | 已核查差距与实现边界 | 当前状态 |
|---|---|---|
| F01 | MainShellView 分页为五个 44pt 点击按钮；补连续拖动仍保留点击/辅助操作，与 TabView 页面横滑区分 | 待开发 |
| F02 | DomainDatePickerView 只列自然周；需要月内连续日期和月初阻尼/松手阈值，不能仅做换周按钮 | 待开发 |
| F03 | 展示层遮挡与 AppState 同月读取取消为不同故障；分别建立测试，不能以消除报错文案替代请求终态 | 展示修复已提交待绿灯；取消竞态待测试 |
| F04 | 当前时间线保留同刻 references，但点会重叠，明细默认只列最新分钟；缺真实三笔字段，不能判断遗漏原因或擅改上传时间语义 | 待脱敏样本/设备路径；拖动提示待开发 |
| F05/F08 | merchantDrill 目前只过滤某商户；应改为整日记账专用下钻，收支明细置于其中 | 待开发 |
| F06 | 比较卡一条 Text 拼接前日/当日值，改分两行，不改金额算法 | 已提交待截图/设备验收 |
| F07 | openDayRecord 把所有正式记录切到 records overlay 并压入详情，关闭先落记录页；需在共享导航边界恢复来源上下文，兼顾 DayDetailView 调用者和编辑删除 | 待开发 |
| F09 | 当前 DomainCatView 只有生成主路径 trim/stroke；原型明确独立面部延迟显现，旧 cat-v3 禁五官已被覆盖 | 待开发；通过 Token SSOT/生成链修正 |
| F10 | 本地归日与识别返回日期要追通；recognize_only 未复用旧睡眠 wake_at 归日；30天基准读取、主要睡眠、各项7晚、中位数均需新测试 | iOS 算法待开发；Edge 修改需另列范围 |
| F11 | 当前 weeklyTrend 的“查看”为日期菜单，不能替代睡眠专用下钻；当前候选须单独标识，不伪造历史 | 待开发 |
| F12 | 其他域当日记录保留；不因记账收支明细移入下钻而一并删去 | 保留现状 |
| F13 | recordRowContent 用 SF Symbol，已有 RecordDetailImageUseCase 的身份/引用/失效边界应复用，照片按钮与详情点击分开 | 待开发；导航复用 F07 |
| F14 | 能量数值＋横向通用参考尺已确认；不得以统一2000替个体目标，缺热量不当零，超参考值不能截满 | 待开发；个人目标保存与历史生效边界另述 |
| F15 | 当前运动 weeklyTrend/periodSummaryEntry 没有原型专用下钻，需真实记录与同源周期摘要 | 待开发 |
| F16 | 阅读维持现状，公共组件影响只回归，不扩产品范围 | 保留现状 |
| F17 | 快捷指令独立数据库写后，回前台可能命中月缓存；手工支出仅写支出详情缓存，其他域详情可能被覆盖；远端历史月及本地跨月编辑失效不齐 | 待按共享写后刷新链逐片修复 |
| F18 | 日历已有 previewDateKey/取消/查看；今天入口优先改预览，继续通过“查看”提交，避免绕过既有确认机制 | 待开发 |
| 候选补全额外发现 | 表单 adjustedRecord 没传入本地 archiveStaging，SQLite 仍读取原 payload/date；需真库测试验证“补全后正式事实读取”，不能只断言表单值 | 待开发；不扩为整个生命周期重构 |

优先级：F03 请求终态 → F17 事实刷新/候选补全 → F10 归日与基准 → F07 共享导航和专用下钻 → 日期/图表/图片/猫/热量交互。F04 真样本缺口与跨 Edge 边界不阻断其他已确认的 iOS 切片。
