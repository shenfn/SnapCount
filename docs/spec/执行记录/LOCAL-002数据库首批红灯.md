# LOCAL-002 数据库首批红灯执行记录

> 状态：有效红灯已取得，最小实现进行中
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

## 下一步

1. 推送红灯提交并取得 macOS 编译失败证据。
2. 只增加 GRDB package、Local Domain、migration 和 Repository 最小实现。
3. 让本文件中的五组不变量转绿，再进入 DB2。
