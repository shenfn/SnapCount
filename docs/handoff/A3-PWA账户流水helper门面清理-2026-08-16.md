# A3 PWA 账户流水 helper 门面清理交接快照

> 任务：PWA-069A 至 PWA-069B
>
> 状态：实现完成，待 PR 验证
>
> 基线：`48823c3`
>
> 分支：`feature/PWA流水helper门面清理`

## 已完成

- 用全量 PWA 源扫描固定“旧流水 helper 不得重新进入产品代码”的边界。
- 红灯准确命中 5 处旧实现，最小删除两个函数及 Store 出口后转绿。
- 专项和相关业务回归共 139 项、PWA build、治理、架构和 diff 检查通过。
- 数据库、iOS、Edge、Planner 与生产配置保持冻结。

## 未验证与剩余风险

- PR 远程 Release Validation 尚未运行。
- 数据库 direct create/void 的完整行为 fixture 仍缺失，但不属于本 PWA 门面清理片。
- iOS wallet 快照仍依赖 create primitive，A4 前不得撤销 authenticated 权限。
- A3 尚未完成阶段对账，不能直接进入 A4。

## 冻结范围

- 根工作区和其他 worktree WIP。
- 数据库 migrations/RPC/grants、iOS、Edge、Planner、生产配置和发布操作。
- 第一批 worktree 归档必须等 A3 收口审计列出精确清单；dirty 对象不进入归档。

## 下一步

1. 提交、推送并创建 PWA-069 实现 PR，等待全部远程门禁。
2. 合并后建立 A3 只读收口审计，不能直接宣称阶段完成。
3. 收口审计完成后按 C4 清单归档 clean 且已进入 main 的 worktree，仅移除 checkout，保留分支。
