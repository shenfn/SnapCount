# PWA-001 业务边界评估执行记录

> 日期：2026-08-16
>
> 基线：`2dd9cba`

## 目标与范围

- 只读确认 PWA 当前依赖、Store 职责、页面直连、纯 Domain 和测试入口。
- 建立 A3 边界评估、首切片 Spec 与 ADR。
- 不修改 PWA、Edge、数据库、iOS 或部署配置。

## 证据

- `useStore.js` 约 4,400 行，包含 12 个不同 RPC 名称和 13 张表/资源入口。
- 24 个 Vue 组件注入 Store；4 个组件直接导入 Supabase，架构 ratchet 记录 5 个 import/fetch 键。
- `src/domains` 当前没有 Vue、Supabase 或 fetch 依赖；`npm run governance:arch` 基线为 production tools 0、page access 5、domain forbidden 0。
- 未发现 `useStore` 直接行为单测；现有表达计划缓存、曝光与反馈测试主要是源契约，首切片需补模块行为测试。
- `npm run build` 在 A2 PR #64 已通过；本评估未重复修改或验证业务构建。

## 决策

- 保留 `useStore` 兼容门面，不引入 Pinia，不按数据域机械拆 Store。
- 首片选择表达计划与反馈，以现有 contract 为回归基线，新增 Feature/Repository 行为测试。
- 设置隐私、认证、中转、正式记录和账户按风险递增顺序后续迁移。

## 未验证与风险

- 尚未证明新 Feature/Repository 结构能在现有 Vite/Vue 环境下工作；须由实现分支红绿 TDD 与 build 验证。
- 当前页面直连和宽 Store API 都是历史基线，本评估没有降低计数。
- Windows 不影响本 PWA 文档评估；后续若改 iOS 仍必须走 macOS CI。

## 下一步

1. 提交本评估文档 PR并等待治理、综合和 iOS Gate。
2. 合并后从最新 main 建立 `feature/PWA表达计划边界`。
3. 按 PWA-001 至 PWA-007 写红灯测试，再做最小迁移。
