# LOCAL-AI-003 Contract / Evidence TDD

## 范围

本片固定 Hosted、BYOK 和确定性降级共用的候选证据合同。当前记录、近期记录和本机记忆分别使用 `current_fact`、`recent_fact`、`local_memory` evidence kind，并明确 `local_record` 或 `local_memory` source。候选必须带 `evidence`，每个 `number_fact` 也必须带自己的 evidence 引用。

`claim_fingerprint` 对 `{semantic_key, canonical_text}` 做稳定 FNV-1a 64 位指纹。Swift 和 Edge 使用相同键排序与 UTF-8 规则独立计算。当前事实的金额只能附着 `current_fact` number provenance。memory candidate 不携带当前事实金额，记忆中的数字后续必须引用自己的 bounded memory key。

## 时间字段

`occurred_at` 和 `order_finished_at` 描述事件语义时间，`record_date` / `record_time` 是结构化兼容字段，`client_captured_at` 只描述客户端捕获或请求上下文时间。Provider 不得把 `client_captured_at` 写成事件发生时间。

## 场景映射

| 场景 | 合同验收 |
| --- | --- |
| LOCAL-AI-003A/B/C | 当前或近期正式事实有可追溯 evidence，候选指纹可独立复算 |
| LOCAL-AI-003D | staging 不作为正式 Planner evidence |
| LOCAL-AI-003F/K | 记忆候选只引用有界 `local_memory` key，关闭记忆时不产生 memory evidence |
| LOCAL-AI-003G | claim 指纹、证据或数值 provenance 不通过时丢弃候选并使用确定性 fallback |

## TDD 记录

- RED：`deno test --no-check supabase/functions/ingest-receipt/local-expression-contract_test.ts`。当前环境没有 Deno CLI，命令返回 `zsh: command not found: deno`。
- RED/编译修正：首次 XCTest 编译暴露 Swift `composed` 作用域和 `NSNull` 三元表达式错误，修正后继续验证。
- GREEN：`node_modules/.bin/esbuild ... --bundle` 解析 Edge 合同、context packet、planner、delivery、index 均通过。
- GREEN：临时 Node Deno harness 执行合同测试 3/3 和 context packet 测试 20/20 通过。
- GREEN：`xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalExpressionContextTests test`，5/5 通过。

## Task 3 Hosted action hardening addendum（2026-11-14）

- Hosted `generate_local_expression` now normalizes the complete read-only packet before Voice. The public candidate contract sees unfiltered evidence and numeric arrays, while invalid candidates are discarded as a unit.
- A rejected candidate selects current-fact-only generation and records the deterministic contract reason in the context trace and action result. Its canonical text, numbers, evidence, fingerprint, and memory-derived claim do not enter Voice.
- Local memory is re-normalized at the Edge boundary to same-domain keys, compact summaries, confidence bounds, and an eight-item limit. An explicit disabled or empty context becomes no memory context.
- Event time uses valid `occurred_at`, then `order_finished_at`, then `record_date` / `record_time`; invalid or absent event timestamps fall back to capture/reference context without relabeling capture time as event time.
- Task 3 focused tests cover valid current/recent/memory candidates, forged fingerprint/evidence, number provenance and array failures, invalid event timestamp fallback, and traceable current-fact-only fallback. The esbuild + Node Deno-compatible harness passes 8/8.
