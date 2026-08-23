# LOCAL-002-UIB 账户准备与本地新增消费红灯

## 状态

红灯已确认，最小实现已落地，等待 macOS iOS Build/XCTest 绿灯。基线为 `origin/main@57e1f39`，对应 UIA 已合并后的主线。

## 本片范围

- 显式创建首个本地账户；
- 账户期初余额的 Decimal 到整数分解析；
- 无账户时本地消费保存的明确失败出口；
- 本地账户列表与派生余额；
- 本地新增消费表面隔离云端账户、财务词表和收入类型。

## 非目标

不处理本地详情、同步、AI Provider、其他数据域、PWA、Edge、数据库迁移、生产部署或 TestFlight。

## 红灯证据

- `npm run test:ios-local-account-boundary` 已运行，5 个断言现已通过：Use Case 契约、金额映射、账户准备 View 和本地 expense View 已落地；
- `npm run test:ios-local-shell-boundary` 通过；
- `npm run test:ios-local-expense-app-boundary` 通过；
- `npm run governance:check` 和 `npm run governance:arch` 通过；
- 首轮 macOS CI 已确认红灯：App 编译通过，但 UIB XCTest 因上述契约缺失失败；最小实现后需重新运行。

## 最小实现

- LocalExpense Use Case 负责 profile、账户读取、余额投影、账户创建和账户归属门禁；
- Records 本地模式新增入口先读取账户 workspace，无账户先进入账户准备；
- 本地账户准备和本地支出表单为独立 View，不读取云端账户或财务词表；
- 账户创建只注入当前消费草稿，不建立默认账户。

## 下一步

最小实现已完成，下一步运行专项边界、完整 XCTest、macOS Build、治理和架构门禁。
