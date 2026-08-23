# LOCAL-002 数据库首批红灯执行记录

> 状态：红灯与绿灯完成，等待 PR 合并
>
> 日期：2026-08-23
>
> 分支：`test/LOCAL-002消费记录本地优先红灯`

## 场景

- LOCAL-002A1：不提供 session、token 或 remote client，也能在本地创建 profile、账户和消费。
- LOCAL-DATA-004A：第二次写入使用重复 operation UUID 导致 Outbox 约束失败时，第二条消费和流水不得残留。
- LOCAL-002B1：释放并重建数据库对象后，消费、账户关系和 pending Outbox 仍可读取。
- LOCAL-002J1：账户余额等于 opening balance 加有效流水方向和金额的确定性求和结果。
- LOCAL-SPIKE-001C 延续：重复消费稳定 UUID 必须拒绝，不得覆盖原金额。

## 预期红灯

`LocalExpenseRepositoryTests.swift` 引用尚不存在的生产类型：

- `LocalDatabase`
- `LocalExpenseRepository`
- `LocalProfile`
- `LocalAccountDraft`
- `LocalExpenseDraft`
- `LocalOutboxOperation`

macOS iOS Build 应在编译 `SnapCountTests` 时因这些类型缺失失败。该失败证明生产本地数据库边界尚未实现，不是 Windows 环境失败。

## 红灯证据

GitHub Actions Run `32617323551`：

- App target 的 `Build for simulator` 先通过；
- `Run unit tests` 编译 `LocalExpenseRepositoryTests.swift` 时失败；
- 明确错误为 `cannot find type 'LocalProfile'`、`LocalAccount`、`LocalExpenseRepository`、`LocalExpenseDraft`；
- Governance、Release Validation、Cloudflare 和 Vercel 适用检查通过。

因此该失败是目标生产类型缺失造成的有效业务红灯，不是 Xcode、依赖下载或 runner 环境故障。

## 冻结范围

- 不接 AppState、页面和现有 `RecordRepository`。
- 不发送 Outbox，不访问 Supabase。
- 不做编辑、删除、导出导入和云端用户迁移。
- 不执行生产迁移、部署或 TestFlight。

## 绿灯证据

GitHub Actions Run `32617626804`：

- `Build for simulator` 成功；
- `LocalExpenseRepositoryTests` 执行 5 个测试，0 failures；
- 完整 `SnapCountTests` 执行 223 个测试，0 failures；
- `TEST SUCCEEDED`，iOS Build Gate 通过；
- Governance、Release Validation、Cloudflare 和 Vercel 适用检查通过。

最小实现范围：

- `LocalDatabase`：GRDB migration 与默认受保护文件路径；
- `LocalModels`：UUID、整数金额和本地版本模型；
- `LocalExpenseRepository`：profile、账户、消费、流水、Outbox 同事务写入与余额派生；
- `ios/project.yml`：生产 App target 增加精确版本 GRDB 依赖；
- 未接 AppState、页面、Supabase 或网络发送。

## 下一步

1. PR #152 最终门禁通过后合并。
2. 从最新主线建立 LOCAL-002-DB2 worktree。
3. 先为编辑、删除、冲销流水、tombstone 和版本递增建立红灯，不接页面。
