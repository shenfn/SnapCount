# Jiezi Local-First Phase 1：本地数据模型 Grooming 结果

> 状态：Grooming v0.2，DM-GAP-02/03/10 已按 2026-09-25 产品拍板与代码事实收口；进入实现前评审
>
> 日期：2026-09-25
>
> 依据：`LOCAL-FIRST-PHASE1-DATA-MODEL-GROOMING.md`、当前仓库代码与现有 Supabase/PWA 业务语义

本文是下一阶段交接文档的执行结果。它固定本地正式事实的边界、生命周期和验证场景，不复制 Supabase 表结构，也不改变 Cloud Sync、Outbox、Cursor、冲突机制或 AI Popup / Expression Planner 主线。

本轮只做只读审计和设计收敛，没有修改业务实现代码，也没有把本地实现缺口解释成产品范围缩减。

## 1. 范围与事实来源

Phase 1 本地正式事实覆盖五个域：

- 消费（expense）
- 饮食（food）
- 睡眠（sleep）
- 运动（sport）
- 阅读（reading）

`Profile` 和 `Account` 是本地身份与消费账务的支撑实体，不是第六、第七个内容域。收入（income）和钱包快照（wallet）按 Q-01 纳入 Phase 1 本地化范围，分别进入 SL-A/SL-B；本轮既有五域模型仍不提前扩展其 schema。

本轮采用以下事实来源：

- Supabase 业务语义：`supabase/migrations/001_init_schema.sql`、`003_domains_and_staging.sql`、`005_ai_recognition_logs.sql`、`007_universal_records.sql`、`012_food_domain.sql`、`014_domain_schema_completion.sql`、`015_sleep_unit_to_minutes.sql`、`016_daily_domain_summary.sql`。
- PWA 领域和读取行为：`src/domains/registry.js`、`src/repositories/recordRepository.js`、`src/repositories/stagingRepository.js`。
- iOS 本地事实：`ios/SnapCount/LocalData/LocalDatabase.swift`、`LocalExpenseRepository.swift`、`LocalRecordRepository.swift`、对应 Use Case、读取模型和导出模型。
- AI 事实边界：`supabase/functions/ingest-receipt/prompts.ts`、`supabase/functions/_shared/expression-core/`、`docs/spec/20-陪伴表达事实契约.md`。

Supabase 的表名、RLS、远端 URL 和同步字段只是参考。iOS 本地模型可以采用不同的存储形状，但必须保持可解释、可验证的业务语义。

## 2. 正式事实模型

### 2.1 物理存储与正式事实归属

| 业务对象 | Phase 1 正式事实归属 | 说明 |
|---|---|---|
| Profile | `local_profiles` | 本地身份根；可关联云账号，但不因登录才存在 |
| Account | `local_accounts` | 消费账务的账户和开户余额；余额由有效流水派生 |
| Account Entry | `local_account_entries` | 消费对账户的账务投影；不是独立内容记录 |
| Expense | `local_expenses` | 五域中的消费唯一正式事实来源 |
| Food / Sleep / Sport / Reading | `local_records` | 通用本地记录表，`domain_key` 区分四个非财务域 |
| AI Candidate / Staging | `local_staging_records` | 候选和待确认内容，不属于正式事实 |
| Outbox / Sync State | 现有表和代码 | 保留并冻结，不因本轮扩展五域而增加协议 |

正式事实的读取边界是一个逻辑投影，不要求新增一张物理表：

```text
LocalFactReader
  ├─ local_expenses + local_account_entries -> expense facts
  └─ local_records                       -> food/sleep/sport/reading facts
```

`Today`、`Records`、本地导出和本地 AI Analysis 都应从这个逻辑正式事实层读取。中转站、墓碑、失败候选和仅用于展示的派生数据不得被正式事实读取器返回。

### 2.2 消费与通用记录不得重叠

固定规则：

1. 任何具有消费金额、币种、商户、支付方式等消费语义的记录，唯一正式归属是 `local_expenses`。
2. `local_records` 不写入新的 `expense` 正式记录；`expense` 候选确认时必须进入消费 Use Case，并按账务规则决定是否创建账户流水。
3. `local_records.domain_key` 当前数据库约束仍包含 `expense`，但当前 `LocalRecordValidation` 已不允许它。后续实现应把这个不一致收敛为“禁止新写入”，并提供兼容迁移策略，不静默把旧记录复制成两份。
4. 账户是消费的关系和账务投影，不是消费记录的替代事实。消费可以在数据模型上独立存在；账户关联和流水投影需要有明确的绑定语义。

当前 iOS 消费实现要求创建时提供账户，且 `local_expenses.account_id` 为非空。2026-09-25 产品拍板维持这一行为：消费必须先选账户，DM-GAP-10 不采纳；后续若出现解耦账户的真实需求，需重新 Grooming，不在当前 Slice 改 schema 或流水语义。

### 2.3 共享字段与事实层级

五域正式事实都需要具备以下语义：

| 类别 | 规范 |
|---|---|
| 稳定身份 | UUID、`profile_id`、`domain_key`；同一正式事实不因页面刷新生成新 ID |
| 业务日期 | 必须保留用户看到的本地日期；不能用上传日期替代发生日期 |
| 精确时间 | 可选；只有来源明确提供完整日期和时分时才保存，不用 `12:00` 等默认值补齐 |
| 版本 | 编辑递增 `local_version`；更新携带期望版本，冲突显式失败 |
| 删除 | 正式记录使用 `deleted_at` tombstone；读取层排除墓碑，但墓碑在生命周期期间保留 |
| 来源 | 记录创建来源必须区分手动、AI 高置信度自动归档、用户确认候选和导入 |
| 原图关系 | 记录最多持有一个本地原图引用；引用是相对路径和 hash，不是远端 URL |
| 展示 | `title`、`summary`、列表分组和指标卡是展示投影，不得替代域事实字段 |

`source_kind`、`domain_version` 已由 local-v6 迁移和通用本地模型落地；高置信度自动归档、低置信度候选、用户确认分别保留 `ai_auto_archive`、`ai_candidate`、`ai_confirmed`。候选到正式记录的关系和现有引用前缀仍由 SL-02/后续候选 Slice 继续用特征测试固化。

### 2.4 五域最小事实契约

域 payload 使用 JSON 承载域字段，但保存前必须由域适配器规范化别名、单位和空值。

| 域 | 必要事实 | 可选事实与约束 |
|---|---|---|
| expense | `amount_minor > 0`、`currency`、`transaction_date`、分类、支付方式 | 商户、平台、时间、备注、`account_id`；金额只能以最小货币单位整数进入本地账务 |
| food | `meal_type`、`total_calorie_kcal` 或可确认的餐食内容 | `dishes[]`、克重、热量、蛋白质、碳水、脂肪、`confidence_note`、`source_app`；热量必须标记为估算性质 |
| sleep | `sleep_minutes`、业务日期 | `quality_score`、`quality_level`、入睡/醒来时间、深睡/浅睡/REM/清醒分钟、`source_app` |
| sport | `sport_type`、`duration_minutes` | `calories`、距离、配速、心率、步数、训练效果、恢复时间、`source_app` |
| reading | `book_name`、`reading_minutes` | `progress_percent`、作者、书籍类型、每日目标、`source_app` |

规范化规则：

- 睡眠正式事实以 `sleep_minutes` 为唯一本地单位。`sleep_hours` 只作为 AI 输入兼容字段或展示派生值，不和分钟形成双重事实。
- 运动正式字段为 `duration_minutes`；`duration`、`duration_min` 等只在输入适配器层兼容。
- 阅读正式字段为 `reading_minutes`；阅读首页没有完整业务日期时，业务日期必须进入待补全/用户确认路径，不能用上传时刻冒充。
- 饮食 `total_calorie_kcal` 是估算事实，不等价于精确医疗或营养结论；`is_estimated` 或等价语义应保留在域 payload 中。
- 缺少域最小事实时，AI 结果不能自动成为正式记录；应进入中转站或失败出口。

## 3. 生命周期与状态机

候选和正式记录是两种不同的对象，不能用一个 `status` 字段混淆：

```text
AI 输入
  -> candidate
       ├─ 高置信度 + 域事实完整 -> formal active
       └─ 低置信度/事实不完整   -> staging pending_review
                                      ├─ 用户确认/编辑 -> formal active
                                      ├─ 重试 -> 新候选或更新候选
                                      └─ 丢弃 -> staging discarded
formal active
  -> 编辑（版本递增）
  -> 删除（tombstone）
```

### 3.1 路由规则

- 高置信度 AI 结果自动归档为正式记录，但必须在归档前通过域字段校验。
- 低置信度、跨域不确定、关键字段缺失或解析失败的结果进入本地中转站。
- 置信度阈值属于域配置，不应由所有域共享一个无法解释的硬编码值。当前本地路由已采用“域阈值优先、无配置时 0.80 兜底”：food 0.80，sport/sleep/reading 0.75；DM-GAP-03 的实现口径已收敛，具名特征测试排入 SL-02。
- 中转站记录未确认前不进入 Today、Records 正式列表、Account 余额或 AI 正式事实上下文。

### 3.2 确认、编辑、删除

- 用户确认中转站后，创建一个稳定 UUID 的正式记录，并保留 `staging -> target_record` 关系；确认动作需要幂等，重复确认不能创建第二条正式事实。
- 用户在确认时编辑域字段，保存后的正式记录以用户确认值为准；AI 原始候选仅作为证据，不覆盖用户修正。
- 正式记录编辑要求携带 `expectedVersion`，版本不匹配时显式失败，不静默覆盖。
- 正式删除产生 tombstone，清理或保留原图遵循本地图片生命周期；删除后相关 Today/Records/Analysis 派生缓存必须失效。
- 中转站丢弃是候选生命周期终点，不产生正式 tombstone；其本地图片和候选内容可按删除规则清理。
- 失败候选可以重试；已丢弃候选不可被后台自动重新归档，除非用户明确重新发起识别。

## 4. 图片与附件

### 4.1 所有权

Phase 1 不把远端 Storage URL 当作本地记录的事实字段。图片关系至少包含：

- 本地相对路径；
- 内容 hash；
- 所属候选或正式记录；
- 图片是否随导出包含。

同一张图片在本阶段不做多条正式记录共享引用；hash 用于识别和幂等，不用“全局唯一 hash”隐式合并两条业务事实。

### 4.2 生命周期

| 动作 | 图片行为 |
|---|---|
| 高置信度自动归档 | 直接保存到正式记录所属本地目录 |
| 低置信度进入中转站 | 保存到中转目录，候选未确认前不进入正式读取 |
| 中转站确认 | 转移或转交同一图片引用，不重复生成第二份业务图片 |
| 中转站丢弃 | 清理候选图片 |
| 正式记录编辑 | 替换图片时先写入新图片，再更新引用，失败不得丢旧引用 |
| 正式记录删除 | 删除或进入受控回收流程；记录 tombstone 不得失去删除语义 |
| 导出 | 默认导出元数据；用户勾选时把图片以可移植内容（如 base64/归档附件）写入，不导出临时签名 URL |

当前 `LocalImageStore` 已能保存、hash、读取和删除本地图片，但缺少真实图片输入接线、正式记录编辑替换和统一引用关系测试；这些是实现缺口，不改变产品范围。

## 5. AI 边界

### 5.1 AI 不是正式事实来源

- AI 负责从图片、文本或快捷输入生成候选；候选包含置信度、结构化字段和证据。
- 只有高置信度且通过域校验的结果自动归档，或用户明确确认后的结果，才进入本地正式事实层。
- AI 原始响应、提示词版本、模型名称、token/cost、重试诊断属于 AI 运行记录，不是五域事实；Phase 1 不把它们塞进正式 payload 作为业务字段。
- AI 关闭、网络不可用、BYOK 失效时，手动创建、查看、编辑、删除和导出正式事实仍必须可用。

### 5.2 BYOK、Hosted AI、AI Popup 与 Analysis

- BYOK 与 Hosted AI 只改变 AI Provider、权限和调用路径，不改变正式事实的 profile、记录 ID、域字段或生命周期。
- AI Popup 继续回答“刚记录这件事，此刻最值得说什么”；跨域 AI Analysis 继续回答“一段时间的多域数据有什么变化或关系”。两者不合并。
- AI Popup 的候选、Expression Plan、曝光确认和用户反馈是派生/遥测数据，不得被当作五域正式事实；它们也不能阻塞本地记录保存。
- Phase 1 保留这些能力的产品范围和既有实现，不在本轮重设计算法或表达协议。后续本地适配应让它们从 `LocalFactReader` 获取正式事实，并将结果作为可失效的派生数据处理。
- 本地模式下 AI 结果和用户反馈是否持久化到本地，需要单独定义 AI 运行记录存储；在该存储定义完成前，不把云端 `ai_feedback`、Expression Plan 或曝光数据复制到五域事实表。
- API Key 只能由 Keychain/等价安全存储管理，禁止进入业务数据库、导出文件、日志和 AI 事实 payload。

## 6. 统一读取边界

### 6.1 统一事实读取器

后续应提供一个只读的本地事实适配层，输出统一记录引用和事实包：

```text
LocalFact
  id / reference / domainKey / profileID
  businessDate / occurredAt?
  title / summary / payload
  sourceKind / localVersion / imageReference?
```

引用规范建议为：

- 消费：`expense/<uuid>`
- 非财务四域：`data/<uuid>`
- 中转站：`local-staging/<id>`

现有 `local-data/<uuid>` 可以作为兼容输入，但不应继续产生第三种正式引用语义。

### 6.2 消费者

- `Today` 和 `Records`：只显示本地正式事实，按业务日期分组；不得把 staging 或 deleted 记录混入。
- `Account`：只对消费和账户流水提供账务视图；余额由 opening balance + 有效流水派生，不能读取一个可覆盖的 current balance。
- 导出：同一份本地正式事实集合覆盖消费、饮食、睡眠、运动、阅读，并根据选项附带图片；不能只导出通用四域而遗漏消费。
- AI Popup / Analysis：读取同一份正式事实投影，允许派生缓存，但不能另建一套业务事实来源。
- 已登录不等于自动混合云端和本地。当前 `AppState` 在某些路径会同时读取本地和远端并合并，这是迁移/同步策略尚未收敛的实现差距；在 Phase 1 没有 Cloud Sync 的前提下，读取模式必须由明确的本地/远端工作区状态决定，不能依赖“本地有记录就和云端拼接”。

## 7. 当前差距与优先级

| 编号 | 差距 | 影响 | 后续处理 |
|---|---|---|---|
| DM-GAP-01 | `local_records` 约束包含 expense，但校验层排除 expense | 存储边界可被绕过 | 先补行为测试，再做约束/迁移收敛 |
| DM-GAP-02 | 通用本地记录的 `source_kind`、`domain_version` 已由 local-v6 与模型字段收敛；候选关系和引用路由仍需特征测试 | AI 来源已可审计，确认关系需继续固定 | 实现已收敛；SL-02 补具名测试，不改同步协议 |
| DM-GAP-03 | 本地路由已按域阈值执行：food 0.80、sport/sleep/reading 0.75、无配置 0.80 兜底 | 高/低置信路由实现口径已收敛 | 实现已收敛；SL-02 补跨端/路由特征测试 |
| DM-GAP-04 | 睡眠 AI 输入仍兼容 `sleep_hours`，本地必须以分钟为准 | 可能形成双事实 | 适配层归一化，正式库只保留分钟语义 |
| DM-GAP-05 | 本地通用导出当前排除 local expense，且本地导出入口按模式分支 | 用户无法获得完整五域归档 | 建立统一 LocalFact 导出，不重做远端导出协议 |
| DM-GAP-06 | 通用记录真实图片输入、编辑替换和 staging UI 未接通 | 图片生命周期尚未形成用户闭环 | 在运动切片完成阶段接入 |
| DM-GAP-07 | `AppState` 存在本地/远端混读 | 可能重复显示或违反本地权威 | 先固定读取模式测试，再最小接线 |
| DM-GAP-08 | Local AI Popup / Analysis 读取适配尚未形成 | AI 能力与本地事实仍断开 | 保留现有 AI 主线，新增只读 LocalFact adapter |
| DM-GAP-09 | 通用记录缺少与消费同等的本地导入/恢复方案 | 本地迁移和换机边界不完整 | Phase 1 先完成可验证导出；导入恢复单独切片 |
| DM-GAP-10 | 当前消费本地实现要求账户非空；2026-09-25 产品拍板维持该规则 | 消费保存继续要求先选账户 | 不采纳；如真实需求改变，另行 Grooming，不进入当前 Slice |

## 8. 验收场景与测试层映射

这些编号是后续实现必须复用的行为编号。本轮只固定场景，不新增测试代码。

| 场景编号 | 不变量 | 主要验证层 |
|---|---|---|
| LOCAL-P1-DM-001 | 五域物理归属固定；消费只进 expense，四个非财务域只进 data | iOS Repository XCTest、模型边界测试 |
| LOCAL-P1-DM-002 | 同一消费不会同时出现在 local_expenses 和 local_records | iOS Use Case XCTest、读取投影测试 |
| LOCAL-P1-DM-003 | 域 payload 经过别名和单位规范化；睡眠正式事实只有 sleep_minutes | Codec/adapter 测试、PWA 语义 fixture |
| LOCAL-P1-DM-004 | 高置信度且字段完整的候选自动归档，正式读取可见 | Intake Use Case XCTest、跨端路由 fixture |
| LOCAL-P1-DM-005 | 低置信度或字段不完整只进入 staging，未确认前正式读取不可见 | Staging Use Case XCTest |
| LOCAL-P1-DM-006 | 确认中转站幂等，只产生一条正式记录并保留 staging 关系 | Repository 事务/重复确认测试 |
| LOCAL-P1-DM-007 | 丢弃候选或删除正式记录后，图片按生命周期清理；正式删除保留 tombstone 语义 | ImageStore + Repository XCTest |
| LOCAL-P1-DM-008 | 编辑必须使用 expected version；旧版本更新失败且不覆盖新事实 | Repository XCTest |
| LOCAL-P1-DM-009 | 缺少完整发生时间时不伪造时间；业务日期不被上传日期替代 | 时间规范化测试 |
| LOCAL-P1-DM-010 | JSON/CSV 导出覆盖五域；图片选项只影响附件内容，不泄露 token、URL 或 Key | Portability XCTest |
| LOCAL-P1-DM-011 | Today、Records、Account、导出和 AI 输入来自同一正式事实投影；staging/deleted 不进入 | LocalFactReader 集成测试、页面边界测试 |
| LOCAL-P1-DM-012 | BYOK/Hosted AI 切换不改变记录事实；AI 关闭不影响手动 CRUD | AI boundary tests、iOS Use Case XCTest |
| LOCAL-P1-DM-013 | 数据库关闭重开后正式记录、staging、图片引用和版本保持一致 | GRDB migration/reopen XCTest |
| LOCAL-P1-DM-014 | 未启用 Cloud Sync 时不因登录状态把本地和云端静默混读或重复展示 | AppState boundary test、手动验收 |

PWA 与 iOS 对同一场景编号验证共享业务含义。Windows 不作为 Swift 编译通过的证明；iOS 编译和 XCTest 结果以 macOS GitHub Actions 为准。

## 9. Grooming 后的最小实现顺序

1. 先为 DM-001 至 DM-005、DM-008、DM-009 补行为红灯，固定存储归属、阈值、单位和时间边界。
2. 收敛通用本地记录模型：来源、版本、候选关系、域版本和 `expense` 禁写边界；不扩展同步协议。
3. 完成运动首片：真实图片输入、本地中转 UI、确认/丢弃、正式详情、编辑、删除和重启验证。
4. 按同一域契约扩展饮食、睡眠、阅读；每个域复用统一 LocalFact/画像/图片/导出边界。
5. 建立统一 LocalFactReader 和五域导出，解决当前消费导出遗漏和本地/远端混读问题。
6. 最后接入 AI Popup / Analysis 的本地只读适配；AI 结果、曝光和反馈不反向成为五域正式事实。

以下内容明确不进入本顺序：Cloud Sync、多设备合并、Cursor/Conflict/CRDT/Outbox 协议扩展、生产迁移、部署和 TestFlight。

## 10. 本轮验证记录

- 已执行仓库级只读代码审计，覆盖 Supabase 领域迁移、PWA registry/repository、iOS LocalData、AppState、图片、导出和 AI 资产。
- 已确认当前工作区存在大量用户 WIP；本轮未清理、未重置、未切换 worktree。
- 本轮没有修改业务代码，也没有运行 Swift/XCTest；Windows 无 Xcode/Swift 工具链，后续需 macOS CI 验证。
- 这份文档本身是设计材料，不代表五域 Local-First 已完成。
