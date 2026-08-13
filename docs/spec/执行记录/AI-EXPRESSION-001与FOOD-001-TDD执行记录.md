# AI-EXPRESSION-001 与 FOOD-001 TDD 执行记录

- 目标行为：Voice 自然表达不必复述 Planner 首选角度；Planner/Signal 事实不冒充主陪伴语；明确食品包装标签优先于小包装估算。
- 当前行为：Planner 语义门禁会淘汰未复述候选的 Voice 文案，规则 `emotion_line` 会回填 `companion_message`；明确 100g/1564kJ 标签会被小包装 20g 启发式覆盖。
- 权威来源：生成式 AI TDD 的“代码负责事实、模型负责表达”原则；食品记录的 Edge 标准化路径。
- 本轮范围：`supabase/functions/ingest-receipt/index.ts`、`signals.ts`、`voice-output_test.ts`，新增轻量 `food-nutrition.ts` 及测试。
- 非范围：生产历史数据回填、Prompt 两段式重构、Planner 排序、客户端 UI、数据库迁移、部署和 TestFlight。
- 基线测试结果：相关 Edge 测试可运行；Windows 不执行 Swift/Xcode。
- 红灯测试及失败原因：新增 `FOOD-001` 标签换算 fixture；更新 `EXP-011` 以证明 Planner 不应强制主文案复述。旧实现会将明确标签记录送入 20g 启发式，且 Voice 候选被 Planner 语义门禁拒绝。
- 最小实现：标签存在时跳过小包装缩放并按 `kJ / 4.184` 计算；只保留硬事实校验和必要的无证据历史比较门禁；Voice 优先，视觉文案仅在 Voice 失败且通过硬事实校验时 fallback；规则反馈只进入 `ai_feedback`。
- 绿灯结果：`food-nutrition_test.ts` 2/2；`voice-output_test.ts` 5/5；`signals_test.ts` 26/26；通知/提示词回归 19/19；`deno check --node-modules-dir=auto supabase/functions/ingest-receipt/index.ts` 通过；`git diff --check` 通过。
- PWA/iOS 差异：本轮只改 Edge 权威输出，PWA/iOS 无代码变更；两端将继续读取同一 `companion_message` 与 `ai_feedback` 契约。
- GitHub CI 结果：尚未推送，待用户确认后由 PR 门禁验证。
- 未解决风险：已有 `56 kcal` 历史记录不会自动回算；标签必须出现在模型结构化文本中才能命中；跨阶段双表面仍需后续专门切片完善。
- 对应提交：未提交。
