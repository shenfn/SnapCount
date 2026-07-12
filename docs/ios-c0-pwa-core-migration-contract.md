# iOS C0：PWA 核心功能迁移契约与执行清单

> 最后更新：2026-07-12  
> 执行分支：`codex/ios-swiftui-native-app`  
> 业务基线：`src/` 成熟 PWA、现有 Supabase 表/RPC/Edge Function  
> 核心原则：iOS 是迁移，不是重新设计；PWA 的字段、状态、导航结果和数据域 key 均为权威契约。

## 1. C0 结论

A2 完成的是认证、Storage、Remote Client 与 Repository 数据访问边界，不代表 PWA 核心功能已经迁移完成。当前 iOS 的首页、记录、数据域和中转站均属于基础骨架，不能按“样式待优化”处理，必须补齐业务模型、导航目标、状态机和字段映射。

完整 B1 启动快照暂缓到 C1-C4 的主要读取契约稳定后进行，避免缓存当前不完整的数据结构。C 阶段可以保留已有图片缓存和详情缓存，但不提前固化完整 Snapshot Schema。

## 2. 权威代码入口

| 业务模块 | PWA 权威入口 | 相关数据/聚合 | iOS 当前入口 |
|---|---|---|---|
| 首页与今日记录 | `src/components/pages/PageHome.vue` | `buildTodaySummary`、`buildDailyCards`、`openDayDetail` | `ios/SnapCount/Features/Today/TodayView.swift` |
| 每日明细 | `src/components/pages/PageDayDetail.vue` | `activeDayRecords`、`activeDayKind` | 当前无独立日详情模型/页面 |
| 记录与账单 | `src/components/pages/PageBills.vue`、`PageRecordDetail.vue` | `bills`、`incomeRecords`、`dataRecords` | `ios/SnapCount/Features/Records/RecordsView.swift` |
| 数据域 | `src/components/pages/PageDomains.vue`、`PageDomainDetail.vue` | `src/adapters/domain/*`、`data_domains`、`data_records` | `ios/SnapCount/Features/Domains/DomainsView.swift` |
| 中转站 | `src/components/pages/PagePending.vue`、`ModalPending.vue` | `pendingBills`、`stagingRecords`、归档/重试/销毁 | `ios/SnapCount/Features/Inbox/InboxView.swift` |
| 全局状态和导航 | `src/composables/useStore.js` | Supabase 查询、状态聚合、页面导航 | `ios/SnapCount/App/AppState.swift` |

## 3. 首页与每日明细契约

### 3.1 PWA 真实行为

“今日记录”按领域展示，不是不可点击的摘要卡片：

- 支出：金额、笔数、平台分布；点击 `openDayDetail(todayKey, 'expense')`。
- 待补全：已识别金额和笔数；点击进入中转站。
- 收入：金额和笔数；点击 `openDayDetail(todayKey, 'income')`。
- 运动：逐条展示运动标题与摘要；点击 `openDayDetail(todayKey, 'sport')`。
- 睡眠：逐条展示睡眠标题与摘要；点击 `openDayDetail(todayKey, 'sleep')`。
- 饮食：餐次数与估算热量；点击 `openDayDetail(todayKey, 'food')`。
- 其他动态域记录：按 `data_domains` 元数据展示，点击对应日详情。

`PageDayDetail.vue` 负责：

- 日期、星期、月份和当前领域标题；
- 当日聚合摘要；
- 按领域过滤后的当日记录列表；
- 支出/收入/通用数据进入各自详情；
- staging 进入中转站；
- 空状态和“回到今天”。

### 3.2 iOS 当前差异

- `TodayView` 的每日卡片主要是静态摘要，缺少统一可导航日详情。
- 当前 `NativeDailySummary` 只突出金额/数量，未承载 PWA 的领域行和日记录列表。
- 没有独立 `DayDetailView`、`DayRecordItem` 和 `DayDetailRepository` 契约。
- 今日运动、睡眠、饮食和动态域无法按 PWA 方式进入当天明细。

### 3.3 C1 验收标准

- 首页今日区域中的每一类可见记录均可点击。
- 点击后进入指定日期、指定领域的日详情，不跳到笼统记录页。
- 日详情中的每条消费、收入、通用记录可以继续进入正确详情。
- 待处理条目进入中转站；空数据、部分失败和加载状态可解释。
- 日期聚合和领域 key 与 PWA 完全一致。

## 4. 记录页面契约

### 4.1 PWA 真实行为

PWA 没有单一的“最近记录占位列表”。记录体系由账单页、收入、通用记录和详情页共同组成：

- 支出记录包含完成与待补全状态、分类、平台、支付方式、账户、日期、图片和备注。
- 收入记录包含收入类型、来源、账户、日期、图片和备注。
- 通用数据记录根据所属数据域及 `payload_jsonb` 展示。
- 记录按月份/日期读取，并支持进入对应详情。
- 详情页承担查看、编辑、删除和图片查看；不能把所有类型压成同一套固定字段。

### 4.2 iOS 当前差异

- `RecordsView` 使用统一最近记录列表，缺少 PWA 的月份/日期组织和完整筛选。
- 通用记录仅把 payload 平铺为通用行，没有数据域字段适配。
- 消费、收入详情字段仍不完整，账户关联和 PWA 状态展示未完全迁移。
- 部分详情依赖点击后再请求，虽然已有缓存，但列表预热范围不足。

### 4.3 C2 验收标准

- 消费、收入、通用记录使用同一入口但保持各自业务字段。
- 支持月份、日期和领域筛选；列表顺序与 PWA 一致。
- 列表点击立即进入缓存详情，缺失时显示局部加载而不是整页空白。
- 编辑、删除、图片查看继续复用现有后端契约。
- 不引入 PWA 不存在的字段、状态或固定业务数据。

## 5. 动态数据域契约

### 5.1 PWA 真实行为

数据域由 `data_domains` 元数据和域适配器驱动：

- `PageDomains.vue` 展示系统域和动态域的记录数量与元数据。
- `PageDomainDetail.vue` 使用适配器生成 Hero、指标、趋势、分布和最近记录。
- `expenseAdapter`、`incomeAdapter` 处理财务域。
- `universalAdapter` 根据 `schema_jsonb`、`summary_config`、`payload_jsonb` 处理运动、睡眠、阅读、饮食等通用域。
- 点击最近记录进入 expense、income 或 universal 详情。

权威域 key：

`expense`、`income`、`sport`、`sleep`、`reading`、`food`、`wallet`。

### 5.2 iOS 当前差异

- 当前数据域页是原生固定展示，不是 `data_domains` 驱动。
- 没有对应 PWA adapter 的 Swift 层，运动等被当成相同的通用记录。
- 缺少 Hero、指标、趋势、分布、最近记录的统一领域展示模型。
- 缺少 schema/summary 配置解释层，后续新增域时仍需改 SwiftUI 页面。

### 5.3 C3 技术契约

新增领域展示层，但不复制 Vue 组件结构：

- `DomainDefinition`：映射 `data_domains`。
- `DomainRecord`：映射 `data_records` 与 payload。
- `DomainPresentationAdapter`：生成 hero、metrics、trend、distribution、recentRecords。
- 财务域专用适配器；通用域使用 schema/summary 配置适配器。
- SwiftUI 页面只消费统一展示模型，新增数据域不需要修改页面主体。

### 5.4 C3 验收标准

- 域列表来自真实 `data_domains`，顺序、名称、图标/色彩语义遵循 PWA。
- 运动、睡眠、阅读、饮食显示各自字段和指标，不再完全相同。
- 领域详情最近记录可进入正确通用详情。
- 未知新域能使用通用适配器展示，不崩溃、不丢原始 payload。

## 6. 中转站契约

### 6.1 PWA 真实行为

中转站同时包含两类待处理实体：

1. `transactions.status = pending` 的待补全账单；
2. `staging_records` 的 AI 路由/抽取记录。

PWA 提供：

- 全部、待补全、AI 失败、待分类、待确认等筛选；
- 今天/昨天/日期分组；
- 状态、截图类型、时间、置信度和错误信息；
- 查看原图和提取字段；
- 补全待处理账单；
- staging 重试识别；
- 归档到真实 `store.domains`；
- 销毁记录；
- 单条与批量操作相关状态；
- 成功/失败反馈。

核心 staging 状态至少包括：

- `ai_error`、`failed`；
- `routing_failed`、`unrouted`、`unassigned`；
- `pending_review`；
- `routed`、`extracted`；
- `confirmed`、`discarded` 等已解决状态不应继续留在待处理列表。

### 6.2 iOS 当前差异

- 只展示 `staging_records`，没有合并 PWA 的待补全 transactions。
- 筛选和日期分组不完整。
- 归档域目前是冻结常量，不是读取真实 `data_domains`。
- 缺少待补全账单编辑入口、批量行为和完整成功反馈。
- 已修复图片按需重签，但仍需统一原图、错误和恢复交互。

### 6.3 C4 验收标准

- 待补全账单与 staging 同时出现，类型明确区分。
- 筛选、日期分组、状态文案和恢复出口与 PWA 一致。
- 归档域来自真实域定义，并严格保留权威 key。
- 重试、归档、补全、销毁后列表和目标记录即时更新。
- 单项失败不清空其他待处理数据。

## 7. 状态流转与边界

### 7.1 非法状态防护

- 已 `confirmed`、`archived`、`discarded` 的 staging 不允许重复归档。
- 归档写入目标表成功、staging 完结失败时，需要显示可恢复错误，不能再次无提示创建重复记录。
- 目标域不存在时必须停留中转站并展示错误，不得改写为其他 key。
- 详情记录已删除时清理导航和缓存，避免永久加载。

### 7.2 数据和性能边界

- 空月份、仅一种领域、超长标题、大量 payload 字段必须正常展示。
- 网络超时、单表失败、签名 URL 失败分别处理，不清空其他成功数据。
- 列表只加载展示需要的字段；详情和图片预热使用有限并发。
- C 阶段不实现离线财务写入；Supabase 仍是结构化数据权威源。

## 8. 多 Commit 执行计划

### C0 文档

1. `docs: 增加 PWA 核心迁移代码契约`
   - 新增本文档。
2. `docs: 重排 iOS 核心迁移路线`
   - 更新进度清单，明确 A2/C/B1 边界。

### C1 首页与日详情

1. `refactor: 建立每日记录展示模型`
   - 日聚合、领域过滤、记录引用模型和 Repository 接口。
2. `feat: 增加原生每日明细页面`
   - 日期摘要、领域筛选、当日列表、空/错/加载状态。
3. `feat: 打通首页今日记录跳转`
   - 消费、收入、运动、睡眠、饮食、动态域、待处理入口。
4. `perf: 预热首页日详情与记录图片`
   - 有限并发预取，复用现有缓存。
5. `test: 固化每日记录领域与导航契约`

### C2 记录页

1. `refactor: 建立多类型记录查询模型`
2. `feat: 迁移记录月份分组与筛选`
3. `feat: 补齐消费收入详情字段`
4. `feat: 增加通用记录详情适配`
5. `perf: 优化记录列表详情预加载`
6. `test: 增加记录筛选与详情契约测试`

### C3 数据域

1. `refactor: 接入动态数据域定义仓库`
2. `feat: 建立数据域展示适配器`
3. `feat: 迁移数据域列表页面`
4. `feat: 迁移数据域详情指标与趋势`
5. `feat: 打通数据域最近记录详情`
6. `test: 固化系统域 key 与通用域降级行为`

### C4 中转站

1. `refactor: 建立统一待处理实体模型`
2. `feat: 合并待补全账单与 AI 中转记录`
3. `feat: 迁移中转站筛选与日期分组`
4. `feat: 补齐待补全编辑和状态恢复`
5. `feat: 接入真实动态归档域与批量反馈`
6. `test: 固化中转站状态机与归档契约`

### B1 快速启动

C1-C4 的主要只读 DTO 稳定后开始：

1. `refactor: 定义用户隔离只读快照格式`
2. `feat: 启动优先恢复本地快照`
3. `feat: 后台静默全量校准并原子替换`
4. `feat: 增加离线与部分失败展示`
5. `test: 增加账号隔离和快照迁移测试`

## 9. 阶段门禁

每个 C 子阶段必须同时满足：

1. 对照上述 PWA 权威入口逐项验收；
2. 使用真实 Supabase 数据；
3. 不改变后端 key、状态机和 RPC 参数；
4. GitHub iOS Build 成功；
5. TestFlight 上传成功；
6. 用户真机确认关键导航、字段、图片和失败恢复。
