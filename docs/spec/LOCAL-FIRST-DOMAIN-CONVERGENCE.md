# 芥子 Local-First 领域收敛与实现切片设计

> 规格编号：LOCAL-FIRST-DOMAIN-001
> 状态：已评审——2026-09-25 用户完成 Q-01~Q-13 拍板（见 §10 拍板记录），无门 Slice 授权进入 TDD；冻结项（同步/迁移/PWA/生产）不变
> 日期：2026-09-25
> 上游：`LOCAL-FIRST-BDD-COVERAGE.md`（LOCAL-FIRST-BDD-001）
> 方法约束：KISS/YAGNI。只有多个真实 Scenario 共同依赖的能力才讨论抽取；本文不引入新架构层，新增代码仅为两处 AppState 内部收敛（见 §5-D2、Slice SL-02）。

## 0. 本轮新增验证事实（设计依据）

在 BDD 文档基础上，本轮对源码补充验证了四个承重点：

| # | 事实 | 证据 | 影响 |
|---|---|---|---|
| F-1 | `IntakeRouter.route(confidence:)` 单参数重载在生产代码零调用，仅 `LocalSportRecordTests:223-225` 在用，且断言 sport 0.80→autoArchive，与分域阈值 sport 0.75 矛盾 | LocalRecordUseCase.swift:220 用三参数版本 | 债务 D6：误导性测试 + 死 API |
| F-2 | `confirmStaging` 时图片文件不跨 bucket 搬移：repository 仅在 DB 层把引用从 staging 行移交正式记录（staging 置 NULL），文件物理位置留在 `staging/` | LocalRecordRepository.swift:309-338；LocalRecordUseCase.swift:258-267 无 move | 不变量 INV-10 的现状形态 |
| F-3 | 正式记录 create 失败补偿：先存图→后写库→失败删图（补偿模式，非跨资源事务） | LocalRecordUseCase.swift:48-83；stage 同构 :162-200 | 事务边界 T4 |
| F-4 | 删除记录/丢弃候选时，图片文件删除在 DB 事务之外（`try? imageStore?.remove`），崩溃可留孤儿文件（DB 权威不受损） | LocalRecordUseCase.swift:110-115,269-274 | 事务边界 T5、不变量 INV-11 |
| F-5 | "写后刷新当月投影"的 `if localFactReader != nil` 分支在 AppState 重复出现约 8 处（4460-4465、2686-2691、3569、3616-3635、1184-1190、1224-1230 等） | AppState.swift grep 24 处命中 | 债务 D2：唯一被多场景共同依赖、值得收敛的重复 |

## 1. Domain / Capability Map

权威归属 = 该业务规则的唯一实现位置。消费方向表示"谁读它"。

| Domain | 存储所有权 | 权威实现 | 消费者 |
|---|---|---|---|
| **D1 身份/Profile** | `local_profiles` | LocalProfileStore.swift:19-48（单 profile、免登录自建、绑定/解绑） | 全部本地域、FactReader、Sync（冻结）、Portability |
| **D2 消费账务** | `local_expenses` + `local_accounts` + `local_account_entries` | LocalExpenseRepository.swift（CRUD+分录+outbox 单事务；余额派生 :699-726） | Today/Records 投影、导出、绑定预览、Sync（冻结） |
| **D3 通用域记录**（food/sleep/sport/reading） | `local_records` | LocalRecordRepository.swift + LocalRecordValidation/Codec（校验与规范化唯一权威，LocalRecordModels.swift:396-516） | Today/Records 投影、导出、FactReader、AI ingest |
| **D4 候选/中转** | `local_staging_records` | LocalRecordRepository.swift:266-373（confirm 幂等+图片引用移交；discard 终态） | Inbox 投影、AI ingest、确认/丢弃 UI |
| **D5 图片** | 文件系统 `JieziLocalData/images/{intake,records,staging}` | LocalImageStore.swift（save/move/remove/hash/路径防越界）；生命周期策略分散在 UseCase 各方法（见 §3-C3） | D2/D3/D4 写路径、导出、详情展示 |
| **D6 识别** | 无自有存储（候选落 D4/D3） | LocalImageRecognition.swift（Provider 协议 + hash 确定性 ID :125,130-145）+ LocalRecordUseCase.ingest（路由唯一入口 :203-244） | Today 相册/拍照、快捷指令 Intent |
| **D7 表达（AI Popup）** | 云端（快照/曝光/反馈三件套） | 冻结沿用云端；本地零实现 | 记录详情、通知卡片 |
| **D8 分析（Insights）** | 云端 `daily_domain_summary`/`ai_insights` | 冻结沿用云端；本地聚合零实现 | 报告页 |
| **D9 同步** | `local_outbox_operations` + `local_sync_state` | LocalSyncCoordinator.swift + SupabaseSyncTransport.swift（**冻结**：仅 expense/账户，单设备） | 设置页手动入口、绑定确认 |
| **D10 可携** | 导出文件 | LocalFactPortability（权威）+ LocalExpensePortability（expense 导入唯一权威）+ LocalRecordPortability（兜底，存疑） | 设置页导出、同步 fallback（冻结路径） |
| **D11 设置** | 云端 `user_configs` 19 项 + 本地 UserDefaults 3 项 | SettingsRepository（云）/ ShortcutFeedbackPreferences+JieziThemeManager（本地） | 设置页、表达/识别配置 |
| **D12 读模型/投影** | 内存（AppState @Published） | LocalFactReader.swift（正式事实唯一读取权威）+ AppState 投影/合并层（现状职责错位，见 D2 债务） | 全部页面 |

**读取权威原则（INV-0）**：正式事实只有两个物理归属（`local_expenses`、`local_records`），唯一读取入口是 `LocalFactReader`；staging、墓碑、outbox、派生投影不得被任何"正式读取者"直接消费。当前违规点仅一处：AppState 双 UseCase 路径（无 FactReader 时的降级）仍直接读双 Repository（AppState.swift:847,895）——属降级兼容，收敛条件见 SL-02。

## 2. 核心 Invariant 清单

> 权威位置 = 违反时应修的唯一地方。状态：✅=已有 XCTest 具名固化；⚠️=代码已实现但无具名测试；❌=未实现（对应 Slice 见 §7）。

| # | 不变量 | 权威位置 | 依赖 Scenario | 状态 |
|---|---|---|---|---|
| INV-1 | 五域物理归属固定：消费只进 `local_expenses`，四域只进 `local_records`；`local_records.domain_key` 校验层禁写 expense（表 CHECK 的 expense 死分支为已知债务 D5） | LocalRecordModels.swift:493；LocalExpenseRepository | DM-001/002、LF-001 | ⚠️ |
| INV-2 | 编辑必须携带 expectedVersion，CAS 失败显式报错不覆盖 | LocalExpenseRepository.swift:296-301；LocalRecordRepository.swift:80-91 | DM-008、LOCAL-002C1-4、SPORT-001-B | ✅ |
| INV-3 | 删除=tombstone（deleted_at+版本递增），读取层排除墓碑；消费删除同事务作废活跃分录 | 两 Repository；LocalFactReader SQL | DM-007、LOCAL-002D1-2、REC-011 本地等价 | ✅ |
| INV-4 | 余额 = 期初 + 活跃分录净额；不存在可覆盖的 current balance | LocalExpenseRepository.swift:699-726 | LOCAL-002J1、财务-001 | ✅ |
| INV-5 | 业务+分录+outbox 同一写事务；任一失败不展示为已保存 | LocalExpenseRepository.swift:163-431 | LOCAL-DATA-004、LOCAL-002A1 | ✅ |
| INV-6 | 候选确认幂等：重复 confirm 返回同一正式记录并保留 staging→target 关系；用户编辑值覆盖 AI 候选值 | LocalRecordRepository.swift:266-350 | DM-006、LF-006、REC-010 本地等价 | ✅（编辑值覆盖部分待 LF-006） |
| INV-7 | 置信度路由唯一权威：分域阈值 food 0.80 / sleep·sport·reading 0.75 / 兜底 0.80，且必须走三参数 `route(domainKey:confidence:payload:)`（单参数重载为死 API，见 D6） | LocalRecordModels.swift:367-394 | DM-004/005、SPORT-001-C/J | ✅（生产路径） |
| INV-8 | 同图重试幂等：正式记录 ID 与候选 ID 由 imageHash 确定性派生；pending 复用、archived 返回、discarded 才重路由 | LocalImageRecognition.swift:125,130-145；LocalRecordUseCase.swift:203-244 | SPORT-001-J、REC-002 本地等价 | ✅ |
| INV-9 | 正式库只存规范单位（sleep_minutes/duration_minutes/reading_minutes），别名单位在 Codec 归一，估算标记保留 | LocalRecordModels.swift:396-516 | DM-003、DM-GAP-04 | ✅ |
| INV-10 | 图片引用=行内相对路径+hash；候选确认时 DB 引用移交、文件不搬移（bucket 目录只是组织习惯，不是所有权判据）；同一引用同一时刻只属于一个业务行 | LocalRecordRepository.swift:337-338（F-2）；LocalImageStore.move | DM-007、SPORT-001-I、LF-003 | ⚠️ |
| INV-11 | 图片文件删除允许最终一致（DB 权威优先）；DB 事务失败不留新图（写库前先落盘、失败补偿删除）；intake 桶 defer 必清 | LocalRecordUseCase.swift:77-83,198-200,273；LocalImageRecognition.swift:90-95 | DM-007、LF-023 | ⚠️ |
| INV-12 | 时间不伪造：业务日期必为 YYYY-MM-DD、时分必为 HH:MM(:SS)；缺发生时间不用上传时刻冒充 | LocalRecordModels.swift:495-516；TIME-REF-001 | DM-009、EXP-002 | ✅ |
| INV-13 | profile 归属校验：所有行级操作 assertProfile；跨 profile 读取抛 invalidIdentifier | 各 Repository assertProfile / UseCase guard | REC-013 本地等价、LF-026 | ✅ |
| INV-14 | 未启用同步时登录不触发静默本地/云端混读；混读只发生在"已绑定"（shouldProjectRemoteData）显式路径 | AppState.swift:1327-1332 | DM-014、LOCAL-003-D4 | ⚠️ |
| INV-15 | 导出不含 token/Key/签名 URL/日志；含稳定 ID 与版本 | LocalFactPortability.swift:117-204 | DM-010、LOCAL-DATA-008、LOCAL-002E1-2 | ✅ |
| INV-16 | AI 结果/候选/日志不进入五域事实表；AI 关闭不阻塞手动 CRUD | 模型层无 AI 字段（local-v6 仅 source 元数据）；UseCase 不依赖网络 | DM-012、AI-001 | ✅ |
| INV-17 | 退出登录保留本地库/图片，仅停同步+清内存投影+清 Keychain | AppState.swift:389-407,4161-4272 | LOCAL-DATA-003、SPORT-001-L | ✅ |
| INV-18 | 单设备单 profile；绑定第二个云账号 → mismatch，仅 [暂不同步, 退出登录] 出口 | LocalProfileStore.swift:19-48；LocalBindingPreviewUseCase.swift:55-60 | LF-026（**决策依赖 Q-02**） | ✅（现状） |

## 3. 共享能力及其现有实现位置

只列被 ≥3 个真实 Scenario 共同依赖的能力。结论：**全部已有单一权威，无需新增抽象层**；两处例外是"策略分散"而非"缺层"，处理方式进 Slice。

| # | 共享能力 | 现有权威位置 | 共同依赖方 | 结论 |
|---|---|---|---|---|
| C1 | 域校验+payload 规范化（含分域阈值） | LocalRecordModels.swift（Validation/Codec/IntakeRouter） | D3 CRUD、D4 stage/confirm、D6 ingest、导出 | 已收敛。唯一动作：删单参数 route 死 API（SL-02 顺手项） |
| C2 | 乐观锁 CAS 写法 | 两 Repository（UPDATE WHERE local_version=?） | 编辑、删除、staging 解决 | 已收敛，不动 |
| C3 | 图片引用转移策略（先写新→后改引用→失败补偿删） | 策略分散在 LocalRecordUseCase.create/stage/ingest 各方法内（F-3） | 手动创建、AI ingest、确认移交、删除清理、LF-003 换图 | **不抽层**。LF-003 换图按同模式在 `update` 内实现即可；若 LF-003 与 staging 编辑（SL-03）都要用，届时才考虑提为 UseCase 私有方法（YAGNI 触发条件已写明） |
| C4 | 写后当月投影刷新 | 分散：AppState 8 处 `if localFactReader != nil` 分支（F-5） | 手动 CRUD、staging 确认、expense 编辑/删除、同步后刷新 | **唯一值得收敛点**：AppState 内一个 private `refreshLocalMonthProjection(monthKey:)`，无新层（SL-02） |
| C5 | hash 确定性 ID | LocalImageRecognition.swift:125,130-145 | ingest 幂等、重试、去重 | 已收敛，不动 |
| C6 | profile 守卫 | profileStore.activeProfile() + assertProfile | 全部写路径 | 已收敛，不动 |
| C7 | Inbox 本地投影 | AppState.applyLocalStagingProjection:999-1022 + refreshInboxProjection:908-913 | Inbox 三入口（主页/分类/下拉） | 已收敛（L 片完成），不动 |
| C8 | 详情缓存失效 | AppState:4466-4471（编辑后失效+重载）+删除路径 | 编辑、删除、确认后跳详情 | 已收敛于 AppState；SL-03/SL-04 复用同模式，不抽象 |
| C9 | 导出模型 | LocalFactPortability（fact）|Record 兜底（存疑 D4） | 设置页导出、同步 archive fallback（冻结） | SL-07 只做可达性确认，不合并 |

## 4. 事务边界

| # | 边界 | 范围 | 权威位置 | 崩溃一致性 |
|---|---|---|---|---|
| T1 | 消费写事务 | expense 行 + 账户分录（void+新插）+ outbox，单 `database.writer.write` | LocalExpenseRepository.swift:163-431 | 原子（INV-5） |
| T2 | 通用记录/staging 写事务 | 单行 INSERT/UPDATE/CAS | LocalRecordRepository.swift:25-157,266-373 | 原子；staging 确认=正式记录行+staging 行同事务（:309-338） |
| T3 | 数据库迁移 | 每版 migrator 事务（GRDB） | LocalDatabase.swift:37-238 | 迁移失败回滚——**无测试**（LF-024） |
| T4 | 文件↔DB 跨资源写 | 图片落盘（先）→ DB 写（后）→ 失败补偿删图 | LocalRecordUseCase.swift:48-83 | 设计选择：补偿模式，DB 权威（INV-11） |
| T5 | 文件删除 | DB 事务提交后 `try? remove` | LocalRecordUseCase.swift:113,273 | 最终一致，崩溃可留孤儿文件；孤儿不影响任何读取（读取以行内路径为准） |
| T6 | 识别全流程 | intake 落盘→Provider→路由写库；intake defer 清理；UseCase 失败清理 staging/records 桶图片 | LocalImageRecognition.swift:90-95 | 同 T4/T5 模式 |

**设计结论**：不引入"文件+DB 跨资源事务"设施。T4/T5 的补偿+最终一致是既定模式且与 INV-11 一致；LF-023（低存储）只需在该模式上补错误出口，不需要新机制。

## 5. 重复实现 / 不一致实现 / 架构债务

| # | 债务 | 现状 | 处置 |
|---|---|---|---|
| D1 | 双读取路径：FactReader 路径 vs 双 UseCase 降级路径，行为不一致（登录态当月投影应用与否、income 恒 0 仅前者） | AppState.swift:832-897,915-1103 | 不删降级（兼容旧库），但 SL-02 先固化两路径现状为特征测试；收敛以"事实库全量覆盖后移除降级"为终态，**不在本轮** |
| D2 | 8 处投影刷新分支重复 | AppState 各写路径 | SL-02 收敛为 private 方法（唯一新增代码点） |
| D3 | 引用体系三套并存：`expense|data/`（FactReader）、`local-expense|local-data/`（UI 读模型）、`local-staging/`（UI） | LocalFactReader.swift:171,198；LocalStagingReadModel.swift:4 | **不合并**（跨片改动大、收益低）；SL-02 用特征测试固定三套前缀的路由行为（loadRecordDetail :2835-2892）防漂移；真合并等 Phase 1 收尾后再议 |
| D4 | 双导出模型：FactPortability（权威）+ RecordPortability 兜底 | AppState.swift:3950-3972 | SL-07 只做兜底可达性确认（读旧库判定）；若不可达则标记移除候选，不直接删 |
| D5 | `local_records` CHECK 含 expense 死分支（可达 schema、不可达业务） | LocalDatabase.swift:155 vs LocalRecordModels.swift:493 | 保持现状（迁移成本>风险）；INV-1 测试固化业务层禁写；本地库下版迁移顺带收敛（记入 backlog，不排 Slice） |
| D6 | 单参数 `route(confidence:)` 死 API + 矛盾断言（sport 0.80 vs 0.75） | LocalSportRecordTests.swift:223-225 | SL-02 删除死 API、改用三参数断言分域阈值 |
| D7 | AppState ~4600 行承担投影/合并/UI 编排多重职责 | AppState.swift 全文 | **本轮不拆**（重构越权）。SL-02 只收敛 C4；更大拆分待五域闭环后按 ADR 流程决策 |
| D8 | 手动消费无业务唯一约束（同笔可重复录入）；本地无近似去重 | LocalExpenseRepository（无唯一索引）；LocalImageRecognition 仅 hash | 保持现状：手动重复=用户意图，AI 侧已有 hash 幂等（INV-8）；近似去重=LF-009（低优先登记，不排 Slice） |
| D9 | confirm 候选时 `recordID: UUID()` 每次新造而非由 staging ID 派生（幂等靠 DB 状态机而非 ID） | AppState.swift:2681-2684 | 可接受：INV-6 幂等已由 archiveStaging 状态机保证；不动 |
| D10 | 文档口径分裂（BDD 文档 V-1/V-4/V-5） | HANDOFF/阶段索引/Grooming | SL-01 文档收口 |

## 6. Feature 依赖图

```text
                    [决策依赖门 Q-01~Q-13 见 §10]

F10 身份/绑定 ──────────┬──────────────┐
   │                    │              │
   ▼                    ▼              ▼
F1 五域事实 ◄── F2 图片 ◄── F3 识别/候选      F12 同步(冻结)
   │  ▲            │          │                 ▲
   │  │            │          ├── F4 表达(依赖门Q-05)
   │  └────────────┘          └── F5 分析(依赖门Q-01/Q-06)
   │
   ├── F6 账务(登录态能力冻结现状)
   ├── F8 可携 ◄── F11 迁移(冻结登记)
   ├── F7 设置(依赖门Q-04)
   └── F9 异常恢复(横切,依赖 F1/F2 稳定)

读取权威: F1 的 LocalFactReader 是 F4/F5/F8 的唯一事实输入(未来时)
```

关键依赖结论：
1. F2 图片是 F3 识别、F4/F5（未来读图证据）、F8 导出的前置——但 F2 现有骨架已够 F3 用，SL 排序不受阻塞。
2. F4/F5 的本地适配全部压在"Q-05 口径 + 本地日聚合（LF-014）"上，聚合是纯读侧能力，可与 F4 解耦先行（SL-06 可选）。
3. F12/F11 冻结，所有 Slice 禁止触碰 outbox/sync 表与 Transport。
4. F9 的 LF-023/024 依赖 F1/F2 稳定即可，无前置 Slice。

## 7. 最小 Feature Slice（单会话单 Slice）

> 约束：一个 Agent 新会话只做一个 Slice；先红灯（具名场景编号）→ 最小实现 → 绿灯 → 回归 → macOS CI 验证 → 写 Handoff（按 `docs/spec/02-TDD实施与交接规范.md`）→ 结束。每 Slice 附"不做清单"防越权。验证命令统一：macOS iOS workflow（模拟器 build + 完整 XCTest + Build Gate）；Windows 侧只做静态检查。

### SL-01 文档口径收口（非代码 Slice）
- 目标：消除 D10 口径分裂，使后续 Slice 有正确基线。
- 动作：更新 HANDOFF §3（未登录四域已本地）、阶段索引双口径标注、Grooming DM-GAP-02/03 标注已收敛、引用前缀事实（`local-staging/`）、本文登记入规格文档索引。
- 覆盖 Scenario：无新编号（文档任务）。
- 不做：不改代码、不改 Spec 编号体系。

### SL-02 投影刷新收敛 + 特征测试加固
- 目标：把"多场景共同依赖"的 C4 收敛为单点，并把现状行为（含不一致处）用特征测试固定，防后续漂移。
- 红灯（具名）：DM-011 具名化（FactReader 排除 staging/墓碑）、DM-014 具名化（未绑定不混读）、LF-001 具名 XCTest（未登录四域手动创建→本地+当月投影刷新）、LF-002 特征化（登录态手动新建四域→云端，固定现状）、三套引用前缀路由特征测试（D3）、D6（删单参数 route + 分域阈值断言改三参数）。
- 实现：AppState private `refreshLocalMonthProjection(monthKey:)` 替换 8 处分支；删除死 API。
- 覆盖 Scenario：LF-001、LF-002、DM-011、DM-014、DM-004/005 具名化核对。
- 不做：不改投影行为语义、不动 sync/outbox、不拆 AppState、不合并引用体系。

### SL-03 本地候选编辑后确认
- 目标：Inbox 本地候选支持编辑字段后确认（对齐 PWA 裁决台）。
- 前置：SL-02。
- 红灯：LF-006（编辑值覆盖候选值→正式记录以用户值为准；AI 原候选仅作证据；重复确认幂等复用 DM-006）。
- 实现：LocalRecordUseCase/Repository 允许 confirm 时携带编辑 payload（现有 archiveStaging 已做 payload 归一化，扩展入口）；Inbox UI 编辑入口。
- 复用：C3 图片移交、C8 缓存失效、C4 投影刷新（SL-02 产物）。
- 不做：不做候选跨域改判（SL-04）、不做批量、不触远端 staging。

### SL-04 本地候选重试与域重判
- 目标：低置信候选可重试识别/改判域，带上限与人工出口（对齐 REC-009 语义）。
- 前置：SL-03。
- 红灯：LF-007（重试→重新路由；上限后仅人工归档/丢弃；已丢弃不可自动复活，除非用户显式重发）。
- 实现：复用 ingest 幂等（INV-8：discarded 才重路由）+ Provider 重调；重试计数落 staging 行（可选新列，本地迁移 v8——若引入，同时是 T3 迁移测试的天然载体）。
- 决策依赖：无（REC-009 语义已拍板，本地等价实现）。
- 不做：不做远端候选重试、不改 REC-009 云端语义。

### SL-05 编辑替换图片
- 目标：正式记录编辑时替换图片，失败不丢旧引用（DM §4.2）。
- 前置：SL-02。
- 红灯：LF-003（先写新图→更新引用→失败旧引用完好；成功后旧图按生命周期清理）。
- 实现：LocalRecordUseCase.update 按 C3 模式扩展（这是 C3 的 YAGNI 触发点：第二个真实消费场景出现，若 staging 编辑也要用，再提私有方法）。
- 不做：不做多图、不做裁剪编辑器。

### SL-06 本地日聚合（可选前置，依赖门 Q-05 半开）
- 目标：为 F4/F5 本地适配提供纯读侧原料：按 Asia/Shanghai 切日的五域聚合，语义对齐 `daily_domain_summary`。
- 前置：SL-02。可在 Q-05 拍板前先行（纯函数、不触 AI）。
- 红灯：LF-014（切日/单位/估算口径与云端视图一致——用云视图 SQL 语义做 fixture 对照）。
- 实现：LocalFactReader 之上的纯函数聚合（Swift 结构体，无新表、无缓存层；缓存属 LF-015，随 Q-05 拍板后切片）。
- 不做：不做 AI 调用、不做 UI、不做缓存。

### SL-07 可携兜底确认 + 孤儿图片巡检（小 Slice）
- 目标：D4 兜底可达性结论 + INV-11 孤儿文件行为特征化。
- 红灯/验证：LocalRecordPortability fallback 可达性测试（旧库 fixture）；删除中断模拟→孤儿文件存在但读取不受损（INV-11 特征化）。
- 不做：不删 RecordPortability（只标记）、不做孤儿清理任务（YAGNI，除非测试证明影响读取）。

### SL-08 异常恢复加固
- 目标：LF-023 低存储、LF-024 迁移失败回滚。
- 前置：SL-02~05 任一完成后即可；建议在 SL-04 引入 v8 迁移后做（有真实迁移可测）。
- 红灯：LF-023（空间不足→明确错误、无伪保存、释放后重试成功）；LF-024（迁移中断→回滚到上一版本状态、App 可恢复）。
- 验证边界：真机低存储需 TestFlight 真机清单项；模拟器覆盖注入错误路径。

### SL-09 四域导入恢复
- 目标：LF-021。
- 前置：SL-02；建议在五域真机验收（M1）后。
- 红灯：LF-021（稳定 ID 幂等、冲突策略与 expense 导入一致、失败不破坏既有数据、图片 base64 恢复）。
- 实现：LocalFactPortability 增加 import（复用 LocalExpensePortability 的校验框架 :389-414 模式）。
- 决策依赖：冲突策略若需偏离 expense 导入（"冲突整包拒绝"），升级为拍板项。

### 决策依赖 Slice（拍板前不启动，仅登记影响面）
| Slice | 门 | 影响域 |
|---|---|---|
| SL-A 收入本地域 | Q-01 | D3 模型+FactReader+导出+聚合+Today（F14/LF-032）；同时决定 LF-008 回退边界是否消失 |
| SL-B 钱包快照本地域 | Q-01 | 同上 + F5 财务推演（LF-033） |
| SL-C 设置本地镜像 | Q-04 | D11 + 登录合并（LF-019/020）；影响 F10 |
| SL-D AI Popup 本地最小闭环 | Q-05 | D7 + SL-06 消费（LF-010~013）；选择 a/b/c 决定 SL-06 之后是否还有表达核心移植片 |
| SL-E BYOK Provider | Q-06 | D6（LF-029~031）；不改 ingest/保存流程（C1/INV-8 不变） |
| SL-F 消费账户解耦 | Q-07 | D2（LF-017）：local_expenses.account_id 可空迁移 + 分录门禁；影响 SL-09 导入模型 |
| SL-G 账号轮换/清空流程 | Q-02 | D1（LF-026）：可能引入多 profile 或门禁清空，牵动 INV-18 |
| SL-H 删 App 提示 / 删账号本地处置 / 本地留存策略 | Q-10/Q-11/Q-09 | D5 + 设置页（LF-025/027/005） |
| SL-I 绑定预览逐条 diff / discard 幂等化 / 登录态本地导出 | Q-12/Q-13/LF-022 | 低优先 |

## 8. 推荐开发顺序

```text
SL-01 文档收口
  → SL-02 投影收敛+特征加固        [风险最低、收益最大：后续所有片踩在稳定读模型上]
  → SL-03 候选编辑确认
  → SL-04 候选重试/域重判          [完成后 Inbox 本地闭环 = HANDOFF §15 延期项清零]
  → M1 里程碑：五域真机验收（K 片待真机清单 + LF-004 重启图片）——用户动作，Gate
  → SL-05 编辑换图 ∥ SL-07 兜底/孤儿确认（可并行）
  → SL-08 异常恢复加固
  → SL-09 四域导入
  → [按拍板结果插入 SL-A~I；SL-06 可在 M1 后任意空闲会话先行]
```

排序理由：①SL-02 前置一切（8 处重复分支是每次写路径改动的公共雷区）；②候选闭环（03/04）直接清偿 HANDOFF 既定延期项，先于换图/导入等新能力；③M1 放在候选闭环后，使真机验收覆盖最完整的本地闭环；④导入（09）放 M1 后，避免导出格式在真机反馈未定前扩张。

## 9. Slice ↔ Scenario 对照总表

| Slice | 覆盖 Scenario（沿用/新增） | 新增编号 |
|---|---|---|
| SL-01 | —（文档） | — |
| SL-02 | DM-004/005/011/013/014 具名化、LF-001、LF-002、D3/D6 特征化 | LF-001、LF-002 |
| SL-03 | DM-006（复用）、LF-006 | LF-006 |
| SL-04 | REC-009 本地等价、LF-007 | LF-007 |
| SL-05 | DM-007 扩展、LF-003 | LF-003 |
| SL-06 | LF-014 | LF-014 |
| SL-07 | INV-11 特征化、D4 可达性 | — |
| SL-08 | LF-023、LF-024 | LF-023、LF-024 |
| SL-09 | LOCAL-002F 模式复用、LF-021 | LF-021 |
| SL-A~I | LF-005/008/009/010~013/015/016/017/019/020/022/025~033 | 随启动时分配子编号 |

未排入任何 Slice 的 BDD 场景：LF-004（真机项，属 M1）、LF-009（登记不排）、LF-011/012/013（SL-D 内拆）、F11/F12 全部（冻结登记）、LF-015/016（SL-D 后续）。

## 10. 拍板记录（2026-09-25 用户确认）与 Slice 门状态更新

### 10.1 拍板结论

| # | 问题 | 结论 | 对 Slice 的影响 |
|---|---|---|---|
| Q-01 | 收入/钱包 | **进 Phase 1 本地化**。钱包取最小形态 a：只记快照事实，不做还款周期/账务推演（依赖 Q-03 不本地化）；登录态收入/钱包继续走云端 | SL-A/SL-B 解锁；LF-008 回退边界在收入域本地化后收窄；SL-06 聚合与导出 schema 按"七域"设计（expense+income+4 数据域+wallet，wallet 是否进聚合随 SL-B 细化） |
| Q-02 | 换账号归属 | 维持现状（mismatch 只能[暂不同步/退出]，B 可见 A 本地数据），不做多 profile | SL-G 关闭（不实施）；风险已知并接受 |
| Q-03 | 还款/截图还款/补绑/周期本地化 | **不做**。云端 RPC 是原子权威（ADR-040），本地重写状态机成本高且制造双权威；Phase 1 维持"登录可用" | SL 门关闭；SL-B 钱包因此定形为"只记事实" |
| Q-04 | 设置本地镜像 | 未登录设置存本地；登录后"谁改得晚谁赢"（以后修改时间合并），之后以云端为准 | SL-C 解锁，策略固定 |
| Q-05 | AI Popup 本地口径 | 方案 a：确定性候选文案（代码算、不调 LLM）；候选最小集=当前记录事实+简单周期两类；本地模式隐藏点评 UI，不实现本地曝光/反馈存储（LF-011 简化为不存储） | SL-D 解锁，范围缩小：无反馈存储、无复杂候选移植 |
| Q-06 | BYOK | **暂缓**，移出 Phase 1 | SL-E 关闭（移出）；LF-029~031 冻结登记 |
| Q-07 | 消费账户解耦 | 维持现状：必须选账户才能保存。DM-GAP-10 不采纳，有真实需求再重新 Grooming | SL-F 关闭；BDD LF-017 标记不实施 |
| Q-08 | 登录态新记录路由 | 维持现状（登录态新建走云端）。双轨定位见 10.2 | LF-002 特征化保留（SL-02），语义冻结 |
| Q-09 | 本地图片留存 | 不做留存档位。验收标准=三条删除路径（删记录/弃候选/换图弃旧图）各有 XCTest 证明无残留文件；接受孤儿文件存在，不做后台清理任务 | SL-05 红灯补充删除残留断言；SL-07 的孤儿特征化口径确认 |
| Q-10 | 删 App 提示 | 设置页数据区常驻文案"本地数据仅存于此设备，删除 App 将一并删除"+ 导出入口；不做弹窗 | SL-H 子项，随 SL-C 设置切片或独立小片实施 |
| Q-11 | 删账号本地处置 | 勾选框默认不勾选"同时删除本地数据"；勾选时动态提示"另有 N 条本地记录仅存在于此设备"（防丢闸） | SL-H 子项 |
| Q-12 | 绑定预览 diff | 不做，维持计数级概览 | LF-028 不实施 |
| Q-13 | discard 幂等 | 改为幂等：重复销毁返回已销毁语义而非报错（约 5 行+1 测试） | 并入 SL-03 或独立微片；INV 状态更新：候选销毁幂等化 |

### 10.2 双轨架构定位（用户原话口径）

双轨（未登录=本地闭环、登录=沿用云端成熟路径）**只是 Phase 1 同步冻结期间的迁移期策略，不是最终架构**。长期目标仍是 Local-First：本地作为主要事实写入路径，Cloud/Sync 是可选增强。同步解冻后再收敛登录态路径，不永久维持两套实现。

### 10.3 更新后的实施顺序

```text
SL-01 文档收口（含：DM-GAP-10 标记不采纳、BDD LF-017/LF-028/LF-029~031 状态更新、BYOK 移出 Phase 1）
  → SL-02 投影收敛+特征测试加固（LF-002 特征化保留）
  → SL-A 收入本地域 → SL-B 钱包快照本地域（最小形态，互相独立可并行）
  → SL-03 候选编辑确认（并入 discard 幂等 Q-13）→ SL-04 候选重试/域重判
  → M1 五域真机验收（Gate：K 片待真机清单 + LF-004 重启图片）
  → SL-05 编辑换图（含 Q-09 删除残留断言）∥ SL-07 兜底/孤儿确认
  → SL-08 异常恢复 → SL-09 四域导入
  → SL-C 设置本地镜像（含 SL-H 的删 App 文案/删账号勾选框，或拆独立小片）
  → SL-D AI 确定性候选文案（范围按 Q-05 收窄后开工）
```

关闭/移出：SL-E（BYOK 暂缓）、SL-F（Q-07）、SL-G（Q-02）、SL-I 剩余项（Q-12）。

## 11. 验证边界声明

- 本文结论基于 2026-09-25 静态只读阅读（分支 `codex/local-first-phase1-fact-reader`）；iOS 编译/XCTest 以 macOS CI 为准。
- 冻结项（F11/F12、PWA 结构、生产迁移/部署/TestFlight）未被本文解冻；任何 Slice 不得触碰 `local_outbox_operations`/`local_sync_state` 之外的同步面、Edge Function、PWA。
- SL-02 的特征测试固定的是**现状行为**（含 LF-002 登录态走云端这一与"本地优先"直觉相反的现状）；特征化≠认可，Q-08 拍板后才改语义。
