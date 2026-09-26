# LOCAL-FIRST SL-01 文档口径收口交接

> 日期：2026-09-25
>
> 分支：`codex/local-first-phase1-fact-reader`
>
> 基线：`7005e81`

## 目标行为

按 `docs/spec/LOCAL-FIRST-DOMAIN-CONVERGENCE.md` §7.1 消除 D10 文档口径分裂，使后续 Slice 使用同一条 Phase 1 基线。

## 当前行为与权威来源

- 未登录四域手动创建已由 `AppState` 走本地记录路径；完整候选、图片和用户闭环仍是后续 Slice。
- Phase 1 已纳入收入与钱包快照，分别进入 SL-A/SL-B；BYOK 按 Q-06 暂缓移出 Phase 1。
- 消费必须先选账户，DM-GAP-10 不采纳；绑定预览维持计数级概览，LF-028 不实施。
- 中转站 UI 引用前缀以 `local-staging/<id>` 为准；`expense/<uuid>`、`data/<uuid>` 等其他前缀债务保持登记，SL-02 只做特征测试，不合并体系。

权威决策和 Slice 定义：`docs/spec/LOCAL-FIRST-DOMAIN-CONVERGENCE.md` §7、§10；TDD 约束：`docs/spec/02-TDD实施与交接规范.md`。

## 本轮范围

已更新：

- `docs/spec/LOCAL-FIRST-PHASE1-HANDOFF.md`
- `docs/spec/03-阶段与任务索引.md`
- `docs/spec/LOCAL-FIRST-PHASE1-DATA-MODEL-GROOMING-RESULT.md`
- `docs/spec/LOCAL-FIRST-BDD-COVERAGE.md`
- `docs/spec/规格文档索引.md`

未修改：业务代码、Spec 场景编号、数据库迁移、Cloud Sync/Outbox、Edge Function、PWA 结构、生产部署和 TestFlight。

## TDD 证据

- 这是纯文档 Slice。按 TDD 规范 §3.2，纯文档不要求先写自动化业务测试；因此本轮没有红灯/绿灯 XCTest。
- 已执行 `git diff --check`，通过。
- 已执行旧口径扫描与 `local-staging/<id>` 引用扫描；旧口径只保留在 BDD 的“文档说法/代码事实”历史差异记录中，当前结论已指向 SL-01 收口结果。
- 未运行 Swift/XCTest、PWA/Edge 构建或 GitHub CI；本轮没有业务代码变更，也未触发 CI。

## 风险与下一步

- 历史执行记录仍保留当时的阶段、分支和产品范围，不作为当前阶段入口；当前入口以阶段索引和本交接快照为准。
- 业务代码中的投影重复、单参数 `IntakeRouter` 死 API 和三套引用前缀没有在本 Slice 修改。
- 下一 Slice 为 SL-02：`AppState` 投影刷新收敛、具名特征测试和三套引用前缀路由测试；Windows 不作为 Swift 编译结论，macOS CI 仍是 iOS 验证门禁。

## Git 与发布

- 未提交、未推送、未创建 PR。
- 未执行生产迁移、部署或 TestFlight。
