# REC-016 TDD 执行记录

- 目标行为：iOS 待补全账单在中转站当前上下文内编辑，完成后继续队列，不压入独立详情导航。
- 当前行为：列表卡片使用 `NavigationLink(.record)`，舞台操作又弹出包含完整详情的 sheet；两条路径都把补全表现为独立详情页。
- 权威来源：`docs/spec/10-记录生命周期规格说明.md` 场景 `REC-016`，字段与事务沿用 `REC-005`。
- 基线提交：`origin/main@6c7fe7d`。
- 工作树：`D:\Business\count\.worktrees\跨记录关联与中转站收口TDD`。
- 分支：`codex/跨记录关联与中转站收口TDD`。
- 本轮范围：iOS Inbox 路由、待补全表单容器、完成后队列定位、失败保留和 XCTest/静态契约。
- 非范围：PWA 补全事务、重试次数上限、数据库 RPC 和视觉系统重构。
- 预计红灯：源码仍存在 pending 账单到 `.record` 的导航路径，且舞台补全以 sheet 详情覆盖当前页面。
- 红灯结果：`ios-inbox-inline-contract.test.mjs` 在改动前因 pending 卡片使用 `NavigationLink(.record)` 而失败。
- 最小实现：待补全卡片改为中转站分类页内的编辑入口，使用 `InboxPendingExpenseEditor` sheet 承载同一字段与确认事务；`openPendingExpense` 改为打开待补全分类，不再直接压入记录详情；舞台路径复用同一编辑器。Sheet 只承载补全表单，不再压入完整记录详情导航，保存后回到当前队列。
- 绿灯结果：`ios-inbox-inline-contract.test.mjs` 通过；保留保存失败、重试上限和队列完成后的 `finishAction` 逻辑；完整行为待 macOS XCTest/人工验收。
- 环境限制：Windows 无法编译 Swift；本轮未修改 PWA 确认 RPC 和重试上限。
- GitHub CI 结果：待提交后执行。
