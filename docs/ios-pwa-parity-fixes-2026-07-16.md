# iOS 与 PWA 功能对齐修复审计（2026-07-16）

## 范围与原则

- 权威业务实现：成熟 PWA，而不是重新设计一套 iOS 流程。
- 第一批范围：中转站全域归档、AI 字段展示、中转站操作体验、数据域和钱包导航、设置页真实功能、视觉识别降级。
- 第二批范围：账号隔离、记录身份与详情竞态、编辑字段完整性、识别租户隔离、中转站原子归档。
- 主题保持“芥青微光”，本批优先保证功能和数据契约，不做额外视觉重构。
- TestFlight 只在本批普通 iOS Build 和单元测试全部通过后手动触发一次。

## PWA 源码对照入口

| 模块 | PWA 权威入口 | iOS 对应入口 |
|---|---|---|
| 中转站列表与操作 | `src/components/pages/PagePending.vue` | `ios/SnapCount/Features/Inbox/InboxView.swift` |
| 中转站归档 | `src/composables/useStore.js` 的 `archiveStagingRecord` | `InboxRepository`、`NativeDataService.archiveStagingRecord` |
| 数据域定义 | `src/domains/registry.js` | `NativeDomainDefinition`、`InboxArchiveDomains` |
| 记录详情字段 | `src/domains/recordDetailAdapters.js` | `NativeRecordPresentation`、`NativeStagingPresentation` |
| 设置主页 | `src/components/pages/PageSettings.vue` | `SettingsView.swift` |
| 截图/拍照模型 | `src/components/pages/PageAiVisionSettings.vue` | `VisionSettingsView`、`NativeUserSettings` |
| 用户配置存储 | `src/composables/useStore.js` 的 `loadUserSettings`、`toggleSetting`、`setRetention` | `SettingsRepository`、`AppState` |
| 识图 Provider | `supabase/functions/ingest-receipt/index.ts` | 同一 Edge Function |
| 登录态清理 | `src/App.vue` 的 `handleSignedOut`、`useStore.resetUserData` | `AppState.resetUserScopedState` |
| 记录详情身份 | `useStore.openRecordDetail(kind, record)` | `NativeRecordReference`、`RecordDetailView` |
| 支出编辑 | `useStore.openExpenseEditModal`、`confirmExpense` | `NativeRecordEditDraft`、`saveRecordDetail` |

## 已确认根因与修复

### 1. 只能归档到消费或收入

PWA 向 `data_records` 写入通用域记录时包含当前用户的 `user_id`。旧 iOS 请求遗漏该字段，在已收紧的 RLS 下，运动、睡眠、阅读、饮食和钱包都会被拒绝。消费和收入走独立 RPC，所以表现为“只有消费能成功”。

本批修复：

- `InboxRepository.archive` 不再接收客户端传入的用户 ID，统一由数据库 `auth.uid()` 确定归属。
- `data_records`、财务记录、staging 更新和路由反馈由同一个事务 RPC 写入。
- 归档域继续使用 PWA 的真实 key：`expense`、`income`、`sport`、`sleep`、`reading`、`food`、`wallet`。
- 消费或收入缺少有效金额时停止归档并提示补全，不再伪造 `0.01`。

### 2. 中转站暴露内部 AI JSON

PWA 中转站不会把 `time_context`、`record_type`、`image_type`、Provider 错误堆栈作为普通业务字段展示。旧 iOS 直接遍历 `extracted_json`，导致真机显示大段内部 JSON。

本批修复：

- 只展示金额、商家、时长、距离、热量、睡眠、阅读、餐次、账户等业务字段。
- 兼容 PWA 当前和历史字段，如 `calories/calories_kcal`、`sleep_minutes/sleep_hours`、`pages/pages_read`。
- `time_context` 等内部字段完全隐藏。
- Provider 错误先显示用户可理解的摘要，完整原始错误仅放在“技术详情”折叠区。

### 3. 中转站操作不方便

本批按 PWA 信息层级适配原生交互：

- 状态筛选显示每类数量。
- 列表显示缩略图、业务摘要、记录时间、置信度进度和友好错误。
- 详情页把归档域改为直接可见的两列按钮，不再隐藏在单个菜单里。
- 重试与销毁并排展示，归档过程保留确认和明确结果反馈。

### 4. 数据域和钱包详情打不开

旧实现依赖嵌套 `NavigationLink(value:)` 和分散的 `navigationDestination` 注册，真机容器层级变化时无法稳定匹配路由。

本批修复：

- 数据域列表直接构造 `DomainDetailView`。
- 数据域最近记录直接构造 `RecordDetailView`。
- 钱包和账户列表直接构造 `AccountDetailView`。
- 移除这些链路上重复、嵌套的值路由注册。

### 5. 设置页与 PWA 差距较大

本批只迁移 PWA 已经真实可用的能力，不添加占位开关：

- 支出、收入、全部财务、通用记录导出，支持 CSV/JSON 和时间范围。
- 截图与拍照 Provider 分开选择。
- Qwen 截图/拍照模型分开配置，支持 `3.6 Flash`、`3.7 Plus` 和自定义模型名。
- 截图/拍照思考模式分开控制。
- AI 陪伴、长期记忆、语气、记忆强度、表达方式、80 字专属指令。
- AI 联动分析 Provider。
- AI 日志、Prompt 优化参与、原图不保留/7 天/30 天/永久保留。
- 从永久保留切换为有限期限时，可选择按新期限处理或立即清理已有原图。
- 快捷指令凭据状态、教程、通知和结果卡片设置继续保留为 iOS 原生能力。

未迁移为真实功能：PWA 的数据导入和 Pro 页面目前也是占位提示，iOS 不伪造实现。

### 6. 视觉识别 Provider 全部失败

真机错误显示三个确定问题：Moonshot 请求超过 8192 token、MiMo 使用未验证模型名、多个超时 fallback 拉长链路。

本批修复：

- Moonshot fallback 使用精简 JSON 提示词，避免重复发送完整长 Prompt。
- MiMo 只有同时配置 `MIMO_API_KEY` 和明确的 `MIMO_MODEL` 时才加入 Provider 队列。
- 移除已确认无效的默认 `mimo-v2-omni`，避免无效请求继续拖慢链路。
- Qwen 主链路和截图/拍照分流规则保持不变。

### 7. 跨账号状态和图片缓存残留

PWA 在 `SIGNED_OUT` 时会调用 `resetUserData`，一次性清空列表、详情和页面历史。iOS 旧实现只清理部分首页与账户状态。

第二批修复：

- 会话失效同时删除 `auth_session` 和 `upload_token`。
- 清空首页、导航栈、当前详情、详情缓存、账户、钱包、洞察和设置状态。
- 账号切换时取消旧用户的数据补充任务。
- 清空内存、URLCache 和磁盘图片缓存，避免旧账号图片在新账号复用。
- 图片 URL 改变时先清旧图，新图失败不再显示上一条记录截图。

### 8. 详情身份分裂与并发覆盖

第二批统一使用 `expense/{id}`、`income/{id}`、`data/{id}` 作为内部身份，同时兼容历史 `tx-`、`income-`、`data-` 链接。

- 预取只写缓存，不再覆盖当前详情。
- 网络返回前后校验账号代际和当前 route。
- 详情页只展示与 route 身份一致的记录。
- 编辑、删除和 pending 确认统一失效同一个规范缓存键。

### 9. 编辑静默破坏原字段

第二批将 PWA 编辑时保留原字段的规则迁移到 iOS：

- 保留交易时间、来源、图片路径、图片哈希和陪伴文案。
- 收入编辑不再强制把来源改为 `ai_scan`。
- 大额出行根据当前分类和金额重新计算，并保留具体交通类型。

### 10. 租户隔离与原子归档

- staging 重试读取、计数和更新都增加当前 `user_id` 条件。
- 支出、收入和通用记录的精确图片哈希查重按用户隔离。
- 新上传图片使用 `user_id/日期/hash` 存储路径。
- 图片哈希唯一约束从全局唯一调整为用户内唯一。
- 缺金额的收入和支出直接进入中转站，重试也不再生成 `0.01`。
- `archive_staging_record` 在数据库事务内锁定 staging、创建或复用目标记录、更新状态并写入反馈，重复调用返回原目标。

## 自动验证

| 项目 | 状态 |
|---|---|
| `git diff --check` | 通过 |
| PWA `npm run build` | 通过；仅有既有大 chunk 和 vConsole eval 警告 |
| iOS 单元测试 | 通过，GitHub run `29514527654` |
| iOS Simulator Build | 通过，GitHub run `29514527654` |
| Edge Function 部署 | 通过，GitHub run `29514206365` |
| TestFlight | 上传成功，build `29515035237`，GitHub run `29515035237` |

第二批新增验证尚待当前分支 CI：

- iOS 测试新增账号状态清理、记录 reference 兼容、详情身份校验、编辑字段保留和原子归档请求契约。
- 数据库迁移：`068_atomic_staging_archive_and_tenant_hashes.sql`。
- 本机没有 Deno 和 macOS/Xcode，Edge 类型检查与 iOS 编译由 GitHub CI 完成。

## 真机验收清单

1. 中转站分别归档到运动、睡眠、阅读、饮食和钱包，不再出现 `data_records` RLS 错误。
2. 缺金额的消费/收入不能直接归档，不产生 `0.01` 假记录。
3. 中转站详情不再出现 `time_context`、`record_type`、`image_type` 原始 JSON。
4. AI 失败只显示简洁原因；展开技术详情仍可查看完整错误。
5. 中转站列表缩略图、置信度、状态数量和筛选正确。
6. 数据域列表的每个域都能进入详情，最近记录能继续进入记录详情。
7. 钱包域的资产、负债账户都能进入账户详情。
8. 设置中的 Provider、Qwen 型号、思考模式保存后退出重进仍保持。
9. AI 陪伴、联动分析、隐私和留存设置与 PWA 使用同一 `user_configs` 数据。
10. 数据导出能生成并分享 CSV/JSON 文件。
11. 拍照或截图识别失败时不再尝试无配置的 MiMo；Moonshot 不再因旧长 Prompt 超出 token 上限。

## 发布门槛

- 普通 iOS Build 和单元测试全部成功。
- Edge Function 部署成功。
- `068_atomic_staging_archive_and_tenant_hashes.sql` 已应用到目标 Supabase 项目；迁移未应用前禁止发布使用新原子 RPC 的 iOS 版本。
- Git 工作区干净，提交范围不含截图、日志、测试结果或用户主工作区改动。
- 满足以上条件后手动触发一次 TestFlight；失败先修复，不连续重复上传。
