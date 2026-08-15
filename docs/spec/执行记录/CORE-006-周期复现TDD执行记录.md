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

1. 将现有纯函数迁入生产核心，Lab 原路径改为兼容 wrapper，Edge 切换导入。
2. 加入 wrapper 兼容测试、PR workflow 双运行时步骤和架构 ratchet 更新。
3. 运行 CORE-006、旧 recurrence 回归、前五片核心回归、Planner、Edge 和治理检查。
