# CORE-004 确定性评分 TDD 执行记录

> 任务：CLEAN-001/A2
>
> 日期：2026-08-15
>
> 分支：`feature/表达核心确定性评分`
>
> 对应提交：`170fe77`；合并提交：`b4da010`（PR #48）
>
> 规格：`docs/spec/模块/表达核心/确定性评分规格说明.md`

## 范围

本切片只迁移候选确定性评分、曝光读取、偏好边界、表面阈值和排序摘要。资格门、候选生成、选择、render contract、端侧业务和生产部署均不在范围内。

## 基线

- `node --test tools/ai-validation/expression-planner/tests/deterministic-scoring.test.mjs`：通过，9/9。
- `npm run governance:arch`：通过，生产 `tools/` 依赖为 9 项。
- `npm run governance:check`：通过。
- `npm run test:expression-eligibility`、`npm run test:expression-plan-selection`：均通过。

## 红灯证据

先建立 CORE-018 至 CORE-023 的共享 fixture、Node/Deno runner 与 wrapper 兼容测试，再运行：

```text
npm run test:expression-scoring
```

结果：失败，`ERR_MODULE_NOT_FOUND`，因为 `_shared/expression-core/deterministic-scoring.mjs` 尚不存在。失败发生在目标模块导入处，证明红灯不是 fixture、断言或环境错误。

## 最小实现

1. 将现有评分纯函数实现迁入生产共享核心。
2. 将 Planner Lab 原文件改为 re-export wrapper。
3. 将 Edge Planner 的评分导入切换到 `_shared`。
4. 将评分 Node/Deno fixture、wrapper 兼容检查加入 PR workflow，并从 ratchet 例外清单移除旧导入。

## 绿灯证据

- `npm run test:expression-scoring`：通过，CORE-018 至 CORE-023 共享 fixture 转绿。
- `npm run test:expression-scoring-wrapper-compat`：通过，确认 Lab 六个公开 API 与生产核心是同一绑定。
- `node --test tools/ai-validation/expression-planner/tests/deterministic-scoring.test.mjs`：通过，9/9。
- `npm run test:expression-eligibility`、`npm run test:expression-plan-selection`：通过，资格和选择切片未回归。
- 迁移前后评分核心逐行一致（仅文件归属和 wrapper/Edge 导入变化）。
- `npm run check:expression-core-boundary`、`npm run governance:arch`、`npm run governance:check`：通过；生产 `tools/` 依赖由 9 降至 8。

## 未验证

- Windows 本地没有 `deno`，CORE-004 Deno runner 未执行。
- Windows 本地缺少 `esbuild`，完整 Planner 回归未执行；已运行不依赖该包的评分、资格和选择回归。
- PR #48 已通过 GitHub CI：Deno、Edge 类型检查、完整 Planner 回归、PWA 构建和迁移门禁均通过。
- 未执行生产部署、迁移或端侧改动。

## 下一步

CORE-004 已通过 PR #48 并合并。A2 下一切片为 CORE-005 事实候选，必须重新建立独立 Spec、fixture 和红灯。
