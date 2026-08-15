# CORE-009 实体归一化边界评估执行记录

- 目标：确认实体归一化规则与公开别名配置是否具备独立、可双运行时迁移边界。
- 基线：`58c11ad`。
- 工作树：`D:\Business\count\.worktrees\表达核心实体归一化边界评估`。
- 分支：`docs/表达核心实体归一化边界评估`。
- 本轮范围：只读检查规则、配置、现有测试和 Edge 调用；建立 Spec、ADR 和交接记录。
- 非范围：生产实现、别名业务内容变更、候选/评分/选择、PWA/iOS、数据库和部署。

## 只读结果

- entity-normalizer 规则函数无 IO，仅复用已迁入生产核心的 `normalizeEntityText`。
- Edge 当前同时反向依赖 `tools` 规则模块和公开别名 JSON；只迁规则不迁配置仍不满足依赖方向目标。
- 现有 7 项 Node 测试覆盖配置别名、唯一历史变体、多实体歧义和非行政营销前缀。
- 配置当前为空 merchants 列表，但仍是生产输入契约，不应删除或留在实验室路径。

## 当前状态

- 评估：已完成。
- Spec/ADR：已建立。
- 实现迁移：待文档 PR 合并后建立 `feature/表达核心实体归一化`。
- Deno：本 Windows 环境是否安装尚未检查，双运行时需由实现 PR CI 验证。

## 实现阶段追加

- 红灯：共享 Node runner 在生产核心文件缺失时按预期以 `ERR_MODULE_NOT_FOUND` 失败。
- 最小实现：新增生产 `entity-normalizer.mjs`，复用 `index.mjs` 的 `normalizeEntityText`；新增生产共享公开配置；Lab 原路径改为 wrapper；Edge 改为直接引用生产核心和配置。
- 删除旧 `tools/ai-validation/expression-planner/configs/entity-aliases.public.v0.1.json`，避免保留第二份配置权威。
- 本地绿灯：CORE-056 至 CORE-061 fixture 1/1、wrapper 1/1、旧实体测试 7/7、Edge 静态契约 1/1；核心边界、治理检查和 `git diff --check` 通过。
- 环境限制：Windows 未安装 Deno，双运行时需由 PR CI 验证；完整 Planner 中与 `esbuild` 相关的既有环境缺口沿用前片记录。
- 生产 `tools/` 的 entity-normalizer 规则和 alias 配置反向依赖已清零，最终依赖计数由 CI 确认。

## 下一步

1. 等待实现 PR 的 Node/Deno、Edge、Planner 和治理门禁。
2. CI 通过后合并实现 PR，并将 A2 推进到下一片纯函数边界评估。
3. 保持根工作区、其他 worktree、PWA/iOS 和生产部署冻结。
