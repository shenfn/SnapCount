# CORE-008 跨记录关系边界评估执行记录

- 目标：确认跨记录关系是否具备独立、纯函数、可双运行时迁移边界。
- 基线：`8e982d2`。
- 工作树：`D:\Business\count\.worktrees\表达核心跨记录边界评估`。
- 分支：`docs/表达核心跨记录边界评估`。
- 本轮范围：只读检查实现、直接测试、Planner 调用和 Shadow/Delivery 来源装配；建立 Spec、ADR 和交接记录。
- 非范围：生产实现迁移、Edge 查询改造、PWA/iOS、数据库迁移、部署和历史回填。

## 只读结果

- `cross-record-relationships.mjs` 无外部 import，约 140 行，零 IO、零运行时专属 API。
- 当前规则集中在对象归一化、时间先后、180 分钟窗口、创建可见性、状态排除和置信度门槛。
- 直接测试 4 项通过，覆盖对象+时间正例和三个关键反例。
- Shadow 与 Delivery 都从 transactions、income_records、data_records 装配相同的 `ShadowRelatedRecord` 结构；expense 与 generic Planner 共用候选函数。
- 发现并登记 `timeZone` 未参与计算、同域候选未被禁止、来源字段投影受限三个边界；均不阻塞机械迁移，但不得在 CORE-008 中顺手改变。

## 当前状态

- 评估：已完成。
- Spec/ADR：已建立。
- 实现迁移：已完成并由 PR #57 合并，合并提交 `58c11ad`。
- Deno：本 Windows 环境未安装；PR #57 Release Validation 已补齐双运行时验证。

## 实现阶段追加

- 红灯：共享 Node runner 在生产核心文件缺失时按预期以 `ERR_MODULE_NOT_FOUND` 失败。
- 最小实现：新增生产 `cross-record-relationships.mjs`，Lab 原路径改为 wrapper，Edge Planner 改为直接引用生产核心；查询字段和 Planner 装配未改动。
- 新增 CORE-049 至 CORE-055 共享 JSON fixture、Node/Deno runner 和 wrapper 兼容测试。
- 本地绿灯：CORE-008 fixture 1/1、wrapper 1/1、旧 cross-record 5/5、表达核心/比较/周期/事实候选回归均通过；边界检查、治理检查和 `git diff --check` 通过。
- 环境失败：本地完整 Planner 逐文件回归中 5 个旧测试因缺少 `esbuild` 无法启动，且 Windows 未安装 Deno；PR #57 CI 后续已验证完整 Planner、Deno 和 Edge 检查通过。
- 生产 `tools/` 反向依赖由 5 项降至 4 项，已由 PR #57 架构检查确认。

## 下一步

1. CORE-008 已收口；由 CORE-009 实体归一化切片接续。
2. 保持根工作区、其他 worktree、PWA/iOS 和生产部署冻结。
