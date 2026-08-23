# LOCAL-002-DB2 编辑删除红灯执行记录

> 状态：准备红灯
>
> 日期：2026-08-23
>
> 分支：`test/LOCAL-002-DB2编辑删除红灯`

## 目标行为

- LOCAL-002C1：非金额字段编辑递增版本、写 `upsert` Outbox，既有有效流水保持不变。
- LOCAL-002C2：金额编辑冲销旧流水并插入替代流水，余额由有效流水重新派生。
- LOCAL-002C3：账户迁移恢复旧账户余额并扣减新账户余额。
- LOCAL-002C4：陈旧 `expectedVersion` 明确失败，不静默覆盖。
- LOCAL-002D1：删除写 `deleted_at` tombstone、冲销有效流水并写 `delete` Outbox。
- LOCAL-002D2：Outbox 冲突导致编辑或删除整笔事务回滚。
- LOCAL-002B2：重启后版本、流水历史、余额和 tombstone 保持。

## 当前行为

DB1 只有创建、默认隐藏 `deleted_at` 行、有效流水余额派生和 pending Outbox 读取。生产 Repository 尚无编辑、删除、tombstone 读取、流水历史读取和乐观版本冲突 API。

## 权威来源

- `docs/spec/模块/iOS本地优先/消费记录垂直切片规格说明.md`
- `docs/decisions/ADR-037-iOS本地业务数据库选择GRDB.md`
- GRDB 同一 `DatabaseQueue.write` 事务与 SQLite 唯一约束。

## 本轮范围

- `LocalModels` 的编辑命令、tombstone、流水历史和显式冲突错误模型。
- `LocalExpenseRepository` 编辑与删除协议/API。
- 必要的 GRDB migration、查询和事务实现。
- Repository 数据库集成 XCTest。

## 非范围

- AppState、SwiftUI 页面、免登录入口和现有远端 Repository 接线。
- Outbox 网络发送、同步状态机、导出导入、AI 和其他数据域。
- PWA、Edge、Supabase migration、生产部署和 TestFlight。

## 基线测试结果

DB1 最终 GitHub Actions Run `32617953115` 全部门禁通过；此前 Run `32617626804` 完整执行 223 个 XCTest，0 failures。Windows 不作为 Swift 编译结论。

## 预期红灯

测试将引用尚不存在的 `LocalExpenseUpdate`、`updateExpense`、`deleteExpense`、`expenseTombstone` 和 `accountEntries` API。macOS iOS Build 应在编译 `SnapCountTests` 时因这些生产 API 缺失失败；App target 和既有测试应先保持可构建。

## 红灯测试及失败原因

待 GitHub macOS CI 验证。

## 最小实现

待红灯成立后实现。

## 绿灯结果

未开始。

## 未解决风险

- 真机文件保护仍由后续发布门禁验证。
- DB2 不定义 Outbox 发送后的压缩或清理策略。
- 跨设备并发合并仍延后到同步阶段；本轮只定义本地乐观版本冲突。

## 对应提交

待用户授权提交后填写。
