# LOCAL-003E 同步孤儿消费与写库错误分类 TDD 执行记录

> 状态：实现完成；两条场景测试通过，全量 617 条回归 0 失败（2026-11-05 15:29）；红灯因环境限制未实测
>
> 关联：`LOCAL-003`、`LOCAL-003C`、`ADR-036`、`ADR-040`
>
> 缺陷来源：`~/WorkBuddy/2026-11-04-15-14-03/reports/调试报告-云同步外键失败.md`（BUG-01、BUG-02）

## 目标行为

1. **LOCAL-003E-1**：远端快照中的消费若引用了本机不存在的账户（远端已删除账户不会写入 `local_accounts`），该条消费跳过，同批其余账户与消费照常导入，不再整批回滚。
2. **LOCAL-003E-2**：本机 SQLite 约束失败时，同步失败类别为 `.localConstraint`、诊断码 `SYNC-LOCAL-CONSTRAINT`、安全原因说明明确指出「本机数据库 / 与网络无关」，不再落到 `SYNC-TRANSPORT`。

## 当前行为（修复前）

- `LocalExpenseRepository.applyRemoteSnapshot`：账户循环对 `deletedAt != nil` 直接 `continue`；消费循环插入前不校验账户是否存在 → `local_expenses.account_id`、`local_account_entries.account_id` 外键失败（SQLite `787 = 19 | (3 << 8)`）→ 整个 `writer.write` 事务回滚。
- `AppState.syncDiagnosticFailure(for:)` 末尾 `return .transport`，GRDB 错误被归为传输失败。
- 数据状态不变，因此每次重试都必然复现；用户只能看到「同步失败，可重试」。

## 权威来源

本机 GRDB 事务与外键约束。不涉及 Supabase 表、RPC、Edge Function 或生产迁移。

## 本轮范围

- `ios/SnapCount/LocalData/LocalExpenseRepository.swift`：新增账户存在性守卫、SQLite 约束错误转 `LocalWriteConstraintError`、跳过计数日志。
- `ios/SnapCount/LocalData/LocalModels.swift`：`LocalSyncDiagnosticFailure.localConstraint`、`LocalWriteConstraintError`。
- `ios/SnapCount/LocalData/LocalHistoryMigrationDiagnostics.swift`：该错误的 `safeReason` 与 `recovery` 文案。
- `ios/SnapCount/App/AppState.swift`：错误分类与诊断码映射。
- 两个测试文件各新增一条场景测试。

## 非范围

- 不为孤儿消费建 `is_archived=1` 占位账户（原报告档 3，会牵动账户列表查询语义）。
- 不把跳过条数暴露到 `LocalSyncRunResult` / 设置页文案（仅写系统日志）。
- 不改 `LocalExpensePortability.importArchive` 路径。
- 不改 UI 结构、不改数据库迁移。

## 预计修改文件

同「本轮范围」。

## 基线测试结果

未执行。本机 AI 执行环境的进程沙箱不允许嵌套 `sandbox-exec`，`xcodebuild` 在「Resolve Package Graph」阶段即失败：

```
xcodebuild: error: Could not resolve package dependencies:
  sandbox-exec: sandbox_apply: Operation not permitted
```

同一限制已记于 `交接文档-环境与调试链路.md` §4.1②。基线由用户在终端执行后回填。

## 红灯测试及失败原因

- `LocalExpenseRepositoryTests.testLOCAL003E1RemoteSnapshotSkipsExpenseOfDeletedAccountWithoutLosingBatch`
  - 修复前预期失败：`applyRemoteSnapshot` 抛 `SQLITE_CONSTRAINT_FOREIGNKEY`，`XCTAssertNoThrow` 失败。
- `LocalSyncAppStateTests.testLOCAL003E2LocalWriteConstraintFailureIsNotReportedAsTransport`
  - 修复前预期失败：`localSyncDiagnostic?.failure` 为 `.transport`，`localSyncFailureDiagnostic` 为 nil 或安全原因为通用兜底文案。

> 说明：`LocalWriteConstraintError` 类型与 `.localConstraint` 枚举分支先于红灯落地，仅为让测试可编译；当时未接线分类逻辑，两条断言仍应失败。若实际执行顺序不同，以真实输出为准，不在此处虚构结果。

## 最小实现

- `applyRemoteSnapshot` 拆为公共入口 + `writeRemoteSnapshot`，入口把 `DatabaseError` 且 `resultCode == .SQLITE_CONSTRAINT` 转成 `LocalWriteConstraintError(extendedCode:)`，其余原样抛出。
- 消费循环在写入前按 `(id, profile_id)` 校验 `local_accounts`，缺失则计数跳过；`deletedAt != nil` 的墓碑路径不校验（不触碰 `account_id`）。
- `AppState.syncDiagnosticFailure` 增加 `LocalWriteConstraintError → .localConstraint` 分支，早于 `.transport` 兜底；诊断码 `SYNC-LOCAL-CONSTRAINT`。
- 诊断文案：`本机数据库拒绝写入（SQLite 约束 {extendedCode}），与网络无关；请反馈脱敏诊断编号。`

## 首次编译反馈（用户终端）

用户执行上述命令后，编译器先报：

```
ios/SnapCount/LocalData/LocalModels.swift:524:9: error: switch must be exhaustive
```

原因：`LocalSyncDiagnosticFailure.title`（`LocalModels.swift` 私有扩展）未覆盖新增的 `.localConstraint`。已补 `case .localConstraint: return "本机数据库写入受限"`。

同轮自查另修一处类型不匹配：GRDB 的 `DatabaseError.extendedResultCode` 是 `ResultCode` 而非 `Int32`，`LocalWriteConstraintError(extendedCode:)` 取值改为 `error.extendedResultCode.rawValue`。两处均为编译期问题，不改变行为。

## 绿灯结果

2026-11-05 15:20，用户在真实终端执行（日志 `/tmp/snapcount_test.log`）：

```
Test Case '-[SnapCountTests.LocalExpenseRepositoryTests testLOCAL003E1RemoteSnapshotSkipsExpenseOfDeletedAccountWithoutLosingBatch]' passed (0.131 seconds).
Test Case '-[SnapCountTests.LocalSyncAppStateTests testLOCAL003E2LocalWriteConstraintFailureIsNotReportedAsTransport]' passed (0.235 seconds).
Executed 2 tests, with 0 failures (0 unexpected) in 0.365 (0.400) seconds
** TEST SUCCEEDED **
```

执行方式：`~/Desktop/测试SnapCount.command`（等价于下方命令，脚本默认只跑这两条，传 `all` 跑全量）。

```bash
cd ~/Developer/Projects/SnapCount/ios
xcodebuild test -project SnapCount.xcodeproj -scheme SnapCount -configuration Debug \
  -destination 'platform=iOS Simulator,id=0A0AB3D7-F316-4B2A-8869-F967E227E181' \
  -clonedSourcePackagesDirPath .spm-packages CODE_SIGNING_ALLOWED=NO \
  -only-testing:SnapCountTests/LocalExpenseRepositoryTests/testLOCAL003E1RemoteSnapshotSkipsExpenseOfDeletedAccountWithoutLosingBatch \
  -only-testing:SnapCountTests/LocalSyncAppStateTests/testLOCAL003E2LocalWriteConstraintFailureIsNotReportedAsTransport
```

**红灯未实测**：受同一沙箱限制，修复前无法运行这两条测试，因此没有「先失败后通过」的实测记录。判断依据是代码事实而非运行证据：

- E1：修复前 `snapshot.expenses` 循环无账户存在性校验，`local_expenses.account_id` 外键必然约束失败，`XCTAssertNoThrow` 应失败。
- E2：修复前 `syncDiagnosticFailure` 无 `LocalWriteConstraintError` 分支，必然落到 `.transport`，`XCTAssertEqual(..., .localConstraint)` 应失败。

**全量回归**：2026-11-05 15:26–15:29，`~/Desktop/测试SnapCount.command all`（`-only-testing:SnapCountTests`）：

```
Executed 617 tests, with 1 test skipped and 0 failures (0 unexpected) in 175.780 (176.051) seconds
** TEST SUCCEEDED **
```

既有用例 `testLF04004EqualVersionLiveSnapshotCannotChargeDeletedExpenseAgain`（快照 `accounts: []`，消费引用本地已存在账户）与 `LocalSyncCoordinatorTests` 中的快照导入路径均未受影响。日志中的 `BUG IN CLIENT OF libsqlite3.dylib: vnode unlinked while in use` 来自 `IOSPrototypeRenderingTests` 的临时 fixture 释放时序，与本轮改动无关，属既有噪声。

## PWA/iOS 差异

无。PWA 处于维护模式，本轮不触碰。

## GitHub CI 结果

未触发（未提交、未推送）。

## 未解决风险

1. **孤儿消费不进本机**：远端已删除账户名下的历史消费不会出现在本机列表，本机合计会小于远端原始合计。这是用「整批写不进」换「少数记录不进」，需产品侧确认可接受，再决定是否做占位归档账户。
2. **跳过条数不可见**：目前只有 `LocalSync` 系统日志 `remote_snapshot_orphan_expenses_skipped count=`，设置页看不到。若真实数据里孤儿很多，用户会察觉「少了记录」却找不到解释。
3. **同步仍会失败一次**：守卫只是让本批可写；若同批还有其它约束冲突（唯一键、非空），仍会转成 `SYNC-LOCAL-CONSTRAINT` 失败，且不再伪装成网络问题——这是预期行为，但不是「同步成功」。

## 对应提交

未提交（用户未授权提交）。
