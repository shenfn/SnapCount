# Agent 工作区规则

## Git 与 worktree

- 开始工作前先运行 `git status --short --branch` 和 `git worktree list --porcelain`。
- 当前任务默认只在用户指定的 worktree 修改；不要进入根工作区清理或重置用户 WIP。
- 禁止未经明确授权执行 `git reset --hard`、`git checkout --`、`git clean -fd`、删除 refs、删除 worktree 或强推。
- 发现分支引用消失、worktree HEAD 为全零、索引异常或未知 Git 进程时，立即停止 Git 写操作并保留只读诊断。
- 不使用 `git add -A`；提交前逐一确认 staged 文件，避免把本地素材、备份和凭据带入。

### Agent 协作权限模式

本仓库存在两种明确的 Agent 工作模式，不能混用：

- **共享 worktree（默认）**：`.git` 通过 worktree 管理目录指向共享仓库。Agent 可以读写源码、文档、测试并运行校验，但不得创建/删除 refs、fetch、提交或修改共享 index；这些动作由 unrestricted Git owner 执行。
- **私有 clone（自主提交）**：需要 Agent 自主提交时，Git owner 必须先在仓库外为该任务创建独立 clone（不得复用共享 `.git`），并记录 clone 路径、分支和基线 SHA。Agent 在通过 preflight 后可以逐路径 `add`、commit 和本地分支操作；push、PR、合并和生产动作仍需按当前任务授权。

私有 clone 的最小创建方式（由 Git owner 执行）：

```powershell
git clone --no-hardlinks <repository-url> D:/Business/count-agent-clones/<scope>
git -C D:/Business/count-agent-clones/<scope> switch -c codex/<scope> origin/main
```

Agent 开工前必须确认自己处于哪种模式：

```powershell
$gitDir = (git rev-parse --git-dir)
$commonDir = (git rev-parse --git-common-dir)
$gitDirAbs = (Resolve-Path $gitDir).Path
$commonDirAbs = (Resolve-Path $commonDir).Path
if ($gitDirAbs -eq $commonDirAbs) {
  Write-Output 'PRIVATE_CLONE: local Git metadata'
} else {
  Write-Output 'SHARED_WORKTREE: Git metadata is shared; owner-only Git writes'
}
```

只要输出 `SHARED_WORKTREE`，Agent 就不能因为命令返回成功而自行提交；受限身份对 `.git/refs` 的写入可能被 ACL/沙箱层回滚。要获得自主提交能力，必须切换到经 owner 验证的私有 clone，不能通过手写 ref、`mkdir` 或重复重试绕过权限。

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
