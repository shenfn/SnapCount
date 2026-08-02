# SnapCount Git、Worktree 与 Agent 交接规范

版本：`2026-08-01`

本文是本仓库所有 Git 写操作的前置规范。它吸收了 2026-07-23 分支引用事故和 2026-07-31 分支收拢的复盘结论。后续 Agent 在创建分支、提交、合并、退役 worktree 或清理引用前，必须先阅读本文和仓库根目录 `AGENTS.md`。

## 1. 核心原则

1. `origin/main` 是唯一长期集成基线；发布来源必须固定到完整 commit SHA。
2. 一个 worktree 对应一个短期 `codex/<scope>` 分支和一个明确责任人；不能用目录名推断实际分支。
3. 多个 worktree 共享同一 `.git`、refs、reflog 和 stash。任一 worktree 的引用删除、强制重写或 prune 都可能影响其他任务。
4. dirty、untracked、staged、reflog-only commit 都是成果；没有可恢复副本前不得删除、覆盖或退役。
5. “整理 Git”不等于“授权发布”。删除历史分支、合并 PR、部署 PWA/Edge、应用迁移和上传 TestFlight 是五类独立动作，分别授权。

## 2. 开工前只读检查

在目标 worktree 中记录以下结果后才能编辑：

```powershell
$ErrorActionPreference = 'Stop'
Get-Location
git rev-parse --show-toplevel
git branch --show-current
git rev-parse HEAD
git status --short --branch
git diff --name-status
git diff --cached --name-status
git worktree list --porcelain
git show-ref --heads
```

出现以下任一情况时停止 Git 写操作：

- 当前目录、分支、HEAD 或基线与任务交接不一致；
- HEAD 为全零、分支显示 `No commits yet` 或大量 refs 同时消失；
- 目标文件已有来源不明的修改；
- 有未知 Git/IDE/Agent 任务正在改 refs、索引或 worktree 元数据。

不要用 `reset`、`checkout`、`clean` 或 stash 让现场“看起来干净”。

## 3. 分支生命周期

### 3.1 创建

- 从已经核对过的 `origin/main` 或明确 PR head SHA 创建短期分支。
- 分支名使用 `codex/<scope>`，一个分支只承载一个可评审目标。
- 创建时在交接信息中记录：worktree、分支、完整基线 SHA、责任人、预计去向。

```powershell
git fetch origin main
git worktree add .worktrees/<scope> -b codex/<scope> origin/main
```

`git fetch` 是远端读操作，但仍会更新共享 refs；多 Agent 并行时由一个明确的 Git 协调者执行，其他 Agent 不同时运行 fetch、merge、rebase、prune 或 branch 删除。

### 3.2 使用

- 只在自己的 worktree 编辑、测试和提交。
- 不进入根工作区或其他 worktree 处理用户 WIP。
- 不使用 `git add -A`、`git add .`；只暂存逐项复核过的路径。
- 每次长时间工作或上下文恢复后重新核对 cwd、branch、HEAD 和 status。
- 混合提交必须文件级审计；不能因为提交“看起来相关”就整体 cherry-pick。

### 3.3 退役门禁

分支或 worktree 只有同时满足以下条件才可列为删除候选：

- tracked、staged、untracked 均为空；
- 分支提交已进入 `main`，或逐提交确认 patch-id 等价；
- 没有只存在于该分支/reflog 的有效提交；
- PR、CI、发布与回滚记录已固定到 SHA；
- 恢复备份已经验证；
- 仓库所有者对具体 worktree、分支和 SHA 单独确认。

“是 `main` 祖先”只能证明提交历史已合入，不能证明未提交文件可删除。补丁等价也不等于可以直接强删 dirty worktree。

## 4. 清理前恢复点

分支收拢必须先建立可恢复点，顺序不可颠倒。

### 4.1 冻结与盘点

1. 暂停所有会写 Git 的 Agent、IDE 自动任务和同步脚本。
2. 保存 refs、HEAD、PR、worktree、status、staged、untracked 和运行进程清单。
3. 找出仅存在于 reflog/unreachable 集合中的提交，并逐个确认对象类型与内容。
4. 为需要保留的 reflog-only commit 建立 `refs/archive/pre-cleanup-<date>/<name>` 本地引用。

普通 `git bundle create ... --all` 只包含被 refs 引用的对象。若先做 bundle、后恢复 reflog-only 引用，bundle 仍会漏成果。

### 4.2 双重 Git 备份

- 在仓库外备份完整 `.git` 元数据；
- 建立 archive refs 后执行 `git bundle create <path> --all`；
- 执行 `git bundle verify <path>`；
- 记录备份目录和 SHA-256，但不在 Git 中保存真实数据或凭据。

完整 `.git` 备份用于恢复 worktree/refs/reflog 现场，bundle 用于验证可移植提交对象；两者不能互相替代。

### 4.3 dirty worktree 备份

每个 dirty worktree 必须分别保存：

- `git diff --binary`；
- `git diff --cached --binary`；
- 实际 untracked 文件归档，保留相对路径；
- 文件清单、大小和 SHA-256；
- 当前 branch、HEAD、upstream、status。

仅保存 untracked 文件名或哈希不能恢复内容，不算备份。归档完成后必须随机抽样并至少完整恢复验证一次，确认路径、文件数和哈希一致。

备份在仓库外加密保存并限制 Windows ACL；`.gitignore` 只防误提交，不提供磁盘保密。

## 5. 清理执行规则

1. 先文件级抢救 dirty worktree，再处理已经证明合并且干净的 worktree。
2. 每次只退役一个具体 worktree/分支，执行前后重新记录 refs 和 status。
3. 不使用 `worktree remove --force`、批量 `branch -D`、`clean`、`prune` 或脚本循环删除。
4. 需要强制删除的分支按“分支名 + 完整 SHA”逐项确认，不能只批准一类名称。
5. 清理完成后验证 archive refs、bundle、主分支、剩余 worktree 和所有 dirty 文件仍可恢复。

未经明确授权禁止：

```text
git reset --hard
git clean -fd / git clean -fdx
git checkout -- <path>
git restore .
git switch -f
git branch -D
git update-ref -d
git worktree remove / prune
git reflog expire
git gc --prune=now
git push --force / --mirror
```

`git stash` 也不是默认清理工具。它进入共享仓库状态，必须记录 stash 名称、文件清单、创建者和恢复责任人后才可使用。

## 6. 提交与 PR

暂存前逐路径核对：

```powershell
git add -- path/to/file-a path/to/file-b
git diff --cached --stat
git diff --cached --check
git status --short --branch
```

提交必须满足：

- 一个 commit 只表达一个逻辑变化；
- 不包含本地备份、真实图片、AI 原始日志、数据库 dump、签名 URL、账号导出或凭据；
- commit body 说明状态机/迁移/跨端影响、已运行与未运行测试、生产动作和回滚边界；
- 数据库、Edge、PWA、iOS 变更优先拆开，避免无法独立回滚的混合提交。

Commit message 使用仓库现有 Conventional Commit 风格，例如：

```text
docs(workflow): 固化 Git 清理恢复门禁
security(auth): 增加版本化同意门禁
fix(auth-ios): 隔离恢复会话与业务数据
test(auth): 覆盖历史账号同意状态
```

PR 合并前固定 head SHA。合并 `main` 可能触发 PWA 或 Edge 生产部署，因此“PR 检查全绿”不等于“已授权合并”。

## 7. 生产动作分权

| 动作 | 是否改变生产 | 最小授权信息 |
| --- | --- | --- |
| 删除已归档本地分支/worktree | 否，但可能丢本地成果 | 具体路径、分支、SHA、恢复点 |
| 合并 PR 到 `main` | 可能 | PR、固定 head SHA、会触发的 workflow |
| 部署 PWA/Legal/Edge | 是 | 固定 main SHA、目标环境、回滚 SHA |
| 应用数据库迁移 | 是且通常不可 Git 回滚 | 迁移版本、dry-run、备份、补偿 SQL |
| 上传 TestFlight | 是 | 固定 main SHA、macOS CI 结果、build 号 |

任何一项的授权都不自动覆盖下一项。数据库迁移和 Edge 部署也不是同一个动作。

## 8. 事故响应

发现 refs 消失、全零 HEAD、索引异常或未知批量 Git 写入时：

1. 停止全部 Git 写操作并保留进程现场；
2. 仓库外复制所有 dirty/untracked 实际文件并校验；
3. 保存 cwd、branch、HEAD、status、worktrees、refs 和 reflog；
4. 只读运行 `git fsck --full --no-reflogs --unreachable --no-progress` 和 `git cat-file -t <sha>`；
5. 先定位并停止持续改 refs 的来源，再按经确认的 SHA 恢复引用；
6. 恢复后连续复查，不用一次成功的 `update-ref` 代替根因调查。

若命令行、日志或聊天中出现 Service Role、JWT、PAT、Apple key、P12 密码或 Qwen key：停止传播，由账户所有者轮换；不能把旧值写入事故文档。

## 9. 交接模板

```text
任务目标：
工作目录：
分支：
HEAD（完整 SHA）：
基线来源：

本次修改：
- tracked：
- untracked：
- staged：
- 其他已有改动：

验证：
- 已运行：
- 结果：
- 未运行及原因：

生产状态：
- main 合并：
- PWA/Edge/Legal 部署：
- 数据库迁移：
- TestFlight：

恢复点：
- 仓库外备份目录：
- bundle verify：
- untracked 恢复校验：

风险与下一步：
- 当前阻断：
- 明确禁止动作：
- 下一位 Agent 第一条只读检查：
```

## 10. 周期性治理

- 每次开始大型功能前做一次只读分支盘点，不等到发布前集中清理。
- 已合并的干净短期分支在确认恢复点后及时退役；研究分支必须写明保留原因和 owner。
- 连续 14 天无 owner、无 PR、无独有提交且干净的分支列入候选清单，但仍不自动删除。
- 同一功能最多保留一个主开发分支和一个明确的发布候选；组合验证分支不得长期承载未提交源码。
- 每次事故或大规模清理后更新本文，记录可复用规则，不把易过期的分支数量和 SHA 写成永久事实。
