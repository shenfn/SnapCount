# EXP-007 TDD 执行记录

- 目标行为：代码根据时间、对象、域转换和事件顺序计算跨记录关系候选，模型只负责是否表达与如何自然表达。
- 当前行为：Expense 与各数据域 Planner 只读取本域历史，没有通用跨记录关系候选，也没有强关系和仅时间接近反例的确定性测试。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 场景 `EXP-007`。
- 基线提交：`origin/main@6c7fe7d`。
- 工作树：`D:\Business\count\.worktrees\跨记录关联与中转站收口TDD`。
- 分支：`codex/跨记录关联与中转站收口TDD`。
- 本轮范围：关系候选纯逻辑、Planner 集成、近期跨域来源装配和对应测试。
- 非范围：国际时区、用户可回答的关系确认交互、长期关系记忆和生产历史回填。
- 预计红灯：饺子外卖支出后出现饺子饮食记录时没有候选；只有时间接近的无关记录也没有明确反例契约。
- 红灯结果：`node --test tools/ai-validation/expression-planner/tests/cross-record-relationship.test.mjs` 在模块不存在时按预期失败。
- 最小实现：新增 `cross-record-relationships.mjs`，并在 Edge Shadow/Delivery 的三类 Planner 输入装配同一用户近期三张业务表的脱敏关系来源；候选只在事件时间、对象重合和合理顺序同时成立时生成。
- 绿灯结果：关系纯逻辑 4/4 通过；对象重合、仅时间接近、缺少事件时间和未来才被写入的记录均有边界测试；新增 Planner/Edge 装配静态契约通过。Node Planner 全量中可运行的 103 项通过。
- 环境限制：完整 Planner 集成集合中 5 项因工作树未安装 `esbuild` 而无法启动；Deno 未安装，Edge 测试需 GitHub CI。
- GitHub CI 结果：待提交后执行。
