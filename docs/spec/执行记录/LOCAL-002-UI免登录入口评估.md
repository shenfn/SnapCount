# LOCAL-002-UI 免登录入口评估记录

> 日期：2026-08-23
>
> 分支：`docs/LOCAL-002-UI免登录入口评估`
>
> 基线：`5f72366`

## 目标

只读确认 LOCAL-002-APP 合并后，用户为何仍无法免登录使用，以及 Root、Tab、月份读取、账户准备和设置应如何收敛。

## 已核对

- `RootView` 无 session 时仍只展示 `LoginView`。
- `bootstrap` 只准备本地 profile，不加载账户和月份。
- `loadRecordMonth`、记录详情预取、Accounts、Settings、Inbox 和 Insights 仍有远端依赖。
- `ManualRecordSheet` 允许无账户保存，但本地 Use Case 要求账户 UUID。
- `LocalExpenseRepository` 已具备本地账户创建、查询和余额派生能力。
- ADR-036 和 LOCAL-PLAN-001 已规定默认本机保存、登录只解锁同步。

## 结论

- 选择 LOCAL-002-UIA“本地安全壳与读取”和 LOCAL-002-UIB“显式账户准备与新增消费”两个实现子切片。
- 未登录只开放 Records 与本地 Settings；已有登录用户暂保留五 Tab。
- 不静默创建账户，不在同步实现前提供本地模式登录入口。

## 验证

- 本轮为纯文档评估，未修改 Swift，未运行 macOS 编译。
- `npm run governance:check`：通过，阶段索引已连接当前入口。
- `npm run governance:arch`：通过，未增加架构基线违规。
- `git diff --check`：通过；规格索引、阶段索引、ADR 和交接引用均存在。

## 下一步

1. 合并评估与规格。
2. 从最新 main 新建 `test/LOCAL-002-UIA本地安全壳红灯`。
3. 先证明 Root、本地月份读取和网络闸门红灯，再写最小实现。
4. UIA 全绿后独立进入 UIB，不在同一 PR 扩大账户表单范围。
