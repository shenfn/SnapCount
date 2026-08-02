# Agent Safety Rules

开始任何代码、Git、数据库或部署操作前，必须先阅读
`docs/agent-git-worktree-handoff.md`。

本仓库使用多个 Git worktree。所有 worktree 共享同一个 `.git` 引用数据库，
所以在一个目录执行分支删除、引用重写、worktree 清理或强制推送，会影响其他
Agent 正在使用的工作区。

必须遵守：

- 每个 Agent 使用独立 worktree 和 `codex/*` 分支，并先记录 cwd、branch、HEAD、status 和 worktree 列表。
- 不操作其他 Agent 的 worktree，不在脏工作区执行 reset、restore、checkout、clean、stash/pop 或强制切换。
- 不删除或重写其他分支，不执行 `git branch -D`、`git update-ref -d`、`git worktree prune`、`git gc --prune=now` 或 force push。
- 只暂存明确审查过的文件，禁止用 `git add -A` 覆盖其他 Agent 的未提交内容。
- 未经用户明确授权，不提交、推送、合并、应用生产迁移、部署 Edge Function 或触发 TestFlight。
- 任何令牌、Service Role key、JWT、原图、数据库 dump 和真实 AI 日志都不得进入 Git、PR、命令输出或交接文档。

发现 HEAD、分支引用或 worktree 状态异常时，立即停止所有 Git 写操作，按交接文档中的事故流程处理。
