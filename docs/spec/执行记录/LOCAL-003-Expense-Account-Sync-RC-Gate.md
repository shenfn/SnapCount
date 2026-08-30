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

