# iOS 与 PWA 功能对齐修复审计（2026-07-16）

## 范围与原则

- 权威业务实现：成熟 PWA，而不是重新设计一套 iOS 流程。
- 本批范围：中转站全域归档、AI 字段展示、中转站操作体验、数据域和钱包导航、设置页真实功能、视觉识别降级。
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

## 已确认根因与修复

### 1. 只能归档到消费或收入

PWA 向 `data_records` 写入通用域记录时包含当前用户的 `user_id`。旧 iOS 请求遗漏该字段，在已收紧的 RLS 下，运动、睡眠、阅读、饮食和钱包都会被拒绝。消费和收入走独立 RPC，所以表现为“只有消费能成功”。

本批修复：

- `InboxRepository.archive` 显式接收认证用户 ID。
- `data_records` 和 `user_routing_feedback` 写入都携带 `user_id`。
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

## 自动验证

| 项目 | 状态 |
|---|---|
| `git diff --check` | 通过 |
| PWA `npm run build` | 通过；仅有既有大 chunk 和 vConsole eval 警告 |
| iOS 单元测试 | 等待 GitHub `iOS Build` |
| iOS Simulator Build | 等待 GitHub `iOS Build` |
| Edge Function 部署 | 等待代码推送并手动触发一次部署 |
| TestFlight | 本批最终 Build 通过后仅触发一次 |

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
- Git 工作区干净，提交范围不含截图、日志、测试结果或用户主工作区改动。
- 满足以上条件后手动触发一次 TestFlight；失败先修复，不连续重复上传。
