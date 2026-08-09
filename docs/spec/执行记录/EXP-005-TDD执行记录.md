# EXP-005 TDD 执行记录

- 目标行为：所有可展示 Planner 候选都带有可追溯、非思维链的判断依据，单条候选不再返回空依据。
- 当前行为：Planner 仅在 `sample_count > 1` 时生成 `detail_reason`；首次记录等单记录候选固定为空。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 场景 `EXP-005`。
- 基线提交：`origin/main@6ae2d5c`，叠加本分支已完成的 `EXP-001` 至 `EXP-004` 本地改动。
- 工作树：`D:\Business\count\.worktrees\事实与表达正确性TDD`。
- 分支：`codex/事实与表达正确性TDD`。
- 本轮范围：Planner 记录详情反馈的证据摘要、下发快照一致性和 Node 集成测试。
- 非范围：模型思维过程、客户端自行生成依据、跨记录关系候选、页面视觉重构和数据库迁移。
- 预计修改文件：表达事实 Spec、执行记录、`expression-delivery.ts` 与 Planner 下发测试。
- 基线测试结果：`node --test tools/ai-validation/expression-planner/tests/expression-delivery.test.mjs`，25/25 通过。
- 红灯测试及失败原因：`node --test tools/ai-validation/expression-planner/tests/expression-delivery.test.mjs`；25 项中 24 项通过、1 项按预期失败。首次商户候选的预览反馈 `detail_reason` 为 `""`，无法说明候选来自当前记录和可用商户历史。
- 最小实现：Planner 下发按候选语义生成确定性证据摘要；首次出现引用当前记录与可用商户历史，间隔/复现引用上一条同类记录，多样本候选保留样本数，其他候选回落到当前已核实字段或可追溯证据数量。预览和确认均从冻结下发快照读取同一摘要。
- 绿灯结果：`node --test tools/ai-validation/expression-planner/tests/expression-delivery.test.mjs`，25/25 通过。
- 本分支最终回归：Edge 相关 Deno 测试 85/85、Planner 全量 176/176、PWA 生产构建和 `git diff --check` 均通过。
- PWA/iOS 差异：服务端统一生成依据；iOS 另用客户端场景保护异步反馈槽，PWA 只消费字段。
- GitHub CI 结果：PR #32 的 Release Validation（run `31314020801`）与 iOS Build（run `31314020808`）全部通过。
- 未解决风险：未知新候选会使用通用可追溯依据，后续新增高价值语义时应补充更具体映射。
- 对应提交：`1bc416e`。
