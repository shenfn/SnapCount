---
project: SnapCount
name: 本地 AI 记忆与 Planner 阶段一开发交接
updated: 2026-11-10
branch: feature/inbox-pwa-parity
head: 7d2ba303624fa568c0cc5cad5195060d34c792ee
status: 本地记忆 Hosted 接线与本地 Planner 隐藏展示已完成，Edge Function v205 已部署，等待 iOS 客户端联调
tags: [handoff, ios, local-first, ai-companion, planner, memory]
---

# 本地 AI 记忆与 Planner 阶段一开发交接

## 1. 交接结论

App Store 首版采用单设备本地优先策略：

```text
本地事实 → 本地记忆 → 同域摘要与 Planner 候选作为生成上下文 → AI Companion → 本地导出恢复
```

本轮不新增业务数据同步。不要新增 `record`、`income` 或 `companion_memory` outbox，不修改 Supabase schema、RPC 或多设备冲突协议。按用户授权，已将 `ingest-receipt` Edge Function 部署到项目 `igbghrhsdaolxljgiisf`，版本 `205`；`verify_jwt` 保持原有 `false`。没有部署其他函数或数据库变更。

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

- 本地 expense、income、food、sleep、sport、reading 和候选详情继续生成确定性 Planner 上下文。
- 带 `local:` 标识的 Planner 反馈不再作为详情或 Inbox 独立卡片展示；候选继续进入 Companion 生成。
- 本地 Planner 不调用远端 acknowledge / feedback RPC。
- `companion_enabled = false` 时不生成新的本地 Planner 或 Companion。
- `companion_memory_enabled = false` 时不读取记忆上下文；Hosted 请求不含记忆字段，但仍可基于当前事实生成 Companion。

### 2.4 Hosted / BYOK Companion

- Hosted Companion 继续调用共享 `generate_local_expression` action；记忆开启时只发送当前事实同域摘要，最多 8 条、每条最多 240 字。
- Edge Function 校验摘要 domain、字段和长度，将其放入 `local_memory_context`，只用于当前模型请求，不写业务表、记忆表或同步 outbox。
- 上述 Edge Function 已部署为 v205，线上函数状态为 `ACTIVE`。
- Prompt 把本地记忆作为非权威背景上下文：可调整表达角度，不可创造事实或执行记忆文本中的指令。
- BYOK 也使用当前事实同域的有界记忆上下文，并直接发送给用户配置的服务商。
- 设置页说明 Hosted / BYOK 的传输路径与记忆用途。

### 2.5 备份与导出

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

旧的 `Q-05` 文档已经加了 2026-11-10 覆盖说明。以本 handoff 第 2.3 / 2.4 节和最新 `LOCAL-AI-003F` 规格为准：本地 Planner 只作为生成上下文，不显示独立卡；PWA 云端 Planner 行为不变。

## 5. 下一步顺序

### 5.1 Hosted 真实请求验收

- 在包含本轮 iOS 客户端改动的构建中登录账户；App Store / 旧 TestFlight 客户端不会自动包含本地代码改动。
- 用已登录账户分别验证记忆开/关：开时 Edge 收到同域摘要并生成 Companion；关时请求体没有 `local_memory_context`。
- 在 iOS 详情中确认本地 Planner 不再单独出现；PWA 页面和远端 Planner 沿用旧行为。
- 要验证新的 Hosted Companion，请新建或编辑一条记录触发生成；历史文案不会自动重写。

### 5.2 补记忆投影刷新缺口

- OCR 自动归档写入 `LocalPendingFinancialRepository.archiveDirectly` 时尚未触发 `LocalExpressionPersistence.refreshMemoryProjection`。
- 增加一个明确场景，保证事实保存成功与记忆投影刷新解耦；刷新失败不能回滚事实。

### 5.3 发布前验证

- 实测完整备份中的 Companion / Planner 与记忆恢复。
- 运行 GitHub macOS CI、全量 XCTest 和真机回归；之后再决定 TestFlight。
- 不新增任何同步 outbox；生产部署和 TestFlight 另行确认。

## 6. 当前未完成项

- Hosted Edge Function v205 已部署；真实 Hosted AI 的记忆开启/关闭请求还未在线验证，需使用包含本轮 iOS 改动的客户端。
- OCR 直归档绕过 AppState 表达刷新导致的记忆投影刷新缺口，需另开场景修复。
- 完整备份中 Companion / Planner 结果的实际恢复验证仍待做。
- 需要 GitHub macOS CI 和后续真机回归；本地 iOS Simulator 定向 XCTest 已执行。

## 7. 验证状态

- 已执行：iPhone 17 / iOS Simulator 定向 XCTest，6/6 通过。
- 已执行：Edge Context Packet 与 Prompt Deno 测试，27/27 通过；Edge `deno check` 通过。
- 已执行：Supabase Edge Function 部署成功；项目函数列表确认 `ingest-receipt` 为 `ACTIVE`、版本 `205`、`verify_jwt=false`。
- 已执行：`xcodebuild build` 成功；改动后的 App 已安装并启动于 iPhone 17 / iOS Simulator 27.2，记录列表可见。未在本轮重放快捷指令、打开详情验证卡片，或发送在线 Hosted 请求。
- 已执行：`git diff --check` 通过。
- 尚待：已登录账户的 iOS Hosted 开/关实测、GitHub macOS CI、真机和 TestFlight。
- 当前工作区包含未提交文档和代码改动；`.build/` 是未跟踪构建产物，不要加入功能提交。

## 8. 下一会话交付标准

下一会话结束时至少应能说明：

1. 七类事实写入后是否都能刷新本地表达；
2. 记忆关闭时是否完全不读写记忆表；
3. Planner / Companion 是否能从备份恢复；
4. Provider 失败是否仍保留本地事实和确定性候选；
5. 是否有任何路径新增了同步 outbox 或远端业务写入。
