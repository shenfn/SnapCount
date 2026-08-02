# SnapCount Git、Worktree 与 Agent 交接规范

版本：`2026-07-23`

本文是本仓库的 Git 协作和发布交接规范，也记录 2026-07-23 分支引用事故的核查结论。后续 Agent 必须先阅读本文，再进行任何 Git 写操作。

## 1. 先读结论

本仓库不是单一工作目录。多个 worktree 共享同一个 `.git` 目录，所有本地分支引用也共享。一个 worktree 中的引用删除、分支重写、worktree 清理或强制推送，可能影响所有 Agent。

默认边界是：Agent 只修改自己的工作树和自己的分支。不确定时停止并报告，不通过猜测修复。

## 2. 2026-07-23 事故结论

### 2.1 已确认影响

- `codex/*` 本地分支引用曾短暂消失，7 个 worktree 的 HEAD 因此显示为全零或未提交状态。
- Git 对象库没有发现缺失对象、损坏 commit 或 hash 错误；commit 对象仍然存在。
- 15 个 `codex/*` 分支已依据 reflog、远程引用和有效 commit SHA 恢复。
- 7 个 worktree 的 HEAD 已恢复，随后连续检查未发现引用再次消失。
- 主工作区原有 16 个未提交文件已复制到被忽略的 `backups/wip-2026-07-23/`，16/16 文件哈希与当前工作区一致。
- 事故期间的 iOS 快进发生在 `codex/ios-swiftui-native-app`：`44b7d0e` 到 `f4f3a92` 共 12 个提交。它涉及 19 个 iOS/CI 文件，与主工作区 15 个 tracked dirty 文件没有重叠，因此未覆盖这批未提交改动。
- 当前没有证据表明这次引用事故合并了 `main`、应用了生产迁移、部署 Edge Function 或触发 TestFlight。

### 2.2 必须纠正的描述

- “同步上游 12 个提交”指的是旧 iOS 分支快进到其远程同名分支，不是把 `origin/main` 合并进发布分支。
- 当前发布 worktree 的目录名是 `release-integration`，但实际分支是 `codex/pending-privacy-review-fixes`，对应 Draft PR #10；不能根据目录名假定分支名。
- HEAD 显示全零时，Git 会把现有索引/工作树解释成未提交内容；这不等于磁盘文件已全部新增，也不等于对象库已损坏。
- 本次没有确认根因。当前未发现 Git hook 或 `sync-codex-history` 文本中有明确删除引用的命令，不能无证据归咎于某个 IDE、Agent 或脚本。若再次发生，必须先保留现场再追来源。

### 2.3 已发现但未自动执行的安全动作

本次工具链中曾出现过 Supabase Service Role/JWT 和 Supabase personal access token 的命令行或输出暴露风险。即使当前文件没有保存明文，也必须按已泄露处理：

1. 停止或重启仍可能持有旧参数的 Agent、终端或开发服务。
2. 立即轮换 Supabase Service Role/JWT。
3. 撤销并重建 Supabase personal access token，并更新 GitHub Actions、MCP、`.env.local` 和本机脚本配置。
4. 不把任何旧值写入 issue、PR、日志、交接文档或 shell history。
5. 公共仓库当前未启用 GitHub Secret Scanning；仓库管理员应启用 secret scanning 和 push protection。

这些轮换需要账户所有者在 Supabase/GitHub 控制台执行，本规范不代替轮换，也不在 Agent 中自动终止未知进程。

生产备份和图片备份位于本地且未启用文件级加密。`.gitignore` 只防止误提交，不防止本机其他进程读取。备份必须加密、限制 Windows ACL，并在确认恢复点后清理过期副本。

## 3. 当前仓库拓扑

### 3.1 长期规则

- `origin/main` 是唯一长期集成基线。
- `main` 是受保护的发布分支；本地 `main` 可能落后，不得把本地旧 `main` 当作最新基线。
- 新功能从最新 `origin/main` 创建短期 `codex/<scope>` 分支。
- 每个 Agent 使用独立 worktree；功能完成后通过 PR 合并，合并后删除短期分支必须由仓库所有者确认。
- 发布候选必须固定到一个可审计 SHA；不要用“当前工作树”或可移动分支描述生产来源。
- Expression Planner 算法分支是受保护的研究/生产来源。没有明确需求时，不修改候选生成、资格判断、评分、选择和统计口径。

### 3.2 当前事故恢复快照

下表是恢复时确认的引用，不是以后创建新分支的模板。使用前仍须执行只读检查：

| 分支 | 恢复/确认提交 | 说明 |
| --- | --- | --- |
| `codex/ios-swiftui-native-app` | `f4f3a929` | 主工作区，存在用户未提交改动 |
| `codex/表达规划器影子接入` | `105c566e` | 生产 Shadow 源码来源 |
| `codex/表达规划器第二阶段` | `bd9c673d` | 研究分支，存在本地改动 |
| `codex/camera-fast-vision` | `613c1417` | `ingest-upload-stability` worktree |
| `codex/ingest-upload-stability` | `7b5b9bd8` | 分支引用已恢复，当前不作为发布基线 |
| `codex/ios-parity-fixes-2` | `92601e4f` | iOS 集成底座 |
| `codex/ios-pwa-parity-batch` | `f4f3a929` | 历史集成分支 |
| `codex/ios-shortcut-templates` | `96fe392f` | 快捷指令模板 |
| `codex/pwa-feedback-production` | `8392b633` | 生产反馈分支 |
| `codex/pending-privacy-review-fixes` | `f6db74a0` | 当前 Draft PR #10 发布候选，存在未提交改动 |
| `codex/release-integration` | `e112794f` | 发布历史分支；不要与 `release-integration` 目录名混淆 |
| `codex/release-owner-backfill-fix` | `edc74f3d` | 已恢复引用 |
| `codex/release-smoke-consent-fix` | `0b38b8cb` | 已恢复引用 |
| `codex/remove-leaked-upload-token` | `377cbec3` | 凭据清理历史分支 |
| `codex/test-smoke-env-fix` | `ebbb8491` | 已恢复引用 |

### 3.3 开始任务前的只读检查

在 PowerShell 中执行，先记录输出再编辑：

```powershell
$ErrorActionPreference = 'Stop'
Get-Location
git rev-parse --show-toplevel
git branch --show-current
git rev-parse HEAD
git status --short --branch
git diff --name-only
git diff --cached --name-only
git worktree list --porcelain
git show-ref --heads
```

如果当前目录、分支、HEAD 或 dirty 文件与任务说明不一致，先停止。不要通过 reset、checkout、clean 或 stash 让状态“看起来干净”。

## 4. Worktree 使用规范

### 4.1 创建

创建前先确认目标目录不存在、分支没有被其他 worktree 使用，并且 `origin/main` 已通过只读 fetch 更新：

```powershell
git fetch origin main
git worktree add .worktrees/<short-purpose> -b codex/<short-purpose> origin/main
```

如果任务必须以某个发布 SHA 或 PR head 为基线，命令和交接文档必须写出完整 SHA，不得写“最新代码”。

### 4.2 使用

- 只在自己的 worktree 中编辑、测试和提交。
- 不进入其他 worktree 执行 `git status` 以外的写操作。
- 不在根工作区自动处理其他 Agent 的 dirty 文件；根工作区当前可能承载用户的 iOS/PWA WIP。
- 每次长时间工作前重新检查 `git branch --show-current` 和 `git rev-parse HEAD`，避免 IDE/终端切换目录后误操作。
- 不运行会扫描、重写或删除整个 `.git` 的同步脚本；任何引用同步工具必须先审查源码并获得所有者确认。

### 4.3 禁止的破坏性操作

没有用户明确授权时，禁止执行：

```text
git reset --hard
git clean -fd / git clean -fdx
git checkout -- <path>
git restore .
git switch -f
git branch -D <branch>
git update-ref -d <ref>
git pack-refs --all --prune
git reflog expire
git gc --prune=now
git worktree remove
git worktree prune
git push --force / git push --mirror
```

`git stash` 也不能作为默认“清理现场”手段。它会把用户改动移入共享仓库状态，容易被另一个 Agent 误取或覆盖；必须先取得明确授权并记录 stash 名称、文件清单和恢复责任人。

## 5. 编辑、测试和提交规范

### 5.1 编辑边界

- 手动修改使用 `apply_patch`，不要用脚本整树重写无关文件。
- 先查看目标文件和相邻调用，再修改根因；不借任务顺手格式化无关文件。
- 如果目标文件已经被其他 Agent 修改，先记录现状并协商，不覆盖、不回滚、不整文件选边。
- 不提交 `backups/`、`local-only/`、`reference/`、`.env*`、真实图片、原始 AI 日志、数据库 dump、签名 URL 或账号导出数据。

### 5.2 暂存

禁止用 `git add -A` 或 `git add .` 批量吞入其他 Agent 的文件。只暂存已经核对过的路径：

```powershell
git add -- path/to/file-a path/to/file-b
git diff --cached --stat
git diff --cached --check
git status --short --branch
```

提交前必须确认：

- staged 文件全部属于当前任务。
- 没有意外删除、重命名、二进制、私有文档或生成目录。
- 没有密钥、JWT、Service Role、个人访问令牌、真实用户 ID、图片和日志。
- `git diff --check` 和相关测试通过。

### 5.3 Commit message

使用现有 Conventional Commit 风格，类型与行为匹配，标题只表达一个逻辑变化：

```text
feat(inbox): 增加待补全记录快速下一条
fix(storage): 修复销毁后原图清理任务
security(auth): 收紧注册同意校验
ci(release): 固定 Supabase CLI 版本
docs(workflow): 补充 Agent worktree 交接规范
test(ingest): 覆盖感知重复进入中转站
```

建议的 commit body 写明：

- 为什么改以及用户可见影响。
- 涉及的状态机、迁移、Edge Function 或 iOS/PWA 边界。
- 运行过的测试及未运行的测试。
- 是否需要生产迁移、部署、TestFlight 或真机验收。
- 回滚方式，特别是数据库和 Storage 行为。

不要把多个独立功能、自动生成文件和私有素材塞进一个 commit。不要为了“让 CI 变绿”修改测试去掩盖真实失败。

### 5.4 Push 与 PR

- 只推送自己的 `codex/*` 分支：`git push -u origin <branch>`。
- 禁止直接推送 `main`，禁止强推共享分支。
- PR 目标固定为 `main`，标题、描述和 head SHA 必须能说明发布范围。
- Draft PR 用于持续验证；转 Ready 前检查 staged diff、生产状态、迁移 dry-run、备份和回滚方案。
- 合并后使用合并产生的固定 `main` SHA 作为部署和 TestFlight 来源，不复用旧工作树。

## 6. 当前 CI/CD 触发边界

以下是仓库当前 workflow 的真实行为，不能用“推送就会全部跑”代替：

| Workflow | 触发 | 作用 | 生产影响 |
| --- | --- | --- | --- |
| `release-validation.yml` | PR 指向 `main`、手动 | PWA/Trace Console 构建、Deno 检查、收据/Shadow/迁移/安全测试 | 无 |
| `ios-build.yml` | PR 指向 `main`、手动 | 检测 iOS 路径并在 macOS 上编译和单测；PR 通过 `iOS Build Gate` | 无 |
| `deploy.yml` | `main` 更新且函数/域/Planner 路径变化、手动 | 部署 `generate-insights` 和 `ingest-receipt`，固定 Supabase CLI `2.109.1`，做 GET 405 健康检查 | 有，属于生产部署 |
| `legal-pages.yml` | `main` 更新且法律页面变化、手动 | 部署 GitHub Pages 法律站点 | 有，更新公开法律页面 |
| `ios-testflight.yml` | 仅手动 | macOS 归档、签名、上传 TestFlight | 有，产生可测试构建 |

特别注意：

- iOS Build 当前没有 `push` 触发器；普通分支 push 不会自动编译，只有 PR 指向 `main` 或手动运行。
- `iOS Build Gate` 在 PR 中检测到 iOS 变更时必须要求构建成功；没有 iOS 变更时允许跳过构建。
- Edge Function 自动部署不等于数据库迁移自动执行。数据库迁移始终按发布检查点人工 dry-run、备份、授权和执行。
- `workflow_dispatch` 也可能触发生产动作；手动运行前必须核对 ref、SHA、Secrets 和用户授权。
- 当前 `main` 分支保护已要求 `PWA, Edge, migrations, and Shadow` 与 `iOS Build Gate`，并启用管理员执行；required PR reviews 当前为 0。正式生产前建议增加至少 1 名人工审查者。

## 7. 迁移与生产边界

- 活跃迁移文件必须使用纯数字版本和 ASCII 小写下划线名称；版本必须晚于线上最大 timestamp，不能使用 `079a`、中文文件名或插入历史的旧编号。
- 延后迁移只能放在 `supabase/deferred-migrations/`，使用未版本化的 `.template.sql` 名称；未经过审查不得移动到 `supabase/migrations/`。
- 每次变更运行 `node scripts/check-migration-versions.mjs`，确认无重复版本、无历史插入、无非法 deferred 文件。
- 生产前必须保存数据库/Storage/函数版本/迁移账本备份和 SHA-256；备份不进 Git。
- 先执行兼容型迁移，再部署兼容代码和生产冒烟；会拒绝旧客户端写入的硬约束必须后置并单独授权。
- Edge Function 回滚使用已归档的固定源码重新部署；Git revert 不会回滚数据库、Storage 对象或已执行 RPC。
- 数据库回滚必须写补偿 SQL，在 PostgreSQL 17 fixture 中验证后单独授权；禁止用 Git 操作假装完成数据库回滚。

## 8. 隐私和凭据规范

### 8.1 不允许的凭据路径

- 不在命令行参数中直接写 Service Role、JWT、Supabase personal access token、Apple key、P12 密码或 Qwen key。
- 不在 `git diff`、CI log、终端截图、PR、Issue、交接文档或测试 fixture 中打印真实值。
- 不把真实 `.env.local`、`accounts.json`、备份、Storage 下载和数据库 dump 放到可提交目录。
- 不因为 `.gitignore` 已忽略就认为磁盘安全；备份仍需加密和限制 ACL。

### 8.2 安全导入

本地 Supabase secrets 使用控制台，或使用已被 `.gitignore` 忽略的临时 env 文件导入。导入后立即删除临时文件并检查 `git status`。不要把真实值替换进 README 命令再执行。

GitHub Actions 只能从 repository/environment secrets 注入，日志必须保持默认掩码；不要用 `echo`、`set -x` 或错误信息打印 Secret。

### 8.3 发现泄露时

1. 立即停止传播，不复制、不转发、不提交、不在回复中复述值。
2. 记录凭据类型和来源，不记录值。
3. 由账户所有者轮换或撤销凭据，并更新所有消费者。
4. 检查 GitHub commit、Actions、shell history、MCP/Codex 配置和运行进程。
5. 如果已进入公共 Git 历史，先轮换，再由仓库所有者安排历史清理；清理需要 force push，不能由普通 Agent 擅自执行。

## 9. 分支引用事故处理

### 9.1 发现信号

以下任一情况都视为 P0 Git 事故：

- `git rev-parse HEAD` 返回全零或 `git status` 显示 `No commits yet`。
- 多个 worktree 同时出现全零 HEAD。
- `git show-ref --heads` 中大量 `codex/*` 消失。
- 分支 reflog 出现无法解释的零 SHA、批量删除或短时间反复重建。
- `.git/index`、`packed-refs` 或 worktree metadata 在无授权情况下变化。

### 9.2 响应步骤

1. 停止所有 Git 写操作；不要继续 merge、pull、commit、push、prune 或重复恢复。
2. 保存当前时间、cwd、分支、HEAD、status、worktree 列表和进程来源；输出中不得包含令牌。
3. 复制所有 dirty 文件到被忽略的事故目录，生成文件清单和 SHA-256；不要 reset 或 clean 原目录。
4. 只读执行 `git fsck --full --no-reflogs --unreachable --no-progress`、`git reflog`、`git show-ref` 和 `git cat-file -t <sha>`。
5. 以远程引用、reflog 和可验证 commit 为来源制作恢复表；每个 SHA 先确认类型为 `commit`。
6. 先停止造成删除的进程或自动化，再恢复引用。恢复操作必须由仓库所有者授权并记录 old/new SHA。
7. 恢复后连续观察引用，确认不再消失；不要把一次成功 `update-ref` 当作根因解决。
8. 复核每个 worktree 的 HEAD、branch、dirty 文件和 staged 文件；最后才允许继续编辑。

### 9.3 不可接受的“修复”

- 用 `git reset --hard` 让状态恢复正常。
- 删除并重新创建 worktree，掩盖用户未提交改动。
- 用远程同名分支覆盖本地分支而不比较 reflog。
- 把所有文件重新 `git add` 并提交，制造一份无法审计的大提交。
- 发现引用再次消失后继续自动循环恢复而不停止来源进程。

## 10. 交接模板

每个 Agent 结束工作时，在回复或任务日志中填写：

```text
任务目标：
工作目录：
分支：
HEAD（完整 SHA）：
基线来源（origin/main / 固定 SHA / PR head）：

本次修改：
- tracked 文件：
- untracked 文件：
- staged 文件：
- 未修改但存在的其他 Agent 文件：

验证：
- 命令：
- 结果：
- 未运行及原因：

生产状态：
- 是否合并 main：否/是，SHA：
- 是否部署 Edge/PWA/Legal：否/是，运行链接：
- 是否应用数据库迁移：否/是，版本：
- 是否触发 TestFlight：否/是，run id：

备份与隐私：
- 备份位置（只写目录，不写内容）：
- 校验结果：
- 是否包含真实用户数据：
- 凭据是否轮换/待轮换：

风险与下一步：
- 当前阻断：
- 明确不应执行的操作：
- 下一位 Agent 的第一条只读检查：
```

## 11. 发布前最小清单

- [ ] 目标 worktree、分支、HEAD 和 dirty 文件已记录。
- [ ] 发布 SHA 固定且与 PR head 一致。
- [ ] 只暂存本次文件，`git diff --cached --check` 通过。
- [ ] 没有凭据、真实用户数据、原图、AI 原文或 dump 进入 diff。
- [ ] PWA、Trace Console、Edge、Planner、迁移和安全检查通过。
- [ ] iOS 变更通过 macOS Build、单测和 `iOS Build Gate`。
- [ ] 迁移 dry-run 只包含预期 timestamp 迁移，无 deferred template 和历史重复。
- [ ] 生产数据库、Storage、函数源码和迁移账本备份完成并校验。
- [ ] 代码部署、数据库迁移、TestFlight 分别经过明确授权。
- [ ] 生产冒烟失败时停止后续动作，不叠加部署和迁移。
- [ ] 最终交接使用第 10 节模板，并明确下一步和禁止动作。
