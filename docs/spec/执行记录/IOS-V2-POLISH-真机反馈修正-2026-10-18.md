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

本地九组业务边界检查：43/43 通过。第一次使用不存在的 test-ios-record-detail-boundary.mjs 路径未执行成功；通过 rg 查得现有 test-ios-local-record-detail-boundary.mjs 后运行，无产品修改用于绕过检查。

F06 / 003 纯视觉：前一天、当天各占一行，金额使用等宽数字并允许大字号换行；算法未变，截图与真机待验证。

## 尚未关闭

F01～F18 及交接 10.2 的刷新/候选保存问题仍按原清单追踪。首片未通过前，不把整个交接标为完成。热量个人目标历史生效范围未定，不擅自实现当前目标覆盖历史。真机手势、视觉、离线和实际故障样本仍需独立验收。
