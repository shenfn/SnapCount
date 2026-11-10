---
project: SnapCount
name: 本地 AI 记忆与 Planner 阶段一开发交接
updated: 2026-11-10
branch: feature/inbox-pwa-parity
head: c1ab044
status: 阶段一已完成，等待下一会话继续接线
tags: [handoff, ios, local-first, ai-companion, planner, memory]
---

# 本地 AI 记忆与 Planner 阶段一开发交接

## 1. 交接结论

App Store 首版采用单设备本地优先策略：

```text
本地事实 → 本地记忆 → 本地 Planner 候选 → Companion / 反馈卡片 → 本地导出恢复
```

本轮不新增业务数据同步。不要新增 `record`、`income` 或 `companion_memory` outbox，不修改 Supabase schema、RPC、Edge Function、多设备冲突协议。

新 profile 的同步保持关闭；新用户云端原图默认关闭；已有用户的明确设置不自动覆盖。

## 2. 本阶段已完成

### 2.1 数据库与记忆

- `LocalDatabase.migrator` 新增 `local-v33-companion-memories`。
- 新增 `local_companion_memories`：
  - profile 隔离；
  - `UNIQUE(profile_id, memory_key)`；
  - JSON object 校验；
  - `confidence` 取值范围校验；
  - source 索引；
  - 软删除和重新 upsert 恢复。
- 新增 `LocalCompanionMemoryRepository`：
  - `upsert`；
  - 按 key 读取；
  - 按 profile 读取有效记忆；
  - 按 key / source 软删除；
  - 输出大小受限的 `{"facts": [...]}` 上下文 JSON。

### 2.2 本地表达与 Planner

- 新增 `LocalExpressionContext`。
- 新增 `LocalPlannerCandidateEngine`。
- 候选统一使用 `NativeAIFeedback` 和 `NativeRecordExpressionFeedbackPolicy` 兼容字段。
- 候选包含稳定的 `candidate_id`、`semantic_key`、`claim_fingerprint`、`presentation_target`、`dimension` 和表达文本。
- 当前确定性 Planner 覆盖：
  - expense
  - income
  - food
  - sleep
  - sport
  - reading
  - wallet 候选结构已支持，但钱包详情还未完整接入

### 2.3 详情与 Inbox

- 本地 expense、income、food、sleep、sport、reading 详情已接入确定性 Planner 卡片。
- 本地 staging / Inbox 候选在没有云端 Planner 时也能生成本地反馈卡片。
- 本地反馈带 `local:` exposure 标识，不调用远端 acknowledge / feedback RPC。
- `companion_enabled = false` 时不生成新的本地 Planner。
- `companion_memory_enabled = false` 时不读取本地记忆上下文，但仍可基于当前事实生成确定性候选。

### 2.4 备份与导出

- `LocalCompleteBackupPortability.currentSchemaVersion` 从 28 升到 29。
- 完整备份加入 `local_companion_memories`。
- v28 及更早可接受的旧备份会自动补空记忆表。
- `LocalHistoryMigrationMapper` 生成的完整备份也包含空的记忆表。

## 3. 主要文件

- 数据库：`ios/SnapCount/LocalData/LocalDatabase.swift`
- 记忆：`ios/SnapCount/LocalData/LocalCompanionMemoryRepository.swift`
- 表达上下文和候选：`ios/SnapCount/LocalData/LocalExpressionContext.swift`
- 本地详情接线：`ios/SnapCount/App/AppState.swift`
- Inbox staging 接线：`ios/SnapCount/Features/Records/LocalStagingReadModel.swift`
- 完整备份：`ios/SnapCount/LocalData/LocalCompleteBackupPortability.swift`
- 历史迁移备份：`ios/SnapCount/LocalData/LocalHistoryMigrationMapper.swift`

## 4. 下一会话必须先读

1. `AGENTS.md`
2. `docs/spec/02-TDD实施与交接规范.md`
3. `docs/handoff/2026-11-09-本地配置记忆与同步开发交接.md`
4. `docs/spec/模块/iOS本地优先/本地AI陪伴与Planner候选域规格说明.md`
5. `docs/spec/模块/iOS本地优先/本地优先隐私配置与导出契约规格说明.md`
6. `docs/spec/执行记录/LOCAL-AI-003A-本地记忆数据层.md`

旧的 `Q-05` 文档已经加了 2026-11-10 覆盖说明。不要恢复“本地零实现”“仅确定性候选”或“隐藏点评”的旧范围。

## 5. 下一阶段开发顺序

### 5.1 写入后表达刷新

为以下路径增加统一的本地表达刷新入口：

- `LocalRecordRepository.createRecord` / `updateRecord` / `deleteRecord`；
- `archiveStaging`；
- expense 创建、编辑、删除；
- income 创建、编辑、删除；
- 待确认财务记录转正式记录；
- wallet snapshot 创建、编辑、删除。

要求：事实写入成功不依赖 AI；表达刷新失败不能回滚事实；刷新必须可重建。

### 5.2 表达结果持久化

- `local_records.payload_json` 保存 Companion 和 `ai_feedback`；
- `local_expenses` / `local_income_records` 使用已有 `companion_message`、`ai_feedback`；
- `local_staging_records.payload_json` 保存候选阶段结果；
- 待确认财务转正式时保留表达结果；
- 不保存原始 Prompt、原始模型响应、Token 或 API Key。

### 5.3 记忆投影生成

- 从 `LocalFactReader` 读取正式事实；
- 从用户明确配置和事实趋势生成结构化记忆；
- 使用 `LocalCompanionMemoryRepository.upsert`；
- 删除或编辑来源事实时调用 `deleteSource` 或重建投影；
- 记忆开关关闭时不读、不写记忆表。

### 5.4 Hosted / BYOK Companion

- 继续复用现有 Provider；
- Hosted 默认只发送当前请求所需的最小上下文；
- BYOK 可在用户允许时使用紧凑记忆上下文；
- Provider 失败时使用确定性 Planner 结果；
- 不把 AI 请求转成业务同步。

### 5.5 导入恢复

- 导入记忆、表达结果和候选状态；
- 新 profile 导入后保持同步关闭；
- 旧备份无记忆表时按空集合处理；
- 检查导出包不包含凭据、Token、API Key 和临时签名 URL。

## 6. 当前未完成项

- wallet 详情页的 Planner 展示。
- 写入路径自动生成和刷新记忆。
- Companion 文案结果的本地持久化和回放。
- Hosted / BYOK 与本地表达上下文的正式编排。
- 完整备份中 Companion / Planner 结果的实际恢复验证。
- macOS XCTest、iOS Build、真机和 TestFlight 回归。

## 7. 验证状态

- 已执行：`swiftc -parse` 语法检查。
- 已执行：`git diff --check`。
- 未执行：XCTest、iOS Build、macOS CI、真机验收、TestFlight。
- 当前工作区包含未提交文档和代码改动；`.build/` 是未跟踪构建产物，不要加入功能提交。

## 8. 下一会话交付标准

下一会话结束时至少应能说明：

1. 七类事实写入后是否都能刷新本地表达；
2. 记忆关闭时是否完全不读写记忆表；
3. Planner / Companion 是否能从备份恢复；
4. Provider 失败是否仍保留本地事实和确定性候选；
5. 是否有任何路径新增了同步 outbox 或远端业务写入。
