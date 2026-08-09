# EXP-002 TDD 执行记录

- 目标行为：允许自然的模糊钟点表达，拒绝与代码时间不一致的具体钟点，并优先保留句中其他有效内容。
- 当前行为：时间清洗只验证“下午、晚上、凌晨”等时段词；时段兼容时会原样保留错误钟点。
- 权威来源：`docs/spec/20-陪伴表达事实契约.md` 场景 `EXP-002`。
- 基线提交：`origin/main@6ae2d5c`，叠加本分支已完成的 `EXP-001` 本地改动。
- 工作树：`D:\Business\count\.worktrees\事实与表达正确性TDD`。
- 分支：`codex/事实与表达正确性TDD`。
- 本轮范围：自然钟点短语解析、语义区间校验、错误钟点局部降级和 Deno 测试。
- 非范围：时区国际化、餐次/活动推断、金额语言、跨记录关系、客户端和数据库迁移。
- 预计修改文件：表达事实 Spec、执行记录、`time-language.ts`、`time-language_test.ts`。
- 基线测试结果：`npx --yes deno test --no-lock supabase/functions/ingest-receipt/time_test.ts supabase/functions/ingest-receipt/time-language_test.ts`，10/10 通过。
- 红灯测试及失败原因：`npx --yes deno test --no-lock supabase/functions/ingest-receipt/time-language_test.ts`；7 项中 6 项通过、1 项按预期失败。`17:13` 的“下午快四点”被原样保留，证明当前实现只校验时段而不校验具体钟点语义。
- 最小实现：增加有限、可审计的中文/阿拉伯钟点短语解析器，按“快/将近、刚过、点多、半点左右、明确分钟”分别校验自然语义区间；不一致的具体钟点只替换为可信时段，保留句中其他内容。补录文案仅在同一短语中出现“补录、上传、现在才记录”等关系词时允许引用上传时间。
- 绿灯结果：`npx --yes deno test --no-lock supabase/functions/ingest-receipt/time_test.ts supabase/functions/ingest-receipt/time-language_test.ts`，15/15 通过。
- 本分支最终回归：Edge 相关 Deno 测试 85/85、Planner 全量 176/176、PWA 生产构建和 `git diff --check` 均通过。
- PWA/iOS 差异：时间文案在 Edge 持久化前统一清洗，客户端只展示结果，无需重复解析。
- GitHub CI 结果：PR #32 的 Release Validation（run `31314020801`）与 iOS Build（run `31314020808`）全部通过。
- 未解决风险：自然语言钟点无法穷举；本轮采用有限、可审计的高频短语语法，未识别表达继续由宽时段门禁处理。
- 对应提交：`1bc416e`。
