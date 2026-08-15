# DESIGN-001 PWA 与 iOS 视觉设计交接

> 日期：2026-08-15
>
> 分支：`docs/PWA与iOS视觉设计规范`
>
> 基线：`origin/main@6d36bf1`

## 已完成

- 建立视觉设计独立 worktree，不混入 C2 清洗或业务 WIP。
- 明确视觉设计可以与 Phase 3 并行，但业务架构实现仍受 Phase 3/4 门禁。
- 将首页设为 D1 试点，iOS 只评估 PR #25。
- 定义 PWA/iOS 行为不变量、状态覆盖、设计系统约束和验证方式。

## 冻结范围

- 不修改 PWA/iOS 页面代码、数据库、Edge Function、Planner、生产配置和 TestFlight。
- 不接管 `ios-home-v3-native`、REC-009 或根工作区素材。
- 不把两端实现放在同一个代码分支。

## 下一步

1. 只读复审 PR #25 的页面结构、业务边界、测试覆盖和与最新主线的冲突。
2. 形成 iOS 首页保留/调整/放弃清单。
3. 基于同一信息层级盘点 PWA 首页，不提前写实现。
4. 评审通过后分别创建 PWA 和 iOS 的 `feature/` 实现分支。

## 未验证

- PR #25 尚未在最新 `origin/main` 上重放。
- Windows 不能验证 Swift 编译和 iOS 最终视觉。
- 尚未采集 PWA/iOS 的完整状态截图基线。
