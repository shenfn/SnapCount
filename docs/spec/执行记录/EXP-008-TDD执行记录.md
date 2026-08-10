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
