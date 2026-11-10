# LOCAL-AI-003A 执行记录：本地记忆数据层

- 目标行为：本地 Companion/Planner 记忆按 profile 持久化，提供有大小上限的结构化上下文；不进入业务同步。
- 当前行为：已完成 v33 迁移、记忆表约束、Repository、本地表达上下文、确定性 Planner 候选种子，以及消费/收入/四域详情和本地 Inbox 候选的 Planner 接线。
- 权威来源：`docs/spec/模块/iOS本地优先/本地AI陪伴与Planner候选域规格说明.md`、`docs/spec/模块/iOS本地优先/本地优先隐私配置与导出契约规格说明.md`。
- 本轮范围：`local_companion_memories`、`LocalCompanionMemoryRepository`、`LocalExpressionContext`、完整备份 v29 兼容、历史迁移归档表清单、AppState 本地详情和 Inbox Planner 接线。
- 非范围：写入路径刷新、钱包详情适配、远端 Provider、同步 outbox、Supabase schema/RPC、TestFlight。
- 预计修改文件：`ios/SnapCount/LocalData/LocalDatabase.swift`、新增记忆 Repository 与表达上下文、`LocalCompleteBackupPortability.swift`、`LocalHistoryMigrationMapper.swift`。
- 基线测试结果：本轮未运行 XCTest；执行了 Swift parse 检查和 `git diff --check`。
- 红灯测试及失败原因：未新增或运行测试，待 macOS XCTest 环境可用后补齐 `LOCAL-AI-003A` 场景验证。
- 最小实现：v32→v33 新增 profile 级记忆表；记忆 key 唯一、内容 JSON 校验、confidence 范围、软删除和来源索引；旧 v28 备份导入时记忆表按空集合兼容。
- 绿灯结果：`swiftc -parse` 通过；`git diff --check` 通过。
- PWA/iOS 差异：本轮只改 iOS 本地数据层；业务同步保持冻结。
- GitHub CI 结果：未触发。
- 未解决风险：写入路径和记忆投影刷新仍待接线；钱包详情尚未接入；本地 Planner 候选目前是确定性种子，尚未接入 Hosted/BYOK 生成。
- 对应提交：未提交。
