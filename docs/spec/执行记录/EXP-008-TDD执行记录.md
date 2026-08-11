# EXP-008 TDD 执行记录

- 目标行为：Planner 异步到达前后，已显示的 Voice 支持内容保持稳定；Planner 只作为独立角度或主句交互身份出现。
- 当前行为：双反馈槽已经存在，但 AppState 仍把 Planner 预览写入兼容选择槽，现有静态测试只检查字段存在，没有比较异步前后的用户可见内容。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 场景 `EXP-008`。
- 基线提交：`origin/main@6c7fe7d`。
- 工作树：`D:\Business\count\.worktrees\跨记录关联与中转站收口TDD`。
- 分支：`codex/跨记录关联与中转站收口TDD`。
- 本轮范围：Swift 反馈装配策略、AppState Planner 预览/确认路径、Records/Inbox 展示稳定性和 XCTest。
- 非范围：重写 Voice 文案、重新设计反馈卡片视觉或改变 Planner 评分。
- 预计红灯：独立 Planner 预览到达后兼容选择槽由 Voice 切换为 Planner，导致 Voice 支持内容消失。
- 红灯结果：稳定性契约在新增策略入口前失败；现有 AppState 的 `feedbackToDisplay` 会把独立 Planner 卡写入兼容选择槽。
- 最小实现：新增 `plannerFeedbackToDisplayWithoutReplacingVoice`；独立 `feedback_card` 只写 `plannerAiFeedback`，兼容 `aiFeedback` 保留 Voice；iOS 详情两个 Surface 使用 `feedbackCardsToRender`，PWA 详情与待处理中转站保留 `legacyFeedbackCard` 并把 Planner 作为独立附加卡；点评提交按卡片 `renderIdentity` 绑定，确认、失败恢复和活动性检查同时按双槽处理。
- 绿灯结果：`ios-expression-stability-contract.test.mjs` 通过；新增 XCTest `testEXP008IndependentPlannerCardKeepsVoiceSupportStable`、`testEXP008FeedbackCardsAppendPlannerWithoutReplacingVoice` 和 `testEXP008ReviewTargetsTheCardTheUserActuallySelected` 待 macOS CI 编译执行。
- 环境限制：Windows 无法编译 Swift，不能把本地静态契约当作 XCTest 结论。
- GitHub CI 结果：待提交后执行。

## 追加执行：多域异步展示与瞬时失败恢复

- 基线提交：`origin/main@31ccefa`。
- 工作树：`D:\Business\count\.worktrees\多域陪伴展示修复`。
- 复现证据：线上 `get_record_expression_plan` 对睡眠记录返回合法的 `feedback_card`、候选 ID 和渲染指纹；PWA 首次请求出现瞬时网络错误时，旧实现直接缓存 `error`，页面没有加载或失败反馈，因此用户只看到 Voice 卡片。
- 代码事实：睡眠、饮食和其他通用域都使用 `data_records`，UI 的 `universal` 只是入口类型，不应成为展示层二次门禁。
- RED：增加记录 ID 绑定、`loading` Surface、多域 `feedback_card` 独立展示，以及瞬时传输错误有限重试的契约测试。
- GREEN：PWA 计划缓存保存 `recordId`，按记录身份解析；详情页显示准备中和可重试失败态；Planner 请求对 `Failed to fetch`、超时、连接重置和 408/425/429/5xx 做有限退避重试；iOS 计划解析对 `URLError` 瞬时错误做同样的有限重试。
- 验证：`npm run test:expression-presentation` 22/22 通过；`npm run build` 通过；`git diff --check` 通过。真实本地页面验证过加载态、失败态和手动重试后睡眠双卡片；Windows 无法执行 Swift 编译，iOS XCTest 待 macOS CI。
