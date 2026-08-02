# 历史回放使用说明

## 目标

从 Supabase 历史数据重建某个用户在指定时间点之前可见的上下文，避免使用未来画像。

## 运行

```powershell
node --env-file=.env.local tools/ai-validation/expression-planner/replay-history.mjs `
  --user-id=<uuid> `
  --as-of=2026-07-12T23:59:59+08:00 `
  --merchant="Example API Hub" `
  --trace-run-id=expression-planner-20260712-example-api-hub
```

## 输出

默认写入：

```text
test-results/expression-planner/replays/*.context.snapshot.json
```

`test-results/` 已被 Git 忽略。脚本只读 Supabase，不执行写入、更新或删除。

## 当前边界

- 第一版只回放 `transactions` 与关联 `ai_recognition_logs`。
- 当前实体归一化使用显式别名配置，不覆盖数据库原始字段。
- 商户语义意图不由别名配置推断，后续从确认后的 Semantic Memory 输入。
- 当前只生成上下文、汇总和数据审计，不生成候选评分或最终文案。

## 2026-07-12 验证基线

以下结果使用合成标识说明回放结构。真实账号、商户和事件覆盖仅保存在 Git 忽略的本地配置与快照中。

以 `<user-uuid>` 和实体 `merchant_example_api_hub` 回放至 `2026-07-12T23:59:59+08:00`：

- 识别事件共 4 条，其中 2 条为 `confirmed_transaction`，2 条经点评覆盖为 `user_confirmed_distinct`。
- 事实计算共计 4 笔、45 元，金额结构为 `10、10、10、15` 元。
- 两条误去重事件保留原机器判断证据，用户决定仅覆盖账本状态，不改写 Supabase。
- 时间跨度为 630 分钟；由于前两条缺少业务发生时间并回退到 `known_at_proxy`，该候选置信度为 `0.55`、数据完整度为 `0.25`。
- 测试样例中的 631 分钟来自固定示例时间 `12:46 → 23:17`，不应作为真实回放预期。

## 下一步边界

在开始评分和大模型措辞前，先完成追踪台导出：

- 将事件账本映射为 `event_ledger_build` step。
- 将事实候选映射为 `fact_candidate_generate` step。
- 完整数组放入顶层 `artifacts.event_ledger` 与 `artifacts.fact_candidates`。
- `artifact_refs` 只引用顶层 key，不使用点号嵌套路径。
- 下一类候选优先实现 `comparison`；暂不实现评分、个性化和最终文案。

## 追踪台导出

历史回放现在同时生成三类文件：

- `*.context.snapshot.json`：完整、领域原生的历史回放快照。
- `test-results/<run-id>/**/*.trace.json`：追踪台兼容的审计视图。
- `test-results/<run-id>/summary.json`：追踪台批次摘要。

默认 run ID 使用 `expression-planner-<日期>-<实体>`，也可通过 `--trace-run-id=<id>` 指定。启动 `npm run trace:console` 后即可从批次列表进入。

当前 trace 包含两个阶段：

- `event_ledger_build`：展示事件状态分布、用户覆盖和时间回退损耗。
- `fact_candidate_generate`：展示事实候选数量、维度及完整候选 artifact。

追踪台文件是 snapshot 的派生视图，不参与事实计算，也不会写入 Supabase。


## Comparison v0.1

第一版比较候选只生成确定性数值主张，不解释行为原因：

- `merchant_daily_vs_active_day_median`：当前日对比历史活跃日中位数。至少需要 3 个历史活跃日；无交易日不进入中位数，避免把“是否使用”与“使用强度”混为一谈。
- `merchant_week_to_date_vs_previous_week_same_period`：本周截至当前日期对比上周相同已流逝天数。不会把半周与完整周直接比较。

当前日使用 recognition ledger，历史日期使用正式 transactions。这样点评确认的误去重事件能够进入当天口径，同时避免与当天已经正式落库的记录重复计算。

2026-07-12 合成 API 中转站验证结果：

- 当天 4 笔、45 元；16 个历史活跃日的中位数为 1.5 笔、15.5 元。
- 本周 2026-07-06 至 2026-07-12 共 20 笔、251 元；上周同期 9 笔、93 元。
- 以上只说明调用/消费记录的数量与金额变化，不能单独推出开发效率、工作质量或消费动机。

## Eligibility Gates v0.1

资格层将两个问题分开：

1. `eligibility.eligible`：证据是否足以支撑该主张。
2. `eligibility.surface_eligibility`：该主张适合出现在哪个展示位置。

硬门槛检查结构化主张、证据、数字推导、置信度、数据完整度以及比较窗口。它不使用变化幅度作为淘汰条件，因此“小变化但数字准确”的事实仍可保留，是否值得优先展示交给后续评分层。

第一版展示位置门槛：

- 快捷指令通知：`confidence >= 0.8` 且 `data_coverage >= 0.75`。
- AI 弹窗：`confidence >= 0.7` 且 `data_coverage >= 0.5`。
- 记录详情页：`confidence >= 0.5` 且 `data_coverage >= 0.2`。
- 周报：`confidence >= 0.6` 且 `data_coverage >= 0.5`。

2026-07-12 的 5 条候选都通过主张资格；时间跨度候选因 `confidence=0.55`、`data_coverage=0.25` 只允许进入记录详情页，其余 4 条进入后续评分候选池。

## Deterministic Scoring v0.1

第一版评分使用完全透明的确定性公式：

```text
display_score =
  100
  × importance
  × relevance
  × confidence
  × novelty
  × user_preference
  - repetition_penalty
  - interruption_cost
```

每个候选保存全部乘数、扣分项、原始分、展示位置分数、阈值和是否过线。当前没有读取偏好记忆和历史曝光，因此使用：

- `user_preference = 1`，来源标记为 `neutral_default`。
- `novelty = 1`、`repetition_penalty = 0`，来源标记为 `empty_baseline`。

第一版重要性按 semantic key 显式配置，不由模型决定。偏好倍率限制在 `0.6–1.2`；偶尔重复会逐步降分，不会因为重复一次就直接排除。

2026-07-12 合成 API 中转站基线结果：

- 快捷指令通知：日次数与金额事实 78 分，周同期比较 75.4 分，二者过 75 分阈值。
- AI 弹窗：日事实 84 分、周同期 81.4 分、活跃日基线 73.2 分过线。
- 记录详情：4 条候选过线；低置信时间跨度为 31.9 分，未过 45 分阈值。
- 周报：4 条候选过线。

评分只回答“候选在某位置有多值得展示”，还没有决定最终说哪一条、组合几条以及是否使用精确事实兜底。该决策属于下一层 Expression Plan。

## Expression Plan v0.1

Expression Plan 根据现有产品固定槽位、位置容量和评分结果决定最终候选，不生成最终自然语言。

当前容量：

- 快捷指令通知：固定保留归档状态、本次记录和今日累计；最多选择 1 条额外候选。
- AI 弹窗：固定保留归档状态、目标域和本次记录；最多选择 1 个主方向。
- 记录详情：最多选择 3 个角度。
- 周报：最多选择 4 个角度。

快捷通知的固定 `今日已花 X（N 笔）` 已覆盖 `merchant_daily_count_total`，因此合成 API 中转站样本不会再次重复该事实，而是选择 75.4 分的周同期比较。AI 弹窗选择 84 分的日汇总事实；记录详情选择日汇总、周同期和历史活跃日基线三个角度。

通知和 AI 弹窗在没有候选过线时允许使用精确 aggregated/observed fact 兜底，避免无意义沉默。固定内容已覆盖的事实不能作为兜底重复出现。

现有 UI 容量和重构建议见 `docs/expression-planner-surface-capacity-v0.1.md`。

## Render Contract 与 Exposure v0.1

真实展示位置统一为：

- `shortcut_notification`
- `pwa_pending_ai_card`
- `record_detail`
- `weekly_report`

不再把快捷指令通知和一个不存在的独立 AI 弹窗重复计算。

Render Contract 为每个位置区分默认可见、展开可见和仅持久化字段。历史回放生成的曝光事件全部标记为 `rendered_preview`、`simulation_only=true`、`counts_for_novelty=false`，不会污染真实重复次数。

追踪台也已修正：只有实际 notification payload 进入“实际返回输出”；companion_message、完整 ai_feedback 和系统推断不再因为被生成或保存就自动标记为用户已看到。

完整生命周期见 `docs/expression-render-exposure-lifecycle-v0.1.md`。

## Exposure Ledger DB Draft v0.1

真实曝光数据库契约已形成草案，但未应用：

`tools/ai-validation/expression-planner/sql/068_expression_exposure_events.draft.sql`

草案采用 append-only、service_role-only write、authenticated own-row read。生产表拒绝 simulation event 和 `local_dry_run_preview` 来源。

本地生产形状预览工具：

```powershell
node tools/ai-validation/expression-planner/preview-exposure-insert.mjs `
  --snapshot=<snapshot.json> `
  --user-id=<uuid> `
  --surface=shortcut_notification `
  --delivery-attempt-id=<id>
```

该工具只写入 `test-results`，输出明确包含 `insert_executed=false`。完整数据库契约见 `docs/expression-exposure-ledger-db-contract-v0.1.md`。
