# CORE-007 比较候选 TDD 执行记录

> 任务：CLEAN-001/A2
>
> 日期：2026-08-15
>
> 分支：`feature/表达核心比较候选`
>
> 规格：`docs/spec/模块/表达核心/比较候选规格说明.md`

## 范围

本切片迁移商户日/周比较与分类周比较的单一权威模块。cross-record、generic-domain、entity-normalizer、render contract、资格、评分和选择均不在范围内。

## 基线

- `node --test tools/ai-validation/expression-planner/tests/comparison-candidates.test.mjs`：现有直接测试共 6 项。
- `npm run governance:arch`：主线生产 `tools/` 依赖为 6 项。
- CORE-001 至 CORE-006 已通过主线 CI。

## 红灯证据

先建立 CORE-040 至 CORE-048 的共享 fixture、Node/Deno runner，再运行：

```text
npm run test:expression-comparison
```

结果：失败，`ERR_MODULE_NOT_FOUND`，因为 `_shared/expression-core/comparison-candidates.mjs` 尚不存在。失败发生在目标模块导入处，证明红灯不是 fixture、断言或环境错误。

## 下一步

1. 机械迁移 comparison 模块，只调整生产核心数值/金额函数导入。
2. Lab 原路径改为两个 API 的兼容 wrapper，Edge 切换到生产核心。
3. 增加 wrapper 测试、双运行时 CI 和架构 ratchet，运行共享 fixture、旧 6 项和完整 Planner 回归。
