# CORE-006 周期复现 TDD 执行记录

> 任务：CLEAN-001/A2
>
> 日期：2026-08-15
>
> 分支：`feature/表达核心周期复现`
>
> 规格：`docs/spec/模块/表达核心/周期复现规格说明.md`

## 范围

本切片只迁移同名记录上一次间隔候选。comparison、cross-record、generic-domain、实体配置、资格、评分、选择和 render contract 均不在范围内。

## 基线

- `node --test tools/ai-validation/expression-planner/tests/recurrence-candidates.test.mjs`：基线测试存在，待迁移后回归。
- `npm run governance:arch`：主线基线通过，生产 `tools/` 依赖为 7 项。
- `npm run governance:check`：主线基线通过。

## 红灯证据

先建立 CORE-031 至 CORE-039 的共享 fixture、Node/Deno runner，再运行：

```text
npm run test:expression-recurrence
```

结果：失败，`ERR_MODULE_NOT_FOUND`，因为 `_shared/expression-core/recurrence-candidates.mjs` 尚不存在。失败发生在目标模块导入处，证明红灯不是 fixture、断言或环境错误。

## 下一步

## 最小实现与绿灯证据

1. 将现有纯函数迁入生产核心，Lab 原路径改为兼容 wrapper，Edge 切换导入。
2. 加入 wrapper 兼容测试、PR workflow 双运行时步骤和架构 ratchet 更新。
3. `npm run test:expression-recurrence`：通过，CORE-031 至 CORE-039 共享 fixture 转绿。
4. `npm run test:expression-recurrence-wrapper-compat`：通过，确认 Lab API 与生产核心为同一绑定。
5. `node --test tools/ai-validation/expression-planner/tests/recurrence-candidates.test.mjs`：通过，8/8。
6. `npm run test:expression-core`、`npm run test:expression-eligibility`、`npm run test:expression-scoring`、`npm run test:expression-plan-selection`：通过，已有切片未回归。
7. `npm run check:expression-core-boundary`、`npm run governance:arch`、`npm run governance:check`：通过；生产 `tools/` 依赖由 7 降至 6。

## 未验证

- Windows 本地没有 `deno`，CORE-006 Deno runner 待 PR CI 验证。
- Windows 本地缺少 `esbuild`，完整 Planner 回归待 PR CI 验证。
- 尚未创建 PR，Edge 类型检查、PWA、迁移和发布门禁待 CI 验证。
- 未执行生产部署、迁移或端侧改动。

## 下一步

创建 PR，以 GitHub CI 完成 CORE-006 双运行时、Edge、完整 Planner、治理、PWA 和迁移验证；CI 全绿后再回写阶段索引并评估 comparison。
