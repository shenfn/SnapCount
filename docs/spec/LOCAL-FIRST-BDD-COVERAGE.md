# 芥子 Local-First 全景 BDD 场景梳理

> 规格编号：LOCAL-FIRST-BDD-001
> 状态：只读梳理稿，待评审（本文档不授权任何实现）
> 日期：2026-09-25
> 基线：主工作区分支 `codex/local-first-phase1-fact-reader`（HEAD `7005e81`，PR #199 系列）；根工作区存在用户 WIP，本轮未触碰
> 编号纪律：沿用既有场景编号（REC/EXP/CORE/PWA/A4-IOS/D-REMOTE/LOCAL-002/LOCAL-003/LOCAL-P1-DM/LOCAL-P1-SPORT/LOCAL-DATA）；仅对**尚无编号的真实缺口**分配新前缀 `LF-001` 起的编号。同一不变量不另造平行编号。

## 1. 目的与事实来源

以现有 iOS + PWA 完整产品能力为基线，确认 Local-First 改造最终需要覆盖的全部用户能力和业务场景；反向检查遗漏；为后续 TDD 切片提供可直接引用的 BDD 场景。

事实来源（六个只读盘点 + 主流程二次验证，全部附代码行号，未做任何修改）：

1. iOS 本地数据层（`ios/SnapCount/LocalData/`、`AppState.swift`、`Features/Records/`）
2. PWA 功能面（`src/`、`src/domains/registry.js`、各 Page/Modal/Feature，以 git HEAD 的 `index.html` 为生产入口）
3. AI 链路（`supabase/functions/_shared/expression-core/`、`ingest-receipt/`、`generate-insights/`、iOS AI 资产）
4. 同步协议与迁移（D-REMOTE 系列、LOCAL-003 RC Gate、ADR-040、LOCAL-DATA 生命周期规格）
5. iOS 云端依赖面（`ios/SnapCount/Repositories/`、`Services/`）
6. 存量场景编号体系（`docs/spec/10-记录生命周期规格说明.md`、`20-陪伴表达事实契约.md`、`01-跨端一致性契约.md`、`docs/spec/执行记录/`、`ios/SnapCountTests/`）

关键结论经主流程对源码二次抽查确认：`discardStaging` 不幂等（[LocalRecordRepository.swift:352-373](file:///d:/Business/count/ios/SnapCount/LocalData/LocalRecordRepository.swift#L352-L373)）、置信度分域阈值（[LocalRecordModels.swift:367-394](file:///d:/Business/count/ios/SnapCount/LocalData/LocalRecordModels.swift#L367-L394)）、staging 引用前缀 `local-staging/`（[LocalStagingReadModel.swift:4](file:///d:/Business/count/ios/SnapCount/Features/Records/LocalStagingReadModel.swift#L4)）、未登录四域手动创建走本地（[AppState.swift:4492-4494](file:///d:/Business/count/ios/SnapCount/App/AppState.swift#L4492-L4494)）。

明确不在本文范围：修改业务代码；解冻同步主线；重新讨论已拍板的产品范围（五域及收入/钱包、AI Popup/Analysis 不合并、Cloud Sync 冻结）。

## 2. 现有能力基线

### 2.1 iOS 本地能力（已实现，附证据）

| 能力 | 状态 | 证据 |
|---|---|---|
| GRDB/SQLite 本地库，8 表，迁移到 local-v7 | ✅ | LocalDatabase.swift:39-238（v6 补 source_kind/domain_version，v7 衮 evidence/missing_fields） |
| 免登录自动创建本地 profile（不静默建云端账户） | ✅ | LocalProfileStore.swift:19-48；AppState.swift:253-258 |
| 消费 CRUD + expectedVersion 乐观锁 + tombstone + 分录联动 + outbox | ✅ | LocalExpenseRepository.swift:163-431 |
| 本地账户创建 + 余额由期初+活跃流水派生 | ✅ | LocalExpenseRepository.swift:61-100,699-726 |
| 四域（food/sleep/sport/reading）CRUD + 乐观锁 + tombstone | ✅ | LocalRecordRepository.swift:25-157 |
| staging 确认幂等（confirmStaging 保留 target 关系+图片移交）/丢弃（重复丢弃抛错不改终态） | ✅ | LocalRecordRepository.swift:266-373 |
| 分域置信度路由：food 0.80，sleep/sport/reading 0.75，兜底 0.80 | ✅ | LocalRecordModels.swift:367-394 |
| 同图重试幂等（imageHash 派生确定性 UUID） | ✅ | LocalImageRecognition.swift:125,130-145；LocalRecordUseCase.swift:203-244 |
| Hosted AI recognize_only → 本地候选/自动归档，零云端业务写入 | ✅（K 片生产已验证） | LocalImageRecognition.swift:148-188；HANDOFF §17-18 |
| 图片本地生命周期（intake/records/staging，失败清理，路径防越界） | ✅ | LocalImageStore.swift:34-93；LocalImageRecognition.swift:90-95 |
| LocalFactReader 统一事实投影（expense+4 域，排除 staging/tombstone） | ✅ | LocalFactReader.swift:63-92 |
| 五域导出 JSON/CSV（可选图片 base64，排除凭据） | ✅ | LocalFactPortability.swift:117-204 |
| expense 域导入（幂等/冲突整包拒绝/版本校验） | ✅ | LocalExpensePortability.swift:159-387 |
| 单设备 expense+账户同步（outbox/cursor/tombstone/冲突终态），已上生产，随 Phase 1 冻结 | ✅🧊 | LocalSyncCoordinator.swift:100-203；SupabaseSyncTransport.swift:95-216 |
| 登录绑定预览（绑定状态比对+计数概览） | ✅ | LocalBindingPreviewUseCase.swift:39-158 |
| 退出登录保留本地库与图片、停同步、清内存投影 | ✅ | AppState.swift:389-407,4161-4272；LocalFirstLogoutProjectionTests |
| 未登录本地读取回退（Records/Inbox/Account 详情） | ✅ | AppState.swift:832-1022,1500-1534,2835-2892 |

### 2.2 iOS 仍依赖云端的能力（未 Local-First 化）

| 能力 | 云端接口 | 本地替代 | 说明 |
|---|---|---|---|
| 收入记录（创建/编辑/补绑） | `save_income_with_account` | ❌ | 本地域只有 expense+4 域；离线收入录入失败 |
| 钱包快照（读取/创建账户/关联） | `apply_wallet_snapshot` | ❌ | DomainsView.swift:377-432 |
| 还款确认/撤销/周期准备/截图还款 | `set_repayment_cycle_paid_amount`/`revoke_liability_payment`/`ensure_liability_repayment_cycles`/`confirm_staging_repayment` | ❌ | A4-IOS-003/005/006，需登录 |
| 补绑（单条/批量） | `save_transaction_with_account` 等 | ❌ | 推荐引擎本地，写入云端 |
| 待补全确认 | `confirm_pending_transaction_with_account` | ❌ | InboxRepository.swift:142-157 |
| 云端中转站归档/销毁/重试 | `archive_staging_record`/`discard_staging_record`/ingest 重试 | 仅本地候选有本地路径 | NativeDataService.swift:556-641 |
| AI Popup（表达计划/曝光/反馈） | get/ack plan、submit_expression_feedback | ❌ | 曝光身份（plan_token/exposure_event_id）硬绑定云端 |
| 跨域 Analysis | `daily_domain_summary`/`ai_insights`/`generate-insights` | ❌ | 强登录；无本地日聚合与缓存 |
| 设置 19 项 | `user_configs` 读/写 | ❌ | 未登录设置页 AI/隐私区块不可保存；仅主题+快捷指令偏好是本地 |
| 已登录数据导出 | REST 三表分页 | 未登录走本地导出 | AppState.swift:3950-3972 |
| 云端原图清理/删除账户/词汇表 | `cleanup_all_images`/`delete_account`/`user_finance_vocabulary` | ❌ | SettingsRepository.swift:46-62 |

### 2.3 PWA 功能面（维护模式基线，与 iOS Local-First 相关的结论)

- 生产入口为 `index.html`（git HEAD；当前磁盘副本被未提交 WIP 覆盖为无关页面，不影响结论）。5 Tab：首页/待处理/数据域/报告/设置；二级页含账户详情、补绑、日详情、记录详情、Insights。
- PWA 完整能力：批量归档/销毁（仅财务域）、裁决台、账单补全、还款/撤销、钱包快照、补绑、五域+收入+钱包、19 项设置、原图留存 4 档+立即清理、词表自学习、AI 识别引擎配置、Insights AI 解读、多文件导出（不含图片）。
- PWA 无文件上传 UI：采集 100% 依赖 iOS 快捷指令。
- 已有后端无 PWA UI 的 action：`delete_account`、`list/delete_companion_memories`。
- PWA 维护模式（03-索引）：仅安全/关键缺陷/同步兼容修改。

### 2.4 文档与代码不一致清单（以代码为准，已记录差异）

| # | 文档说法 | 代码事实 | 处置 |
|---|---|---|---|
| V-1 | HANDOFF §3："未登录手动入口目前主要覆盖消费" | 未登录四域手动创建已走本地（AppState.swift:4492-4494；`shouldCreateLocalDomainRecord` 未登录直接 true） | SL-01 已更新 HANDOFF；完整候选/图片闭环仍按后续 Slice |
| V-2 | Grooming DM-GAP-03："iOS 通用实现固定 0.80" | 已是分域阈值 food 0.80/其余 0.75+兜底 | SL-01 标记 DM-GAP-03 已收敛；SL-02 补具名特征测试 |
| V-3 | Grooming §6.1 引用规范 `staging/<id>`；DM-GAP-02"通用记录缺 source/domain_version" | 实际前缀 `local-staging/<id>`；另并存 `local-expense/`、`local-data/` 双引用体系；local-v6 已补 source_kind/domain_version | SL-01 更新事实口径；三套引用并存仍登记为架构债务 |
| V-4 | LOCAL-002 Spec §5.1 部分行写"待红灯" | APP 片红灯+绿灯已完成（Run 32623778871，242/242） | 索引滞后 |
| V-5 | 03-阶段与任务索引：当前阶段 LOCAL-003-RC | 当前阶段已切换为 Phase 1 Local-First 主线；LOCAL-003-RC 保留历史同步证据 | SL-01 已收口；双轨仅为同步冻结期迁移策略 |
| V-6 | 状态-001："已解决不得重复确认" | discardStaging 重复调用抛 invalidRecord（confirmStaging 幂等返回既有结果） | 语义可接受（重复丢弃不改终态），BDD 已固化；如需幂等返回需小改 |
| V-7 | Grooming §2.2：本地消费 `account_id` 可空（DM-GAP-10） | `local_expenses.account_id` 非空约束，创建必须先选账户 | Q-07 已拍板维持现状；DM-GAP-10 不采纳 |
| V-8 | 06-计划 §7 要求低存储/迁移失败验证 | 无对应测试 | 真实缺口（LF-023/024） |

### 2.5 需要注意的行为事实

- 登录态手动新建四域默认走云端，只有编辑"已有本地记录"时才走本地（AppState.swift:4492-4500）。
- 登录态 Records = 本地月分组与远端按 canonical reference 去重合并、本地优先（AppState.swift:794-826）。
- 两条本地月份投影路径对"登录态是否应用当月投影"行为不一致（`applyLocalFactMonth` 仅未登录当月应用 vs `applyLocalRecordMonth` 登录也应用，AppState.swift:949-952,1092-1097）。
- 本地 `applyLocalFactMonth` income 恒 0（本地无收入域）。
- `local_records` 表 CHECK 允许 `expense` 但校验层禁止（可达 schema、不可达业务）。
- 本地 expense 无业务唯一约束：手动重复录入同笔消费会重复（云端 ingest 有三层去重；本地手动无）。
- 同一设备本地库只有单一 profile；绑定第二个云账号会 mismatch，仅能"暂不同步/退出登录"，本地数据仍属第一账号（见 Q-02）。
- 快捷指令对不支持的域（income/wallet）静默回退云端完整 ingest，产生云端业务写入而本地无副本。

## 3. 覆盖关系总表

| # | 现有产品能力 | Local-First 状态 | BDD Feature | 场景编号来源 |
|---|---|---|---|---|
| 1 | 免登录本地 profile | ✅ 已实现 | F1 | LOCAL-DATA-001 / LOCAL-002A1 |
| 2 | 消费 CRUD/余额/账户 | ✅ 已实现 | F1/F6 | LOCAL-002A-J |
| 3 | 四域手动 CRUD（未登录） | ✅ 已实现（V-1） | F1 | LF-001 |
| 4 | 图片本地生命周期 | ✅ 骨架完成；编辑换图缺 | F2 | SPORT-001-E/F/G、DM-007、LF-003~005 |
| 5 | Hosted AI 识别→本地候选/归档 | ✅（K 片已生产验证） | F3 | SPORT-001-J/K、LF-006~009 |
| 6 | 本地中转站确认/丢弃 | ✅；编辑/重试延期 | F3 | DM-005/006/007、LF-006/007 |
| 7 | AI Popup / 表达 | ❌ 云端权威 | F4 | EXP-006/008/012（登录态）、LF-010~013 |
| 8 | 跨域 Analysis | ❌ 云端权威 | F5 | —（登录态沿用）、LF-014~016 |
| 9 | 还款/撤销/补绑/截图还款/周期账务推演 | ❌ 登录+云端 | F6 | A4-IOS-003/005/006/007（登录态）、Q-03 |
| 10 | 设置 | ❌ 云端 19 项 | F7 | —、LF-019/020 |
| 11 | 五域导出 | ✅（未登录）；登录态走云端 | F8 | LOCAL-002E、DM-010、SPORT-001-F、LF-022 |
| 12 | 导入恢复 | ⚠️ 仅 expense | F8 | LOCAL-002F、LF-021 |
| 13 | 单设备同步（expense/账户） | 🧊 冻结（已上生产） | F12 | LOCAL-003-D1~D4、DREMOTE-010~017 |
| 14 | 老用户迁移 L2 | ❌ 待开始 | F11 | LOCAL-DATA-010/011（提议） |
| 15 | BYOK | 🧊 冻结登记（协议就位，零实现） | F13 | LF-029~031、BYOK-Grooming |
| 16 | 收入 | ⏳ 范围已拍板，待 SL-A | F14 | Q-01、LF-032 |
| 17 | 钱包快照 | ⏳ 范围已拍板，待 SL-B（最小形态） | F14 | Q-01、LF-033 |
| 18 | 异常恢复（重启/断网/低存储/迁移失败） | ⚠️ 重启/断网已测；低存储/迁移失败未测 | F9 | LOCAL-002B/G、DM-013、LF-023~025 |
| 19 | 登录绑定/退出登录/账号轮换 | ✅ 基础闭环；轮换归属未定义 | F10 | LOCAL-003C、DREMOTE-010~017、SPORT-001-L、LF-026~028 |

## 4. BDD 场景

> 约定：`[沿用]` 表示已有编号的场景，仅登记不重写验收标准；`[新 LF-xxx]` 表示尚无编号的真实缺口，需要按 TDD 规范补红灯后再实现。真机类场景以 macOS CI 构建产物在 iPhone 上执行。

### Feature F1：五域本地正式事实与记录生命周期

```gherkin
Feature: 五域记录的本地正式事实能力
  本地数据库是当前设备的事实来源；未登录、断网、AI 关闭均可完成记录管理。

  [沿用] Scenario: 免登录首次启动创建本地 profile（LOCAL-DATA-001 / LOCAL-002A1）
    Given 全新安装且未登录
    When App 启动完成 bootstrap
    Then 本地库存在一条 cloud_user_id 为空的 profile，且没有向 Supabase 发起任何业务写请求

  [沿用] Scenario: 未登录创建消费并派生余额（LOCAL-002A1 / J1）
    Given 未登录且已存在账户
    When 创建一笔消费
    Then 消费、账户分录、outbox 在同一事务落库；余额等于期初加活跃分录净额

  [新 LF-001] Scenario: 未登录手动创建饮食/睡眠/阅读记录
    Given 未登录且本地 profile 存在
    When 从手动表单分别创建 food/sleep/reading 记录（sport 已有 SPORT-001 覆盖）
    Then 记录写入 local_records，LocalFactReader 可读出，Today/Records 当月投影立即刷新
    And 不产生任何云端请求
    # 代码已实现（AppState.swift:4492-4494），但缺独立场景编号与 XCTest 具名覆盖

  [沿用] Scenario: 编辑使用乐观锁（LOCAL-002C1-4 / DM-008）
    Given 一条正式记录本地版本为 v
    When 用 expectedVersion ≠ v 提交编辑
    Then 编辑显式失败且不覆盖新事实

  [沿用] Scenario: 删除产生 tombstone 并作废分录（LOCAL-002D1-2 / DM-007）
    Given 一条绑定账户的消费
    When 删除该消费
    Then deleted_at 置值、版本递增、活跃分录作废、outbox 写删除操作；读取层不再返回该记录

  [沿用] Scenario: 数据库重开一致性（LOCAL-002B2 / DM-013）
    Given 本地库已有正式记录、staging、图片
    When 关闭并重新打开数据库（模拟 App 重启）
    Then 全部行、版本、图片引用与删除语义保持一致

  [沿用] Scenario: 域 payload 规范化（DM-003 / DM-GAP-04）
    Given AI 或手动输入含别名单位（sleep_hours、duration_min 等）
    When 保存为正式事实
    Then 正式库只保留规范单位（sleep_minutes/duration_minutes/reading_minutes），估算标记保留

  [沿用] Scenario: 时间不伪造（DM-009 / TIME-REF-001）
    Given 记录缺少精确发生时间
    When 保存与展示
    Then 业务日期保留用户日期；不用上传时刻或默认时间冒充发生时间

  [沿用] Scenario: 统一事实读取边界（DM-011）
    Given 本地存在正式记录、staging 候选、已删除记录
    When LocalFactReader 读取
    Then 只返回 expense/<uuid> 与 data/<uuid> 正式事实；staging 与墓碑不出现在任何正式读取者

  [沿用] Scenario: 未启用同步时不混读（DM-014 / LOCAL-003-D4）
    Given 用户已登录但未确认绑定同步
    When 浏览 Today/Records/Account
    Then 不发生云端与本地的静默拼接或重复展示

  [新 LF-002] Scenario: 登录态手动新建四域的路由语义固化
    Given 用户已登录且已绑定同步
    When 手动新建一条 sport 记录
    Then 按现状写入云端（createRemoteManualRecord）；本地库不出现该记录，直到投影/同步路径明确带入
    And 该行为按 Q-08 固化为现状特征；SL-02 只测试防漂移，不改登录态路由
```

### Feature F2：本地图片生命周期

```gherkin
Feature: 图片与记录同生命周期的本地存储
  图片以本地相对路径+内容 hash 归属记录，不依赖远端 URL。

  [沿用] Scenario: 识别图片先落 intake 且失败清理（SPORT-001-J）
    Given 一张待识别图片
    When 识别流程启动后 AI 请求失败
    Then intake 文件被清理，不留下只有数据库的候选

  [沿用] Scenario: 候选确认后图片移交正式记录（SPORT-001-I / DM-007）
    Given 本地 staging 候选带图片
    When 用户确认候选
    Then 图片所有权移交正式记录，staging 行清空图片引用并保留 archived 关系

  [沿用] Scenario: 丢弃候选清理图片（DM-007）
    Given 本地 staging 候选带图片
    When 用户丢弃候选
    Then 候选置 discarded 终态并清理图片文件

  [沿用] Scenario: 导出附带图片（SPORT-001-F / DM-010）
    Given 本地事实与图片
    When 用户勾选包含图片导出
    Then 图片以 base64 进入归档；不导出任何 token、签名 URL 或 Key

  [新 LF-003] Scenario: 编辑正式记录时替换图片
    Given 一条带本地图片的正式记录
    When 用户在编辑中替换为新图片且新图写入失败
    Then 旧图片引用不被破坏，记录保持可用；成功时先写新图再更新引用
    # DM §4.2 已定义，代码未实现（DM-GAP-06 残余）

  [新 LF-004] Scenario: App 重启后图片仍可展示（真机）
    Given 识别或手动创建产生的本地图片
    When App 完全退出后重新启动并打开对应记录
    Then 图片从本地目录加载成功，不依赖网络
    # HANDOFF §17-18 待真机清单项

  [新 LF-005] Scenario: 本地图片留存策略（Q-09 不设留存档位）
    Given 本地图片随记录累积
    When 用户查看存储占用或清理入口
    Then 不提供云端四档留存的本地等价配置；删记录、弃候选、换图弃旧图分别由 XCTest 证明无残留文件，接受偶发孤儿文件
    # Q-09 已收敛；不做后台清理任务
```

### Feature F3：AI 识别的本地候选闭环

```gherkin
Feature: 图片识别产生的候选全部本地生命周期
  Hosted AI 只产生候选；候选经阈值与字段完整性路由为自动归档或本地中转。

  [沿用] Scenario: 支持域在两态都只产本地事实（SPORT-001-J/K）
    Given 登录或未登录用户提交一张运动截图
    When Hosted AI 返回高置信完整候选
    Then 正式事实只写入本地库，云端业务表与 Storage 零新增（生产 smoke 已验证）

  [沿用] Scenario: 低置信或字段缺失只进本地 Inbox（SPORT-001-H / DM-005）
    Given AI 返回低置信或缺关键字段
    When ingest 路由执行
    Then 候选只进入 local_staging_records，正式读取不可见

  [沿用] Scenario: 同图重试幂等（SPORT-001-J / REC-002 本地等价）
    Given 同一张图片（同 hash）重复提交
    When ingest 再次执行
    Then 已存在正式记录直接返回；pending 候选复用；已丢弃候选才重新路由

  [新 LF-006] Scenario: 本地候选的编辑后确认
    Given 本地 Inbox 存在一条低置信候选
    When 用户编辑候选字段后确认
    Then 正式记录以用户确认值为准，AI 原始候选仅作证据；确认仍幂等
    # HANDOFF §15 明确延期项；PWA 裁决台已有对应能力（ModalPending）

  [新 LF-007] Scenario: 本地候选的重试与域重判
    Given 本地候选识别错误或置信度不足
    When 用户发起重试
    Then 候选可重新识别并按结果更新路由；重试有上限与人工出口（对齐 REC-009 语义）
    # 当前本地候选无重试路径；云端候选重试走 ingest staging_record_id

  [新 LF-008] Scenario: 不支持域的回退边界
    Given 用户提交收入或钱包快照截图
    When 快捷指令/应用内识别判定域不受本地支持
    Then 按现状回退云端完整 ingest（产生云端业务写入，本地无副本）
    And 该体验与"功能不缩水"的偏差需产品拍板（Q-01）

  [新 LF-009] Scenario: 本地识别重复提交的近似去重（低优先）
    Given 同一票据轻微裁剪后两次提交（hash 不同）
    When 本地 ingest 执行
    Then 现状会生成两条候选（无感知哈希检测）；是否补齐近似去重由拍板决定
    # 云端有 sha256+感知哈希+3 分钟疑似重复三层；本地仅 hash 确定性 ID
```

### Feature F4：AI Popup / 陪伴表达的本地适配

```gherkin
Feature: 表达能力从本地正式事实读取
  表达核心算法为纯函数可移植；缺口在数据供给、曝光/反馈持久化与离线出口。

  [沿用] Scenario: 登录态表达链路保持（EXP-006/008/012）
    Given 已登录用户查看记录详情
    When 表达计划下发与曝光确认发生
    Then Voice 与 Planner 双槽互不覆盖，点评必须先有曝光确认

  [新 LF-010] Scenario: 表达候选从 LocalFactReader 供给
    Given 本地存在五域正式事实
    When 生成表达候选
    Then 候选输入来自 LocalFactReader（补 income/wallet 后为完整事实集），表达核心规则（EXP-001~007）不变
    # DM-GAP-08；表达核心（expression-core）为纯函数可移植，需数据适配层

  [新 LF-011] Scenario: 本地模式隐藏点评且不存曝光/反馈
    Given 本地模式产生表达计划、曝光、用户点评
    When 用户产生行为
    Then 本地模式隐藏点评 UI，不新增本地曝光/反馈存储；这些派生数据不混入五域事实表
    # Q-05 方案 a；在线表达仍沿用云端能力

  [新 LF-012] Scenario: AI 关闭/断网时手动记录不受阻且有表达出口
    Given AI Provider 为 Disabled 或网络不可用
    When 用户创建/编辑/删除/导出记录
    Then 全部成功；表达区按拍板口径显示确定性候选文案或隐藏（Q-05）

  [新 LF-013] Scenario: 本地模式的曝光身份语义
    Given 表达在本地模式运行（无云端 plan_token/exposure_event_id）
    When 用户查看与点评
    Then 本地模式不产生曝光确认、去重或点评持久化；只返回确定性候选文案或隐藏点评 UI
```

### Feature F5：跨域 Analysis 的本地适配

```gherkin
Feature: 多域洞察基于本地事实或显式云端模式

  [沿用] Scenario: 登录态 Analysis 保持
    Given 已登录用户打开联动分析
    When 请求生成解读
    Then 走 generate-insights + daily_domain_summary + ai_insights 缓存（现状）

  [新 LF-014] Scenario: 本地日聚合等价视图
    Given 本地五域事实
    When 计算每日聚合
    Then 按 Asia/Shanghai 切日聚合 expense/food/sleep/sport/reading 口径，与云端 daily_domain_summary 语义一致
    # 云端视图定义：migrations/016_daily_domain_summary.sql

  [新 LF-015] Scenario: 离线查看最近一次分析
    Given 用户曾生成过分析
    When 断网打开联动分析
    Then 显示本地缓存的最近一次结果并标注生成时间；无缓存时显示空态而非报错
    # 现状 iOS 仅内存持有 aiInsight，无本地缓存

  [新 LF-016] Scenario: 未登录本地模式的 Analysis 能力边界
    Given 用户未登录且无可用 LLM Provider
    When 打开联动分析
    Then 明确空态与原因说明；是否提供 BYOK 文本链路由 Q-06 决定
```

### Feature F6：账户与消费账务

```gherkin
Feature: 账务能力分层：本地基础 + 登录态完整账务

  [沿用] Scenario: 本地账户创建与余额派生（LOCAL-002A/J1）
  [沿用] Scenario: 登录态还款/撤销/截图还款/钱包快照/补绑（A4-IOS-003/005/006/007，云端 RPC）

  [新 LF-017] Scenario: 消费未绑定账户的保存（Q-07 不采纳）
    Given 用户想先记一笔消费、暂不选账户
    When 保存
    Then 保存被账户选择门禁阻止；`account_id` 保持非空，已绑定账户的消费才产生有效流水
    # DM-GAP-10：不采纳；如需解耦账户，另行 Grooming

  [新 LF-018] Scenario: 登录态账户读取的本地/远端边界固化
    Given 已登录且已绑定
    When 读取账户列表/详情
    Then shouldProjectRemoteData 镜像行为（按稳定 ID 幂等回灌本地投影）固化为测试，不随重构漂移
    # AppState.swift:1251-1332
```

### Feature F7：设置本地化

```gherkin
Feature: 设置项在本地模式可用

  [沿用] Scenario: 纯本地设置保持
    Given 未登录用户
    When 修改主题、上传通知、快捷指令卡片偏好
    Then 立即生效并本地持久化（现状）

  [新 LF-019] Scenario: 未登录设置可保存
    Given 未登录用户
    When 修改 AI/隐私/陪伴类设置（19 项 user_configs 的本地子集）
    Then 保存到本地设置存储并生效；登录后按“谁改得晚谁赢”合并，之后以云端为准
    # 现状：未登录这些设置不可保存

  [新 LF-020] Scenario: 登录后本地与云端设置的合并（Q-04 已拍板）
    Given 用户在未登录时修改过本地设置，随后登录
    When 设置同步发生
    Then 按每项修改时间以较晚值胜出，合并结果可见，之后以云端为准
```

### Feature F8：导入导出与数据可携

```gherkin
Feature: 用户拥有完整可携的本地数据

  [沿用] Scenario: 五域导出不泄凭据（DM-010 / LOCAL-002E / SPORT-001-F）
  [沿用] Scenario: expense 导入幂等与冲突拒绝（LOCAL-002F1-F4）

  [新 LF-021] Scenario: 四域导入恢复
    Given 用户在新设备或重装后持有五域导出归档
    When 导入
    Then food/sleep/sport/reading 记录按稳定 ID 幂等恢复；冲突策略与 expense 导入一致；失败不破坏既有数据
    # DM-GAP-09：目前仅 expense 有导入

  [新 LF-022] Scenario: 已登录用户的本地导出入口（待拍板，低优先）
    Given 已登录且本地存在绑定前产生的记录
    When 用户导出
    Then 是否同时提供"本地事实导出"由产品确认（现状登录态只导云端）
```

### Feature F9：生命周期与异常恢复

```gherkin
Feature: 极端条件下本地事实不丢失、不伪状态

  [沿用] Scenario: 断网全功能（LOCAL-002G）
  [沿用] Scenario: AI 失败不阻塞手动记录（LOCAL-002H / DM-012）
  [沿用] Scenario: 重启恢复（LOCAL-002B / DM-013）
  [沿用] Scenario: 并发写乐观锁（DM-008；DatabaseQueue 单写）

  [新 LF-023] Scenario: 低存储空间
    Given 设备剩余空间不足以写入图片或数据库页
    When 用户创建带图记录
    Then 保存失败有明确用户可读错误；数据库不进入损坏/伪保存状态；重试在空间释放后成功
    # 06-计划 §7 要求，当前无测试

  [新 LF-024] Scenario: 本地迁移失败回滚
    Given App 升级后首次打开触发 local-v7→v8 迁移
    When 迁移中途失败
    Then 数据库回滚到上一版本状态，App 显示可恢复错误而不是静默丢弃数据
    # GRDB 迁移事务性需验证；当前无测试

  [新 LF-025] Scenario: 删除 App 的数据结局提示（Q-10 已拍板）
    Given 用户准备删除 App
    Then 设置页常驻显示"本地数据仅存于此设备，删除 App 将一并删除"并提供导出入口，不弹窗
```

### Feature F10：登录、绑定与账号生命周期

```gherkin
Feature: 登录身份与本地数据的显式关系

  [沿用] Scenario: 登录不自动同步（身份-001 / DREMOTE-010）
  [沿用] Scenario: 绑定预览与 mismatch 出口（LOCAL-003C）
  [沿用] Scenario: 退出登录保留本地数据（LOCAL-DATA-003 / SPORT-001-L）
  [沿用] Scenario: 世代隔离（REC-013：userStateGeneration 防串用户）

  [新 LF-026] Scenario: 换账号使用同一设备的数据归属（Q-02 维持现状）
    Given 用户 A 曾在本机登录并绑定，本地库已有 A 的数据；A 退出登录
    When 用户 B 在同一设备登录
    Then 现状：绑定预览判 mismatch，B 只能暂不同步或退出；B 会看到 A 的本地记录
    And 不新增多 profile 或换设备主人流程；仅提供暂不同步、退出登录两个出口
    # 本地库单 profile（activeProfile 取最早创建）；bindingMismatch 时仅 [deferSync, signOut]

  [新 LF-027] Scenario: 删除云账号后的本地数据处置（Q-11 已拍板）
    Given 用户在设置中执行删除账户（delete_account）
    When 云端账号删除完成
    Then “同时删除本地数据”默认不勾选；勾选时提示仅存在本设备的本地记录条数
    # 云端账号删除与本地数据删除保持显式分离

  [新 LF-028] Scenario: 绑定预览的内容深度（Q-12 不实施）
    Given 用户首次登录且本地已有记录
    When 查看同步预览
    Then 维持计数级概览（本地条数/云端 scope），不实现逐条 diff
```

### Feature F11：老用户首次本地化迁移（L2，冻结登记）

```gherkin
Feature: 现有云端用户升级到本地优先
  状态：待开始（06-计划）；以下场景登记自 LOCAL-DATA-010/011，不解冻、不展开。

  [登记] Scenario: 首次本地化只读拉取（LOCAL-DATA-010）
  [登记] Scenario: 断点续传与迁移状态
  [登记] Scenario: 迁移期回滚保留云端读取（LOCAL-DATA-011）
  [登记] Scenario: 迁移不静默改余额

  # 现状说明：绑定开启同步后的全量 pull + 按月隐式镜像只覆盖 expense/accounts，
  # 且不是 LOCAL-DATA-010 定义的迁移流程（无断点续传/迁移状态机）。
  # 云端 income/钱包/通用域完全无迁移路径。
```

### Feature F12：可选同步（L3，冻结登记）

```gherkin
Feature: 单设备 expense/账户同步
  状态：D-REMOTE 服务端契约与 iOS 接线已上生产（PR #176/#177），随 Phase 1 决策冻结：不删除、不扩展、不作为发布阻塞。ADR-040 收缩为单设备+云端写入者；冲突自动 take-remote；多设备并发/人工冲突出口属 Phase B。

  [登记·冻结] Scenario: 绑定确认后首次同步（DREMOTE-010）
  [登记·冻结] Scenario: 同步成功发布 synced 并刷新读模型（DREMOTE-011）
  [登记·冻结] Scenario: 同步失败保留本地事实可重试（DREMOTE-012 / LOCAL-DATA-005）
  [登记·冻结] Scenario: rejected/cursor 过期/冲突终态（DREMOTE-014/015/016）
  [登记·冻结] Scenario: 四域与 staging 不在同步协议内（现状事实）
  # 解冻需用户显式决策；解冻前不补任何新同步场景。
```

### Feature F13：BYOK 与 AI Provider

```gherkin
Feature: AI Provider 可插拔且 Key 不出设备
  状态：BYOK 按 Q-06 暂缓，移出 Phase 1；以下场景只做冻结登记，不启动 Provider 适配。

  [登记·冻结 LF-029] Scenario: BYOK 识别直连 Provider
    Given 用户配置自己的视觉模型 Key
    When 提交图片识别
    Then 结果与 Hosted 同构（local-recognition-candidate-v1），进入同一本地 ingest，不产生第二套保存流程

  [登记·冻结 LF-030] Scenario: Key 安全边界
    Given 任意 AI Provider 配置
    When 识别/存储/导出/日志发生
    Then Key 只存 Keychain；不进入业务数据库、导出文件、日志或候选 payload（AI-001 / DM §5.2）

  [登记·冻结 LF-031] Scenario: Key 失效的用户出口（Q-06 暂缓）
    Given BYOK Key 被撤销或配额耗尽
    When 识别请求失败
    Then 返回结构化失败；是否自动回退 Hosted 由拍板决定；手动记录不受影响
```

### Feature F14：收入与钱包域（Q-01 已纳入 Phase 1）

```gherkin
Feature: 收入与钱包快照的本地域
  现状：云端完整、本地实现尚未开始；Q-01 已拍板纳入 Phase 1，分别由 SL-A（收入）与 SL-B（钱包快照）推进。

  [登记 LF-032] Scenario: 收入本地域（SL-A）
    Given 未登录用户收到一笔收入
    When 手动创建收入记录
    Then 收入写入本地独立存储，Today/Records/导出可见；offline 全可用

  [登记 LF-033] Scenario: 钱包快照本地域（SL-B，最小形态只记快照事实）
    Given 用户录入一张负债/现金快照截图或手动表单
    When 本地保存
    Then 快照与本地账户关联语义明确；Analysis 财务推演可读取
```

## 5. 反向遗漏检查（PWA/iOS 能力 → Local-First 覆盖）

| PWA/iOS 能力 | Local-First 覆盖 | 结论 |
|---|---|---|
| 五域手动 CRUD | F1 | 已覆盖（LF-001 补编号） |
| 收入域 | F14 / LF-032 | **范围已拍板，待 SL-A 实现** |
| 钱包快照域 | F14/F6 / LF-033 | **范围已拍板，待 SL-B 实现；最小形态只记快照事实** |
| 还款/撤销/截图还款/补绑 | F6 | 登录态保留；本地化待裁决（Q-03） |
| 批量归档/销毁中转 | F3（单条）；批量本地候选未定义 | 记录差异：本地候选暂无批量操作，低优先 |
| 账单补全（pending 交易三出口） | F6/收件箱 | 登录态云端保留；未登录无此对象（本地无 pending 交易概念），可接受 |
| 裁决台改判任意域 | LF-007 覆盖重试/重判 | 延期项已登记 |
| AI Popup/表达 | F4 | 适配缺口已登记（缺口最大） |
| Insights AI 解读 | F5 | 适配缺口已登记 |
| 报告页趋势/排行/分布 | F5（本地聚合）+ 月报基于 dashboard 投影 | 已覆盖读取；本地聚合为 LF-014 |
| 19 项设置 | F7 | 缺口已登记 |
| 原图留存 4 档/立即清理 | LF-005 | 待拍板 |
| 词表自学习（渠道/支付→账户） | 无本地场景 | 记录差异：登录态云端能力保留；本地模式无词表，不影响核心 |
| 多文件导出（不含图） | F8 | iOS 本地导出含图且更强，已覆盖 |
| 上传 Token 快捷指令链路 | F3 | 支持域已本地闭环；income/wallet 回退为 LF-008 |
| AI 识别引擎配置（provider/model） | 云端 user_configs 维持 | 未登录识别用 upload_token 由云端函数反查配置，不受影响；记录 |
| delete_companion_memories | 无 UI（两端皆是） | 不算产品遗漏 |
| 删除账户 | LF-027 | 本地处置待定义 |
| PWA 查看已同步数据 | 维护模式；Phase 1 无 Cloud Sync | 产品边界：登录不自动同步（已拍板），PWA 不承诺看到本地记录——无需新场景，但对外沟通需一致 |
| 首页组件开关排序（localStorage） | iOS 无对应配置 | 记录差异：iOS Today 布局固定，非 Local-First 阻塞项 |
| 快捷指令上传凭据 | Keychain upload_token | 已覆盖 |

反向检查结论：**除收入/钱包域（Q-01）外，未发现其他被完全遗漏的现有产品能力**；批量操作、词表、首页组件配置为记录级差异，不阻塞 Phase 1。

## 6. 发现的遗漏与风险

1. **AI 三链路数据供给全部在云端**（表达/Analysis/识别的配置与历史）：表达核心可移植但零移植；曝光/反馈/偏好三件套无本地存储形态（DM §5.2 留白）。这是 Phase 1 承诺"保留 AI Popup"与现状之间最大的工作量与设计空白。
2. **收入/钱包本地缺位**与"功能不缩水"承诺冲突；unsupported domain 静默回退云端 ingest 会产生"云端有、本地无"的分叉数据（LF-008/032/033）。
3. **单设备单 profile 的账号轮换**：换账号登录后 mismatch 只能暂不同步，且会看到前任账号的本地数据（LF-026）——隐私与体验双重风险。
4. **删除 App = 本地数据全丢**，产品无任何提示或兜底（LF-025）；四域导入缺失使"导出→导入"自助换机桥不完整（LF-021）。
5. ** discardStaging 不幂等**（重复调用抛错）：与状态-001"终态不死锁"精神一致但语义未成文（V-6）。
6. **两条本地月份投影路径行为不一致**（登录态当月投影应用与否），存在混读回归风险（§2.5）。
7. **本地无近似去重**：手动/AI 重复录入无感知哈希防护（LF-009）。
8. **低存储、迁移失败无测试**（LF-023/024），06-计划 §7 的最高规格验证未闭环。
9. **文档口径分裂**（V-1/V-4/V-5）：已由 SL-01 收口；历史差异仍保留在 V 表中作为追踪证据，当前入口以阶段索引和 Phase 1 Handoff 为准。
10. **`local_records` CHECK 含 expense 的死分支**与引用体系三套并存（`expense//data//local-expense//local-data//local-staging/`）：架构债务，建议在收敛切片处理。
11. **macOS CI 依赖**：本文全部代码结论来自静态阅读；iOS 编译/XCTest/真机验收以 GitHub macOS 与 TestFlight 为准（K 片待真机清单仍未关闭）。

## 7. 需要拍板的问题

> Q-01~Q-13 已于 2026-09-25 在 `LOCAL-FIRST-DOMAIN-CONVERGENCE.md` §10 收敛。本节保留问题背景，当前结论以该文为准；已移出 Phase 1 或标记不实施的场景不启动实现。

| # | 问题 | 背景/选项 |
|---|---|---|
| Q-01 | 收入/钱包域是否进入 Phase 1 本地化？ | **已拍板进入**；收入与钱包分别进入 SL-A/SL-B，钱包先只记快照事实（LF-032/033） |
| Q-02 | 换账号使用同一设备的数据归属与清理流程？ | 选项：带门禁的"更换设备主人"清空流程 / 多 profile 支持 / 维持现状并明示限制（LF-026） |
| Q-03 | 还款/撤销/补绑/截图还款/周期账务推演是否需要本地实现？ | **已拍板不做**；云端 RPC 保持原子权威。钱包快照按 Q-01 进入 SL-B 的只记事实形态 |
| Q-04 | 设置 19 项的本地镜像与登录后合并策略？ | 未登录可存本地是底线；合并策略需定（云端覆盖/本地覆盖/按项）（LF-019/020） |
| Q-05 | AI Popup 本地适配的最小闭环口径？ | 选项：a) 确定性候选文案（代码算、不调 LLM）先行；b) 全量表达核心移植+本地曝光/反馈存储；c) 本地模式隐藏表达（LF-010~013） |
| Q-06 | BYOK 三问题：Direct/Proxy/Aggregator？首批 Provider？Key 失效是否自动回退 Hosted？ | **已拍板暂缓**，移出 Phase 1；LF-029~031 仅冻结登记 |
| Q-07 | 本地消费是否解耦账户（account_id 可空）？ | **已拍板维持现状**：消费必须先选账户；DM-GAP-10 不采纳 |
| Q-08 | 登录态手动新建四域默认走云端的路由是否维持？ | **已拍板维持现状**；LF-002 作为特征测试，双轨仅是同步冻结期迁移策略 |
| Q-09 | 本地是否需要原图留存策略（对应云端 4 档/立即清理）？ | LF-005 |
| Q-10 | 删除 App 的数据结局是否需要产品内提示？ | LF-025 |
| Q-11 | 删除云账号后本地数据处置？ | LF-027 |
| Q-12 | 绑定预览是否需要逐条 diff（现为计数级）？ | **已拍板不做**，维持计数级概览（LF-028） |
| Q-13 | discard 重复调用语义：接受"报错不改终态"还是改为幂等返回？ | V-6 |

## 8. 建议后续实施顺序

按"先文档口径、再红灯、后最小实现"的既有纪律排列；每步先补场景编号与红灯，不越权实现。

1. **口径收口（SL-01，已完成）**：HANDOFF §3、阶段索引双口径、Grooming DM-GAP-02/03/10 状态和引用前缀事实（`local-staging/`）已更新。
2. **补红灯**：为已有实现但缺具名覆盖的场景补 XCTest——LF-001、DM-004/005/007/012/013/014 的具名化、F2 生命周期（LF-003 前）。
3. **本地候选闭环补全**：LF-006 候选编辑确认、LF-007 重试/域重判（HANDOFF §15 延期项，Inbox 完整性）。
4. **运动切片真机验收收口**：K 片待真机清单（相机/相册/快捷指令、断网、重启、登录切换）+ LF-004 重启图片展示。
5. **饮食/睡眠/阅读用户闭环**：按运动切片模式逐域推进（HANDOFF §13 既定方向）。
6. **编辑替换图片**：LF-003（DM-GAP-06 残余）。
7. **五域导入恢复**：LF-021（换机自助桥闭环）。
8. **异常恢复加固**：LF-023 低存储、LF-024 迁移失败回滚。
9. **按已拍板范围推进**：收入/钱包（SL-A/SL-B，LF-032/033）、设置本地镜像（LF-019/020）、AI 本地适配最小切片（LF-014/015 + LF-010~013 中的拍板口径）；BYOK（LF-029~031）保持冻结登记。
10. **显式决策后才启动**：L2 迁移（F11）、同步解冻（F12）、账号轮换流程（LF-026）。

明确不进入：Cloud Sync/多设备/CRDT/Outbox 扩展、生产迁移、部署、TestFlight（除非当轮用户明确授权）。

## 9. 验证边界声明

- 本文所有代码结论来自 2026-09-25 静态只读阅读（分支 `codex/local-first-phase1-fact-reader`）；Windows 无 Swift 工具链，编译与 XCTest 以 macOS CI 为准。
- 生产同步 RPC、Edge Function 生产版本以 HANDOFF §12/18 记录为准，本文未在线复核生产库。
- PWA 盘点以 git HEAD 为基线；磁盘上 `index.html` 存在被未提交 WIP 覆盖的异常，如需以磁盘文件为准请先处理该 WIP。
