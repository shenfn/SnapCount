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

## 最小实现与绿灯证据

1. 机械迁移 comparison 模块，只调整生产核心数值/金额函数导入。
2. Lab 原路径改为两个 API 的兼容 wrapper，Edge 切换到生产核心。
3. `npm run test:expression-comparison`：通过，CORE-040 至 CORE-048 共享双契约 fixture 转绿。
4. `npm run test:expression-comparison-wrapper-compat`：通过，确认 Lab 两个 API 与生产核心为同一绑定。
5. `node --test tools/ai-validation/expression-planner/tests/comparison-candidates.test.mjs`：通过，6/6。
6. `npm run test:expression-core`、`npm run test:expression-eligibility`、`npm run test:expression-scoring`、`npm run test:expression-plan-selection`：通过，已有切片未回归。
7. `npm run check:expression-core-boundary`、`npm run governance:arch`、`npm run governance:check`：通过；生产 `tools/` 依赖由 6 降至 5。

## 本地未验证与 CI 补齐

- Windows 本地没有 `deno`，因此未在本机执行 CORE-007 Deno runner；PR #54 Release Validation 后续已验证通过。
- Windows 本地缺少 `esbuild`，因此未在本机完成完整 Planner 回归；PR #54 Release Validation 后续已验证通过。
- 未执行生产部署、迁移或端侧改动。

## PR 验证与合并

- PR #54：`https://github.com/shenfn/SnapCount/pull/54`
- GitHub Release Validation：通过，包含 Node/Deno comparison、Edge、完整 Planner、PWA、迁移和 Shadow 门禁。
- GitHub Governance Validation：通过。
- GitHub iOS Build：检测到无 iOS 变更，SwiftUI 构建按条件跳过；iOS Build Gate 通过。
- PR 已于 2026-08-15 合并，合并提交：`68434cb`。

## 下一步

只读评估 cross-record 的输入契约、纯函数边界和是否能独立迁移；先建评估文档和 Spec，再决定是否实现。
