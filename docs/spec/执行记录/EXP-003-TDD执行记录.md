# EXP-003 TDD 执行记录

- 目标行为：中午等时间维度不能单独授权“午餐、吃饭、趁热吃”等活动断言；存在独立餐饮对象证据时保持模型表达自由。
- 当前行为：`validateModelTone` 只校验数字和统计口径，任何与时段兼容的餐次扩写都会通过。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 场景 `EXP-003`。
- 基线提交：`origin/main@6ae2d5c`，叠加本分支已完成的 `EXP-001`、`EXP-002` 本地改动。
- 工作树：`D:\Business\count\.worktrees\事实与表达正确性TDD`。
- 分支：`codex/事实与表达正确性TDD`。
- 本轮范围：记录对象事实白名单、餐次/进食断言的确定性证据门禁、逐字段 Deno 测试。
- 非范围：商户黑名单、固定文案、用时间直接推断餐次、受益人推断、跨记录关系、客户端布局和数据库迁移。
- 预计修改文件：表达事实 Spec、执行记录、`signals.ts`、`signals_test.ts`，以及向 Voice 事实白名单补齐现有识别字段的装配代码。
- 基线测试结果：`npx --yes deno test --no-lock supabase/functions/ingest-receipt/signals_test.ts`，20/20 通过。
- 红灯测试及失败原因：`npx --yes deno test --no-lock supabase/functions/ingest-receipt/signals_test.ts`；22 项中 21 项通过、1 项按预期失败。普通生活支出只有中午时段证据时，“好好吃饭”和“这顿午餐记得趁热吃”均被原样放行，证明现有门禁没有区分时间与活动事实。
- 最小实现：在 `validateModelTone` 增加有限餐次/进食断言识别，并只接受饮食记录类型、餐饮分类、`food_photo`、结构化餐次/菜品或饮食信号作为独立证据；Voice 财务事实白名单补充现有 `domain_key`、`image_type` 和结构化 `payload`，不使用商户黑名单。
- 绿灯结果：`npx --yes deno test --no-lock supabase/functions/ingest-receipt/signals_test.ts`，22/22 通过。
- 本分支最终回归：Edge 相关 Deno 测试 85/85、Planner 全量 176/176、PWA 生产构建和 `git diff --check` 均通过。
- PWA/iOS 差异：事实门禁在 Edge 持久化前统一执行，客户端不重复计算。
- GitHub CI 结果：未运行。
- 未解决风险：餐饮语义词和识别字段采用有限白名单；新增对象类型需显式扩充并补回归测试。
- 对应提交：随本次 PR 提交。
