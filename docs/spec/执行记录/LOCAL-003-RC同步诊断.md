# LOCAL-003 RC 同步诊断执行记录

> 状态：账户依赖修复实现完成，等待 macOS 门禁与真实 TestFlight 回归
>
> 范围：iOS Expense + Account 同步失败的脱敏诊断摘要

## 目标

为 RC 真机复现提供一条可读的同步诊断链，区分本地准备、传输/服务、部分失败、游标过期、冲突和响应无效，同时不记录认证 token、完整业务 payload 或远端原始错误文本。

## 本轮改动

- `LocalSyncDiagnostic` 记录同步阶段、profile 标识、待处理操作数量、上传/拉取计数、失败类别和本地同步状态。
- `AppState.synchronizeLocalData()` 在同步开始、成功和失败时更新诊断摘要。
- 设置页展示最近一次诊断摘要，便于 TestFlight 复现后反馈。
- 失败类别只保留稳定枚举，不把服务端响应原文写入 UI 或本地持久化。
- 本轮补充修复：本地账户创建与 `account/upsert` Outbox 在同一事务提交；旧账户若仍被待上传消费引用且缺少账户操作，则幂等补偿一条账户操作；待上传列表按账户优先排序；账户导入也生成账户 Outbox。
- 设置页本地账户说明改为“默认保存在本机，开启云端同步后同步到云端账号”，与实际行为一致。

## 行为不变量

- 诊断不会改变同步请求、绑定、Outbox、cursor 或冲突处理语义。
- 同步失败仍保留原有本地事实和重试出口。
- 成功状态只有在现有 `LocalSyncRunner` 返回成功后才展示；诊断不会将失败改写为成功。
- 未登录、服务不可用等前置失败不生成包含凭据的诊断内容。

## 验证

- `git diff --check`：通过。
- `node scripts/check-project-governance.mjs`：通过。
- `node scripts/check-architecture-boundaries.mjs`：通过，未新增架构违规。
- `test:ios-local-expense-app-boundary`、`test:ios-local-record-detail-boundary`：通过。
- Swift XCTest 和 macOS iOS Build：Windows 无工具链，待 GitHub 门禁执行。
- `LocalSyncAppStateTests`：新增成功与失败诊断断言；需 GitHub macOS XCTest 验证。
- Windows 不执行 Swift 编译；TestFlight 真实账号、生产 RPC、迁移和双设备仍未验证。

## 下一步

从门禁通过的固定提交触发 TestFlight，用 `test2` 重试 RC-004/005/009/010/011/012/015；先确认账户操作成功，再确认 4 条消费全部接受、重复同步不重复落库且余额无漂移。双设备场景继续标记为环境暂不可验证。
