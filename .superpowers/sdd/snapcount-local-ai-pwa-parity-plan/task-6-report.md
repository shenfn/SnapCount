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
node_modules/.bin/esbuild supabase/functions/ingest-receipt/index.ts supabase/functions/ingest-receipt/local-expression-action.ts supabase/functions/ingest-receipt/context-packet.ts supabase/functions/ingest-receipt/expression-delivery.ts --bundle --platform=neutral --format=esm --external:'npm:*' --outdir="$EDGE_TMP"
```

Output:

```text
esbuild parse bundles: 4/4 passed (npm: imports externalized)
```

Deno-compatible Edge harness. Deno is unavailable in this environment (`zsh: command not found: deno`), so the three focused Edge test files were bundled with esbuild and executed under a Node harness that provides `Deno.test`.

```text
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
