# PWA-065A 至 PWA-065E PWA 账户读取边界实现记录

> 日期：2026-08-16
>
> 基线：`8ea4dc7`（PWA-065 收口 PR #97 合并提交）
>
> 分支：`feature/PWA账户读取边界实现`
>
> 状态：本地实现与回归完成，待 PR 验证

## 当前范围

- PWA-065A：账户列表 Repository 与列表失败收敛。
- PWA-065B：详情 section Repository 与 ensure/list 分离。
- PWA-065C：Account Detail State 的 Promise 复用和 account/user/generation stale。
- PWA-065D：分区 partial error 与刷新结果。
- PWA-065E：Store/Page 兼容接线。

## 已完成

- 已读取 TDD 规范、账户读取边界评估、ADR-026 和收口交接。
- 已建立正式 Spec、文件范围、非目标、测试层与完成定义。
- 已扩展 Account Repository 的账户、流水、还款记录、周期读取和显式 ensure transport，DTO 从 Store 移出。
- 已新增 Account Detail Feature，覆盖同请求复用、账户/用户/reset stale、负债分区适用性和 partial/failed 结果。
- 已让 `loadData`、`refreshAccountsFromDB`、`openAccountDetail` 和 `refreshAccountDetail` 经新边界委托，并移除账户读取后的隐藏 repair 调用。
- 已在详情页增加来源快照、周期、还款记录和流水的分区 loading/error/重试状态。
- 已新增 `test:account-read` 并接入 Release Validation。

## TDD 证据

| 场景 | 测试文件 | 红灯/特征 | 当前状态 |
|---|---|---|---|
| PWA-065A | `accountRepository.test.mjs`、`accountReadBoundary.test.mjs` | 缺少 `listAccounts` 时红；实现后绿 | 已完成 |
| PWA-065B | `accountRepository.test.mjs`、`accountDetailFeature.test.mjs`、`accountReadBoundary.test.mjs` | 缺少详情 transport 时红；实现后绿 | 已完成 |
| PWA-065C | `accountDetailFeature.test.mjs` | Feature 模块不存在时红；实现后绿 | 已完成 |
| PWA-065D | `accountDetailFeature.test.mjs`、`accountReadBoundary.test.mjs` | 结构化状态和分区收敛缺失时红；实现后绿 | 已完成 |
| PWA-065E | `accountReadBoundary.test.mjs` | 页面无分区错误状态时红；实现后绿 | 已完成 |

## 红灯证据

- `npm run test:account-read` 首个有效红灯：12 项中 4 项通过、8 项失败。
- 失败原因是 `createAccountDetailFeature.js` 不存在、Account Repository 缺少 `listAccounts/listAccountEntries/listAccountPayments`、Store 无 `accountDetailState`/委托，以及页面无分区错误状态。
- 红灯前修正了一处测试切片标记错误；该环境/测试缺陷未冒充业务红灯。

## 绿灯证据

- 最小实现后 `npm run test:account-read` 17 项全部通过。
- 实现审查补充“资产账户不读取负债专属 payments/cycles”场景，防止普通钱包被缺表错误误报为 partial。

## 验证

- `npm run test:account-read`：17 项通过。
- `npm run test:repayment`：15 项通过（包含新增 Account Repository 读取特征）。
- `npm run test:account-binding`：11 项通过。
- `npm run test:finance-save`：16 项通过。
- `npm run test:record-read`：14 项通过。
- `npm run test:wallet-snapshot-amount`：通过。
- `npm run build`：通过，仅既有 `eval` 与 bundle size 警告。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过，仅既有人工清单警告。
- `git diff --check`：通过，仅 Git 行尾转换提示。
- 未执行生产查询、迁移、部署、真实数据写入或 TestFlight。

## 未验证与风险

- 远程 Release Validation 与预览门禁尚未运行。
- 未在已登录真实页面执行账户快速切换和分区错误视觉验收；本轮由 Feature/源边界测试与 Vite 构建覆盖。
- 来源快照读取协作者仍复用 Store 的 `data_records` 与图片签名能力；它未进入 Account Repository，后续可在 Record/Wallet Snapshot 读取切片继续收窄。
- wallet repair 仅移出隐式读取调用，最终替代入口不在本片实现；这会停止读取触发的自动余额回填，符合 ADR-026，但后续显式 repair 入口尚未建立。
