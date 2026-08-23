# iOS 本地数据库选型 Spike 规格说明

> 规格编号：LOCAL-SPIKE-001
>
> 状态：证据完成，选型见 ADR-037
>
> 基线：`origin/main@b864030`

## 1. 目标

在不接入生产 `SnapCount` target 和业务 Repository 的隔离实验中，对比 GRDB/SQLite 与 SwiftData 是否能支撑芥子的 Local-First 数据权威、Outbox、迁移、导入恢复和后续同步协议。

本 Spike 只回答数据库基础设施选型，不实现免登录、本地消费 Repository、同步引擎、生产数据迁移或发布能力。

## 2. 冻结范围

- 不修改 `ios/SnapCount/**`、`ios/SnapCountTests/**` 和 `ios/project.yml`。
- 不修改 PWA、Edge Function、Supabase migration、生产配置和现有发布 workflow。
- 不把 Spike 类型或第三方依赖接入 App target。
- 不使用真实用户数据、凭据、生产数据库或线上 API。
- 实验产物必须可整体删除，不形成两套生产实现。

## 3. 隔离实验形态

实验位于 `ios/Spikes/LocalDatabaseSpike/`，使用独立 XcodeGen 工程和 iOS Simulator XCTest：

```text
LocalDatabaseSpikeHarness
  -> LocalDatabaseSpike framework
       -> GRDB probe
       -> SwiftData probe
  -> LocalDatabaseSpikeTests
```

专用 workflow 只在 Spike 目录或自身变化时运行。现有 `SnapCount` 工程不依赖该 framework。

## 4. 场景矩阵

| 场景 | 行为不变量 | 验证方式 |
|---|---|---|
| LOCAL-SPIKE-001A | 消费记录和 Outbox 必须在一次持久化边界内同时成功 | 两个候选分别写入并核对计数 |
| LOCAL-SPIKE-001B | 消费写入后发生故障时，不得留下半条业务事实 | 注入故障并核对消费、Outbox 均为 0 |
| LOCAL-SPIKE-001C | 稳定 UUID 的重复写入语义必须明确、可测试 | GRDB 验证约束拒绝；SwiftData 验证 `unique` 的实际语义 |
| LOCAL-SPIKE-001D | schema v1 文件升级到 v2 后不得丢失既有消费 | 建 v1 文件、写记录、以 v2 重开并读取 |
| LOCAL-SPIKE-001E | 关闭并重新创建 Store 后，记录和 Outbox 仍存在 | 文件数据库重启测试 |
| LOCAL-SPIKE-001F | Outbox、tombstone、幂等键和顺序字段可以显式建模 | 代码评审 + A/C/D 证据，不在本轮实现同步器 |
| LOCAL-SPIKE-001G | 数据库文件可使用 iOS Data Protection；额外加密能力和代价必须明确 | 平台能力评估，不把 Simulator 当作真机加密证明 |
| LOCAL-SPIKE-001H | 候选能通过当前 XcodeGen + iOS 17 + Swift 5.9 工具链编译测试 | 专用 macOS workflow |

## 5. 评估维度与裁决规则

| 维度 | GRDB/SQLite 关注点 | SwiftData 关注点 | 阻断条件 |
|---|---|---|---|
| 事务 | 显式数据库事务、抛错自动回滚 | 单次 `ModelContext.save()` 与应用层 rollback | 无法稳定证明业务事实和 Outbox 同成同败 |
| 唯一约束 | 主键/唯一索引拒绝冲突 | `@Attribute(.unique)` 的 upsert/合并语义 | 重复稳定 ID 会静默覆盖且 Repository 无法区分 |
| Migration | 显式、有序、可重复的 `DatabaseMigrator` | `VersionedSchema` 与 `SchemaMigrationPlan` | v1→v2 无法在 CI 稳定复现 |
| 测试 | 临时文件、SQL 检查、故障注入 | 临时 Store、模型查询、故障注入 | 只能依赖 UI 或真实设备验证核心事务 |
| 导入导出 | SQL/Row 可精确控制字段和批量事务 | 需经过模型对象和 Context | 无法原子校验后再整体导入 |
| 同步适配 | 可显式设计 Outbox、tombstone、序号和索引 | 可建模，但持久化语义由框架管理 | 无法审计幂等和冲突处理所需底层行为 |
| 文件保护 | SQLite 文件可设置 iOS Data Protection | Store 文件可设置 iOS Data Protection | 无法使用系统文件保护 |
| 额外加密 | 可评估 SQLCipher 构建变体，增加依赖和迁移成本 | 无官方 SQLCipher 接入口 | 未完成威胁模型前不作为 L1 阻断项 |
| 工程接入 | 增加一个 Swift Package 和 Repository adapter | 系统框架，无第三方包 | 侵入现有 AppState/Domain 或要求双实现 |

裁决优先级：数据正确性与可审计性 > 迁移和测试能力 > 同步适配性 > 接入代码量。少写几行代码不能抵消事务、唯一约束或迁移证据不足。

## 6. 选型结论

- 选择 GRDB/SQLite 作为 iOS 生产本地业务事实库，详见 `ADR-037`。
- SwiftData 与 SwiftUI 集成更直接，但本项目的本地数据库位于 Repository 之后，View 自动观察不是首要选型指标。
- `@Attribute(.unique)` 已在 iOS Simulator 证实为 upsert：重复稳定 UUID 保留一条记录并覆盖金额。导入和同步必须显式处理冲突，不能把这个默认语义当作权威行为。
- iOS Data Protection 是默认最低保护。是否引入 SQLCipher 必须由威胁模型、备份恢复、性能和密钥生命周期共同决定，不能只因“隐私优先”直接引入。

## 7. 完成定义

1. LOCAL-SPIKE-001A 至 H 的证据和限制写入执行记录。
2. 专用 macOS/iOS Simulator workflow 通过；Windows 不冒充 Swift 编译结论。
3. 形成接受状态的选型 ADR，并明确未选方案为何不适合作为当前生产权威。
4. 更新阶段索引和交接快照，给出 LOCAL-002 红灯入口。
5. Spike 未接入生产 App target，未执行迁移、部署或 TestFlight。
