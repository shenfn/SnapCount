# EXP-006 TDD 执行记录

- 目标行为：iOS 分开保存持久化 Voice 反馈与 Planner 下发状态，异步 Planner 不再删除原有推断和判断依据。
- 当前行为：`NativeRecordDetail` 只有 `aiFeedback`；`prepareRecordExpressionPlan` 将该字段替换为 Planner 预览，详情页随后只能读取被替换后的单一对象。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 场景 `EXP-006`。
- 基线提交：`origin/main@6ae2d5c`，PR #31 的 iOS Build Gate 已通过；本地 Windows 不作为 Swift 编译结论。
- 工作树：`D:\Business\count\.worktrees\事实与表达正确性TDD`。
- 分支：`codex/事实与表达正确性TDD`。
- 本轮范围：iOS 详情模型双反馈槽、AppState 异步装配、Records/Inbox 详情展示、静态契约与 XCTest。
- 非范围：重新设计卡片视觉、PWA 状态模型、Planner 候选算法、跨记录关系和数据库迁移。
- 预计修改文件：表达事实 Spec、执行记录、`NativeDataService.swift`、`AppState.swift`、Records/Inbox 详情 View、`SnapCountTests.swift` 和 iOS 静态契约测试。
- 基线测试结果：`origin/main@6ae2d5c` 对应 PR #31 macOS SwiftUI Build、XCTest 和 iOS Build Gate 均通过。
- 红灯测试及失败原因：`node --test tools/ai-validation/expression-planner/tests/ios-feedback-slot-contract.test.mjs`；1 项按预期失败。`NativeRecordDetail` 不存在 `legacyAiFeedback` / `plannerAiFeedback`，AppState 和 Records/Inbox 详情也只能传递单一 `aiFeedback`。
- 最小实现：`NativeRecordDetail` 新增 Voice/Planner 来源槽并保留原 `aiFeedback` 作为状态机兼容选择；AppState 在读取、Planner 预览、曝光确认、图片水合、缓存回填和失效恢复时同步槽位。Records 与 Inbox 详情将 Voice 支持内容和 Planner 曝光/点评身份分别传递；没有 Voice 时回退展示 Planner 自带依据。
- 绿灯结果：Windows 静态契约 `node --test tools/ai-validation/expression-planner/tests/ios-feedback-slot-contract.test.mjs` 1/1 通过；新增 XCTest 覆盖 Planner 主陪伴与独立卡片两条路径，待 macOS CI 执行。
- 本分支最终回归：Edge 相关 Deno 测试 85/85、Planner 全量 176/176、PWA 生产构建和 `git diff --check` 均通过；这些本地结果不替代 Swift 编译与 XCTest。
- PWA/iOS 差异：PWA 已有独立 `legacyAiFeedback` / `plannerAiFeedback`；本轮只补齐 iOS 同一契约。
- GitHub CI 结果：PR #32 的 macOS SwiftUI Build、XCTest 和 iOS Build Gate（run `31314020808`）通过；Release Validation（run `31314020801`）通过。
- 未解决风险：Windows 无法执行 XCTest，最终 Swift 行为以 PR 的 macOS CI 为准。
- 对应提交：`1bc416e`。
