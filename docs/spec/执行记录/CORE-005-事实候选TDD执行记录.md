# CORE-005 事实候选 TDD 执行记录

> 任务：CLEAN-001/A2
>
> 日期：2026-08-15
>
> 分支：`feature/表达核心事实候选`
>
> 规格：`docs/spec/模块/表达核心/事实候选规格说明.md`

## 范围

本切片只迁移支出当前记录、日聚合和实体首次出现候选。实体别名配置、recurrence、comparison、cross-record、generic-domain、资格、评分、选择和 render contract 均不在范围内。

## 基线

- `node --test tools/ai-validation/expression-planner/tests/fact-candidates.test.mjs`：通过，8/8。
- `npm run governance:arch`：通过，生产 `tools/` 依赖为 8 项。
- `npm run governance:check`：通过。
- `npm run test:expression-core`、`npm run test:expression-eligibility`、`npm run test:expression-scoring`、`npm run test:expression-plan-selection`：均通过。

## 红灯证据

先建立 CORE-024 至 CORE-030 的共享 fixture、Node/Deno runner 与 wrapper 兼容测试，再运行：

```text
npm run test:expression-fact-candidates
```

结果：失败，`ERR_MODULE_NOT_FOUND`，因为 `_shared/expression-core/fact-candidates.mjs` 尚不存在。失败发生在目标模块导入处，证明红灯不是 fixture、断言或环境错误。

## 最小实现

1. 将现有事实候选函数迁入生产共享核心，仅把 `expression-core-adapter` 路径改为 `_shared/index.mjs`。
2. 将 Planner Lab 原文件改为 re-export wrapper。
3. 将 Edge Planner 的事实候选导入切换到 `_shared`。
4. 将事实候选 Node/Deno fixture、wrapper 兼容检查加入 PR workflow，并从 ratchet 例外清单移除旧导入。

## 绿灯证据

- `npm run test:expression-fact-candidates`：通过，CORE-024 至 CORE-030 共享 fixture 转绿。
- `npm run test:expression-fact-candidates-wrapper-compat`：通过，确认 Lab 三个公开 API 与生产核心是同一绑定。
- `node --test tools/ai-validation/expression-planner/tests/fact-candidates.test.mjs`：通过，8/8。
- `npm run test:expression-core`、`npm run test:expression-eligibility`、`npm run test:expression-scoring`、`npm run test:expression-plan-selection`：通过，已有切片未回归。
- `npm run check:expression-core-boundary`、`npm run governance:arch`、`npm run governance:check`：通过；生产 `tools/` 依赖由 8 降至 7。
- 迁移前后事实候选函数体逐行一致，唯一差异是生产核心从 `_shared/index.mjs` 导入已有数值/金额函数。

## PR 验证与合并

- PR #49：`https://github.com/shenfn/SnapCount/pull/49`
- GitHub Release Validation：通过，包含 Node/Deno 事实候选测试、Edge 检查、完整 Planner、PWA、迁移和 Shadow 门禁。
- GitHub Governance Validation：通过。
- GitHub iOS Build：检测到无 iOS 变更，SwiftUI 构建按条件跳过；iOS Build Gate 通过。
- PR 已于 2026-08-15 合并，合并提交：`c79ed56`。

## 未验证

- Windows 本地没有 `deno`，CORE-005 Deno runner 未执行。
- Windows 本地缺少 `esbuild`，完整 Planner 回归未执行；已运行不依赖该包的事实候选和核心回归。
- 未执行生产部署、迁移或端侧改动。

## 下一步

只读评估 recurrence；若边界、调用点和既有测试适合独立迁移，再新建 CORE-006 Spec、共享 fixture 和红灯，不能直接迁移实现。
