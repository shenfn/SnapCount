# ADR-001：冻结根工作区并使用独立治理 worktree

> 状态：已接受
>
> 日期：2026-08-15
>
> 关联任务：GOV-001

## 决策

治理规范和架构规划从最新 `origin/main` 创建独立、干净的 worktree 开始。根工作区及其他任务 worktree 的现有 WIP 保持原状，暂不清理、重置、归类或提交。

## 背景

根工作区落后于 `origin/main`，同时包含 personal-context、security contract、Edge prompt、脚本和媒体素材等多个关注面。多个 worktree 也存在不同任务的未提交内容。合并分支不等于 worktree 干净。

## 备选方案

- 直接在根工作区继续治理工作。
- 把根工作区全部 stash 或提交后再继续。
- 从最新 `origin/main` 创建独立治理 worktree。

## 选择原因

独立 worktree 能提供可复现基线，同时不覆盖或改变其他任务的 WIP。根工作区的保全和归属判断作为独立的 Git 治理任务处理。

## 影响与边界

- 当前治理分支基于 `origin/main@49614c8`。
- 根工作区和其他 worktree 在本任务中视为只读。
- 任何 WIP 清理、分支删除或远端操作都需要单独确认。

## 验证证据

- 27 个 worktree 已完成只读盘点。
- 治理 worktree 创建后 `git status --short --branch` 为空。
- `npm run governance:check` 已通过。
