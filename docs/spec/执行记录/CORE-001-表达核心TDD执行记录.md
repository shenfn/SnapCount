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

## 未验证

- 本地没有 `deno` 命令，Deno runner 未执行，属于环境未验证。
- GitHub Actions 的 Deno 双运行时 job 尚未取得 CI 结果。
- Planner Lab adapter 和 Edge 入口尚未切换到 `_shared`，生产反向依赖仍按 A1 基线保留。

## 下一步

1. 在可用 Deno 环境运行同一 fixture 的 `deno_test.mjs`。
2. 评估 Planner Lab adapter 是否只复用四个核心函数，不复制规则。
3. 为 Edge 第一切片替换导入前增加对比 fixture，确认 fallback 行为不变。
