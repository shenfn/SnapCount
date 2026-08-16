# PWA-063 PWA 账户补绑边界评估记录

> 日期：2026-08-16
>
> 基线：`564bd20`
>
> 分支：`docs/PWA账户补绑边界评估`

## 本轮范围

- 只读核对单笔推荐补绑、手动补绑、批量预览与批量执行调用链。
- 核对 canonical RPC、Record Repository 复用范围、刷新与用户切换出口。
- 产出边界评估、ADR-024、PWA-063A 至 PWA-063F 场景和后续实现门禁。

## 证据摘要

- `bindRecordToAccount` 对支出与收入仍直接调用保存 RPC，并各有两个同名 `p_occurred_at` 对象键。
- JavaScript 当前以后一个同值键覆盖前一个，构建可通过；这是静默维护缺陷，不是当前线上值变化。
- 两个 RPC 使用 `auth.uid()`、记录行锁并原子维护账户流水，且返回 canonical 正式记录；本轮无需修改数据库。
- Store 丢弃 RPC 返回数据，只检查 `error`；成功后刷新函数的结构化失败结果未被消费。
- 批量顺序循环只累计布尔成功/失败，`silent` 不抑制逐项错误提示，也没有用户/generation 检查。
- reset 会清空页面 action 锁，却不能终止旧批量循环；旧循环可能继续尝试 RPC、刷新新用户页面并显示旧任务结果。
- 推荐函数同时使用支付线索和默认账户；本轮明确冻结推荐策略，避免 transport 收拢夹带产品行为变化。

## 基线验证

| 命令 | 结果 |
|---|---|
| `npm run test:finance-save` | 16 项通过 |
| `npm run test:record-read` | 14 项通过 |
| `npm run test:finance-occurred-at` | 通过 |
| `npm run test:finance-options` | 通过 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过，仅既有人工清单警告 |
| `npm run build` | 通过，仅既有 `eval` 与 bundle size 警告 |

## 结论

- 后续实现复用 Record Repository，但建立独立 Account Binding Feature。
- PWA-063A 至 PWA-063F 分别固定 transport、并发冲突、会话隔离、accepted/refresh 分层、批量逐项结果和 Store/Page 收敛。
- 当前分支只写文档；未修改业务代码、RPC、迁移、账户规则或生产状态。

## 未验证与剩余风险

- 未连接真实服务执行补绑；数据库行为依据现有迁移与契约测试只读核对。
- 默认账户进入批量推荐的产品风险未解决，需独立产品评审后才能改变。
- Account Binding Feature 与 Finance Save Feature 之间不提供全局写入串行化；现有 UI 交互降低并发概率，但该边界不得被描述为已解决。
- 批量写入没有数据库级 operation ID 或事务包裹，网络不确定性和部分成功是必须保留的事实。
