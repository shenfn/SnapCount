# LOCAL-FIRST SL-02 交接快照：投影刷新收敛与特征测试加固

- 日期：2026-09-25
- 分支：`feature/SL-02-投影刷新收敛`（自 `feature/SL-01-文档口径收口` @ `1e768e4` 拉出）
- 上游交接：`docs/handoff/LOCAL-FIRST-SL-01-文档口径收口-2026-09-25.md`
- 依据 Spec：`docs/spec/LOCAL-FIRST-DOMAIN-CONVERGENCE.md` §7 SL-02、§5 F-5/D3/D6、§9
- 状态：**已完成并合入 main**（PR #200，merge commit `7c64bae`，2026-09-26 全绿合并）

## 1. 本轮范围（已完成）

| 任务 | 内容 | 状态 |
|---|---|---|
| C4 投影刷新收敛 | AppState 新增私有 `refreshLocalMonthProjection(monthKey:)`，替换全部 8 处写路径"写后当月投影刷新"分支 | 完成，待 CI 回归 |
| LF-001 特征测试 | 未登录 food/sleep/reading 手动创建 → 本地事实层 + 当月投影刷新，零会话查询 | 完成，待 CI |
| LF-002 特征测试（Q-08） | 登录态四域手动创建 → 走云端（recordRepository spy 收到 create），本地事实层为空 | 完成，待 CI |
| DM-014 特征测试 | 已登录未绑定 → 云端消费不静默写入本地；绑定后 → importRemoteExpenses 被调用 | 完成，待 CI |
| D3 前缀路由特征测试 | `expense/`、`data/`、`local-expense/`、`local-data/` 四种引用均路由到本地详情（零会话查询）；`local-staging/` 不进正式详情路由 | 完成，待 CI |
| DM-004/DM-005 具名化 | sleep/reading 分域阈值 0.75/0.74 边界显式断言（补 DM-003 只覆盖 sport/food 的缺口） | 完成，待 CI |
| D6 死 API 删除 | 删除 `LocalRecordIntakeRouter.route(confidence:)`；SPORT-001-C 测试改写为三参数路由断言（修正其 0.80 断言与 sport 分域阈值 0.75 的矛盾） | 完成，待 CI |

不在本轮范围（按 Spec 明确不做）：Sync/Outbox/Edge/PWA/生产/TestFlight、读取路径收敛（:833 读路径选择、:905 识别投影保持原样）、引用体系合并、AppState 拆分。

## 2. 改动文件

| 文件 | 改动 |
|---|---|
| `ios/SnapCount/App/AppState.swift` | +`refreshLocalMonthProjection(monthKey:)`（:860-874）；替换 8 处写后刷新：loadRemoteRecordMonth 当月分支（:1199）、非当月 fetch 后（:1230）、归档中转站（:2685）、expense 编辑（:3541-3544）、expense 删除（:3562）、record 编辑（:3606-3609）、record 删除（:3625）、四域手动创建（:4451） |
| `ios/SnapCount/LocalData/LocalRecordModels.swift` | 删除单参数 `route(confidence:)`（D6） |
| `ios/SnapCountTests/LocalFirstSL02ProjectionTests.swift` | 新增：LF-001、LF-002、DM-014、D3、C4 共 5 个特征测试 + 独立测试替身（record spy、dashboard/domain/finance stub、snapshot store stub、expense stub、session 计数器） |
| `ios/SnapCountTests/LocalPhase1DataModelTests.swift` | 新增 `testLOCALP1DM004DM005SleepAndReadingConfidenceBoundariesFollowDomainThresholds` |
| `ios/SnapCountTests/LocalSportRecordTests.swift` | SPORT-001-C 测试改写为三参数边界断言 |

## 3. 行为差异说明（C4 收敛的语义微调，已在上轮分析中对齐）

- **FactReader 权威模式下**：expense 编辑/删除、record 编辑/删除原先走降级读取模型（`readDeviceExpenseMonth`/`readDeviceRecordMonth`），会把投影缓存重写为 `local-expense/`、`local-data/` 前缀，与 loadUnifiedRecordMonth 产生的权威 `expense/`、`data/` 前缀漂移。收敛后这些写路径刷新统一事实月，前缀保持权威形态（C4 红灯测试锁定该行为）。
- **降级双 UseCase 模式下**：归档中转站、expense 删除、四域手动创建等点从单域刷新变为 expense+record 双域刷新。均为幂等读取，且 `apply*Month` 有"当月才上屏"门禁，非当月写零 UI 影响。

## 4. 执行记录（TDD §6）

- 红灯先行：C4 测试 `testLOCALP1SL02FactReaderModeEditRefreshesFactMonthProjectionWithCanonicalReferences` 在旧实现下预期红灯（编辑后投影引用为 `local-expense/` 而非权威 `expense/`）；其余特征测试按特征测试规则首次通过属正常。
- **Windows 无法本地验证**：以上红灯/绿灯均需 macOS CI 证明。当前仅完成代码审读级验证（签名核对、调用方核对、diff 自审）。
- 已做静态验证：`git diff --check` 通过；`route(confidence:)` 全库无残留调用；剩余 `localFactReader != nil` 仅 3 处（读路径 :833、统一方法 :864、识别投影 :905，均在范围外）。

## 5. 测试基建说明

- 测试 target 走 XcodeGen（`ios/project.yml` 按 `SnapCountTests/` 目录自动收源），新文件无需改工程文件。
- LF-002 链路涉及 `refreshDashboard`/`scheduleDashboardSupplement`/`loadFinanceVocabulary`，已注入 dashboard/domain/finance/snapshotStore 测试替身，全程无网络访问。
- DM-014 使用固定历史月份 `2000-01`（永远非当月）避开 refreshDashboard 分支；C4 使用 `2026-01` 避开当月门禁。
- LF-001 的"当月投影刷新"断言依赖 `NativeMonthKey.current()`，存在跨月零点运行的理论边界（与生产行为一致，接受）。

## 6. 风险与未验证项

1. **编译未验证**：新测试文件约 500 行，均为新代码，签名已逐一与源码核对，但 Windows 无法编译，CI 首跑可能暴露笔误。
2. **CI 基线未知**：`feature/SL-01-文档口径收口`（1e768e4）未跑过 iOS Build；若基线已红，需先区分基线失败与本次失败。
3. **降级模式双域刷新**新增一次幂等读，极端数据量下有轻微额外开销（当月门禁限制实际影响）。

## 7. CI 回归与修复记录（2026-09-26）

- 首轮（b34381b）：17 处编译错误——测试夹具签名与真实 API 偏差（LocalExpenseCommand 应为 id/createdAt、recordGroups/loadRecordDetail 参数标签、SupabaseAuthSession.expiresAt 为 Int epoch、expenseStub 可选解包），逐一对源码修正（4520e1f）。
- 次轮（99f0804）：1 处编译错误——@MainActor 测试类静态 fixture 被非隔离 spy 调用导致隐式异步，移出为文件级 SL02RemoteExpenseFixture。
- 三轮（860b808）：运行时断言失败（仅 DM-014）——根因是 validSession→apply 每次调 refreshLocalSyncState() 从 localBindingRepository 重读绑定状态，手工塞 localSyncState 被覆盖；修复为 harness 注入真实 LocalProfileStore 并走 confirmBinding 真实链路。
- 终轮（860b808）：iOS Build + XCTest 全绿（7m11s），PR #200 全绿合入 main（7c64bae）。
- 经验：Windows 侧写 Swift 测试必须逐一对照真实 init/参数标签/访问级别/actor 隔离，不能凭同构记忆；AppState.validSession 链路会覆盖手工注入的 localSyncState，绑定状态测试必须走真实仓库。
