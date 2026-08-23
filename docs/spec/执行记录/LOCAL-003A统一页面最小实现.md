# LOCAL-003A 统一页面最小实现执行记录

> 状态：实现完成，待 macOS CI 验证
>
> 分支：`feature/LOCAL-003A统一页面最小实现`
>
> 基线：`origin/main@d29efd1`

## 本轮完成

- `RootView` 收敛为一棵统一五 Tab 树，登录状态不再选择本地壳或云端壳。
- `RecordsView` 使用同一列表、筛选、详情导航和新增入口；移除页面内按登录态拆分的本地/云端业务树。
- `SettingsView` 合并本机存储、云端身份、同步状态和登录入口；删除临时 `LocalSettingsView`。
- `AppState.loadRecordMonth` 通过统一门面先读本地 GRDB，再在需要时调用远端兼容读路径。
- `AppState.createManualRecord` 通过统一门面让消费记录始终先写本地；非消费域保留远端兼容路径。
- 新增记录使用单一入口容器；未登录时继续走本地账户准备与本地消费表单，避免统一壳改造造成本地保存回归。

## 验证

- `LOCAL-003A` 统一页面边界测试：5/5 通过。
- 既有 `LocalExpenseAppUseCaseTests` 已按 LOCAL-003 本地优先语义更新：已登录且本地月份为空时验证远端兼容回退。
- 旧 `LOCAL-002` 本地壳测试：不作为本片通过条件；其中断言已淘汰的两 Tab 壳和 `LocalSettingsView`，与 LOCAL-003 决策冲突。
- Windows 无法验证 Swift 编译；必须以 GitHub macOS iOS Build/XCTest 为准。

## 未完成与范围边界

- 尚未实现登录绑定预览、首次同步、Outbox 上传、冲突合并、同步代次和其他数据域迁移。
- Today、Inbox、Insights 的本地读模型仍待后续切片接入；本片不新增远端同步行为。
- 本片没有修改 GRDB schema、Supabase、Edge Function、PWA 或生产配置。

## 下一步

1. 推送并创建 LOCAL-003A 实现 PR，等待 macOS iOS Build/XCTest 与治理门禁。
2. 根据 macOS 编译结果修复 Swift 兼容问题；不在 Windows 声称编译通过。
3. 进入 LOCAL-003B 前先补 expense/accounts 的统一详情、编辑、删除和余额投影场景测试。
