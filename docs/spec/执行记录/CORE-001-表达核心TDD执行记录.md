# CORE-001 表达核心 TDD 执行记录

> 任务：CLEAN-001/A2
>
> 日期：2026-08-15
>
> 分支：`docs/表达核心模块规格`
>
> 规格：`docs/spec/模块/表达核心/规格说明.md`

## 范围

本切片验证 `parseFiniteNumber`、`roundMoney`、`normalizeEntityText` 和 `buildExpenseFactContract` 四类纯函数。测试向量位于 `supabase/functions/_shared/contracts/表达核心-v0.1.json`，Node/Deno runner 共用 `feature-assertions.mjs`。

## 红灯证据

先运行：

```text
node --test supabase/functions/_shared/expression-core/node.test.mjs
```

结果：失败，`ERR_MODULE_NOT_FOUND`，因为 `_shared/expression-core/index.mjs` 尚不存在。该失败证明测试确实先于实现建立。

## 绿灯证据

实现最小纯函数后运行：

```text
npm run test:expression-core
npm run check:expression-core-boundary
```

结果：Node 特征测试通过；核心边界检查通过。测试只断言结构化结果和事实范围，不断言模型自然语言。

Planner Lab 的实体归一、金额/数值解析、周期/比较计算和事实契约模块已通过 adapter 复用生产核心；Edge Planner 的数值解析和事实契约导入已切换到 `_shared`。

Planner Lab Node 回归：排除 5 个依赖 `esbuild` 的环境测试文件后，103/103 通过；全量启动结果为 103 个通过、5 个因当前环境缺少 `esbuild` 无法加载的测试。该 5 项记录为环境失败，不判定为业务回归。

## 未验证

- 本地没有 `deno` 命令，Deno runner 未执行，属于环境未验证。
- GitHub Actions 的 Deno 双运行时 job 尚未取得 CI 结果。
- 完整 Planner 候选链尚未全部迁移，生产仍保留 11 条 `tools/` 基线导入。

## 下一步

1. 在可用 Deno 环境运行同一 fixture 的 `deno_test.mjs`。
2. 为 Edge 第一切片增加对比 fixture，确认 fallback 行为不变。
3. 在完整 Deno 验证后再迁移下一组候选规则。
