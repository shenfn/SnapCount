# Agent 工作区规则

## Git 与 worktree

- 开始工作前先运行 `git status --short --branch` 和 `git worktree list --porcelain`。
- 当前任务默认只在用户指定的 worktree 修改；不要进入根工作区清理或重置用户 WIP。
- 禁止未经明确授权执行 `git reset --hard`、`git checkout --`、`git clean -fd`、删除 refs、删除 worktree 或强推。
- 发现分支引用消失、worktree HEAD 为全零、索引异常或未知 Git 进程时，立即停止 Git 写操作并保留只读诊断。
- 不使用 `git add -A`；提交前逐一确认 staged 文件，避免把本地素材、备份和凭据带入。

## 发布边界

- iOS 视觉分支只修改 iOS 页面、设计系统和相关文档，不修改数据库迁移、Edge Function、Planner 算法或生产配置。
- 不执行生产迁移、生产部署或 TestFlight 上传，除非用户在当前任务中明确授权。
- TestFlight 只能从已通过 iOS Build/单测的固定提交手动触发。
- Windows 不能验证 Swift 编译；必须以 GitHub Actions 的 macOS iOS Build 结果为准。

## 设计系统

- Token 唯一来源是 `trae-design-system/tokens/design-tokens.json`。
- 运行 `trae-design-system/scripts/generate-*.mjs` 生成各端产物，不手改 `trae-design-system/dist/`。
- 新页面优先使用 `JieziType`、`JieziSpacing`、`JieziRadius`、`JieziCard`、`JieziSectionHeader`、`JieziListRow`、`JieziMetric` 和 `JieziEmptyState`。
- 视觉改动必须保留 AppState、Repository、导航、保存、删除和确认门禁逻辑。

详细流程、提交格式、CI/CD 触发规则和异常恢复方式见：

- `docs/ios-视觉美化交接.md`
