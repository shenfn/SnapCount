# PWA-069A 至 PWA-069B PWA 账户流水 helper 门面清理记录

> 日期：2026-08-16
>
> 基线：`48823c3`
>
> 分支：`feature/PWA流水helper门面清理`
>
> 状态：实现完成，待 PR 验证

## 实现

- 删除 `useStore.js` 中无消费者的 `upsertAccountEntry`、`voidAccountEntries` 及公开返回值。
- 新增全量 `src/` 源边界测试，禁止两个旧 API 和两个数据库 primitive 调用名进入 PWA 产品代码。
- 新增 `npm run test:account-entry-helper` 并接入 Release Validation。
- 未修改数据库 RPC、migration、权限、iOS、Edge 或 Planner。

## 红绿证据

- 红灯：专项测试失败并命中 `useStore.js` 5 处旧定义、调用和出口。
- 绿灯：最小删除后专项测试 1 项通过。
- 相关业务回归 138 项通过，连同专项共 139 项。

## 验证结果

| 命令 | 结果 |
|---|---|
| `npm run test:account-entry-helper` | 1 项通过 |
| `npm run test:finance-save` | 16 项通过 |
| `npm run test:account-binding` | 11 项通过 |
| `npm run test:repayment` | 18 项通过 |
| `npm run test:screenshot-repayment` | 30 项通过 |
| `npm run test:account-read` | 20 项通过 |
| `npm run test:account-management` | 19 项通过 |
| `npm run test:wallet-snapshot` | 10 项通过 |
| `npm run test:record-read` | 14 项通过 |
| `npm run build` | 通过；只有既有 eval 与 bundle size 警告 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过；只有既有人工清单警告 |
| `git diff --check` | 通过 |

## 未验证与风险

- 未运行 PostgreSQL fixture，因为数据库定义和调用链没有变化。
- iOS 仍直接使用 create primitive；A4 接入 `apply_wallet_snapshot` 前必须保留兼容。
- 未执行生产查询、migration、部署、真实数据写入或 TestFlight。

## 下一步

1. 复核 diff，提交、推送并创建实现 PR。
2. 远程门禁通过并合并后，从最新 main 建立 A3 只读收口审计。
3. 收口审计明确页面直连、数据域 adapter、RPC 契约清单和兼容门面的剩余处置，再决定 A3 是否完成。
