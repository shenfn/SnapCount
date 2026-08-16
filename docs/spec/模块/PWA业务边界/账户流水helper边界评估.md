# PWA 账户流水 helper 边界评估

> 任务：CLEAN-001/A3、PWA-069
>
> 基线：`7d8cba9`（PWA-068 收口 PR #109 合并提交）
>
> 状态：只读评估完成，PR #110 已合并

## 1. 结论

PWA Store 中的 `upsertAccountEntry` 与 `voidAccountEntries` 已经没有产品消费者。PWA-068 将最后一个调用者迁移到 `apply_wallet_snapshot` 后，这两个函数只剩定义和 Store 公开返回值；继续保留会扩大公共门面，并暴露“失败只写 warning、调用方无法判断是否 accepted”的错误契约。

后续 PWA-069 实现片可以删除这两个 Store helper 及其公开出口，并增加源边界测试，禁止 PWA 产品代码重新直接调用 `create_account_entry_for_record` / `void_account_entries_for_record`。这次清理不需要 Repository 替代，也不新增数据库 migration。

同名数据库 RPC 不能随 PWA 门面一起删除或改签名。当前有效的财务保存与统一删除事务仍在数据库内部调用它们，iOS wallet 快照关联生产路径也直接调用 `create_account_entry_for_record`。数据库兼容面必须冻结到 A4：先让 iOS 接入 PWA-068 已建立的 `apply_wallet_snapshot` 原子命令，再用独立 PostgreSQL fixture 固定流水 primitive 的权限、replacement、void、余额触发器和失败回滚，最后才评估是否撤销客户端直接执行权限或收窄为内部函数。

## 2. 调用与归属矩阵

| 对象 | 当前消费者 | 当前语义 | 本轮裁决 |
|---|---|---|---|
| `useStore.upsertAccountEntry` | 无；仅定义并从 Store 返回 | 参数不合法或 RPC 失败均返回 `undefined`，失败只 `console.warn` | PWA-069 最小实现删除定义和公开出口 |
| `useStore.voidAccountEntries` | 无；仅定义并从 Store 返回 | 缺参或 RPC 失败均返回 `undefined`，失败只 `console.warn` | PWA-069 最小实现删除定义和公开出口 |
| `create_account_entry_for_record` | 当前财务保存 RPC；iOS wallet 快照关联 | 锁定当前用户账户；同来源、同类型旧流水先 void，再插入新流水 | 数据库与 iOS 兼容面冻结，不删除、不改签名 |
| `void_account_entries_for_record` | 当前财务保存解绑；统一记录删除 | 只作废 `auth.uid()` 名下匹配来源的活跃流水；重复调用返回 0 | 数据库内部事务 primitive，冻结 |
| `apply_wallet_snapshot` | PWA wallet 快照 Feature | 创建/关联、账期、付款证据与余额校准的原子权威 | PWA 继续使用；A4 作为 iOS 替代入口 |

仓库静态搜索确认：`src/` 中两个 camelCase helper 的命中仅为 `useStore.js` 的定义和返回值；没有页面、Feature、Repository、测试或其他产品模块调用。数据库迁移中的多处命中包含历史函数版本，不能按命中数量误判为多套运行实现。按最终 migration 顺序，当前有效依赖是：

- `20260808120000_finance_occurred_at_contract.sql` 的 canonical `save_transaction_with_account` / `save_income_with_account` 调用 create/void primitive；
- `074_unified_record_deletion_and_cleanup_audit.sql` 的 `delete_record_with_cleanup` 调用 void primitive；
- `WalletSnapshotRepository.swift` 的负债快照关联调用 create primitive；
- `20260816210000_wallet_snapshot_atomic_contract.sql` 已改为在事务内部直接写入明确类型的流水，不依赖通用 helper。

## 3. 只读发现

### B-47：PWA 兼容门面已经变成无消费者 API

两个 helper 仍从 Store 返回，使任意页面都能绕过 Record/Account Repository 直接调用安全定义者 RPC。它们没有结构化 `accepted`、`rejected` 或 `failed` 结果，也没有用户/generation stale 保护。最后一个旧调用者已由 PWA-068 移除，因此保留门面不再提供兼容价值。

删除范围必须同时包含函数定义和 Store 返回值；只取消导出会留下死代码，只删除定义会造成运行时引用错误。源边界测试应扫描整个 `src/`，而不是只断言某个函数片段。

### B-48：数据库 create 是 replacement primitive，不是严格幂等命令

`create_account_entry_for_record` 会锁定当前用户账户，把同 `source_table + source_id + entry_type` 的活跃流水标记为 `replaced_by_upsert`，随后总是插入一条新流水。重复相同请求的余额净效果依赖余额触发器先撤销再应用，但流水 ID 和审计历史会继续增长。

因此旧 Store 注释“保证幂等”不准确。该函数更接近“替换当前来源流水”，不能作为网络重试的 exactly-once 命令。未来若仍允许客户端直调，必须明确 operation identity 或把调用收进更高层原子业务命令。

### B-49：安全定义者 primitive 的客户端权限仍然过宽

create primitive 会验证 `account_id` 属于 `auth.uid()`，void primitive 也按当前用户过滤，因此不能直接修改其他用户余额。但 create 不验证 `source_table/source_id` 是否存在、是否属于同一用户或是否与 `entry_type` 匹配；已认证客户端可以在自己的账户中制造指向任意 UUID 的来源证据。void 也允许客户端按任意来源组合批量作废自己名下流水。

`051_revoke_anon_on_security_definer_functions.sql` 与后续 finance migration 已撤销 anon/PUBLIC 并保留 authenticated 执行，这阻止匿名调用，但不等于收窄已认证客户端能力。PWA-069 不改权限，因为 iOS 仍直接依赖；A4 替换 iOS 调用后，应单独评估撤销 authenticated execute，让 create/void 只作为数据库事务内部 primitive。

### B-50：现有测试只覆盖部分间接语义

finance PostgreSQL fixture 已间接证明：保存支出/收入时会生成活跃流水、未知发生时间保持 null、同租户时间回填不会污染跨租户流水，并连续执行 finance migration 两次。Node contract 也固定了 create primitive 的 `occurred_at` 语义。

现有测试没有直接固定以下行为：

- create/void 的 authenticated、anon、跨账户所有权边界；
- 相同来源 replacement 后旧流水、余额与返回行；
- 重复 void 的返回值与余额不重复变化；
- 不存在或跨用户 `source_id` 的处理策略；
- create 中途失败对旧流水和余额的事务回滚；
- 并发 replacement 的审计与最终余额。

这些缺口不阻止删除无消费者的 PWA 门面，但会阻止直接删除数据库 RPC、收窄权限或宣称它们具备 exactly-once 语义。

### B-51：iOS 仍是实际生产消费者，不是历史死代码

iOS `DomainsView` 可触发 `AppState.linkWalletSnapshot`，继而调用 `WalletSnapshotRepository.link`。关联负债快照时，Repository 会调用 `reconcileLiability`，其中直接执行 `create_account_entry_for_record`，成功后再 patch `last_reconciled_at`；RPC 失败被转换成 warning，但前面的账户和记录写入已经可能成功。

这条路径仍由可见 UI 入口触发，不能按“PR 已关闭”或“PWA 已迁移”视为遗留代码。PWA-068 已提供跨端可复用的原子 RPC，正确顺序是 A4 先替换 iOS 多步写入，再处理通用流水 primitive 的外部权限。

## 4. PWA-069 最小实现范围

后续实现只包含两个场景：

| 场景 | 行为不变量 | 测试层 |
|---|---|---|
| PWA-069A | `src/` 不再定义、公开或调用 `upsertAccountEntry` / `voidAccountEntries`；PWA 不直接调用两个数据库 primitive | Node 源边界测试 |
| PWA-069B | 删除门面后财务保存、账户补绑、还款、wallet 快照、正式记录与 PWA build 保持通过 | 既有专项回归与构建 |

实现不新建 Account Repository 方法。无消费者 API 不应为了“分层完整”先迁入 Repository 再删除；这样只会把无效契约固化到新边界。

## 5. 冻结与后续边界

PWA-069 实现片继续冻结：

- `supabase/migrations/`、数据库函数签名、grant/revoke 和生产 schema；
- iOS `WalletSnapshotRepository`、AppState 和页面；
- Edge、Planner、真实数据、生产部署、migration 和 TestFlight；
- 历史 migration 文本中的函数定义和引用。

A4 的独立后续任务应按以下顺序进行：

1. 为 iOS wallet 快照建立与 PWA-068 相同的场景 fixture 和 XCTest transport 契约。
2. 将 iOS 创建/关联改为调用 `apply_wallet_snapshot`，删除客户端多步 REST 与 direct create primitive 调用。
3. 建立 create/void primitive 的 PostgreSQL 行为 fixture，核对所有当前数据库内部调用者。
4. 再决定保留 authenticated 兼容、撤销外部 execute，或由新的受限内部函数替代；不得在同一片顺手删除。

## 6. 进入实现的门禁

1. 本评估、执行记录、交接快照和索引通过纯文档 PR 门禁并合并。
2. 从合并后的最新 main 建立独立 `feature/PWA流水helper门面清理` worktree。
3. 先增加 PWA-069A 源边界红灯，证明当前 Store 定义/公开两个 helper 且 `src/` 存在 direct RPC。
4. 最小实现只删除 `useStore.js` 的两个函数和返回值，不修改数据库或 iOS。
5. 专项、财务、账户、wallet、正式记录、build、治理和架构检查通过后，再做 A3 阶段对账；不能因代码删除很小就直接宣称 A3 完成或进入 A4。

## 7. 本轮验证

- 已只读核对 PWA Store、页面、Feature、Repository 和测试中的全部 camelCase helper 引用。
- 已只读核对最终 finance、统一删除、权限 hardening、wallet snapshot migrations 及相关 PostgreSQL/Node fixture。
- 已只读核对 iOS `DomainsView -> AppState -> WalletSnapshotRepository -> reconcileLiability` 实际调用链。
- `npm run governance:check`：通过。
- `npm run governance:arch`：通过；只有既有的 RPC 契约与重复业务规则人工清单警告。
- `git diff --check`：通过。
- 未执行 PostgreSQL fixture、PWA build、生产查询、migration、部署、真实数据写入或 TestFlight；本轮没有业务代码变更。
