# CORE-002 表达计划选择 TDD 执行记录

> 任务：CLEAN-001/A2
>
> 日期：2026-08-15
>
> 分支：`feature/表达核心降级选择`
>
> 规格：`docs/spec/模块/表达核心/降级选择规格说明.md`

## 范围

本切片只迁移表面容量、选择排序、覆盖排除、容量、多样性、周期冷却和两类 fallback 选择逻辑。候选生成、资格门、评分、渲染契约和端侧业务均不在范围内。

## 基线

- `npm run governance:check`：通过。
- `npm run governance:arch`：通过，生产 `tools/` 依赖为 11 项。
- `node --test tools/ai-validation/expression-planner/tests/expression-plan.test.mjs`：基线测试在迁移前通过（8/8）。

## 红灯证据

先建立 `CORE-008` 至 `CORE-012` 的共享候选 fixture 和 Node/Deno runner，再运行：

```text
npm run test:expression-plan-selection
```

结果：失败，`ERR_MODULE_NOT_FOUND`，因为 `_shared/expression-core/plan-selection.mjs` 尚不存在。失败发生在目标模块导入处，fixture 已被读取，证明红灯不是断言或环境错误。

## 预计最小实现

1. 将现有 `tools/ai-validation/expression-planner/lib/expression-plan.mjs` 的纯函数实现移入生产共享核心。
2. 将 Lab 原文件改为 re-export wrapper。
3. 将 Edge Planner 的四个选择相关导入切换到 `_shared`。

## 未验证

- 尚未实现核心模块、wrapper 或 Edge 导入切换。
- 尚未运行 Deno、完整 Planner 回归或 GitHub CI。
- 未执行部署、迁移或端侧改动。

## 下一步

实现最小选择核心后重新运行 CORE-002 fixture、原有 expression-plan 回归和边界检查。
