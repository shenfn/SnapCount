# LOCAL-SPIKE-001 本地数据库选型执行记录

> 状态：实验与远程验证完成，选型 ADR 已形成
>
> 日期：2026-08-23
>
> 分支：`test/LOCAL-SPIKE-001本地数据库选型`

## 当前证据

| 场景 | GRDB | SwiftData | 状态 |
|---|---|---|---|
| 001A 消费 + Outbox | 显式同一 `DatabaseQueue.write`，通过 | 同一 `ModelContext.save()`，通过 | Run `32616469206` |
| 001B 回滚 | 抛错后两表均为 0，通过 | 保存前显式 rollback 后两类模型均为 0，通过 | Run `32616469206` |
| 001C 稳定 UUID | 主键拒绝重复，原记录和 Outbox 不变 | `unique` 执行 upsert，金额由 2680 变为 3180 | 关键选型差异已复现 |
| 001D v1→v2 | `DatabaseMigrator` 升级并保留旧记录，通过 | lightweight migration 升级并保留旧记录，通过 | Run `32616469206` |
| 001E 重启恢复 | 重建 Queue 后记录和 Outbox 存在，通过 | 重建 Container 后记录和 Outbox 存在，通过 | Run `32616469206` |
| 001F 同步适配 | 表、约束、索引、顺序和 tombstone 可显式控制 | 模型可表达，冲突和底层约束需要额外包裹 | GRDB 优先 |
| 001G 文件保护/额外加密 | Data Protection 可用；SQLCipher 待威胁模型 | Data Protection 可用；无官方 SQLCipher 接口 | 真机保护强度仍未验证 |
| 001H 工程接入 | 独立 XcodeGen package dependency 编译通过 | 系统框架编译通过 | Run `32616469206` |

## 环境说明

- Windows 当前没有 Swift/Xcode，本地没有冒充 Swift 编译结论。
- GitHub Run `32616469206` 在 `macos-26` 的 iOS Simulator 执行 10 个测试，0 failures，`TEST SUCCEEDED`。
- GitHub Run `32616469205` 的现有 App Build、完整 `SnapCountTests` 和 iOS Build Gate 通过。
- Governance、Release Validation、Cloudflare 和 Vercel 适用检查均通过。

## 未验证与风险

- SQLCipher 未接入，不能声称数据库已有额外静态加密。
- Simulator 不能证明锁屏、设备重启和备份场景下的 iOS Data Protection 强度。
- 本 Spike 没有实现 tombstone、同步冲突或批量导入，只验证候选是否给这些能力留下可控基础。

## 下一步

1. 合并 PR #151，使 ADR-037 和 Spike 证据进入主线。
2. 从合并后的 `origin/main` 建立 LOCAL-002 独立 worktree。
3. 先写 GRDB 生产接入、schema、migration、文件保护和 Repository 的红灯，不复用 Spike 类型作为生产实现。
4. 按 LOCAL-002A-J 的顺序完成消费记录垂直切片。
