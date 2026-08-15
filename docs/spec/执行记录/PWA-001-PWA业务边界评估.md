# PWA-001 业务边界首切片执行记录

> 日期：2026-08-16
>
> 评估基线：`2dd9cba`
>
> 实现基线：`60f40ef`（PR #65 合并提交）
>
> 实现分支：`feature/PWA表达计划边界`

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

## 实现与 TDD 证据

### 红灯

先新增 Repository 与 Feature 行为测试，目标模块尚不存在时运行：

```text
node --test src/repositories/__tests__/expressionRepository.test.mjs src/features/expression/__tests__/expressionPlanState.test.mjs
```

结果为 2 个 `ERR_MODULE_NOT_FOUND`，失败原因只来自目标模块缺失，作为有效红灯。

### 最小实现

- 新增 `expressionRepository.js`，只负责 session token、Edge action HTTP、DTO 解包和传输错误元数据。
- 新增纯工厂 `createExpressionPlanState.js`，承载 cache、去重、revision/version、ACK 和反馈绑定，不依赖 Vue、Supabase 或 `fetch`。
- `useStore` 保留原公开 ref/action，只组合 Repository/Feature，并在 `resetUserData` 调用 Feature reset。
- 既有记录 mutation 的成功后失效调用保持原位，页面与组件零改动。

### 绿灯与回归

| 命令 | 结果 |
|---|---|
| 新 Feature/Repository + 既有 PWA 表达契约联合测试 | 22/22 通过 |
| `npm run test:expression-presentation` | 22/22 通过 |
| `npm run test:finance-occurred-at` | 通过 |
| `npm run governance:check` | 通过 |
| `npm run governance:arch` | 通过；计数保持 tools 0、页面直连 5、Domain 禁止依赖 0 |
| `npm run build` | 通过；153 modules transformed |

## PR 结果与剩余风险

- GitHub PR #66 综合、治理、iOS 变更检测和预览门禁已通过，并以 `52aa92a` 合并到 main。
- `npm ci` 报告 5 个既有依赖漏洞（1 moderate、4 high）；本切片没有升级依赖或运行自动修复。
- Vite 仍报告 vconsole `eval` 与大 chunk 警告；均非本切片引入，未借机扩展范围。
- 页面 Supabase 直连仍为 5 项，等待后续“设置与隐私”和“认证会话”切片逐步 ratchet。

## 下一步

PWA-001 已完成；当前任务转入 PWA-008 设置与隐私边界评估，见 `docs/handoff/A3-PWA设置隐私边界评估-2026-08-16.md`。
