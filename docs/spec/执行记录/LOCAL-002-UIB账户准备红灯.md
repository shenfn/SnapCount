# LOCAL-002-UIB 账户准备与本地新增消费红灯

## 状态

红灯建立中。基线为 `origin/main@57e1f39`，对应 UIA 已合并后的主线。

## 本片范围

- 显式创建首个本地账户；
- 账户期初余额的 Decimal 到整数分解析；
- 无账户时本地消费保存的明确失败出口；
- 本地账户列表与派生余额；
- 本地新增消费表面隔离云端账户、财务词表和收入类型。

## 非目标

不处理本地详情、同步、AI Provider、其他数据域、PWA、Edge、数据库迁移、生产部署或 TestFlight。

## 红灯证据

- `npm run test:ios-local-account-boundary` 已运行，5 个断言全部按预期失败：Use Case 契约、金额映射、账户准备 View 和本地 expense View 尚未存在；
- `npm run test:ios-local-shell-boundary` 通过；
- `npm run test:ios-local-expense-app-boundary` 通过；
- `npm run governance:check` 和 `npm run governance:arch` 通过；
- `LocalExpenseAccountPreparationTests.swift` 尚未在 macOS 上编译，预期会因 `LocalExpenseWorkspace`、账户命令和错误出口尚未实现而失败。

## 下一步

红灯确认后，仅实现最小本地账户准备与本地 expense 表单闭环，再运行专项边界、完整 XCTest、macOS Build、治理和架构门禁。
