# IOS-V2-POLISH 开发复核与 CI 记录

日期：2026-10-17。用户本次授权：检查另一会话实现并触发 CI/CD。执行目录：`D:\Business\count\.worktrees\ios-v2-skeleton`；原实现基线 `5086b52b6bc9f1eafc2ca770fd2a4a17b1ab06ce`。

## 1. 复核结论

**当前阶段实现已通过 macOS 模拟器 Build 和 332 个 XCTest，不是原型全量还原或 S0～S5 全部验收完成。** 原执行记录中的“代码已实现/源码迁移已完成”不能代替以下缺项与运行验证。

本地权威 Spec：`docs/spec/模块/iOS本地优先/iOS原型全量还原与设计系统重构规格说明.md`，仍为既有未提交文档；本次不混入其变更。以该 Spec 的覆盖矩阵和场景作为复核依据。

## 2. 待补项（本次不冒充已完成）

| 优先级 | 文件/范围 | 已确认缺口 | 验收影响 |
|---|---|---|---|
| P1 | Features/Root/NativeDomainPageView.swift | 主体为 hero、指标双卡、通用周柱图和记录列表；缺消费时间线/选择、商户汇总、比较、观察及原型对应信息组织；睡眠未实现区间图，饮食缺最多一餐/周均等对应构图 | POLISH-003/004、原型 V-04/05/11 尚未完整覆盖 |
| P1 | Features/Root/MainShellView.swift、Features/Records/UnifiedManualRecordEntry.swift | 全局新增始终调用无领域参数的 UnifiedManualRecordEntry；未登录仍进入财务账户准备/消费表单，已有记录的非财务页没有对应新增操作承接。空态另有域级 ManualRecordSheet，但不能代替全局入口 | 从睡眠等领域点击底部加号不能完成预期领域录入；POLISH-002/004/010 未完整覆盖 |
| P1 | Features/Root/MainShellView.swift、NativeDomainPageView.swift | 底栏没有领域中英文名称；主值仍在概要卡，大领域标题仍存在；顶部/底部用固定 146/134 避让，非真实栏高/安全区计算 | 原型结构和大字体适配尚不成立，不能宣称高还原 |
| P2 | DesignSystem/JieziTheme+Generated.swift 与生成器、多个覆盖层 | 调整了底色、字体和 tint，但卡片仍消费旧 glass 内距/阴影参数；多页主要只加 tint/背景，未证明原型构图统一；页面内仍有大量手写字号/表面 | “所有可达页面迁移完成”缺逐页证据，POLISH-010/011 未完成验收 |
| P2 | Features/Onboarding/OnboardingFlowView.swift | 五个语义步骤与免登录进度已接线，但仍以旧式纵向时间线折叠卡展示；试一次主要打开 shortcuts:// 并由用户自行确认，未接实际识别结果的等待/失败反馈状态 | 五步数量不等于完整原型外观/真实试用反馈验收 |
| P2 | 日期窗口 | 睡眠/饮食标签“近七日”实际使用所在自然周，可包含未来日期；与原型近七晚/近七日含义需落实一致 | 统计时间范围与标签不可混用 |

以上属于真实范围缺项，保留后续实施；本次用户要求检查和触发构建，不用未经真机对照的大范围改版掩盖它们。

## 3. 本次已修问题

1. `NativeRecordPresentation.swift` 的两处新增 durationMinutes 调用漏写 `payload:` 标签，与现有声明不符。补齐标签。
2. `SnapCountTests.swift` 和 `LocalFirstSL02ProjectionTests.swift` 仍引用已删除的 NativeDomainPageModel，必然阻塞测试编译。迁移到 NativeDomainScenePresentation，保留收支、按域过滤、实际 SQLite 创建/重开/删除最后一条的断言，不恢复无运行消费者的旧月模型。
3. 域页重试调用未传 force，缓存存在时不能保证重新加载并清除错误。为 loadRecordDateWindow 增加默认 false 的 force 参数，重试传 true；增加 `testIOSV2POLISH002RetryReloadsCachedDateWindowAndClearsError` 验证缓存窗口再次读取和错误清除。普通浏览仍使用缓存。
4. `ios-build.yml` 缺少已要求的生成一致性门禁。补 Node 20、生成器语法和 `--check`；PR 路径识别覆盖设计 Token/生成器。

这些 Swift 修复先由静态声明/调用和失效引用证实；本机无 Swift，未伪称已运行 XCTest 或完成红绿测试。运行结果见下节后续证据。

## 4. 本地验证

- 三个生成器 `node --check` 通过；iOS 生成器 `--check` 通过，未手改生成文件。
- Token JSON 与 Info.plist XML 解析通过。
- 九组边界检查 43/43 通过：local-record-detail、pending-confirmation、staging-lifecycle、record-detail-image、wallet-snapshot-action、repayment-action、account-management-action、account-read、account-binding。
- `test-ios-local-shell-boundary.mjs` 四项失败。对 HEAD `5086b52` 核对：LocalSettingsView.swift 已不存在，Root 不含 localTabRoot，Records 不含旧登录门禁匹配。这些要求旧双 Tab/隐藏未登录创建的检查在实现前已不成立；未为迎合旧断言回退当前产品行为，也未删检查伪造全绿。
- 字体三份 TTF 共 43,174,744 字节，另有 OFL 文本；尚无 Archive/IPA 体积和真机字体渲染证据。
- `git diff --check` 于提交前核对。Swift 编译、XCTest、真机、VoiceOver、动画和快捷指令完整安装尚待运行/验收。

## 5. CI、提交与发布边界

- 本次仅提交本轮实现、必要字体/OFL、构建门禁和本复核记录。原有未跟踪 Spec/方案/交接及规格索引修改继续保留本地；根工作区 WIP 不动。
- 用户“检查并触发 CI/CD”的本次授权用于推送当前功能分支并手动运行 `ios-build.yml`；不触发 TestFlight、后端/生产部署，不合并主线。
- 本节在获得实际 workflow 结果后补充固定提交、run URL、Build 与测试结果。运行成功不代表第 2 节缺项消失。

首轮固定代码：`9a381a8ee7e8ac3b14a633206d7e37b759abffe9`。

- 仓库治理检查通过：https://github.com/shenfn/SnapCount/actions/runs/39011990895 。
- macOS 首轮：https://github.com/shenfn/SnapCount/actions/runs/39012002392 。Token 一致性与工程生成通过，模拟器编译失败，未进入 XCTest。
- 编译根因：生成器输出 `return .expense` 等成员访问，返回类型 JieziSceneTokens 没有这些成员；实际静态值属于 JieziScene。修复生成器为显式 JieziScene 限定，再执行 --sync-app；不手改生成文件。
- 新增本地重试测试与旧模型测试迁移仍待后续 macOS XCTest，首轮失败不作为业务红灯。
- 远端仓库已配置拍照/截图模板 URL 的 Secret 名称；没有读取 Secret 值，不能以本地未配置推断远端缺失，也不能从名称存在证明实际安装和回调成功。

第二轮固定代码：`625abfe6b562014447d3b51375d96295d1f2c80c`。

- macOS 第二轮：https://github.com/shenfn/SnapCount/actions/runs/39012212034 。Token 一致性、Xcode 工程生成与模拟器 Build 通过；全部 332 个 XCTest 通过，0 failures，日志含 `TEST SUCCEEDED`。日期强制重试新增测试通过；四域创建/重开/删除回归属于本次完整测试集合。
- 同提交治理检查通过：https://github.com/shenfn/SnapCount/actions/runs/39012210832 。

当前远端执行状态：第二轮成功。代码验证对象始终是 `625abfe6b562014447d3b51375d96295d1f2c80c`；后续仅本记录证据回填不代表又一次代码构建。

截至上述 CI 核查完成时未执行：真机视觉/手势/VoiceOver/快捷指令安装及真实回调、Archive/IPA 包体核验、TestFlight 上传、生产部署或主线合并。第 2 节需求缺项仍未完成，不能用 CI 绿灯消除。后续 TestFlight 授权与结果见第 6 节。

## 6. 用户追加授权的 TestFlight 预览

用户随后明确要求“触发 TestFlight”。本次按已验证代码发布预览，不将未通过的原型/真机验收描述为完成。

- 固定提交：`625abfe6b562014447d3b51375d96295d1f2c80c`，对应第 5 节成功 macOS Build 与 332 项 XCTest。
- 固定标签：`codex/ios-v2-polish-preview-20261017`，已推送；没有改写分支/标签或合并主线。
- 上传工作流：https://github.com/shenfn/SnapCount/actions/runs/39013041290 。触发时间：2026-10-17 15:16:48（Asia/Shanghai）。
- 工作流使用 github.run_id 写入构建号，本次为 `39013041290`，不是 workflow 的顺序编号。
- 最终状态：工作流成功，Archive、Export IPA 与上传均通过；Apple 工具日志明确为 `UPLOAD SUCCEEDED with no errors`、`No errors uploading archive`。
- IPA 内 Info.plist 实际打印构建号 `39013041290`，与前述预期一致。上传成功时间：2026-10-17 15:23:18；工作流完成时间：15:23:24（Asia/Shanghai）。
- GitHub 保存 `SnapCount-ipa` artifact，ID `12093727550`；artifact ZIP 为 37,777,358 字节。此数值不是 App Store 下载/安装体积，尚未核实设备安装后占用。
- 尚未独立核实 Apple 后续处理、测试组可见性或设备可安装状态；没有主线合并或后端生产部署。第 2 节视觉/功能缺项和真机验收仍保留。
