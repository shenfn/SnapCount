# Task 6 report — integration regression and contract documentation

## Status

Implemented and self-reviewed the public-seam integration regression coverage and updated the LOCAL-AI-003 authority with the final packet contract and LOCAL-AI-003A-K acceptance matrix.

## Delivered

- Added `LocalAIIntegrationRegressionTests.swift` with four public-seam tests covering the Hosted request/response packet, normalized result persistence, memory-off request omission, provider failure with deterministic fallback preservation, formal-fact/staging separation, confirmation retry idempotence, Shortcut notification/result-sheet de-duplication, and AppState route idempotence.
- Updated `docs/spec/模块/iOS本地优先/本地AI陪伴与Planner候选域规格说明.md` with the final current/recent/memory/planner/provider packet, evidence kinds and sources, per-number provenance, stable fingerprint, limits, event/capture time semantics, fail-closed fallback reasons, Hosted/BYOK normalized result schema, notification/result-sheet rules, and the A-K matrix.
- Preserved the untracked `.build/`, `prototype/settings-variants.html`, and `tools/persona-lab/` worktree items.

## TDD RED

The new public-seam test was run with an intentionally incorrect action expectation before the green run:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalAIIntegrationRegressionTests/testHostedLocalExpressionRoundTripPersistsTheBoundedPacket test CODE_SIGNING_ALLOWED=NO
```

Output included:

```text
XCTAssertEqual failed: ("Optional(\"generate_local_expression\")") is not equal to ("Optional(\"generate_local_expression_missing\")")
** TEST FAILED **
```

## TDD GREEN

Focused integration XCTest:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalAIIntegrationRegressionTests test CODE_SIGNING_ALLOWED=NO
```

Output:

```text
Executed 4 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

Full simulator XCTest:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
```

Output:

```text
Executed 654 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

Edge parse checks:

```text
EDGE_TMP="$(mktemp -d /tmp/snapcount-edge-parse-task6.XXXXXX)"
for entry in supabase/functions/ingest-receipt/index.ts supabase/functions/ingest-receipt/local-expression-action.ts supabase/functions/ingest-receipt/context-packet.ts supabase/functions/ingest-receipt/expression-delivery.ts; do
  name="$(basename "$entry" .ts)"
  node_modules/.bin/esbuild "$entry" --bundle --platform=neutral --format=esm --external:'npm:*' --outfile="${EDGE_TMP}/${name}.js" >/dev/null
done
printf 'esbuild parse bundles: 4/4 passed (npm: imports externalized)\n'
```

Output:

```text
esbuild parse bundles: 4/4 passed (npm: imports externalized)
```

Deno-compatible Edge harness. Deno is unavailable in this environment (`zsh: command not found: deno`), so the three focused Edge test files were bundled with esbuild and executed under a Node harness that provides `Deno.test`.

```text
EDGE_TMP="$(mktemp -d /tmp/snapcount-edge-task6.XXXXXX)"
for test_file in local-expression-contract_test local-expression-action_test context-packet_test; do
  node_modules/.bin/esbuild "supabase/functions/ingest-receipt/${test_file}.ts" --bundle --platform=node --format=cjs --outfile="${EDGE_TMP}/${test_file}.cjs" >/dev/null
done
EDGE_TMP="$EDGE_TMP" node --input-type=module <<'NODE'
import { readdirSync } from 'node:fs';
import { join } from 'node:path';
const root = process.env.EDGE_TMP;
let passed = 0;
let total = 0;
for (const file of readdirSync(root).filter((name) => name.endsWith('.cjs'))) {
  const tests = [];
  globalThis.Deno = { test(name, fn) { tests.push({ name, fn }); } };
  await import(`file://${join(root, file)}?${Date.now()}-${file}`);
  for (const test of tests) { await test.fn(); passed += 1; total += 1; }
}
console.log(`Edge Node Deno-compatible harness: ${passed}/${total} passed`);
NODE

Edge Node Deno-compatible harness: 36/36 passed
```

Static check:

```text
git diff --check
```

Completed with no output and exit status 0.

## Concerns

- The full simulator run emitted existing iOS simulator accessibility duplicate-class and API handler warnings. No test failed.
- Real-device Shortcut acceptance, TestFlight processing, production deployment, and phone screenshot gates remain Task 7 scope.

## Round 1 fixes

- Strengthened the staging exclusion assertion to require the formal sport fact title set to exactly `["正式运动"]` and explicitly reject the staged title `"待确认运动"`. This would fail if a staging row leaked into the `LocalFactReader` projection.
- Updated the existing handoff `docs/handoff/2026-11-10-本地AI记忆与Planner阶段一开发交接.md` with the final packet contract, A-K matrix, and current Task 6 validation state.

Focused regression after the fixes:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalAIIntegrationRegressionTests test CODE_SIGNING_ALLOWED=NO
```

Output:

```text
Executed 4 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

`git diff --check` completed with no output and exit status 0 after the fixes.

## Round 2 handoff reconciliation

Updated the existing handoff frontmatter to `head: cdc201f` and replaced the stale `6/6`, `27/27`, and `deno check passed` claims with the authoritative Task 6 state. The handoff now records focused XCTest 4/4, full XCTest 654/654, Edge bundle parse 4/4, Node Deno-compatible Edge harness 36/36, and Deno CLI unavailable.

Exact documentation and diff check:

```text
git diff --check
git diff --check: passed (no output)
```

```text
6:head: cdc201f
7:status: Task 6 集成回归与最终 packet 合同已完成，等待 Task 7 真机门禁
133:- 当前 Task 6 authoritative validation：iPhone 17 / iOS Simulator focused integration XCTest 4/4 通过；全量 XCTest 654/654 通过。
134:- 当前 Edge validation：esbuild bundle parse 4/4 通过；Node Deno-compatible harness 36/36 通过。
135:- Deno CLI 当前不可用，原生命令返回 `zsh: command not found: deno`；不要将当前状态描述为 `deno check` 已通过。
174:- `xcodebuild ... -only-testing:SnapCountTests/LocalAIIntegrationRegressionTests test CODE_SIGNING_ALLOWED=NO`：4/4 通过。
175:- 全量 iOS Simulator XCTest：654/654 通过。
176:- esbuild + Node Deno-compatible Edge harness：36/36 通过；4 个 Edge bundle parse 通过。
```
