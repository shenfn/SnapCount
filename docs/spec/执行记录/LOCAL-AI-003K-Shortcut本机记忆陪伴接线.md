# LOCAL-AI-003K Shortcut 本机记忆陪伴接线

- 状态：代码已接入；Edge v206 与默认值迁移已部署；iOS 编译与 626 条模拟器 XCTest 已通过；尚未真机验收
- 日期：2026-11-11
- 对应规格：[`本地 AI 陪伴与 Planner 候选域规格说明.md`](../模块/iOS本地优先/本地AI陪伴与Planner候选域规格说明.md) 的 LOCAL-AI-003K
- 目标：让快捷指令识别后正式保存在本机的记录，使用本机同域记忆、当前表达偏好和本地时间生成并保存 Hosted/BYOK Companion。

## 改动

- `recognize_only` 图片识别只返回识别事实，不再读取云端 Companion 记忆、云端域画像或调用 Voice；正常 PWA `ingest` 路径不改。
- Hosted 与 BYOK 图片识别现在都只返回事实；Shortcut、App 内图片识别和失败图片重试在正式入账后，由 iOS 从本地设置决定是否生成 Companion。Hosted 使用 Keychain 内登录会话的有效用户 JWT；会话过期时尝试刷新。图片上传专用 `upload_token` 不作为文案生成凭据。BYOK 使用现有本机 Qwen Key。
- 文字请求包含当前结构化事实、匹配当前商户/类别的本机 Planner 候选、用户 persona / 记忆强度 / 表达风格 / 自定义偏好、真实设备本地时间、星期，以及记忆开启时最多 8 条同域摘要和最多 5 条旧文案用于去重。
- Hosted 服务端对偏好、时间、星期和最近文案做长度/枚举限制；本机摘要沿用同域、条数、置信度和摘要长度校验，不写业务表、云端记忆或同步 outbox。
- 记忆默认关闭。客户端与服务端的缺省值均为关闭；数据库迁移只修改新行默认值，不更新已有用户选择。关闭时不读取同域记忆或最近文案，也不发送记忆字段。
- 自动 OCR 归档成功后刷新本机记忆投影。新增近 30 天重复商户/类别的定性摘要，至少需要 2 条正式记录；待确认事实不进入投影。用户在本机确认待确认消费/收入后触发同一 Companion 流程。
- 记忆关闭时删除来源仍会清除直接关联的记忆项；重新开启时基于当前正式事实重建派生投影。
- 中英文隐私政策、iOS 内置隐私文本、设置提示、上架清单和本地隐私契约同步说明摘要会发送给模型服务商的条件与路径。

## 未完成验收

- 本轮 iOS Debug 编译通过；iPhone 17 / iOS 27.2 Simulator 的 626 条 XCTest 全部通过。Deno CLI 当前不可用，尚未运行 Deno 测试。
- 尚未在登录真机/当前快捷指令上验证记忆开关、摘要真实内容、Hosted 模型输出、详情页最终持久化、待确认后生成和失败退化。
- Supabase `ingest-receipt` 已从 v205 部署到 v206，状态 `ACTIVE`，保留 `verify_jwt=false`；部署后读取远端源码确认包含 `local_memory_context` 与 `recognize_only` 更新。
- 已应用数据库迁移 `20261111001813_default_companion_memory_opt_in`；数据库列默认值验证为 `false`，31 个既有账户仍为 `true`。
- 因此代码接线已经完成，但用户要求的“文案能看出本机习惯、自然接近 PWA”仍未验收，不应据此解锁 App Store 发布。

## 主要文件

- `ios/SnapCount/Intents/UploadScreenshotIntent.swift`
- `ios/SnapCount/LocalData/LocalImageRecognition.swift`
- `ios/SnapCount/LocalData/QwenBYOKImageRecognitionProvider.swift`
- `ios/SnapCount/LocalData/LocalCompanionComposition.swift`
- `ios/SnapCount/LocalData/LocalExpressionPersistence.swift`
- `ios/SnapCount/LocalData/LocalExpressionContext.swift`
- `ios/SnapCount/Services/SnapCountUploadService.swift`
- `ios/SnapCount/App/AppState.swift`
- `supabase/functions/ingest-receipt/index.ts`
- `supabase/migrations/20261111001813_default_companion_memory_opt_in.sql`
