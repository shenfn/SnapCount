# LOCAL-SPIKE-001 本地数据库选型执行记录

> 状态：实验已建立，等待 GitHub macOS CI
>
> 日期：2026-08-23
>
> 分支：`test/LOCAL-SPIKE-001本地数据库选型`

## 当前证据

| 场景 | GRDB | SwiftData | 状态 |
|---|---|---|---|
| 001A 消费 + Outbox | 显式同一 `DatabaseQueue.write` | 同一 `ModelContext.save()` | 待 iOS Simulator 验证 |
| 001B 回滚 | 抛错触发数据库事务回滚 | 保存前显式 `ModelContext.rollback()` | 待 iOS Simulator 验证 |
| 001C 稳定 UUID | SQLite 主键冲突应拒绝整次写入 | `unique` 预期表现为 upsert | 待 iOS Simulator 验证 |
| 001D v1→v2 | `DatabaseMigrator` 新增可空 `note` | lightweight `SchemaMigrationPlan` | 待 iOS Simulator 验证 |
| 001E 重启恢复 | 重建 Queue 后读取文件 | 重建 Container 后读取 Store | 待 iOS Simulator 验证 |
| 001F 同步适配 | 表、索引、顺序和 tombstone 可显式控制 | 模型可表达，底层 SQL 约束控制较弱 | 代码证据已建立，待综合裁决 |
| 001G 文件保护/额外加密 | Data Protection 可用；SQLCipher 需独立评估 | Data Protection 可用；无官方 SQLCipher 接口 | 真机保护强度未验证 |
| 001H 工程接入 | 独立 XcodeGen package dependency | 系统框架 | 待 macOS CI 编译 |

## 环境说明

- Windows 当前没有 Swift/Xcode，不能运行或证明 XCTest。
- 本地只完成了目录、YAML、Swift 源码和测试的静态复核。
- 真实编译、SwiftData migration 行为和 GRDB 版本兼容性必须以 GitHub `macos-26` workflow 为准。

## 未验证与风险

- SwiftData v1→v2 的 lightweight migration 是否能在当前 Xcode 版本处理嵌套 VersionedSchema 模型。
- SwiftData `unique` 冲突在当前 iOS 17+ runtime 的实际 upsert 结果。
- SQLCipher 未接入，不能声称数据库已有额外静态加密。
- Simulator 不能证明锁屏、设备重启和备份场景下的 iOS Data Protection 强度。
- 本 Spike 没有实现 tombstone、同步冲突或批量导入，只验证候选是否给这些能力留下可控基础。

## 下一步

1. 推送分支并创建 PR，运行专用 iOS Simulator tests。
2. 按 CI 日志修复实验代码，不扩大到生产 App。
3. 记录两端实际结果并编写选型 ADR。
4. ADR 合并后，按 LOCAL-002 的红灯顺序开始消费记录垂直切片。
