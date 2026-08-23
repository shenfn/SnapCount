# ADR-037：iOS 本地业务数据库选择 GRDB

> 状态：已接受
>
> 日期：2026-08-23
>
> 关联任务：LOCAL-SPIKE-001、LOCAL-002

## 决策

iOS 本地优先业务事实库采用 GRDB/SQLite。SwiftData 不作为消费、账户、流水、Outbox、tombstone、导入恢复和同步状态的生产权威存储。

生产接入遵循以下边界：

1. GRDB 只存在于 Local Database adapter，不进入 Domain Model、Use Case、SwiftUI View 或 Repository Protocol。
2. 业务记录和对应 Outbox 操作必须通过同一个 GRDB 写事务提交；抛错时整体回滚。
3. 稳定 UUID 使用数据库主键或唯一约束。重复 ID 必须进入显式的 ignore、reject 或 merge 策略，禁止依赖隐式 upsert 静默覆盖。
4. schema 版本由 `DatabaseMigrator` 顺序维护；每条 migration 必须有旧文件升级、重复启动和失败恢复测试。
5. 金额以最小货币单位整数保存；账户余额由可审计流水派生，不直接最后写入覆盖。
6. 本地数据库、WAL 和 SHM 文件位于受保护的 App 容器目录，并显式应用 iOS Data Protection。真机文件保护在 L1 发布门禁中验证。
7. L1 不立即引入 SQLCipher。额外数据库加密必须先完成威胁模型、密钥恢复、导出导入、性能和升级迁移评估，再由独立 ADR 决定。

## 背景

芥子的本地数据库不是 SwiftUI 缓存，而是免登录模式下的业务权威，并将承载离线编辑、版本化导入、Outbox、删除 tombstone 和多设备同步。选型优先级因此是显式事务、冲突语义、迁移可审计性和故障注入能力，而不是 UI 自动观察代码量。

LOCAL-SPIKE-001 在独立 iOS 17 XcodeGen 工程中，用同一组场景比较 GRDB 与 SwiftData。实验没有接入生产 `SnapCount` target。

## 证据

GitHub Actions Run `32616469206` 在 iOS Simulator 执行 10 个 XCTest，零失败：

- GRDB：消费与 Outbox 同事务提交、抛错自动回滚、重复 UUID 被主键拒绝、v1→v2 migration、文件重启恢复全部通过。
- SwiftData：同一次 `ModelContext.save()`、保存前手动 rollback、lightweight migration 和文件重启恢复通过。
- SwiftData 的 `@Attribute(.unique)` 重复 UUID 实际执行 upsert：记录数保持 1，但旧金额被新金额静默替换。该行为可被额外代码包裹，却不符合本项目默认拒绝或显式合并同步冲突的要求。
- GRDB migration 场景约 `0.010s`，SwiftData lightweight migration 场景约 `3.825s`。该单次 Simulator 时间不作为主要选型依据，只记录为后续性能基线。

GitHub Actions Run `32616469205` 的现有 SwiftUI App Build、`SnapCountTests` 和 iOS Build Gate 全部通过，证明隔离 Spike 没有破坏主工程。

## 备选方案

### SwiftData 作为业务事实库

优点是系统原生、模型声明简洁、与 SwiftUI 观察机制集成直接。Spike 也证明它能完成本轮基础持久化和轻量迁移。

未选择原因：

- 唯一属性采用 upsert 语义，稳定 ID 冲突需要额外检测才能避免静默覆盖。
- 本轮回滚证据依赖在 `save()` 前由应用代码调用 `rollback()`；GRDB 可直接把完整命令放进显式数据库事务。
- Outbox、tombstone、部分索引、批量导入和同步游标需要更明确的 SQL、约束和 migration 控制。
- SwiftUI 自动观察不是当前 Repository 后置存储层的核心收益。

SwiftData 未来若用于非权威缓存或独立系统功能，必须证明不会形成第二套业务事实库，并单独评审。

### 直接使用 SQLite C API

控制力足够，但会增加 statement、类型映射、migration 和并发封装成本。GRDB 保留 SQLite 的约束和事务能力，同时提供成熟 Swift API，因此不手写底层封装。

### Core Data

成熟但与当前 iOS 17、Local-First/Outbox 目标相比没有优于 GRDB 的显著收益，并会引入另一套对象图和迁移复杂度，本 Spike 不继续扩大比较面。

## 影响

- LOCAL-002 可以在 `ios/project.yml` 中增加 GRDB package，并建立唯一的 Local Database adapter；该动作必须在独立红灯切片中完成，本 ADR 本身不接线生产 App。
- 需要设计 schema、migration、数据库路径、文件保护、故障分类和测试 factory。
- SwiftData 模型不会与 GRDB 模型并行存在，避免双写和数据权威漂移。
- 第三方依赖增加了供应链和版本升级责任；生产接入时必须固定可复现版本并由 iOS CI 构建。
- SQLCipher 暂缓不等于忽略隐私：L1 必须先落实 iOS Data Protection、Keychain 隔离、无日志泄漏和版本化导出。

## 未解决项

- 真机锁屏、重启和备份恢复下的文件保护验证。
- SQLCipher 是否属于产品威胁模型的必需能力。
- DatabaseQueue 与 DatabasePool 的生产并发选择；不得改变 Repository 的事务不变量。
- LOCAL-002 的完整 schema、outbox 状态机、tombstone 和导出格式。
