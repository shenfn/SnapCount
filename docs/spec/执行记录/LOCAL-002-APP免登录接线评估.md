# LOCAL-002-APP 免登录接线只读评估记录

> 日期：2026-08-23
>
> 基线：`origin/main@e68a64d`
>
> 状态：评估完成，尚未进入代码实现

## 已核对

- `AppState.bootstrap()` 仍以 Supabase 会话恢复为启动入口。
- `createManualRecord`、`saveRecordDetail`、`deleteRecord` 和历史月份读取仍强制走远端 `RecordRepository`。
- `LocalDatabase` 已提供 Application Support 下 GRDB 文件和 `local-v1` migration。
- `LocalExpenseRepository` 已覆盖本地 profile/账户/消费的写事务、编辑删除冲销、tombstone、Outbox 和导入导出，但尚无页面查询投影与 profile 恢复入口。
- `NativeManualRecordDraft` 属于 UI 表单模型，金额为 `Double` 解析结果，不能直接作为本地持久化模型。
- `DashboardSnapshotStore` 仍是展示缓存，不能承担本地事实库职责。

## 结论

先实现窄的 Local-First Expense Use Case 和 profile lifecycle，再接 AppState 兼容入口。禁止在 AppState 内复制本地/云端事务分支，禁止把远端 DTO 或 Dashboard 快照冒充本地读模型。

## 未验证

- Windows 未运行 Swift 编译和 XCTest；
- 尚未修改 AppState、页面或生产配置；
- 尚未验证真实设备 Application Support、文件保护和低存储错误呈现；
- 尚未实现登录绑定、同步发送、云端迁移和 AI Provider。

## 下一步

1. 新建 `LOCAL-002-APP` 模块 Spec，先写 profile lifecycle/network gate/mapping 红灯。
2. 设计 `LocalProfileStore` 与 `LocalExpenseUseCase` 的最小协议，避免引入云端依赖。
3. 在 macOS CI 上取得有效红灯后，再做最小实现和 AppState 接线。
