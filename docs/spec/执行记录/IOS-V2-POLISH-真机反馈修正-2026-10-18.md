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

历史月完整绿灯：`de484e2`，[CI 39081955367](https://github.com/shenfn/SnapCount/actions/runs/39081955367) App Build 成功、357 项 XCTest 全通过，含取消重入及图片重叠复用测试。至此 F03 的本片展示/历史月读取已具备红绿证据，快速跨月/用户切换/真机仍按后续验收清单保留。

最终布局第二次复核：已查看 `58e969c` 的普通/辅助字号图片，主指标/猫位于原处，刷新失败及重试在指标下方，已有餐次可滚动查看。后续历史月请求实现没有布局变化，不额外重复视觉打磨。猫眼睛属于 F09 尚未开发，截图中的缺眼不作为本次全量原型验收。

## F09 / 009 原型猫接入（后续视觉切片）

- 主原型 SHA256 已在本轮重新核实，与交接指纹相同。只将五域猫的必要路径/装饰数据转成 SSOT，不提交原型 HTML 或其他私有素材。
- 用原型五个主路径替换旧 cat-v3；直线/二次曲线转等价三次曲线，硬币圆弧以四段标准三次圆弧近似。面部路径独立保留多次 move，装饰位置、颜色、透明度进入 Token；统一 200×200 视框。
- 生成器输出 drawsFace 分层和五域装饰；通过 `generate-ios.mjs --sync-app` 同步 App 副本，没有手改生成文件。
- DomainCatView 分主线、面部、装饰；主线按原型收回后留空帧再画入，850ms 后面部渐显350ms；收回360ms、绘入1150ms。快速切域取消旧任务；减少动态效果、后台恢复显示包含眼睛的静态终态。睡眠先用原型中性闭眼姿态，不移植演示中的固定“睡够”阈值。
- Node 红灯：`node --test --test-name-pattern=F09 scripts/test-ios-prototype-generation.mjs` 因“面部必须独立于主线绘制”失败。实现后全套生成检查 10/10 通过，包括确定性和 PWA 产物隔离；`node --check` 与 App Token `--check` 通过。
- 涉及 Token、iOS 生成器、生成 Swift、DomainSceneView、生成检查脚本、本记录。尚待新固定提交 macOS Build/合成截图与真机动画、快速反向、减少动态效果验收；Node 结果不代替这些验收。

## F17 / 006、SL-02-C4 新增支出后全域投影（下一业务切片）

范围：AppState.createLocalExpense 的写后投影、LocalFirstSL02ProjectionTests 的真实 SQLite fixture；复用 refreshLocalMonthProjection，不改账户事务、数据库、远端创建或其他写入契约。

场景 006-F17-支出新增：给定当前月已有一条正式饮食记录且页面已读热缓存，手工新增本地支出成功后，AppState 月列表包含两域；原饮食详情与热量仍可读取；新支出使用 FactReader 权威引用且有详情；当前月 Dashboard 保留饮食组，账户余额按新支出更新；普通非 force 重读不能再次变旧，不查询云端会话。测试入口为 AppState.createManualRecord/createLocalExpense → recordGroups/recordDetails/NativeDomainScenePresentation，fixture 使用既有真实库 harness。

预期红灯：现路径以仅支出的字典替换 localRecordMonthDetails，以仅支出组替换 dashboard.dayRecordGroups，并绕开 localFactMonths 的统一刷新。应由饮食详情/指标与跨域组断言失败证明；不以 SQL、账户准备或环境失败冒充红灯。前一片完整绿灯后再写该业务测试。

本地九组业务边界检查：43/43 通过。第一次使用不存在的 test-ios-record-detail-boundary.mjs 路径未执行成功；通过 rg 查得现有 test-ios-local-record-detail-boundary.mjs 后运行，无产品修改用于绕过检查。

F06 / 003 纯视觉：前一天、当天各占一行，金额使用等宽数字并允许大字号换行；算法未变，截图与真机待验证。

F17 当前测试：前一片完整绿灯后已新增 `testIOSV2POLISH006F17NewExpensePreservesAllDomainFactsAndDetailsInWarmMonth`。尚未修改支出写后实现；与 F09 纯视觉变更同一固定提交进行 macOS 编译/测试，F09 的 Node 红绿与本业务测试结果分别记录。

F17 首个红灯：`25e46dd`，[CI 39082590048](https://github.com/shenfn/SnapCount/actions/runs/39082590048)。App Build 成功（含新猫）；358 项 XCTest 中目标用例两条失败：新支出不是统一事实引用、当前月 Dashboard 未保留饮食组。当前月饮食详情和450千卡断言通过，因为 recordDetails 可从 dashboard.recordDetails 兜底。不能把这些通过的断言写成已复现丢指标。补同一场景的历史月 `2000-01-05`，在无当前 Dashboard 兜底时验证整月详情覆盖；仅为这两个来源条件抽取测试 helper，支出实现仍保持原样。下一固定提交运行红灯及待验证 UI。

## F18 / 002-B 日历定位今天

在日历月份标题下补“回到今天”按钮，复用 NativeLocalDate.dateKey(Date()) 设置 previewDateKey，与点选日历日期保持相同的取消/查看门禁；月份变化仍走既有 task(id: monthKey) 读取。没有改业务日期算法、归属或保存规则。按钮有44pt触区及“点查看后生效”的辅助标签。沿用既有上海日期 XCTest、六行月历普通/辅助字号合成截图；实际远月定位、取消和查看生效待真机操作，不把截图当点击行为证据。

## F14 / 004 默认能量参考尺

本片只接已确认默认模式：主值文案“已记录食物能量”、保留“约/估算”，横向尺的点位只读现有 knownPrimaryTotal；虚线与可点击说明明确 2,000 千卡为通用营养参考，不是个人目标/超标线/剩余可吃额度。坐标自动包含零、参考值及真实点位，不把大于参考的值截满；没有记录或估算不完整时不画能量点。沿用暖橙场景、字体、卡片与间距；没有新增热量累计、有效日分母或餐次字段推导。现有餐次列表为次级回顾入口。

新增零值、3,200 超参考、未估算三组合成 fixture，普通/辅助字号各一份；既有空态和带本地事实的远端失败 fixture 继续覆盖。截图和 macOS 结果待验证。个人目标设置/保存/历史生效不在本片：当前没有可靠目标事实，不新增假开关，不用当前目标重写历史。

## F01 / 005 底部分页拖动

现有五个44pt按钮的布局不变，页点组接入最小8pt拖动，按本地横坐标连续选择领域；点击和 VoiceOver 的逐项按钮继续可用，组增加“领域选择”的递增/递减动作，只有领域实际变化时触觉反馈。`page_dot_hit_width` 从旧未消费的32修正为当前既有44，并经生成链输出；新增拖动距离 Token。映射在 AppDomain.pagerDomain(at:) 中集中，有限坐标两端夹取、无效坐标不选，先限制范围后转 Int，避免越界/溢出。

小测试 `testIOSV2POLISH005F01PagerPositionsRespectHitAreasAndClampFiniteEdges` 覆盖负坐标、0、43.99/44边界、五域、220/远端越界、NaN/Infinity。本片是 UI 选择与命中映射，不改变核心记录/保存/日期语义，不冒充业务红灯。下一固定提交运行该测试及原生编译；真机拖动、点击竞争、旁边入口和辅助操作待验证。

## 尚未关闭

F01～F18 及交接 10.2 的刷新/候选保存问题仍按原清单追踪。首片未通过前，不把整个交接标为完成。热量个人目标历史生效范围未定，不擅自实现当前目标覆盖历史。真机手势、视觉、离线和实际故障样本仍需独立验收。

## 交接分析与接续范围

下表区分实现与验收；“待统一验证”不代表已有本批 macOS 或真机证据。原型决定按最新交接，不恢复旧 Spec 已被覆盖的决定。

| 反馈 | 已核查差距与实现边界 | 当前状态 |
|---|---|---|
| F01 | MainShellView 分页为五个 44pt 点击按钮；补连续拖动仍保留点击/辅助操作，与 TabView 页面横滑区分 | 已实现，macOS 编译和映射测试通过；真机手势待验 |
| F02 | 月内原生横向浏览；40pt边界回弹提示及松手跨月，辅助月边界操作 | 已实现；待统一编译、截图及真机手势验证 |
| F03 | 展示层、历史月取消已有红绿证据；当前月改为共享 Dashboard Task，月份加载纳入当前核心请求状态 | 历史片已绿；本批当前月及强刷竞态待统一验证 |
| F04 | 保留原时间优先级；增加选中记录/金额浮层、时间来源、同刻多笔及缺时间笔数说明 | 交互已补待统一验证；原三笔根因仍待脱敏样本 |
| F05/F08 | 商户卡进入整日记账下钻；金额柱/图内累计、商户、前日金额/笔数/最高一笔、全量收支记录和当前候选 | 已实现；待统一验证 |
| F06 | 比较卡一条 Text 拼接前日/当日值，改分两行，不改金额算法 | 已提交待截图/设备验收 |
| F07 | homePath 原生推入详情，保留原域/日期/滚动位置；DayDetailView 原有 NavigationLink 保留 | 已实现并补来源上下文测试；待统一验证/真机 |
| F09 | 原型要求独立面部延迟显现，旧 cat-v3 禁五官已被覆盖 | Node 10/10、macOS 编译通过，五域静态截图已查；动画/设备待验 |
| F10 | 本机写入/候选/确认/旧事实读投影按醒来日，主要睡眠及分项30天中位数；缺时长不能冒选最长，缺区间不反推 | iOS 已实现及补测试待统一验证；云端识别/查询未改，单列边界 |
| F11 | 近七夜“查看”进入睡眠下钻，独立日期/域；主要睡眠、基准、正式记录、当前候选同源分离 | 已实现；待统一验证 |
| F12 | 其他域当日记录保留；不因记账收支明细移入下钻而一并删去 | 保留现状 |
| F13 | 独立照片缩略图与详情按钮；复用图片 UseCase 的身份/代次/路径保护，原生大图支持捏合/双击和辅助缩放 | 已实现并补本地照片实存截图用例；待统一验证/设备 |
| F14 | 能量数值＋横向通用参考尺已确认；不得以统一2000替个体目标，缺热量不当零，超参考值不能截满 | 默认模式已实现及截图检查；个人目标保存与历史生效边界另述 |
| F15 | 周图/周期入口进入运动专用下钻，领域/日期独立，真实周期摘要与全量正式记录 | 已实现；待统一验证 |
| F16 | 阅读维持现状，公共组件影响只回归，不扩产品范围 | 保留现状 |
| F17 | 支出全域刷新已有361项绿灯；前台本机重读、历史远端写后、跨月编辑、强刷较新结果保护均补齐 | 本批待统一验证；双连接SQLite锁争用仍单列风险 |
| F18 | 日历已有 previewDateKey/取消/查看；今天入口优先改预览，继续通过“查看”提交，避免绕过既有确认机制 | 已实现并查看两字号截图；实际定位/取消/查看待设备验证 |
| 候选补全额外发现 | 原事务接收编辑字段，持久化真实补全结果；图片/身份/归档幂等沿用原行 | 已实现及真实SQLite用例待统一验证 |

优先级：F03 请求终态 → F17 事实刷新/候选补全 → F10 归日与基准 → F07 共享导航和专用下钻 → 日期/图表/图片/猫/热量交互。F04 真样本缺口与跨 Edge 边界不阻断其他已确认的 iOS 切片。

## 2026-10-18 接续：F17 历史月红灯与最小修复

`6f8db0f` 的 [CI 39083206524](https://github.com/shenfn/SnapCount/actions/runs/39083206524)：App Build 通过，361 项 XCTest 有7条断言失败。F17 当前月2条（引用和Dashboard跨域组），历史月4条（引用、饮食详情、450千卡指标、普通重读后详情仍缺）。因此历史月覆盖详情的因果已有真实 SQLite/macOS 红灯，当前月详情因Dashboard兜底通过，二者不混写。

最小实现仅将 createLocalExpense 的专属缓存覆盖块替换为现有 refreshLocalMonthProjection(monthKey:)；账户事务、prepareLocalWorkspace、保存结果与提示保持原流程。统一 FactReader 刷新同时更新全域组、详情及权威引用，降级模式继续使用该共享入口的既有行为。绿灯待本次固定提交 CI。

第7条失败来自既有 AccountBindingUseCaseTests 的重复绑定次数2而非1。原测试 async let duplicate 加8次 Task.yield 没有保证重复调用实际先于释放；与此前图片测试相同。改为先验证冲突，再在 MainActor 直接 await 重复调用，排队的释放任务仅在调用等待在途结果后执行。保留原有冲突、结果、调用次数断言，不修改绑定业务实现。

本地支出应用与账户绑定边界脚本7/7通过。额外两份旧 shell 脚本共5/5失败：缺旧 LocalSettingsView、旧登录分树/隐藏新增断言、旧 shellBottomBar 字符串。已在临时目录从本轮起点 ddf30a2 逐文件导出对应源文件/脚本重跑，同样5/5失败；作为已验证的基线失效记录，不改产品以满足旧字符串检查，不删除或弱化脚本。

已下载本次 ios-prototype-captures 到系统临时目录，查看五域 content-large、新猫均有对应面部/装饰；能量零值、3200和未估算辅助字号无冒充零值/截满；日历普通与辅助字号有今天入口，月历仍可滚动，底部取消/查看可见。能量尺辅助字号稀疏刻度部分端点文字未显示，数值和2000说明保持可读，后续设备验收留意刻度可读性。这些是合成截图，不能证明点击、滚动、动画时序、真机性能或真实数据。

## 下一切片预案：006-F17-外部写入与回前台

现状/目标：SnapCountApp 的 scenePhase.active 只调用 refreshDashboardIfStale(force:true)，该入口未登录直接返回；要让独立数据库写入在活跃首页、已打开历史月及当前月出现，不要求重启或切月。已有其他域的缓存、业务日期和所选领域应保留正确语义。

预定范围：AppState.refreshDashboardIfStale 的本地事实重读；LocalFirstSL02ProjectionTests；本记录。复用 prepareLocalWorkspace、refreshLocalMonthProjection 及既有身份代次检查；不改 Intent 识别算法、图片、数据库或云同步权限，不新增通知框架。前一片全量绿灯后才写测试，真实目标红灯后才改实现。

测试层/公开边界：真实 SQLite 的第二个 LocalDatabase/LocalRecordUseCase 连接提交当前月及2000-01历史月的两条正式饮食记录，主 AppState 事先读热缓存；调用应用实际前台入口 refreshDashboardIfStale(force:true)。从 recordGroups/recordDetails 与 NativeDomainScenePresentation 验证两月记录与不同热量均更新，所选历史日期/领域不变；未登录不请求云会话，已登录仍保留远端刷新入口。验证的是外部提交后的刷新，不冒充系统快捷指令安装、相册或真实识别测试。

F17 支出切片完整绿灯：`41246b5`，[CI 39084075083](https://github.com/shenfn/SnapCount/actions/runs/39084075083) 成功，App Build 与361项 XCTest 全通过（0失败），含当前/历史月支出新增及绑定重叠测试。此结果不代表 F17 其他入口全部修复。

已按上面预案新增两条公开前台入口真库测试（未登录/已登录），只改测试与本记录；回前台实现保持原状，等待固定提交 macOS 红灯。

## F02 / 002-A 日期栏交互切片

范围：DomainDatePickerView、日期条布局 Token 与生成产物、IOSDomainBlocksTests 的手势提交决策检查、合成截图及本记录。日期计算复用 NativeLocalDate，不改记录归属、时区、存储或加载 API。

交互基准：原生水平 ScrollView 展示当前月，普通字号约七列、大字号保持可读触区。月初右拉依原生回弹阻尼，拉距达到40pt才提示“返回上月”，松手选上月最后一天；不足、反向或竖向拖动不提交。反向越过月末采用下月第一天，是实现选择而非用户原话。VoiceOver 提供同等月边界操作；日历保留预览/取消/查看。几何阈值映射用小型 XCTest 检查（UI 行为，不新增业务日期算法）；原生滚动、TabView 竞争、取消和手感须真机验收。当前 F17 仅测试提交在 CI 中，其业务实现不因本片提前修改。

前台入口首轮 `36dcd66`，[CI 39084857785](https://github.com/shenfn/SnapCount/actions/runs/39084857785)：App Build 成功，363项测试有5条失败。未登录用例4条目标断言失败（两月记录数0、热量nil），构成有效红灯。已登录用例在外部 INSERT 时 SQLite error5/database is locked，尚未到刷新断言，不算该分支业务红灯。

原预热调用 loadRecordMonth 在登录态同时启动 Dashboard 异步补充；此次锁日志只证明双连接争用，没有占锁事务证据，不能宣称已定位数据库根因。本条验收前提是“外部已成功提交后刷新”，改用已有 refreshLocalRecognitionProjection 分别预热历史/当前本地缓存，保持登录态不变，排除准备阶段云补充任务。独立进程与云读取同时进行时的 SQLite 争用另列风险，本片不改数据库配置或伪装已解决。前台业务实现仍未修改，重跑已登录红灯。

F02 实现采用原生 ScrollView 回弹及 ScrollViewReader 定位所选日，GestureState 取消自动退出提示；只发布两端回弹距离，月内正常滚动不发布逐帧坐标。原生日单元格触区及高度使用 ScaledMetric，保留选中状态/记录点/VoiceOver边界动作。40pt阈值进入SSOT并生成，月边界提交复用现有日历日期函数；新增UI决策检查和月初/月末普通/辅助字号合成截图入口。Node生成测试10/10及App Token检查通过，Swift、截图及真机仍待后续固定提交验证。

## 用户更新验证约束：合并开发，统一一次 CI

用户明确要求停止逐片触发远端红灯，完成全部开发后统一触发 CI，以控制额度。此指示覆盖本轮仓库/技能中的逐片远端红绿执行顺序；保留场景与测试、本地静态检查和最终 macOS 验证，未运行的测试不写成通过。已对在途 39085444340 提交取消请求，后续不再逐片 dispatch。

前台刷新实现已复用现有共享入口：先读账户工作区，重读当前、所选及已缓存的本地月份，再执行原登录态 Dashboard 刷新；未登录不请求会话。每次 await 后核对身份代次，防旧循环继续处理新身份。尚未通过最终 macOS 验证。

## 合并开发范围与当前实现（最终统一 CI 前）

F17：AppState 远端新增、详情编辑/删除、候选归档和待确认支出统一重读已打开月份；写前在途历史请求结束后再强读，保留身份代次门禁。本地完整表单跨月编辑刷新旧新月。候选补全新增 LocalStagingConfirmation 值对象，UseCase/Repository 原事务接收编辑字段；候选身份、原图与幂等目标仍读数据库原行，已归档重试返回首次目标。相关真库 XCTest 已添加，尚未运行。

F07/F05/F08/F11/F15：首页增加独立 NavigationStack/homePath；直接详情不切 records overlay。领域专用下钻复用同源模型/内容，但单独持有日期与领域，返回保留首页上下文；记账商户卡打开整日下钻，收支明细仅在该下钻；其他域当日记录保留。睡眠/运动“查看”进入专用下钻，候选区明确标“当前最新”，不伪造历史候选。

F10：iOS 侧新增主要睡眠与30天基准模型，所选日D之前D-30..D-1，每天取最长且稳定引用排序；时长/入睡/醒来分别至少7晚后给中位数，午夜钟点以中午为界展开再取中位。首页总时长保留午休，七夜图与时间卡使用主要睡眠。读取窗口扩至30天。LocalRecordUseCase 写入/候选/确认及 FactReader 读投影按完整 wake_at 的上海业务日归属；旧本地行只读纠正，不改写历史或迁移。旧睡眠跨月查询暂包含全部本地睡眠后按规范业务日过滤，已留 ponytail 上限/升级注释。远端 recognize_only 及云端按 record_date 的历史查询仍受原边界限制，未改 Edge/服务端，不能宣称这部分修复。

这些均为开发实现记录，不是已编译/测试通过。按用户新约束，全部本地检查结束后只统一触发一次 macOS CI。

合并开发补充：当前月 Dashboard 也使用会话所属共享 Task，页面取消/重入不让核心读取提前终止；重置取消并清空，结果与错误均核对代次。记录写后先等待写前核心/历史在途请求，再强制读取新事实。三个本机读入口按类型/月记录读取版本，force 不再被旧在途门禁跳过，旧返回不覆盖较新结果或清掉其加载状态；本地候选投影也检查读取版本/身份，确认移除会使旧读取失效。已补公开读入口的可控竞态 XCTest，未运行。

F13 本地照片测试使用临时数据库和 LocalImageStore 实际保存合成 JPEG，再验证缩略图返回 file URL 且不抢占 selectedRecordDetail。生产缩略图不调用详情加载/Planner；云图沿用 RecordDetailImageUseCase，另核对当前列表、身份代次及图片路径；本地仍走文件存储校验。大图支持系统滚动、捏合/双击及辅助缩放。没有提交样本图片或私有原型。

统一验证前本地结果：Token 生成器语法、App Token --check 通过；原型生成10项及九组业务边界43项、支出应用2项共55/55通过，0失败；git diff --check通过。Windows没有Swift/Xcode，新增XCTest、原生编译、截图和设备交互均不标绿。旧shell两脚本的5条基线失败仍保留，不用修改产品迎合旧断言。

仍需区分：F04原三笔发生/交易/标签时间缺脱敏实际字段；F10远端recognize_only和云端record_date查询未改；独立写入与云端补充同时发生的SQLite锁曾观察到，本批未改连接配置；个人热量目标及历史生效未获规则，不做假设置；真机手势/返回/离线/性能与发布没有验收。本批只做已明确的iOS改动及统一CI，不包含TestFlight。
