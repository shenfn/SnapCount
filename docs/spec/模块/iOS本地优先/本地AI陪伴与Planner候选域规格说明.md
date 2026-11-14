# 本地 AI 陪伴与 Planner 候选域规格说明

> 编号：LOCAL-AI-003
>
> 更新：2026-11-14
>
> 状态：已拍板，图片链路已接入，待真机场景验收

## 1. 目标

让本地优先记录在未登录、无业务同步的情况下仍能获得接近完整云端链路的两类能力：

1. Companion：根据当前事实和有限本地记忆生成更贴合的陪伴文案；
2. Planner：从当前事实、近期事实和记忆中生成可解释的候选角度，作为 Companion 的内部上下文。

本规格不建立业务数据同步。Provider 请求和业务同步是两条不同的路径：Provider 只处理当前 AI 请求；业务事实、记忆和表达结果仍由本机持久化。本地 Planner 候选只用于生成和解释 Companion，不作为独立反馈卡展示。PWA 当前的云端 Planner 和 UI 不在本次 iOS 本地链路调整范围内。

## 2. 当前缺口

- 本地 `LocalFactReader` 已经能统一读取消费、收入和四域正式事实，但没有记忆上下文输出。
- 本地记录详情路径会直接返回，不会调用远端 `getRecordExpressionPlan`，所以未登录本地记录没有 Planner 候选。
- `NativeAIFeedback` 和 `NativeRecordExpressionFeedbackPolicy` 已有 Planner 的候选、去重和展示语义，应复用而不是创建第二套反馈模型。
- 本地识别和财务写入已有 `companion_message` / `ai_feedback` 持久化位置，应在此基础上扩展。

## 3. 本地表达管线

```text
LocalFactReader
    ↓
LocalMemoryRepository → CompactMemoryContext
    ↓
LocalPlannerCandidateEngine
    ↓
LocalExpressionContext
    ├── LocalCompanionComposer
    └── NativeAIFeedback / NativeRecordExpressionFeedbackPolicy
    ↓
LocalRecordReadModel / LocalFactReadModel / Inbox
```

### 3.1 `LocalExpressionContext`

必须包含：

- `current_fact`：当前记录的结构化事实；
- `recent_facts`：受时间窗和数量上限约束的近期事实；
- `memory_context`：仅在记忆开关开启且 Provider 策略允许时提供；
- `planner_candidates`：当前候选包；
- `provider_mode`：Hosted、BYOK 或确定性降级。

快捷指令图片路径当前不发送近期事实列表。记忆开启时，只额外发送最多 5 条本域旧陪伴文案用于去重；记忆关闭时，这些文案也不读取、不发送。

当前事实优先于记忆。记忆不能改变事实字段，也不能让模型补写当前记录没有的金额、时间、商户、频率或健康判断。

### 3.2 记忆上下文

记忆上下文只允许输出紧凑 JSON，例如：

```json
{
  "facts": [
    {"key": "food.preference", "value": "晚餐偏清淡", "confidence": 0.82},
    {"key": "sleep.trend", "value": "近 7 天平均睡眠偏少", "confidence": 0.71}
  ]
}
```

必须限制：

- 最大条数和最大字节数；
- Hosted 请求只带与当前事实同域的摘要，最多 8 条、每条最多 240 字；
- 只输出当前 profile 的有效记忆；
- 删除或过期的记忆不进入上下文；
- 不输出原图路径、Prompt、模型原始响应和凭据。

### 3.3 最终请求包合同（LOCAL-AI-003A-K 共用）

本地表达上下文只使用一个只读请求包。iOS 在 Hosted 和 BYOK 两条路径都先构造同一组字段，Hosted 通过 `generate_local_expression` 投影其中的请求字段，BYOK 将相同上下文放入本机 Provider 的 JSON facts。请求包的顶层字段如下：

```json
{
  "current_fact": {},
  "recent_facts": [],
  "memory_context": {"facts": []},
  "planner_candidates": [],
  "provider_mode": "hosted|byok|deterministic",
  "expression_preferences": {},
  "client_local_time": "YYYY-MM-DD HH:mm",
  "client_captured_at": "ISO-8601",
  "weekday": "周X",
  "recent_companion_lines": []
}
```

Shortcut 的 Hosted 线上请求保持现有入口语义，传输 `current_fact`、选中的 `planner_candidate`、可选的 `local_memory_context`、偏好和时间字段；`recent_facts` 与 `provider_mode` 仍是 iOS 本地上下文和 Edge 归一化所使用的路由元数据。不得因此扩展图片识别或 PWA 业务请求。

`current_fact` 是当前正式事实，`recent_facts` 只来自同 profile、同 domain 的正式事实，最多 12 条。`local_staging_records` 的 `pending_review`、`failed` 或已删除行不会进入这两个字段。事件时间按 `occurred_at`、`order_finished_at`、`record_date + record_time` 的顺序取值。`client_captured_at` 和请求接收时间只表示捕获/请求上下文，不得改写成事件发生时间。

`memory_context` 仅在 `companion_memory_enabled` 开启时读取和发送。它只允许当前 domain 的 key，最多 8 条，每条 `type` 最多 32 字、`summary` 最多 240 字，`confidence` 必须在 0…1。记忆关闭或归一化后为空时省略整个字段。`recent_companion_lines` 同样受记忆开关控制，最多 5 条，用于去重。

`planner_candidates` 的每项必须包含 `candidate_id`、`semantic_key`、`canonical_text`、`claim_fingerprint`、`dimension`、`source=expression_planner`、`evidence`、`numbers`、`count_numbers` 和 `number_facts`。`evidence` 最多 8 项，`numbers`、`count_numbers`、`number_facts` 各最多 8 项；候选文本最多 300 字，标识最多 200 字，证据 field 最多 80 字。证据 kind/source 使用 `current_fact/local_record`、`recent_fact/local_record`、`local_memory/local_memory`，每个 `number_fact` 必须带自己的 evidence。`claim_fingerprint` 是对 `{semantic_key, canonical_text}` 按键排序后使用 UTF-8 FNV-1a 64 的稳定指纹，格式为 `fnv1a64:<16位小写十六进制>`。

Provider 无法使用、候选验证失败或证据/指纹越界时，丢弃整个非法候选，保留 `current_fact` 并使用确定性 fallback。Edge 的 `plannerFallbackReason`/`trace.fallback_reason` 记录 `invalid_planner_candidate`、`candidate_bounds_exceeded`、具体合同校验原因或 `null`。fallback 不撤销事实写入，也不写入业务同步 outbox。

Hosted 和 BYOK 的结果在持久化前归一化为同一 schema。`companion_message` 是最多 30 字的可空主句，`ai_feedback` 为可空对象，字段固定为 `version=feedback-v1`、`domain_key`、`badge`、`icon`、`band`、`tone=ai_generated`、`emotion_line`、`utility_line`、`detail_reason`、`confidence`、`internal_score`、`source=hybrid`。`confidence < 0.5`、缺失 `emotion_line`/`confidence`、畸形类型或与最近表达重复时，`ai_feedback` 归一化为 `null`，不会产生第二套 Provider 合同。

通知和结果页都先保留稳定事实 fallback，再按 `companion_message`、`ai_feedback` 的顺序合并。重复的主句、情绪行、工具行和事实行只保留第一次出现。Shortcut 结果按 `status`/`record_type` 生成 `inbox/<id>` 或 `records/<kind>/<id>` route，点击通知只改变 AppState overlay/path。结果页可以显示 Companion 和反馈，但不显示带 `local:` 标识的独立 Planner 卡。重复重试必须复用稳定记录 ID/指纹，不重复正式记录、通知行或结果卡。


## 4. Companion 规则

### 4.1 开关

- `companion_enabled = false`：不生成新的 Companion；已持久化文案仍可展示。
- `companion_memory_enabled = false`：不读、不写记忆，也不把记忆送入任何 Provider；仍可基于当前事实生成 Companion。
- Provider 不可用：保留结构化事实，使用确定性反馈降级。

### 4.2 Provider

- BYOK Provider 可以使用 `current_fact + memory_context + planner_candidates` 生成 Voice；
- Hosted Provider 使用当前事实和选中的 Planner 候选；只有记忆开关开启时，才额外接收同域、限量的本地记忆摘要，以改善陪伴表达；服务端校验摘要结构和长度，不保存原始记忆上下文；
- Hosted 和 BYOK 均不得发送完整历史或整份个人上下文；模型输出的事实仍须由当前事实或明确的 Planner 候选支持；
- 快捷指令 `recognize_only` 只做图片识别并返回结构化事实，不读取云端 Companion 记忆、不调用 Voice；正式入账后由 iOS 设备在本机组合同域摘要，再调用 `generate_local_expression`；
- Hosted 本地文案请求必须使用登录用户 JWT；Shortcut `upload_token` 仅用于原有图片入口，不可用于文字生成鉴权；
- 无论 Provider 类型如何，记忆都不得进入业务同步 outbox；
- 原始响应不落本地业务表。

### 4.3 持久化

- `local_records.payload_json` 保存 `companion_message` 和 `ai_feedback`；
- `local_expenses`、`local_income_records` 使用已有列；
- `local_staging_records.payload_json` 保存候选阶段的表达结果；
- 待确认财务记录转正式记录时，表达结果随事实一并转移。

## 5. Planner 候选规则

### 5.1 覆盖域

候选引擎必须覆盖：

| 域 | 事实来源 | 首版允许的候选方向 |
| --- | --- | --- |
| `expense` | `local_expenses` | 当前消费、分类或近期频率 |
| `income` | `local_income_records` | 收入来源、周期或变化 |
| `food` | `local_records` | 结构化饮食事实和近期偏好 |
| `sleep` | `local_records` | 睡眠时长、作息趋势 |
| `sport` | `local_records` | 运动频率和连续性 |
| `reading` | `local_records` | 阅读主题和连续性 |
| `wallet` | 钱包快照 / staging | 账单、还款或负债事实 |

未确认的 `local_staging_records` 只能在收件箱中展示候选，不进入正式统计和记忆聚合。

### 5.2 候选结构

每个候选至少包含：

- `candidate_id`
- `semantic_key`
- `claim_fingerprint`
- `presentation_target`：`feedback_card` 或 `companion_message`
- `source`：固定为 `expression_planner`
- `dimension`
- `band`
- `emotion_line`
- `utility_line`
- `detail_reason`

候选必须能通过 `claim_fingerprint` 回溯到当前事实或记忆键。没有证据的候选直接丢弃。

### 5.3 展示与去重

复用 `NativeRecordExpressionFeedbackPolicy`：

- 本地 Planner `feedback_card` 只作为内部候选，不作为独立反馈卡片展示；远端 Planner 保持各端既有行为；
- Planner `companion_message` 必须匹配当前可见 Companion 的 claim；
- Planner 不覆盖已经展示的 Voice 事实；
- 同一 claim 不重复渲染；
- 本地曝光确认只更新本机状态，不调用远端 acknowledge RPC。

## 6. 接入点

### 6.1 写入后

以下成功写入后触发表达刷新：

- `LocalRecordRepository.createRecord`、`updateRecord`、`deleteRecord`；
- `archiveStaging`；
- OCR 财务 `archiveDirectly`；
- 消费、收入的创建、更新、删除；
- 待确认财务转正式事实。

事实写入和表达刷新分离。表达失败不能回滚事实；刷新任务必须可重建。

### 6.2 读取时

本地详情路径必须在构造 `NativeRecordDetail` 后调用本地 Planner：

- `local-data` / 本地 `data`；
- `local-expense` / 本地 `expense`；
- `local-income` / 本地 `income`；
- 本地钱包和待确认候选详情。

本地路径不得因为没有 session 而回退到远端 Planner，也不得静默丢弃已有的本地候选。

## 7. 验收场景

| 编号 | 场景 | 结果 |
| --- | --- | --- |
| LOCAL-AI-003A | 未登录本地 food 记录 | Companion 可生成或确定性降级；Planner 候选只在内部参与表达，不显示独立反馈卡 |
| LOCAL-AI-003B | 本地 expense / income | 使用事实和近期摘要生成候选，不等待同步；Hosted 仅接收同域摘要 |
| LOCAL-AI-003C | 本地 sleep / sport / reading | Planner 候选域可回溯到事实，并作为 Companion 内部上下文 |
| LOCAL-AI-003D | wallet / staging | 待确认事实只在收件箱展示；确认前不进入正式统计或记忆聚合 |
| LOCAL-AI-003E | 关闭 Companion | 事实保存，新的 Companion 和 Planner 不生成 |
| LOCAL-AI-003F | 关闭记忆 | 不访问记忆表，不把记忆送入 Provider |
| LOCAL-AI-003G | Provider 失败 | 事实保留，确定性反馈继续可用 |
| LOCAL-AI-003H | 导出再导入 | Companion、Planner、记忆和候选状态保持一致 |
| LOCAL-AI-003I | Hosted Companion 与记忆开关 | 开启时请求仅携带同域有界摘要，服务端将其作为背景上下文且不持久化；关闭时请求不含记忆字段 |
| LOCAL-AI-003J | 本地 Planner 反馈卡 | iOS 详情和收件箱不显示带 `local:` 标识的独立 Planner 反馈卡，生成后的 Companion 仍可使用当前事实、Planner 候选和允许的记忆上下文；PWA 云端流程不变 |
| LOCAL-AI-003K | Shortcut 正式入账后的本机记忆陪伴 | 识别只返回事实；自动入账后 Hosted 文字请求携带当前事实、同域本机摘要（仅开关开启时）、用户表达偏好和当前本地时间；待确认记录只在确认后生成；记忆关闭时不读/不发本机记忆；生成失败不影响事实保存；PWA 维持原流程 |

### 7.1 Task 6 回归验收矩阵

| 场景 | 回归入口 | 必须观察到的结果 |
| --- | --- | --- |
| LOCAL-AI-003A | `LocalExpressionPersistence.makeCompositionContext` + Hosted/BYOK provider | 未登录或无网络仍有当前事实、候选和确定性 fallback，Planner 只作为 Companion 内部上下文 |
| LOCAL-AI-003B | `LocalFactReader`、`LocalExpressionContext` | expense/income 近期正式事实最多 12 条，staging 不混入，Hosted 只收到同域摘要 |
| LOCAL-AI-003C | `LocalPlannerCandidateEngine` | food/sleep/sport/reading 候选 evidence 可回溯到正式事实，数字带 per-number provenance |
| LOCAL-AI-003D | `LocalFactReader` + staging confirmation retry | pending staging 不进入 formal context，确认两次返回同一稳定正式记录 |
| LOCAL-AI-003E | `LocalExpressionPersistence` settings gate | Companion 关闭时不构造表达 context，事实保存不受影响 |
| LOCAL-AI-003F | `makeCompositionContext` + request body capture | 记忆关闭时不访问 memory repository、不发送 `local_memory_context` 或最近文案 |
| LOCAL-AI-003G | Hosted/BYOK provider failure | Provider 错误可见，事实仍保留，已有 deterministic Planner feedback 不被清除 |
| LOCAL-AI-003H | complete backup/export portability tests | Companion、Planner、memory 和候选状态随本机完整备份导出/导入保持稳定 |
| LOCAL-AI-003I | Hosted action normalizer + `context-packet-v2` | memory 只带同域、有界摘要，Edge trace 记录 packet fingerprint、memory counts 和 fallback reason |
| LOCAL-AI-003J | notification/result-sheet seams | Companion 与固定事实合并去重，不渲染独立 `local:` Planner 卡，PWA 云端流程不变 |
| LOCAL-AI-003K | Shortcut result + AppState route + post-confirm composition | recognize-only 只返回事实，确认后再表达，通知 route 可重试且不重复行/卡，失败不影响入账 |
