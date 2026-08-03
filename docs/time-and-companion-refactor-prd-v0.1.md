# 时间与陪伴文案重构 PRD v0.1

- **状态**：Draft，待用户 review
- **作者**：芥舟
- **日期**：2026-08-03
- **基线**：`origin/main @ f72e63b0`
- **配套文档**：`docs/time-and-companion-refactor-handoff-v0.1.md`

---

## 1. 问题陈述

### 1.1 现象
星之柠 6.80 元这笔支出记录：
- 记录时间显示原始 UTC 字符串（不友好）
- 发生时间显示 `2026-08-01 23:46:31`（错误，应为 07:46:31）
- AI 陪伴文案称"给开发中转站的小额充值"（判决式表述）
- 重复检测提示"3 分钟内"（错误，实际差 16h32m）

### 1.2 根本矛盾
系统里"时间"没有类型，"事实"和"判断"没有边界。任何时区 bug 修完还会以别的形式复发；任何文案 bug 改完还会以别的记忆复发。

## 2. 目标

**主目标**：把"时间"抽成独立领域模块（`time-core`），前后端 iOS 三端同构；把"用户记忆"从"判决"降级为"信号"，只让通用规则/LLM 决定是否引用。

**非目标**：
- 不做 UI 视觉改造
- 不改 AI 算法主体，只改事实层与信号注入方式
- 不做 IAP、Sign in with Apple 等无关工作

## 3. 成功指标

| 指标 | 现状 | 目标 |
|---|---|---|
| `transactions.transaction_time` 与 `created_at` 时区一致 | ❌ | ✅（DB 生成列约束）|
| 前端 `new Date(str)` 出现次数（除 `time-core/`）| 未统计 | 0（ESLint 守护）|
| `detail_reason` 里"X 分钟内"由代码实时计算 | ❌ | ✅ |
| 陪伴文案不出现"记忆判决式"表述 | ❌ | ✅（人工样本审核）|
| iOS / PWA / Edge 三端 API 同名 | ❌ | ✅（`formatDisplay`/`diffHuman`/`parseInstant`）|

## 4. 设计原则

1. **内部一律 Instant（UTC epochMs）+ IANA tz**，边界（UI/AI/DB）才格式化
2. **事实层由代码算好后再交给 LLM**，禁止让 LLM 生成时间距离词
3. **记忆是信号不是判决**：任何单一记忆命中都不允许直接改写 badge / detail_reason
4. **同名 API 跨端**：`formatDisplay(instant, tz) → string`、`diffHuman(a, b) → "16 小时前"`、`parseInstant(iso|ymd, tz) → Instant`
5. **渐进式**：DB 迁移放最后，前端展示先修，事实层再修，DB 最后切

## 5. 分阶段任务清单

### 🔴 P0 — 半天内（前端展示 + 硬编码降级）

| # | 任务 | 涉及文件 | 验收 |
|---|---|---|---|
| P0-1 | 新建 `src/lib/time-core/{instant,zonedDateTime,format,parse,index}.js`，仅导出 `formatDisplay/formatDateKey/diffHuman/parseInstant` 4 个 API | 新增目录 | 单元测试通过 |
| P0-2 | `src/utils/helpers.js` 中 `formatDate/formatDateTimeLabel/getLocalDateKey` 改为薄壳 re-export；删除 `new Date(dateStr + 'T00:00:00')` | 修改 | 前端页面无回归 |
| P0-3 | `PageRecordDetail.vue` "记录时间"改用 `formatDisplay(record.created_at, 'Asia/Shanghai')` | 修改 | 星之柠这笔显示 07:46 |
| P0-4 | "发生时间"暂时改从 `record.created_at` 派生（`transaction_time` 数据坏，P2 修好后切回） | 修改 | 星之柠这笔显示 07:46 |
| P0-5 | `index.ts:2308-2331` 硬编码 `isDevelopmentRelay` 分支降级为 `signals.push({ kind:'memory_hint:development_relay', weight, source_memory_key })`，不再改写 badge/detail_reason | Edge Function | 星之柠 detail_reason 不再出现"明确为开发模型 API 中转站" |

**风险**：P0-5 需要发 Edge Function，需用户明确授权部署时机。

### 🟠 P1 — 一天（Edge 事实层同构）

| # | 任务 | 涉及文件 |
|---|---|---|
| P1-1 | `supabase/functions/_shared/time-core/{index,format,parse,diff}.ts` 同构 P0 时间层 | 新增 |
| P1-2 | `normalizeAiDateTime` 返回 `{ instant, iana, iso }`，废弃 `{date, time}` 裸字段 | `time.ts` |
| P1-3 | 重复/临近判定文案改由 `diffHuman(now, historical.instant)` 计算，LLM 只接收结构化事实字符串 | `expression-shadow-planner.ts` / `realtime-expense-profile.ts` / `prompts.ts` |
| P1-4 | `voice-memory.ts` 记忆包成 `{ kind, text, weight, expires? }`；规则 builder 决定引用 | `voice-memory.ts` / `index.ts::buildMerchantRepeatRuleFeedback` |
| P1-5 | Prompt 增加铁律："memory_hint 只作参考，emotion_line 与 detail_reason 保持事实/判断分层" | `prompts.ts` |

### 🟡 P2 — 两三天（DB 迁移，一次性做对）

| # | 任务 |
|---|---|
| P2-1 | 迁移：`transactions ADD COLUMN occurred_at timestamptz NOT NULL DEFAULT NOW(), ADD COLUMN user_tz text DEFAULT 'Asia/Shanghai'` |
| P2-2 | 回填：`UPDATE ... SET occurred_at = (transaction_date::text || ' ' || COALESCE(transaction_time,'12:00:00')) AT TIME ZONE 'Asia/Shanghai'`，逐用户核对 |
| P2-3 | `transaction_date/time` 改生成列 `GENERATED ALWAYS AS ((occurred_at AT TIME ZONE user_tz)::date/time) STORED` |
| P2-4 | Edge 写入路径改写 `occurred_at`；前端读路径改用 `occurred_at` |
| P2-5 | 一致性告警：`ABS(EXTRACT EPOCH FROM (transaction_date - created_at::date)) > 12h` 记 warning 日志 |

### 🟢 P3 — 一周（iOS + 守护）

| # | 任务 |
|---|---|
| P3-1 | `ios/SnapCount/TimeCore/TimeCore.swift` 同名 API |
| P3-2 | ESLint：`no-restricted-syntax` 禁 `new Date(` 出现在 `src/` 除 `time-core/` |
| P3-3 | 用户"文案不准"举报：给 `memory_key` 打 `disputed` 标签，规则层跳过 |

## 6. 数据库迁移草案

```sql
-- migration: 20260805_time_core_facts_up
BEGIN;

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS occurred_at timestamptz,
  ADD COLUMN IF NOT EXISTS user_tz text NOT NULL DEFAULT 'Asia/Shanghai';

-- 回填（需要按 user 分批，此处仅示意）
UPDATE transactions
   SET occurred_at = ((transaction_date::text || ' ' || COALESCE(transaction_time::text,'12:00:00'))::timestamp
                       AT TIME ZONE user_tz)
 WHERE occurred_at IS NULL;

-- 校验通过后再改 NOT NULL 与生成列（分两个迁移）
COMMIT;
```

## 7. 回滚策略

- P0 全部为文件级改动，`git revert` 即可
- P1 Edge 部署走 CI 的旧版回滚
- P2 DB 迁移**必须**配套 down 脚本，且回填前先 `pg_dump` 关键表
- P3 无需回滚

## 8. 测试计划

- P0：`time-core/*.test.js` 单测（时区边界、跨日、闰秒兜底）
- P1：`ingest-receipt/*.test.ts` 契约测试（`memory_hint` 不再改写 badge）
- P2：回填脚本先在 staging 跑，抽 100 条人工对拍
- E2E：以星之柠 6.80 元这笔为 golden case，走完录入→展示全链路

## 9. 开放问题

- 用户争议标签 UI 落哪个入口？（记录详情页 or 设置页反馈）
- 海外用户默认 `user_tz` 从哪里推断？（浏览器 `Intl` 首次登录固化 + 设置页可改）
- iOS `TimeCore.swift` 是否引用 `swift-composable-architecture` 或纯 Foundation？（倾向纯 Foundation，无新依赖）

## 10. 决策记录

- 2026-08-01：确认两个问题必须一起改
- 2026-08-02：Git 事故导致开工暂停
- 2026-08-03：PRD/交接文档落盘，等待用户 review + Git 恢复决策
