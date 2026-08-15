# PWA-008 设置与隐私边界评估执行记录

> 日期：2026-08-16
>
> 基线：`52aa92a`（PR #66 合并提交）
>
> 分支：`docs/PWA设置隐私边界评估`

## 目标与范围

- 正式收口 PWA-001，并只读评估设置、隐私、导出与认证的真实边界。
- 建立 PWA-008 首实现 Spec 与 ADR-015。
- 不修改 PWA 业务代码、数据库、Edge、iOS 或部署配置。

## 证据

- PR #66 已合并到 main，merge commit 为 `52aa92a`；综合、治理、iOS 变更检测和预览门禁通过。
- `PageSettings.vue` 约 1,166 行，含 9 次 `user_configs` 访问和 1 个直接 fetch。
- `PageAiVisionSettings` 3 次、ModalWelcome 1 次、AuthPage 1 次、Store 4 次 `user_configs` 访问。
- 架构 ratchet 当前为页面直连 5 项，分布在 4 个组件。
- Store、PageSettings 与 PageAiVisionSettings 分别维护配置默认、legacy fallback 和失败回滚。
- retention 保存失败不向调用方返回结果，页面可能继续执行 `cleanup_all_images`。

## 验证

| 命令 | 结果 |
|---|---|
| `node --test scripts/test-registration-consent-helper.test.mjs` | 1/1 通过 |
| `npm run check:security-contracts` | 通过 |
| `npm run governance:arch` | 通过；tools 0、页面直连 5、Domain 禁止依赖 0 |

## 决策

- 首片统一全部 `user_configs` 配置读写与共享状态，不同时迁移导出、清理 transport 或认证。
- `AuthPage` 暂留认证边界；PageSettings 可因导出/清理/signOut 保留直连 import，但不得再直接访问 `user_configs`。
- retention 保存必须返回明确结果，立即清理必须以保存成功为前置条件。
- 实现分支预计只收紧 ModalWelcome 与 PageAiVisionSettings 两个 import 基线项，实际计数以 diff 为准。

## 未验证与风险

- 尚未证明 Settings Feature 能覆盖三处页面状态与 legacy fallback，需实现分支红绿 TDD。
- 数据导出静默忽略查询错误的问题已登记，但明确不在配置首片修复。
- 原图清理仍是页面直连 Edge action，后续需要单独的不可逆副作用 Spec。
- 当前无设置客户端行为测试，不能依赖源码正则替代并发和回滚验证。

## 下一步

1. 提交本评估文档 PR并等待门禁。
2. 合并后从最新 main 建立 `feature/PWA设置配置边界`。
3. 按 PWA-008 至 PWA-017 写红灯与特征测试，再做最小实现。
