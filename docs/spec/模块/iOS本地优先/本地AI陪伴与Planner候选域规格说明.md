# 本地 AI 陪伴与 Planner 候选域规格说明

> 编号：LOCAL-AI-003
>
> 更新：2026-11-10
>
> 状态：已拍板，待实现

## 1. 目标

让本地优先记录在未登录、无业务同步的情况下仍能获得接近完整云端链路的两类能力：

1. Companion：根据当前事实和有限本地记忆生成陪伴文案与反馈；
2. Planner：从当前事实、近期事实和记忆中生成可解释的候选角度，并在本地详情和收件箱展示。

本规格不建立业务数据同步。Provider 请求和业务同步是两条不同的路径：Provider 只处理当前 AI 请求，业务事实、记忆和表达结果仍由本机持久化。

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
- 只输出当前 profile 的有效记忆；
- 删除或过期的记忆不进入上下文；
- 不输出原图路径、Prompt、模型原始响应和凭据。

## 4. Companion 规则

### 4.1 开关

- `companion_enabled = false`：不生成新的 Companion；已持久化文案仍可展示。
- `companion_memory_enabled = false`：不读、不写记忆；仍可基于当前事实生成 Companion。
- Provider 不可用：保留结构化事实，使用确定性反馈降级。

### 4.2 Provider

- BYOK Provider 可以使用 `current_fact + memory_context + planner_candidates` 生成 Voice；
- Hosted Provider 只接收当前请求所需的最小上下文，是否携带 `memory_context` 由《AI 供应方与 BYOK 安全契约》的 Provider 隐私策略和用户确认决定；默认不发送完整历史或整份个人上下文；
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

- Planner `feedback_card` 是独立反馈卡片；
- Planner `companion_message` 必须匹配当前可见 Companion 的 claim；
- Planner 不覆盖已经展示的 Voice 事实；
- 同一 claim 不重复渲染；
- 本地曝光确认只更新本机状态，不调用远端 acknowledge RPC。

## 6. 接入点

### 6.1 写入后

以下成功写入后触发表达刷新：

- `LocalRecordRepository.createRecord`、`updateRecord`、`deleteRecord`；
- `archiveStaging`；
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
| LOCAL-AI-003A | 未登录本地 food 记录 | Companion 可生成或确定性降级，Planner 候选可展示 |
| LOCAL-AI-003B | 本地 expense / income | 使用事实和近期摘要生成候选，不等待同步 |
| LOCAL-AI-003C | 本地 sleep / sport / reading | 候选域可见，claim 可回溯到事实 |
| LOCAL-AI-003D | wallet / staging | 只在候选状态展示，确认前不进入正式统计 |
| LOCAL-AI-003E | 关闭 Companion | 事实保存，新的 Companion 和 Planner 不生成 |
| LOCAL-AI-003F | 关闭记忆 | 不访问记忆表，不把记忆送入 Provider |
| LOCAL-AI-003G | Provider 失败 | 事实保留，确定性反馈继续可用 |
| LOCAL-AI-003H | 导出再导入 | Companion、Planner、记忆和候选状态保持一致 |
