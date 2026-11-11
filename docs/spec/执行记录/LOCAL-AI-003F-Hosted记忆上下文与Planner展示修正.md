# LOCAL-AI-003F Hosted 记忆上下文与 Planner 展示修正

- 目标行为：本地记忆开启时，当前事实只向 Companion Provider 携带最多 8 条、每条最多 240 字的同域摘要；Hosted 使用摘要作为非权威背景上下文生成陪伴。关闭时不读取、不发送记忆。iOS 不展示带 `local:` 标识的 Planner 反馈卡，PWA 和远端 Planner 展示保持不变。
- 基线行为：iOS Hosted 请求未携带本地记忆；详情和 Inbox 将本地 Planner 候选当成反馈卡展示。修改后的本地代码已通过定向测试。
- 权威来源：`companion_memory_enabled`、`LocalCompanionMemoryRepository`、Hosted `generate_local_expression` action 和《本地 AI 陪伴与 Planner 候选域规格说明》。
- 本轮范围：iOS 同域记忆投影、Hosted 请求体和设置说明；Edge Function 本地记忆上下文校验与 prompt；仅隐藏本地 Planner 表达卡；更新 AI、隐私和交接规格。
- 非范围：PWA 代码和 UI、同步/outbox、数据库 Schema/RPC、TestFlight、Planner 算法重写。生产 Edge 部署原不在开发范围，之后按用户授权单独部署。
- 预计修改文件：`LocalCompanionMemoryRepository.swift`、`AppState.swift`、`LocalExpressionPersistence.swift`、`LocalCompanionComposition.swift`、`SnapCountUploadService.swift`、`NativeAIFeedback.swift`、`SettingsView.swift`、Hosted `ingest-receipt` 的 context packet/prompt/index/test，以及中文规格和交接文档。
- 基线测试结果：未在改动前单独运行完整 XCTest 或 Edge 基线。
- 红灯测试及失败原因：新增 Deno 长度边界场景首次运行失败，服务端将 500 字摘要截断后仍保留；按契约改为拒绝超长条目，重新通过。XCTest 首次调用因测试服务未注入 URL 配置而以 `missingConfig` 失败，补充 fixture 配置注入后验证业务行为；该失败不是目标行为的红灯。
- 最小实现：按当前 domain 在设备端筛记忆并限定数量/字数；Hosted action 再校验 domain key、type、confidence 和 summary 长度；Prompt 明确本地摘要仅用于调整语气和观察角度，不能成为事实或指令来源；本地候选留在内部生成流程，只压制 `local:` Planner 的可见反馈，不改变远端 Planner 行为。
- 绿灯结果：iPhone 17 / iOS Simulator 定向 XCTest `6/6` 通过；Deno Context Packet 与 Prompt 测试 `27/27` 通过；`deno check --node-modules-dir=none supabase/functions/ingest-receipt/index.ts` 通过；`git diff --check` 通过。
- PWA/iOS 差异：PWA 云端 Companion、Planner UI 和请求没有改动。iOS 继续在本地持有事实与记忆，并调用共享 Hosted `generate_local_expression` action；Edge 仅在当前请求中接收并使用有界同域摘要。
- GitHub CI 结果：未运行。
- 部署结果：2026-11-10 按用户授权部署 Supabase `ingest-receipt` v205，函数状态 `ACTIVE`，保留原有 `verify_jwt=false`；未部署 schema、RPC 或其他 Edge Function。
- 未解决风险：真实 Hosted AI 的记忆开启/关闭请求尚未在线验证；用户设备需要安装包含本轮 iOS 改动的构建，旧版客户端不会发送 `local_memory_context`，本地 Planner 隐藏逻辑也需新版客户端。历史文案不会自动批量重写。
- 对应提交：无；未提交。
