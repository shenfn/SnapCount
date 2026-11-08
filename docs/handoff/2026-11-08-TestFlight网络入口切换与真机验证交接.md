---
project: SnapCount
name: TestFlight 网络入口切换与真机验证交接
updated: 2026-11-08
branch: release/1.0
head: c8bdc35
status: TestFlight #160 已上传；真机 Hosted AI Voice 已出现真实动态文案，等待新包处理完成后的网络与快捷指令矩阵验收
tags: [handoff, testflight, ios, hosted-ai, shortcuts]
---

# TestFlight 网络入口切换与真机验证交接

> 当前状态优先以本文件为准。此前 `2026-11-07-App-Store上架路线与当前交接.md` 和 Obsidian 路线笔记仍保留完整历史，但其中的旧 build、旧 SHA 和旧入口地址不再代表当前候选。

## 1. 这轮要解决的问题

真机快捷指令曾出现：

- 快捷指令动作显示“未知错误”；
- 待处理页出现“网络连接失败”；
- 部分请求显示 `uncertain` 或“AI 识别未完成”。

排查目标有三个：

1. 确认请求是否真的到达 Hosted AI；
2. 确认图片是否被持久化到 Supabase Storage；
3. 减少中国网络分流下直连 Supabase 函数域名的回包不稳定。

## 2. 已完成的代码与后端工作

### Hosted AI 本地优先路径

iOS 快捷指令的 Hosted AI 路径仍然使用：

`operation=recognize_only`

服务端先调用视觉模型得到结构化候选，再对完整且高置信的财务/内置域候选调用第二次 Voice 模型，生成：

- `companion_message`
- `ai_feedback`

Voice 失败时保留事实校验后的规则兜底。

生产 Edge Function：

- Supabase 项目：`igbghrhsdaolxljgiisf`
- `ingest-receipt`：v203
- 线上源码已包含 `recognize_only` 的 `generateVoiceFeedback` 调用

### BYOK 链路

BYOK 已改为两次模型调用：

1. 图片识别：图片 + 识别约束 → 结构化事实候选；
2. Voice：只发送候选事实 JSON，不重新发送原图 → 陪伴文案和结构化反馈。

本地测试：`LocalBYOKProviderTests 7/7` 通过。

### 图片留存边界

快捷指令的 `recognize_only` 路径在服务端明确跳过 Supabase Storage 上传：

- 不创建 Supabase Storage 原图对象；
- 不把原图写入云端业务记录；
- 图片仍会通过网络发送到 Edge Function，并继续发送给视觉模型做临时推理。

因此准确表述是：

> 快捷指令原图不持久化到 Supabase Storage，但 Hosted AI 模式并非“图片完全不离开手机”。

普通 `operation=ingest` 路径与此不同，不能用本结论替代普通云端归档路径的图片留存策略。

## 3. 网络入口切换

### 旧状态

build 159 的请求实际走：

`https://igbghrhsdaolxljgiisf.supabase.co/functions/v1/ingest-receipt`

服务端日志显示：

- 请求确实到达；
- HTTP 200；
- 单次耗时约 7.6–10.9 秒；
- 其中一次 22:11 左右请求耗时约 10.9 秒。

因此“网络连接失败”不是服务端完全没收到请求，更像是分流/VPN路径下的回包不稳定，或客户端在拿到响应时连接中断。

### 当前状态

已更新 GitHub Actions repository secret：

`IOS_SUPABASE_FUNCTIONS_URL=https://api.snapflow.me`

`IOS_SUPABASE_URL` 保持不变。

这只改变 iOS 上传识别函数的入口，不改变本地数据库、Hosted AI 两阶段调用或图片留存策略。

## 4. TestFlight 状态

已从 `release/1.0` 触发新的 TestFlight 构建：

- GitHub Actions run：[#160](https://github.com/shenfn/SnapCount/actions/runs/42383391617)
- Run ID：`42383391617`
- 触发提交：`e4c01f2`
- 当前文档提交：`c8bdc35`
- Archive：成功
- Export IPA：成功
- 签名：成功
- Upload to TestFlight：成功
- IPA artifact：成功

注意：workflow 使用 GitHub Run ID 作为 `CFBundleVersion`，因此 App Store Connect 里可能显示 `42383391617`，而不是页面上的 run number `160`。

## 5. 已完成的真机验证

用户在 2026-11-07 22:55 左右提供的详情页截图显示：

- 商家：串意十足东北烧烤·爆汁大油边
- 金额：¥29.42
- 渠道：美团
- 分类：food
- AI 陪伴标题：深夜暖胃
- 陪伴文案：
  - “深夜的烧烤香气，29.42 元已归档。”
  - “周六深夜，这点烟火气看着挺踏实。”
- 建议语：“吃完早点休息，别太晚熬夜啦。”

这组文案具有当前金额、星期、时段和商家事实，说明真实 Voice 生成链路已经在真机结果中出现，不是旧的固定规则模板。

## 6. 仍待验证

### 新入口是否改善网络稳定性

新 TestFlight 处理完成后，需要用同一张真实账单测试：

1. VPN 关闭；
2. VPN 开启，分流 `final` 选择海外代理节点；
3. VPN 开启，全局/全隧道模式；
4. Wi-Fi 与蜂窝数据分别测试。

每次都记录：

- 快捷指令是否完成；
- 是否出现系统“未知错误”；
- 待处理页是否出现网络失败；
- 是否产生本地正式记录；
- AI 陪伴是否正常返回。

### 快捷指令输入链路

继续验证：

- 截屏 → 调整大小 → 转换 JPEG → 上传 JPEG 到芥子；
- 相册选择图片；
- 辅助键触发；
- 重试；
- 重复截图判重；
- `uncertain` 图片进入待处理；
- 图片处理失败后原图是否仍保留本机。

### 其他发布门禁

仍未完成或仍需重跑：

- App Store Connect 处理完成后的新包安装；
- 完整 XCTest 的云端配置用例；
- 五域、收入、钱包、同步、导出、删号和无障碍回归；
- 历史迁移 `imported_row_count=0` 与 227 条 unresolved 的最终口径说明；
- App Store 隐私资料、审核账号和提交前最终冻结。

## 7. 交接时先看哪里

1. 本文件：当前 TestFlight #160、网络入口和真机验证状态；
2. [2026-11-07-App-Store上架路线与当前交接.md](2026-11-07-App-Store上架路线与当前交接.md)：完整发布路线和历史验收；
3. [2026-11-07-待处理页改版与本地环境交接.md](2026-11-07-待处理页改版与本地环境交接.md)：页面改版和本地环境；
4. `supabase/functions/ingest-receipt/index.ts`：Hosted AI、Voice 和 `recognize_only`；
5. `ios/SnapCount/Services/SnapCountUploadService.swift`：iOS 函数入口和 multipart 请求；
6. `ios/SnapCount/Intents/UploadScreenshotIntent.swift`：快捷指令 App Intent。

## 8. 本轮提交与文档同步

- 代码修复提交：`4725f18`、`e4c01f2`
- 当前文档提交：`c8bdc35`
- `release/1.0` 与 `feature/inbox-pwa-parity` 已推送到 `c8bdc35`
- Obsidian 路线笔记和 SnapCount 记忆索引已同步更新

