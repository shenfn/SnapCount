# 时间与陪伴文案重构 — 交接文档 v0.1

- **状态**：核心实现已在 `codex/陪伴候选统一出口` 收口；本文的国际多时区部分暂缓
- **建立日期**：2026-08-03
- **责任 Agent**：芥舟
- **对应 PRD**：`docs/time-and-companion-refactor-prd-v0.1.md`
- **目标基线**：`origin/main @ f72e63b0`
- **建议工作分支**：`codex/time-companion-refactor`（尚未成功创建）

---

## 1. 背景（一句话）

星之柠 6.80 元这笔记录暴露出两类系统性缺陷：**时间层事实错位**（`transaction_time` 存了 UTC 时分却和北京日期拼接）和**判断层混淆事实**（用户点评被硬编码正则转成"判决式"文案）。这两个问题必须一次性从架构上解决，否则会持续渗漏。

## 2. 触发案例（含 MCP 查证）

| 事实 | 数据库真值 |
|---|---|
| `transactions.created_at` | `2026-07-31 23:46:31 UTC` = 北京 08-01 07:46 ✅ |
| `transactions.transaction_date` | `2026-08-01` ✅（北京日期正确）|
| `transactions.transaction_time` | `23:46:31` ❌（**存的是 UTC 时分**）|
| AI 原始 `occurred_at` | `2026-08-01T07:45:00+08:00` ✅ |
| 命中的高权重记忆 | `merchant_context:qlhazycoder`，weight=5.0，content="QLHazyCoder 数字中心是用户开发时调用不同模型的 API 中转站……" |
| `staging_record` | id=`19ca7b77-…`, status=`archived`, review_reason=`possible_duplicate`（**误判**：实际时间差 16h32m，但 `detail_reason` 写"3 分钟内"）|

## 3. 根因定位（含代码坐标）

### 3.1 时间层
- **写入路径**：`supabase/functions/ingest-receipt/time.ts::normalizeAiDateTime` 返回 `{ date, time }`，其中 `time` 取自 ISO 中间段字符串，未按用户时区还原。
- **DB Schema**：`transactions` 表**没有** `occurred_at timestamptz`；只有 `transaction_date date` + `transaction_time time`，且两者没有强约束一致来源。
- **前端展示**：`src/utils/helpers.js::formatDate` 用 `new Date(dateStr + 'T00:00:00')`，隐式吃系统时区，海外必炸。
- **PageRecordDetail.vue**：直接把 `created_at` 原始 UTC 字符串塞进"记录时间"栏。

### 3.2 陪伴文案 / 记忆判决化
- **`supabase/functions/ingest-receipt/index.ts:2308-2331`**：硬编码正则 `/(开发|编程|代码).*(API|模型|中转站)|.../i` 命中记忆后强制 `isDevelopmentRelay=true` → 直接写 `badge="开发充值"` + `detail_reason="商户用途记忆明确为开发模型 API 中转站……"`。
- **`prompts.ts:406-408`**：memoryBlock 原文注入 LLM，"开发中转站"文案由此产生（不是模型联想）。
- **`voice-memory.ts::memoryMatchesMerchant`**：通过 `evidence.merchant_aliases` 别名把 `qlhazycoder` 挂到"星之柠"（这一步合理）。

## 4. 分阶段执行计划

见 PRD §5。摘要：

| 阶段 | 内容 | 影响面 | 依赖 |
|---|---|---|---|
| **P0**（半天） | `src/lib/time-core/` 骨架 + helpers 迁移 + PageRecordDetail 展示修复 + `isDevelopmentRelay` 硬编码降级为 signal | 前端 3-4 文件 + 1 处 Edge | — |
| **P1**（一天） | `_shared/time-core/` TS 同构；`normalizeAiDateTime` 改结构化；时间差事实化；记忆信号化 | Edge 主流程 | P0 |
| **P2**（两三天）| DB 迁移：`occurred_at timestamptz` + 回填 + 生成列改造 | 一次性 SQL | P1 |
| **P3**（一周） | iOS `TimeCore.swift` + ESLint 守护 + 用户争议标签 + 一致性告警 | iOS + 工具 | P2 |

## 5. 已完成的准备工作

- ✅ MCP 查证 `transactions` 表结构、`staging_records`、`user_companion_memories` 命中项
- ✅ 定位所有关键代码坐标（见 §3）
- ✅ 方案文档（本文档 + PRD）
- ✅ Git 规范只读检查

## 6. 未完成 / 阻塞项

- ❌ **`codex/time-companion-refactor` 分支创建失败**（见 §7）
- ❌ 代码 0 行修改
- ❌ 未运行任何测试

## 7. Git 写入异常（P0 阻塞）

**时间**：2026-08-02 13:20-13:24
**症状**：
```
$ git worktree add .worktrees/time-companion-refactor -b codex/time-companion-refactor origin/main
# exit=0，"branch set up to track" 但目录未创建

$ git branch codex/time-companion-refactor origin/main
# exit=0，但 show-ref/for-each-ref/packed-refs/refs/heads 全部查不到

$ git update-ref refs/heads/codex/time-companion-refactor <sha>
# exit=0，ref 依然未持久化
```

**副作用**：`.git/config` 里残留 2 行 `branch.codex/time-companion-refactor.remote/merge` 孤立配置（可安全 unset）。

**未损伤**：
- 仓库对象库、其他 11 个 codex/* 分支、3 个 worktree HEAD 均正常
- 没有 lock 文件、没有 gone 分支、fsck 通过

**可疑因素**：
- `.git/fsmonitor--daemon/` 存在，`core.fscache=true`
- Windows + `core.ignorecase=true` + 带斜杠的新 ref name

**恢复动作（用户择一）**：
- **A**：用户在自己终端手工重复同一命令，看是否复现
- **B**：先 `git config --unset-all branch.codex/time-companion-refactor.{remote,merge}`，然后换分支名（如 `codex/refactor-time-2026-08-03`）重试
- **C**：重启 fsmonitor daemon 后重试

## 8. 严格红线

- ❌ 不 `git gc` / `git pack-refs --prune` / 手改 packed-refs
- ❌ 不 force push / reset --hard / clean -fd
- ❌ 不动 iOS 视觉分支、不动数据库迁移（除 P2 明确迁移）
- ❌ 不在根工作区改代码
- ❌ 未经明确授权不部署 Edge Function、不上 TestFlight

## 9. 起手式（Git 恢复后）

```bash
cd D:/Business/count
git fetch origin main
git worktree add .worktrees/time-companion-refactor -b codex/time-companion-refactor origin/main
cd .worktrees/time-companion-refactor
# 按 PRD §5 P0-1 起步
```

## 10. 相关文件索引

- PRD：`docs/time-and-companion-refactor-prd-v0.1.md`
- Git 规范：`.worktrees/release-integration/docs/agent-git-worktree-handoff.md`（已归档，同步在 `docs/agent-git-worktree-handoff.md`）
- 恢复点：`D:\Business\count-final-cleanup-20260802\`
- 事故记录：`.workbuddy/memory/2026-08-02.md`
- 案例数据：`transactions` 表 merchant='星之柠网络科技工作室' 最新一笔

## 11. 2026-08-08 决策更新

- 本轮不继续推进用户时区配置、IANA 时区持久化或 DST 迁移；当前线上契约固定为 `Asia/Shanghai`。
- 已采用 `occurred_at`（业务发生时刻）与 `client_captured_at`（上传时刻）双时间模型。发生时刻缺失时保持未知，不以上传时刻代替。
- PWA/iOS 已按“发生时间、上传时间”分开显示；Edge Prompt、Voice 和最终清洗均以代码生成的 `TimeContext` 为唯一时段依据。
- 本文第 4 节的 P0-P3 原计划作为历史记录保留，不代表本批次仍需按旧顺序重做；后续国际化应另开版本化设计和迁移计划。
