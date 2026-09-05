# LOCAL-003 Expense + Account Sync Release Candidate Gate

> 状态：进行中
>
> 基线：`7bcb87a`（PR #186 合并提交）
>
> 范围：iOS `expense/accounts` 本地优先、可选云同步闭环

## 1. 目标

确认消费与账户同步骨架可以进入真实环境候选版本。通过条件是：本地事实不丢失，云端同步可重试，重复操作不重复落库，失败状态可解释，账户余额不因同步重放漂移。

本 Gate 不扩展到收入、运动、睡眠、饮食/阅读，不实现冲突人工解决 UI，也不替代 TestFlight 的发布审批。

## 2. 前置条件

| 条目 | 状态 | 证据/说明 |
|---|---|---|
| D-REMOTE-007 入口接线 | 已完成 | PR #176，已合并 |
| D-REMOTE-008 失败出口 | 已完成 | PR #177，已合并；门禁全绿 |
| 主线固定提交 | 已确认 | `origin/main@7bcb87a` |
| 同步数据库迁移 | 已应用并登记 | 生产已应用 `20260826090000`、`20260828090000`、`20260829100000`；`supabase migration list --linked` 显示 Local/Remote 完全一致 |
| 真实 Supabase/账号 | 已具备 | 项目 `igbghrhsdaolxljgiisf` 已完成 schema、RPC、RLS 与权限复核；真机业务验收待执行 |
| macOS Build/XCTest | 已通过 | PR #186 的 `Build SwiftUI app` 和 `iOS Build Gate` 全绿 |

## 3. 验收矩阵

### A. 单设备本地优先

| 编号 | 场景 | 预期 | 状态 |
|---|---|---|---|
| RC-001 | 未登录创建消费和账户 | 页面可用；数据写入本地；Outbox 不要求登录 | 待真机 |
| RC-002 | 杀 App/重启后查看本地数据 | 消费、账户、Outbox、Checkpoint 状态可恢复 | 待真机 |
| RC-003 | 编辑和删除本地消费 | 本地事实正确；删除产生 tombstone/失败可重试状态 | 待真机 |

### B. 绑定与首次同步

| 编号 | 场景 | 预期 | 状态 |
|---|---|---|---|
| RC-004 | 登录并绑定 Workspace | 绑定成功后才允许上传；未绑定不可上传 | 待真机/真实环境 |
| RC-005 | 本地已有数据首次同步 | 云端出现对应消费、账户和流水；本地页面仍从同一套本地读模型读取 | 待真机/真实环境 |
| RC-006 | 云端已有数据首次 Pull | 本地投影可见；不覆盖本地未上传事实 | 待真机/真实环境 |

### C. 双设备与离线恢复

| 编号 | 场景 | 预期 | 状态 |
|---|---|---|---|
| RC-007 | 设备 A 创建消费，设备 B Pull | B 最终看到同一消费和账户余额 | 待双设备 |
| RC-008 | A 断网创建，恢复网络后同步 | 本地立即可见；恢复后 Outbox 上传且不重复 | 待双设备 |
| RC-009 | 上传中杀 App 后重启 | 未完成操作仍在 Outbox；重试后至多落库一次 | 待真机 |

### D. 失败、幂等与冲突

| 编号 | 场景 | 预期 | 状态 |
|---|---|---|---|
| RC-010 | 部分 rejected | accepted 才标记 sent；rejected 保持 failed；UI 不显示“同步完成” | 自动化已覆盖；真机待验证 |
| RC-011 | cursor_expired | 清除旧 cursor；本地事实和 Outbox 保留；下一次可全量 Pull | 自动化已覆盖；真机待验证 |
| RC-012 | 同一操作重试 | 幂等键保证不产生重复消费、流水或余额变更 | 自动化已覆盖；真实环境待验证 |
| RC-013 | 版本冲突 | 进入 unresolved/failed；远端投影不静默覆盖本地冲突实体 | 自动化已覆盖；双设备待验证 |
| RC-014 | 账号切换/旧任务回写 | 旧 Workspace 的结果不能污染新账号；失败有重新绑定出口 | 自动化已覆盖；真机待验证 |

### E. 余额和发布候选

| 编号 | 场景 | 预期 | 状态 |
|---|---|---|---|
| RC-015 | 重复同步、编辑、删除后核对余额 | `current_balance` 与有效流水重算一致，无漂移 | 待真实环境 |
| RC-016 | 迁移应用后完整回归 | 迁移可重复执行；RPC、RLS 和现有财务契约不回归 | 待生产/验收环境 |
| RC-017 | TestFlight 候选构建 | 从固定且门禁通过的主线提交触发；安装后完成 RC-001 至 RC-015 | 构建 104 上传成功（Run `33237295903`，主线 `7bcb87a`）；等待 App Store Connect 处理和真机复验 |

## 4. 放行规则

生产迁移确认、自动化门禁和固定提交是 TestFlight 前置条件。满足前置条件并获得用户授权后，触发 TestFlight 候选构建，再用该构建执行真机和双设备验收。

RC Gate 只有在 RC-001 至 RC-017 全部有证据、且没有未解释的业务失败时通过。环境失败（网络、权限、Apple/GitHub 队列）单独记录，不得伪装成业务通过。

通过后：

1. 消费/账户同步作为其他数据域的适配模板；
2. 再评估收入、运动、睡眠、饮食/阅读接入，不为每个域复制一套同步核心。

## 5. 当前阻断与授权边界

- 旧财务迁移存在版本命名差异（生产 `20260808054219`、仓库文件 `20260808120000`），作为独立治理项处理，不阻断本 RC。
- TestFlight 已上传，等待 App Store Connect 完成处理后进行真机验收。
- Windows 不能替代 macOS 验证 Swift；iOS 编译以 GitHub macOS 门禁为准。

## 6. 本轮真实验证记录（2026-08-29）

- TestFlight 构建：`1.0 (33228057081)`，基于已合并的同步诊断提交；安装后使用既有主账号 `test2`。
- 结果：本地存在 4 条待处理消费操作，同步失败并显示 `account not found`；本地消费、账户和 Outbox 保留，未发现本地事实丢失。
- 诊断链：本地 `expense` Outbox → `sync_expense_batch` → 服务端按 payload.account_id 查找当前用户账户 → 云端账户不存在 → RPC 抛出 `account not found` → 客户端标记失败并保留待重试。
- 根因分类：业务代码缺陷。`LocalExpenseRepository.createAccount` 原先只写 `local_accounts`，没有写 `account` Outbox；已有账户也没有补偿事件。不是账号切换、网络或迁移执行失败的证据。
- 修复范围：账户 Outbox 与消费依赖顺序；不扩展到其他数据域、冲突 UI 或同步协议重构。

## 7. 下一步

完成账户 Outbox 窄修复后，以 macOS iOS Build/XCTest 和治理门禁为准合并，再从固定提交触发新的 TestFlight。安装后使用 `test2` 重试，确认账户先上传、4 条消费全部接受、重复同步不重复落库且余额无漂移。修复前不把 RC 标记为通过，也不进入其他数据域。

## 8. 第二轮真实验证与字段契约修复（2026-08-29）

- 账户 Outbox 修复已合并到 `main@c90d4a8`，新 TestFlight 中原 `account not found` 已不再是当前错误。
- 新失败：`null value in column "type" of relation "transactions" violates not-null constraint`。本地事实和待重试 Outbox 仍保留。
- 根因：同步 RPC 插入消费时未写生产必填字段 `transactions.type`；测试 fixture 缺少该非空约束，因此旧门禁误绿。集中审计同时发现 RPC 未明确写 `status/source`、编辑未覆盖全部字段、Pull 丢失 `platform/note`，以及删除错误写入约束不允许的 `status=deleted`。
- 当前范围：仅修复 Expense + Account 同步字段契约。新客户端 payload 明确发送 `type=expense/source=manual`；服务端兼容已有旧 Outbox；RPC 写入正式消费 `type=expense/status=done`，完整更新可编辑字段；Pull 往返 `platform/note`；删除沿用统一删除模型 `transactions.deleted_at`。
- 数据库落地：新增迁移 `20260829100000_remote_sync_expense_field_contract.sql` 替换已部署 RPC，不修改已登记的 `20260826090000` 历史迁移。
- 测试：生产关键非空/枚举/删除约束写入 PostgreSQL fixture，新增 DREMOTE-018/019；iOS 测试固定 Repository/导入 Outbox 和 Pull 字段映射。
- 已验证：治理检查、架构依赖检查、LOCAL-002-APP 与 LOCAL-003B 边界脚本通过；`git diff --check` 通过。临时 PostgreSQL 17 容器已按 CI 顺序重复执行旧同步迁移和新字段迁移，DREMOTE 数据库契约全绿。
- 未验证：Windows 无法执行 Xcode/XCTest，Swift 编译与 XCTest 交给 PR 的 macOS iOS Build。
- 已知基线：`test:ios-local-account-boundary` 的旧 `showLocalAccountPreparation` 静态断言在当前 main 已失效，与本次字段契约无关，不在本 PR 修改页面。

发布执行结果：PR #186 全部门禁通过并合并为 `7bcb87a`。生产 dry-run 只包含 `20260829100000_remote_sync_expense_field_contract.sql`，迁移应用成功；远端 `public` schema 导出确认 `sync_expense_batch` 已包含 `type=expense`、`status=done`、`deleted_at` tombstone 和 `platform/note` Pull 字段。TestFlight Run `33237295903` 从固定 `main@7bcb87a` 上传成功，实际构建号 104，Delivery UUID `73b36822-cbdf-49d6-af60-b2bf04349049`。

下一步：等待构建 104 在 TestFlight 可安装后，用 `test2` 重试 RC-005/012/015。先确认原 4 条待处理消费全部接受并出现于云端，再连续同步两次确认不重复落库，最后核对本地与云端账户余额无漂移；出现失败时保存新的脱敏诊断摘要，不继续猜测字段缺口。

## 12. 真机月份投影与云端删除问题（2026-08-31）

- 真机反馈：进入日期后首页没有数据；登录/退出云端时同一日期的记录数量不一致；云端删除交易后 iOS 本地仍保留。
- 根因一：`AppState` 用同一个月份字典同时承载本地 Expense 与远端月份，并在本地非空时提前跳过远端加载；本地读取还会覆盖远端月份，导致远端其他数据域和云端记录缺失。
- 根因二：本地记录状态为 `local`，首页统计原先只把 `done` 视为已确认消费，因此本地事实没有计入日期金额/数量。
- 根因三：PWA/旧删除路径物理删除 `transactions`，未写入 `sync_change_log`；iOS 的同步协议没有删除变更可应用，故本地投影不会收敛。
- 本轮修复：分离本地/远端月份缓存与详情；登录时即使本地非空也加载远端并按稳定记录 ID 合并；`local` 计入首页消费聚合；新增 `20260831100000_remote_sync_transaction_delete_tombstone.sql`，以 `AFTER DELETE` 触发器为硬删除写入用户隔离的 Expense tombstone 和 change log；远端同步门禁迁移重复执行两次。
- 自动化补强：新增月份本地+远端合并 XCTest、本地状态首页聚合 XCTest，以及硬删除触发器存在性和行为 SQL 断言。
- 已验证：`npm run governance:check`、`npm run check:expression-core-boundary`、`node scripts/check-migration-versions.mjs`、`test:ios-local-expense-app-boundary`、`test:ios-record-detail-image-boundary` 通过；`git diff --check` 通过。
- 环境未验证：Windows 无 Xcode/XCTest；本机 Docker/psql 服务未运行，SQL fixture 尚未本地执行；交由 PR macOS Build 与 Release Validation 门禁验证。
- 已知基线失败：`test:ios-local-shell-boundary` 在当前主线即因缺失 `Features/Settings/LocalSettingsView.swift` 和旧签名断言失败，本轮未修改该既有范围。
- 首轮 PR 门禁反馈：Swift 编译通过，但全套 XCTest 暴露两处旧测试假设（本地非空时不加载远端、同步后状态不受当前月刷新影响）；已按新统一投影契约更新测试，并保留会话有效时的同步结果状态。

下一步：提交并推送本修复 PR；以 CI 的 Swift 编译/XCTest 与 PostgreSQL 双次迁移契约为准审查。合并后再安排一次集中 TestFlight，验证日期首页、本地/云端统一记录、云端删除下拉收敛；本轮不触发 TestFlight。

## 9. 生产 schema 对账与修复（2026-08-29）

- 真正的生产 schema 对账发现：`public.transactions` 缺少同步 RPC 已使用的 `deleted_at` 与 `updated_at`；迁移历史为 applied 不能替代列级 schema 检查。
- 修复分支新增 `20260829150000_remote_sync_transaction_timestamps.sql`：仅添加两列，按既有 `created_at` 回填 `updated_at`，再设置默认值、非空约束和用户/删除时间索引；不删除或重写交易事实。
- 远端同步 fixture 已调整为先模拟生产缺列状态；迁移按 CI 顺序执行两次后，完整 D-REMOTE 契约测试通过，验证新增迁移可重复执行且同步 RPC 的删除/更新字段真实可用。
- 生产应用授权已获得，但在 PR 门禁和 macOS iOS Build 通过前不执行；应用后需重新执行列级 schema 查询、RPC smoke 和 `test2` 真机重试。

下一步：合并修复 PR 后，将新迁移应用到生产并记录 `migration list` 与 schema 查询结果；生产 smoke 通过后从固定主线提交触发新的 TestFlight，重新验证 RC-005/012/015。

## 10. 断网手动记录修复（2026-08-30）

- TestFlight 构建 105 已验证同步成功，但真机发现断网后已登录用户无法保存手动消费。
- 根因定位：手动消费已经走本地 GRDB，但统一表单打开时只刷新云端 `accounts`；断网刷新失败后，表单没有本地账户候选，导致本地消费命令拿不到 `accountID`。
- 修复范围：统一表单打开时先准备本地 workspace；消费类型优先读取 `localAccounts`，云端账户仅作为其他记录类型的候选来源；消费无显式默认账户时选取第一个本地账户。未修改同步协议、数据库迁移或远端保存路径。
- 回归测试：新增已登录但云端 session 不可用时，手动消费仍调用 `LocalExpenseUseCase`、不查询远端 session、返回“记录已保存（本机）”的 AppState 测试。
- 未验证：Windows 无法执行 Swift/XCTest；需由 PR 的 macOS iOS Build 验证，并在新 TestFlight 开启飞行模式复验。

下一步：完成 macOS Build/XCTest 和门禁后合并；从固定主线触发新 TestFlight，按“飞行模式创建消费 → 重启 App → 恢复网络同步”验证 RC-008/009。

## 11. 登录后本地投影与统一页面修复（2026-08-30）

- 真机复验发现：登录后记录页被云端快照覆盖、本地账户未参与已登录消费表单、未登录账户页直接调用云端接口导致 `Auth session missing`、退出登录后只显示本机新建消费。
- 根因不是本地数据库被清空，而是读模型和投影接线不完整：云端账户/消费没有在常规登录刷新时镜像到本地；当前实现的本地化范围仍只有 Expense + Account，收入、运动、睡眠、饮食、阅读和钱包扩展数据域尚未接入本地同步。
- 修复分支 `feature/LOCAL-003-RC本地云端统一`：云端账户与消费按稳定 ID 幂等写入本地投影且不产生 Outbox；记录页按“本地同 ID 优先、云端记录补齐”合并；无 session 时账户列表和详情回退本地读模型；统一手动消费表单在账户镜像尚未完成时仍可稳定落本地。
- 账户与消费的本地事实不因退出登录清空；退出登录后的页面可继续显示已落地的本地 Expense + Account。其他数据域退出后不可见属于当前范围限制，不宣称已经本地化。
- 原图目前仍由既有远端签名 URL + 缓存机制提供，不等同于完整本地附件库；无网络下只有已命中缓存的图片可见，本轮不扩大到附件迁移。
- 新增 Repository 投影测试，验证云端事实导入幂等、账户流水可读且不产生 Outbox。Windows 无法执行 Swift/XCTest，需由 PR macOS Build 验证。

下一步：完成 PR 门禁后集中进行一次 TestFlight 验证，覆盖“登录后云端数据落本地 → 退出登录仍可见 → 无网络手动消费 → 恢复网络同步”。在该验证通过前不扩展其他数据域，也不重复触发构建。

## 13. PR 合并、生产迁移与 TestFlight（2026-09-02）

- PR #191 `fix/LOCAL-003-RC月份与删除投影` 已通过全部门禁并合并到 `main@fe763a4`；macOS Swift 编译与 XCTest 全部通过。
- 生产项目 `igbghrhsdaolxljgiisf` 已应用 `20260831100000_remote_sync_transaction_delete_tombstone.sql`；`supabase migration list --linked` 显示该版本 Local/Remote 一致。
- 从固定提交 `fe763a4` 触发 TestFlight Run `33636788186`，Archive、Export、Upload 全部成功；构建号为 `33636788186`，Delivery UUID 为 `b9d28d3f-e6b7-4a3c-b959-6494f26521a3`。
- 本机因未运行 Docker，无法执行 `supabase db dump` 的列级 schema 导出；迁移应用与版本登记成功，触发器行为仍以真机删除同步验收为最终证据。

下一步：等待构建在 App Store Connect 处理完成后，使用 `test2` 验证 RC-005/RC-012/RC-015：日期首页、本地与云端合并、云端删除后本地投影收敛、重复同步不重复落库且余额无漂移。双设备场景仍标记为环境未验证；真机验收通过前不关闭 RC Gate。
## 14. TestFlight 重复投影事件（2026-09-03）

- 真机发现同一日期的本地与云端记录出现两行，部分记录金额、商户和时间相同；详情页分别显示 `local` 与云端来源。
- 根因确认：本地列表使用纯 UUID / `local-expense/<uuid>`，云端列表使用 `expense-<uuid>` / `expense/<uuid>`；合并逻辑直接比较展示 ID，没有按 `aggregate_kind + raw_id` 归一，因此同一同步实体被渲染两次。
- 本轮窄修复：`NativeRecordReference.canonicalValue` 将 `local-expense` 归一为 `expense`；月份投影按规范化引用去重并保留本地优先；本地详情加载保留本地路由，不因规范化而误请求云端。
- 回归测试新增：同一 UUID 的本地/云端消费只生成一条列表记录，且优先保留本地引用。
- 重要边界：如果本地和云端是不同 UUID，即表示历史上确实创建了两笔独立事实，本修复不会自动删除或合并，需另行做可审计的重复候选复核。

下一步：完成本修复 PR 的 macOS Build/XCTest 后，先用现有 TestFlight 构建确认重复行消失；若仍存在不同 UUID 的重复，导出脱敏 ID/字段清单后再决定是否提供用户确认式合并工具。本轮不自动删除用户数据。

## 15. Phase A 范围收缩与新放行标准（2026-09-05）

只读裁决确认当前多设备双写协议不放行。依据 ADR-040，本 Gate 不再把第二台设备并发编辑作为 Phase A 承诺，改为“单设备 + 云端 AI/PWA 写入者”。

Phase A 放行前置条件：

- B3：批次内单操作失败落库为 `rejected(reason)`，同批其他操作可继续，客户端能定位具体 operation；
- B2：版本冲突自动 take-remote，冲突 outbox 进入终态丢弃并保留诊断原因，`conflict_status` 不进入永久 `unresolved`；
- B1：本地账户保存 `origin`，远端导入账户不被消费补偿逻辑重新上传；
- B4：同步响应移除派生 `remote_account_entries`，本地余额只由有效本地 expense 投影重算；
- 删除生产测试钩子、修复金额四舍五入和 fractional seconds 时间解析；
- PostgreSQL fixture 与生产约束同构，并有确定性操作序列测试；
- 双设备并发、人工冲突 UI 和其他数据域明确标记为 Phase B，不得作为当前 RC 模板能力。

## 16. Phase A 实施与当前验证（2026-09-05）

- 已在 main@050c265 的隔离 worktree codex/LOCAL-003-phase-a 实施 B1/B2/B3/B4、F1/F3/F6；根工作区 WIP 和其他 worktree 未修改。
- B1：local_accounts.origin 区分 local/remote，远端账户不进入消费账户补偿 Outbox。
- B2：冲突操作标记为终态 sent 并保留“云端已更新，请复核”，继续应用远端快照；历史 unresolved 不再阻止同步，成功同步清零冲突状态。
- B3：公开 RPC 逐操作调用并隔离异常，失败落库 rejected(reason)，同批成功操作继续提交。
- B4：公开响应和本地投影不再消费 remote_account_entries，账户流水由本地有效消费投影派生。
- F1/F3/F6：金额转换使用四舍五入；时间解析支持 fractional seconds；公开 RPC 不保留 expired 特殊输入或 force_failure 行为。
- 已通过：npm run governance:check、npm run governance:arch、node scripts/check-migration-versions.mjs、LOCAL-002-APP/LOCAL-003B/LOCAL-003D 边界脚本、git diff --check。
- 未验证：Windows 无 Swift/XCTest；Docker daemon 未运行，PostgreSQL fixture 尚未执行。上述两项交由 GitHub macOS iOS Build/XCTest 与 PostgreSQL Release Validation 门禁验证。
- 已知基线失败：test:ios-local-account-boundary 的旧 showLocalAccountPreparation 静态断言在当前主线即失败，本轮未修改 Records 页面。
- 当前不执行：commit、push、生产迁移、部署、TestFlight；待用户确认并取得 CI 证据后再进入收口。

## 17. Phase A PR 门禁完成与 RC 入口（2026-09-05）

- 修复分支为 `fix/LOCAL-003-记录投影去重`，隔离 worktree 为 `.worktrees/LOCAL-003-协议收缩与修复`；根工作区 WIP 和其他 worktree 未修改。
- PR #195 已打开，当前提交为 `6143243`：`4ca7445` 实施 Phase A 契约，`f1d23dd` 修正 iOS 编译兼容，`3c9788c` 修正 `origin` 重复初始化，`6143243` 恢复 DREMOTE-016 测试实际调用同步入口。
- iOS Build `33951506319`（HEAD `6143243`）通过：模拟器编译与 280 个 XCTest 全绿。
- Release Validation `33951508600`（HEAD `6143243`）通过：PWA、Edge、迁移双次执行、PostgreSQL remote sync fixture 和既有边界检查全绿。
- 首轮 iOS Build `33950875174` 的 3 个失败均来自 DREMOTE-016 测试遗漏 `synchronize` 调用，已以单独测试提交修复；未改变生产实现。
- 当前未验证：真实 iPhone/TestFlight 单设备 RC 走查。范围为 RC-001…006、009…012、015；双设备并发按 ADR-040 标记“范围外”，不标记为失败。
- 当前不执行：合并 PR、生产迁移、部署或 TestFlight，直到用户对发布步骤作当前任务的明确授权。

下一步：获得发布授权后，从通过门禁的固定提交执行迁移与 TestFlight，再进行一次集中单设备 RC 走查；真机若发现问题，只修复具体红灯并重新跑门禁。

