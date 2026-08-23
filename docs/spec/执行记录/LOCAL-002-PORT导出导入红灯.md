# LOCAL-002-PORT 导出导入红灯执行记录

> 状态：准备红灯
>
> 日期：2026-08-23
>
> 分支：`test/LOCAL-002-PORT导出导入红灯`

## 目标行为

- LOCAL-002E1：导出版本化、可恢复的 profile/账户/消费/tombstone/流水业务包。
- LOCAL-002E2：导出包排除 cloud 绑定、凭据、缓存、诊断和源 Outbox。
- LOCAL-002F1：向空数据库原子恢复业务事实、关系、历史流水和派生余额。
- LOCAL-002F2：重复导入相同稳定 ID 与内容时幂等跳过。
- LOCAL-002F3：相同稳定 ID 内容冲突时整包拒绝，不 silent upsert。
- LOCAL-002F4：未知版本或非法关系在写入前拒绝。
- LOCAL-DATA-004C：导入生成的新 Outbox 失败时整包事务回滚。

## 当前行为

- `DashboardSnapshotStore` 只保存用户隔离的展示快照，没有业务关系、流水、tombstone 或事务恢复能力。
- `SettingsRepository.export` 从 Supabase 导出报表字段，依赖 access token，也不包含本地稳定关系和删除事实。
- production Local Database 已有 profile、账户、消费、流水、tombstone 和 Outbox，但没有版本化 archive codec 或原子导入 API。

## 权威来源

- `docs/spec/模块/iOS本地优先/消费记录垂直切片规格说明.md`
- `docs/spec/模块/iOS本地优先/本地优先数据生命周期规格说明.md`
- `docs/decisions/ADR-037-iOS本地业务数据库选择GRDB.md`

## 本轮范围

- 纯 Codable archive 模型与 JSON codec。
- profile 级消费垂直切片导出。
- 导入前关系校验、稳定 ID 比较与单一 GRDB 事务恢复。
- 新导入当前状态对应的 fresh pending Outbox。
- Repository/数据库集成 XCTest。

## 非范围

- SwiftUI 分享面板、文件选择器、AppState 和免登录入口接线。
- 云端报表导出替换、自动同步、云端用户绑定和跨设备合并。
- PWA、Edge、Supabase migration、生产部署和 TestFlight。

## 基线测试结果

DB2 最终 GitHub Actions Run `32619112015`：完整 230 个 XCTest、iOS Build Gate 和其他适用门禁全部通过。

## 预期红灯

测试将引用尚不存在的 `LocalExpensePortability`、`LocalExpenseArchive`、`LocalExpenseImportResult` 和 archive 错误语义。macOS iOS Build 应在测试 target 编译阶段因这些生产类型缺失失败；App target 应先保持构建成功。

## 红灯测试及失败原因

待 GitHub macOS CI 验证。

## 最小实现

待红灯成立后实现。

## 绿灯结果

未开始。

## 未解决风险

- 首版只覆盖消费垂直切片，不承诺其他数据域已可完整备份。
- 文件加密、分享面板临时文件清理和真机文件保护由 LOCAL-002-APP/发布门禁继续验证。
- archive schema 的后续升级兼容必须新增 migration fixture，不允许直接修改 v1 含义。

## 对应提交

待用户授权提交后填写。
