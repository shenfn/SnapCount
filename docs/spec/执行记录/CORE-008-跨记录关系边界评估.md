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
- 实现迁移：待建立 `feature/表达核心跨记录关系` 分支。
- Deno：本 Windows 环境未安装，需由 PR CI 验证。

## 下一步

1. 合并本评估文档 PR。
2. 从最新 `origin/main` 建 CORE-008 实现 worktree。
3. 新增共享 Node/Deno fixture，先验证目标文件缺失时的有效红灯。
4. 机械迁移、替换 Lab wrapper、切 Edge 导入，并跑旧回归及完整 Planner。
