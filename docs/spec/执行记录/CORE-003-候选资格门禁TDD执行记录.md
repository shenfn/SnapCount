# CORE-003 候选资格门禁 TDD 执行记录

> 任务：CLEAN-001/A2
>
> 日期：2026-08-15
>
> 分支：`feature/表达核心资格门禁`
>
> 对应提交：`2a4a6c1`；合并提交：`b7738a5`（PR #47）
>
> 规格：`docs/spec/模块/表达核心/资格门禁规格说明.md`

## 范围

本切片只迁移候选硬性事实门禁、商户活跃日实质性判断、surface 资格和周期路由。候选生成、评分、选择、render contract、端侧业务和生产部署均不在范围内。

## 基线

- `node --test tools/ai-validation/expression-planner/tests/eligibility-gates.test.mjs`：通过，14/14。
- `npm run check:expression-core-boundary`：通过。
- `npm run governance:arch`：通过，生产 `tools/` 依赖为 10 项。
- `npm run governance:check`：通过。

## 红灯证据

先建立 CORE-013 至 CORE-017 的共享 fixture、Node/Deno runner 与 wrapper 兼容测试，再运行：

```text
npm run test:expression-eligibility
```

结果：失败，`ERR_MODULE_NOT_FOUND`，因为 `_shared/expression-core/eligibility-gates.mjs` 尚不存在。失败发生在目标模块导入处，证明红灯不是 fixture、断言或环境错误。

## 最小实现

1. 将现有 `tools/ai-validation/expression-planner/lib/eligibility-gates.mjs` 的纯函数实现迁入生产共享核心。
2. 将 Planner Lab 原文件改为 re-export wrapper。
3. 将 Edge Planner 的资格门导入切换到 `_shared`。
4. 将 Node/Deno fixture 与 wrapper 兼容检查加入 PR workflow，并从 ratchet 例外清单移除旧导入。

## 绿灯证据

- `npm run test:expression-eligibility`：通过，CORE-013 至 CORE-017 共享 fixture 转绿。
- `npm run test:expression-eligibility-wrapper-compat`：通过，确认 Lab 四个公开 API 与生产核心是同一绑定。
- `node --test tools/ai-validation/expression-planner/tests/eligibility-gates.test.mjs`：通过，14/14。
- `npm run test:expression-core`、`npm run test:expression-core-compat`、`node --test tools/ai-validation/expression-planner/tests/expression-plan.test.mjs`：均通过。
- `npm run check:expression-core-boundary`、`npm run governance:arch`、`npm run governance:check`：通过；生产 `tools/` 依赖由 10 降至 9。

## 未验证

- Windows 本地没有 `deno`，CORE-003 Deno runner 未执行。
- Windows 本地缺少 `esbuild`，完整 Planner 回归未执行；已运行不依赖该包的资格门和计划选择回归。
- PR #47 已通过 GitHub CI：Deno、Edge 类型检查、PWA 构建、迁移门禁和完整 Planner 回归均通过。
- 未执行生产部署、迁移或端侧改动。

## 下一步

CORE-003 已通过 PR #47 并合并。A2 下一切片为 CORE-004 确定性评分，必须重新建立独立 Spec、fixture 和红灯。
