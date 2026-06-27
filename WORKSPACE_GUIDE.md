# 工作区分区指南

这份文档用于约束后续人工和 AI Agent 在本仓库中新建文件的位置，目标是减少根目录堆积、避免误提交隐私素材，并让正式代码、开发工具、文档和本地材料边界清晰。

## 核心原则

任何新增文件前，先判断它属于以下哪一类：

- 正式产品代码
- 正式后端 / 数据库 / Edge Function
- 可复用开发工具
- 可提交的正式文档
- 本地私有材料
- 临时草稿或历史归档

如果无法判断，不要直接放到项目根目录，先说明用途再决定位置。

## 推荐目录

| 目录 | 用途 | 是否提交 |
|---|---|---|
| `src/` | 正式前端 PWA 代码 | 是 |
| `supabase/` | Supabase migrations、Edge Functions、数据库相关代码 | 是 |
| `cloudflare-worker/` | Cloudflare Worker / 代理相关代码 | 是 |
| `scripts/` | 仓库级可复用脚本 | 是 |
| `tools/` | 开发工具、测试工具、未来后台工具雏形 | 是，前提是不含隐私数据 |
| `docs/` | 可公开或可随仓库维护的正式文档 | 是 |
| `local-only/` | 本地私有材料、测试图片、真实截图、临时输入 | 否 |
| `本地私有/` | `local-only/` 的中文等价目录 | 否 |
| `archive/` | 暂时不删但不希望进入仓库的历史材料 | 否 |

## AI 本地验证功能建议位置

工具代码可以进入仓库，测试素材和结果不能进入仓库。

推荐长期结构：

```text
tools/
  ai-validation/
    README.md
    scripts/
    server/
    ui/
    docs/

local-only/
  ai-validation/
    test-cases/
    test-results/
    references/
```

当前阶段可以先保留已有脚本位置，但后续如果要做 Web 页面或后台雏形，优先放入 `tools/ai-validation/`，不要继续散落到项目根目录。

## 禁止提交

以下内容默认不得提交：

- `.env`、`.env.local`、各类密钥、token、service role key
- `test-cases/`、`test-results/`、`.ai-validation-cache/`
- 真实截图、真实账单、测试照片、用户隐私素材
- `local-only/`、`本地私有/`、`archive/`
- agent 缓存目录，例如 `.claude/`、`.superpowers/`、`.tmp/`
- 临时原型 HTML、一次性草稿、下载素材

## Git 操作提醒

- 本地可以小步 commit，但 push 前必须说明会推哪些 commit、是否触发部署、最大风险是什么。
- 如果工作区里有大量 untracked 文件，只能精确 add 当前任务相关文件。
- 不要用 `git add .`。
- 不要为了“清理干净”删除或回退不属于当前任务的文件。
- 提交前必须实际读取/复审本次要提交的文件内容，不能只根据文件名、`git status` 或记忆判断文件用途。
- 如果某个文件内容没有读过，或者不确定是否属于当前任务，不要把它加入 commit。

## 新文件放置规则

新增文件时按这个顺序判断：

1. 会影响正式用户运行吗？放 `src/`、`supabase/` 或 `cloudflare-worker/`。
2. 是可复用工具吗？放 `scripts/` 或 `tools/`。
3. 是正式说明、计划、交接文档吗？放 `docs/`。
4. 是隐私素材、测试输入、实验结果吗？放 `local-only/` 或 `本地私有/`。
5. 是暂时不删但不继续维护的旧材料吗？放 `archive/`。

根目录只保留项目入口级文件，例如 `README.md`、`package.json`、`vite.config.js`、`WORKSPACE_GUIDE.md`。
