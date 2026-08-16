# PWA-063A 至 PWA-063F PWA 账户补绑边界实现记录

> 日期：2026-08-16
>
> 基线：`30aed05`
>
> 分支：`feature/PWA账户补绑边界实现`

## 目标行为

- Account Binding Feature 独立持有单笔/批量补绑的并发、冲突、generation、stale 和刷新结果。
- Store 只提供推荐、确认和页面收敛，不直接组装保存 RPC。
- Record Repository 的 canonical DTO 是成功补绑的唯一事实输入。

## 本轮范围

- PWA-063A 至 PWA-063F 的 Spec、Feature、Store 接线、reset 接线、专项测试和发布门禁。

## 非范围

- RPC、迁移、账户流水、余额方向、推荐算法、默认账户、manual/edit、staging、待补全、wallet、删除、图片签名、iOS、Edge、Planner 和部署。

## 基线验证

沿用评估 PR #90 已登记结果；实现前重新确认财务保存、正式记录读取、发生时间、账户选项、构建和治理基线通过。

## 红灯证据

- 命令：`npm run test:account-binding`。
- 结果：4 个测试入口全部失败，退出码 1。
- PWA-063A/F：`createAccountBindingFeature.js` 不存在，测试加载报 `ERR_MODULE_NOT_FOUND` / `ENOENT`。
- PWA-063A：Store 源边界找不到 Account Binding Feature，`bindRecordToAccount` 仍直接组装两个保存 RPC。
- PWA-063E：批量函数仍在 Store 内 `for` 循环单笔补绑，找不到 `bindBatch` 和结构化计数。
- 失败来自目标 Feature 与接线缺失，不是网络、凭据或环境问题。

## 最小实现

- 新增 `createAccountBindingFeature.js`，提供正式记录 DTO 到 Repository 输入的单一映射。
- 同记录同账户共享 Promise；同记录不同账户返回 `binding_conflict`。
- generation / 用户检查覆盖 Repository 返回、收敛回调、刷新回调和批量下一项入口。
- 单笔保留 accepted 与 refresh 分层；批量返回逐项结果、成功/失败计数和一次刷新结果。
- Store 的单笔和批量补绑统一委托 Feature，以 canonical record 更新财务数组并移除成功未绑定项。
- 推荐、预览、默认账户和确认逻辑保持原状；`resetUserData` 增加 Feature reset。
- 发生时间契约改为读取 Feature 的单一 `occurredAt` 映射；Release Validation 增加专项步骤。

## 绿灯与回归

| 命令 | 结果 |
|---|---|
| `npm run test:account-binding` | 11 项通过 |
| `npm run test:finance-save` | 16 项通过 |
| `npm run test:record-read` | 14 项通过 |
| `npm run test:finance-occurred-at` | 通过 |
| `npm run test:finance-options` | 通过 |
| `npm run test:wallet-snapshot-amount` | 通过 |
| `npm run test:staging-archive` | 13 项通过 |
| `npm run test:staging-read` | 10 项通过 |
| `npm run test:staging-discard` | 14 项通过 |
| `npm run test:staging-retry` | 12 项通过 |
| `npm run test:expression-presentation` | 22 项通过 |
| `npm run check:security-contracts` | 通过 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过，仅既有人工清单警告 |
| `npm run build` | 通过，仅既有 `eval` 与 bundle size 警告 |
| `node --check`（Feature、Store、发生时间契约） | 通过 |
| `git diff --check` | 通过 |

## 未解决风险

- 批量补绑是多次数据库事务，允许部分成功。
- 网络超时后的重复请求没有 operation ID，不能承诺端到端幂等。
- 推荐默认账户的产品策略保持现状，未在本任务重新评审。
- Account Binding Feature 与 Finance Save Feature 之间不提供全局串行化。

## 发布边界

- 不执行生产查询、迁移、部署、真实数据写入或 TestFlight。

## 首轮远程门禁修复

- PR #91 首轮 PWA build、账户补绑专项、财务保存、正式记录、Edge 和双运行时核心检查均通过。
- Shadow Planner 为 184/185 项通过；唯一失败是旧缓存静态契约仍要求 `bindRecordToAccount` 函数体直接出现失效调用，未识别 accepted 回调委托给 `convergeAccountBinding`。
- 契约已收窄为验证：Account Binding Feature 的失败结果在 accepted 回调前退出；Store 的 accepted 回调使用 canonical record 调用收敛函数；收敛函数以 `record.id` 失效缓存。
- 定向缓存契约 3 项通过。
- Windows 全量 Shadow 中 105 项通过，5 个依赖 `esbuild` 的测试在加载阶段失败；这是环境失败，最终完整结果等待 GitHub `npm ci` 环境复核。

## 远程门禁与合并结果

- 修复提交 `0e51204` 推送后，PR #91 第二轮治理、PWA/Edge/迁移/Shadow、iOS 检测与预览门禁通过。
- GitHub 状态汇总为 8 项成功；SwiftUI 构建因无 iOS 文件变更按条件跳过，不属于失败或未验证。
- 规格提交：`db63e80`。
- 实现提交：`a783149`。
- 静态契约修复提交：`0e51204`。
- PR：#91。
- 合并提交：`35dae06`。
- 合并时间：2026-08-16。
