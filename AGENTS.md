# Agent 工作区规则

## Git 与 worktree

- 开始工作前先运行 `git status --short --branch` 和 `git worktree list --porcelain`。
- 当前任务默认只在用户指定的 worktree 修改；不要进入根工作区清理或重置用户 WIP。
- 禁止未经明确授权执行 `git reset --hard`、`git checkout --`、`git clean -fd`、删除 refs、删除 worktree 或强推。
- 发现分支引用消失、worktree HEAD 为全零、索引异常或未知 Git 进程时，立即停止 Git 写操作并保留只读诊断。
- 不使用 `git add -A`；提交前逐一确认 staged 文件，避免把本地素材、备份和凭据带入。

## 发布边界

- iOS 视觉分支只修改 iOS 页面、设计系统和相关文档，不修改数据库迁移、Edge Function、Planner 算法或生产配置。
- 不执行生产迁移、生产部署或 TestFlight 上传，除非用户在当前任务中明确授权。
- TestFlight 只能从已通过 iOS Build/单测的固定提交手动触发。
- Windows 不能验证 Swift 编译；必须以 GitHub Actions 的 macOS iOS Build 结果为准。

## 设计系统

- Token 唯一来源是 `trae-design-system/tokens/design-tokens.json`。
- 运行 `trae-design-system/scripts/generate-*.mjs` 生成各端产物，不手改 `trae-design-system/dist/`。
- 新页面优先使用 `JieziType`、`JieziSpacing`、`JieziRadius`、`JieziCard`、`JieziSectionHeader`、`JieziListRow`、`JieziMetric` 和 `JieziEmptyState`。
- 视觉改动必须保留 AppState、Repository、导航、保存、删除和确认门禁逻辑。

## Spec 与 TDD

- 核心业务状态、金额、时间、权限、幂等、账户影响、删除级联或跨端契约变更，开始前必须阅读对应中文 Spec 和 `docs/spec/02-TDD实施与交接规范.md`。
- 没有场景编号、范围说明和测试层映射，不开始业务实现；实际改动超出预先说明的模块时，先暂停并重新确认范围。
- 已有行为先用特征测试固定；新增或修复行为按红灯、最小实现、绿灯和回归顺序执行，不把环境失败当作业务红灯。
- PWA 与 iOS 使用同一场景编号验证共享业务含义；iOS 最终结果仍以 GitHub macOS CI 为准。
- 生成式 AI 测试固定事实、候选、证据和语义边界，不把某一句模型文案写成唯一正确答案。

## 文档入口

- 产品方向与原型入口：`docs/product/`（总 PRD、原型总览、工程实施与验收规范）。
- 规格入口：`docs/spec/规格文档索引.md`。
- 当前阶段与任务：`docs/spec/03-阶段与任务索引.md`。
- 架构治理与恢复流程：`docs/spec/04-架构治理与进度保护规范.md`。
- 清洗与架构总计划：`docs/spec/05-仓库清洗与架构收拢实施计划.md`。
- 设计决策：`docs/decisions/` 下相关 ADR。
- 任务接续：`docs/handoff/` 下对应交接快照。
- 如果入口文件缺失或状态互相矛盾，先报告缺失和冲突，不凭聊天记忆猜测当前阶段。

详细流程、提交格式、CI/CD 触发规则和异常恢复方式见：

- `docs/ios-视觉美化交接.md`
- `docs/spec/02-TDD实施与交接规范.md`

## 产品设计与开发总方向

- 本地优先的目标是：在隐私边界成立的基础上，让用户获得完整的核心功能体验；本地化不应以功能缩水为代价，并为后续商业化打基础。
- 先完成产品范围和第一期高还原原型，再进入功能开发。原型是体验、页面结构、操作路径和状态展示的验收基准；Spec 定义业务规则，测试验证实现稳定性。
- 流程保持精简：产品总 PRD → 原型总览与阶段原型 → 必要的域级 Spec/技术方案 → TDD 开发 → 原型对照验收、功能验收和发布验收。只在确有架构决策时新增 ADR，不为普通细节堆叠文档。
- 先完成一个完整的本地核心样板域，再推进其他数据域；未完成原型和验收边界的域不进入开发。图片、导入导出、离线、重启、登录绑定和数据生命周期属于本地化完整体验的一部分。
- `D:\Business\count` 是长期主工作区。收拢前先审计分支、未提交改动和归属，保护根工作区 WIP，逐个处理已合并或废弃 worktree，最多保留必要的短期隔离 worktree，不批量清理。
