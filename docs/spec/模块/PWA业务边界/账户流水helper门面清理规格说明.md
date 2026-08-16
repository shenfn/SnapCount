# PWA 账户流水 helper 门面清理规格说明

> 任务：CLEAN-001/A3、PWA-069A 至 PWA-069B
>
> 基线：`48823c3`（PWA-069 评估 PR #110 合并提交）
>
> 状态：实现完成，待 PR 验证

## 1. 目标

删除 PWA Store 中没有消费者、吞掉失败且绕过既有业务边界的 `upsertAccountEntry` / `voidAccountEntries` 兼容门面，并用持续集成源边界测试阻止它们或对应数据库 primitive 被 PWA 产品代码重新直接调用。

数据库函数、权限、iOS 调用和历史 migration 全部保持不变。无消费者 API 不迁入 Repository。

## 2. 场景与测试映射

| 场景 | 行为不变量 | 测试层 |
|---|---|---|
| PWA-069A | `src/` 不定义、公开或调用两个 camelCase helper，也不直接出现两个数据库 primitive 调用名 | `accountEntryHelperBoundary.test.mjs` 全量源扫描 |
| PWA-069B | 删除门面不改变财务保存、补绑、还款、截图还款、账户读写、wallet 快照和正式记录行为 | 既有 8 组专项回归与 PWA build |

## 3. 实现范围

- `useStore.js`：删除两个函数定义和 Store 返回值。
- `src/features/accounts/__tests__/accountEntryHelperBoundary.test.mjs`：递归扫描 PWA 产品源码。
- `package.json` 与 `release-validation.yml`：提供本地命令并在 PR 综合门禁执行。
- Spec、执行记录、阶段索引和交接快照：持久化红绿证据与后续边界。

## 4. TDD 证据

红灯首次命中 5 处：两个函数定义、两个 direct RPC 调用和一个 Store 公开出口。最小删除后专项测试 1 项通过。

PWA-069B 回归共 138 项通过：财务保存 16、账户补绑 11、还款 18、截图还款 30、账户读取 20、账户管理 19、wallet 快照 10、正式记录 14。连同 PWA-069A 专项共 139 项。

## 5. 非目标

- 不修改、删除或改签名 `create_account_entry_for_record` / `void_account_entries_for_record`。
- 不修改 migration、grant/revoke、iOS、Edge、Planner、生产配置或真实数据。
- 不建立通用 Account Entry Repository；数据库内部事务 primitive 的收窄在 A4 另行评估。
- 不因本片通过而直接宣称 A3 完成；必须先做阶段收口审计。

## 6. 完成定义

- PWA-069A 红灯和绿灯证据存在，测试进入 Release Validation。
- PWA-069B 全部专项回归、PWA build、治理、架构与 diff 检查通过。
- PR 合并后建立 A3 只读收口审计，裁决页面直连、数据域 adapter 和 RPC 契约清单等剩余项。
