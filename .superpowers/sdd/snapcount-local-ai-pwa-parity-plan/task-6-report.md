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

## Final-review fix wave

Implementation commit: `df50f3c` (`fix(local-ai): align planner packet contract and notification merge`). This wave is local-only: no push, no deploy, no migration, no TestFlight.

### Critical 1 — Hosted planner packet omitted `canonical_text`

- Changed `HostedAICompanionProvider.plannerPayload` to emit `canonical_text = candidate.emotionLine` on the wire (`ios/SnapCount/LocalData/LocalCompanionComposition.swift:89-101`, assignment at `:98`). The persisted `localPayload` shape is unchanged, and the value is byte-identical to `emotion_line`, so the Swift and Edge fingerprints agree.
- Added contract assertions to the Hosted round-trip test: `canonical_text` is non-empty, equals `emotion_line`, its recomputed fingerprint equals `claim_fingerprint`, every evidence reference resolves to the current fact or a supplied memory key, and `number_facts`/`numbers` equal `12.8` (`ios/SnapCountTests/LocalAIIntegrationRegressionTests.swift:63-91`). It also runs the full Edge mirror validator.
- The test fails if the key is merely present but empty or re-worded, because it compares against the actual `emotion_line` and recomputes the fingerprint.

### Important 2 — Cross-record candidates were unreachable and contract-invalid

- Added `LocalPlannerCandidateEngine.maxCandidateEvidence = 8` and deterministic prioritization: current fact first, then at most 7 supplied recent facts (`ios/SnapCount/LocalData/LocalExpressionContext.swift:217,382-427`).
- Candidate evidence now uses the same field as its number provenance (`amount` for amount-bearing facts, otherwise `record`) via `evidenceField(for:)` (`:430-437,463-467`). Repeat candidates therefore satisfy `number_evidence_not_in_candidate`.
- Continuity no longer emits a derived count number fact: Edge's `numericFieldValue` cannot resolve a count to a single fact field, so the candidate carries no numbers instead of an unresolvable count (`:413-426`).
- Added a test that enumerates every produced candidate type (current, repeat, continuity, memory) and asserts evidence/number bounds plus full Edge-mirror validation (`ios/SnapCountTests/LocalExpressionContextTests.swift:156-214`). The mirror is labelled test-only and kept next to the Swift suite (`ios/SnapCountTests/LocalAIIntegrationRegressionTests.swift:279+`).
- Added the required comment at `selectedCandidate`: only current and high-confidence memory are selectable; repeat/continuity stay internal until a product decision (`ios/SnapCount/LocalData/LocalExpressionContext.swift:487-492`).
- Updated the existing repeat test to the new evidence bound (7 recent references) and continuity test to assert no derived count numbers.

### Important 3 + 10 — Notification composition merged twice / omitted Companion

- Archived Shortcut outcomes now use one composition path: `ShortcutUploadResult.archived(notificationText:companionMessage:feedback:)` merges once and reuses the same string for `displayText` and `notificationText` (`ios/SnapCount/Services/SnapCountUploadService.swift:335-351`; called at `ios/SnapCount/Intents/UploadScreenshotIntent.swift:123-127`).
- `ShortcutUploadResult.init(payload:)` now merges once instead of merging then re-merging (`ios/SnapCount/Services/SnapCountUploadService.swift:316-331`).
- Added an archived-outcome notification test: the body contains the companion line and the fixed amount/today facts and stays within 160 characters (`ios/SnapCountTests/LocalAIIntegrationRegressionTests.swift:218-240`). The idempotent payload test also asserts `displayText == notificationText` (`:199`).

### Important 4 — Integration test only asserted presence

- The Hosted round-trip now validates the captured packet with the same rules as Edge: identity, fingerprint, evidence support, numeric provenance, and value equality (`ios/SnapCountTests/LocalAIIntegrationRegressionTests.swift:63-91`).
- Added `EdgePlannerValidatorMirror`, a clearly labelled test-only mirror of `validateLocalPlannerCandidate` (`ios/SnapCountTests/LocalAIIntegrationRegressionTests.swift:279+`), including numeric field resolution through `payload_json`/`payload`.
- Added a cross-end golden fixture: `{"local_expense_current_fact", "这笔便利店消费已记录，金额为¥12.80。"} → fnv1a64:510d871ebff57f0f` is asserted in Swift (`ios/SnapCountTests/LocalExpressionContextTests.swift:146-154`) and in Edge (`supabase/functions/ingest-receipt/local-expression-contract_test.ts`, "cross-end golden fingerprint...").

### Important 5 — Timezone-dependent assertion

- Threaded an injectable `TimeZone` through `LocalPlannerCandidateEngine.makeContext` and `localTimeContext` (`ios/SnapCount/LocalData/LocalExpressionContext.swift:219-232,533-552`) and through `LocalExpressionPersistence.makeCompositionContext` (`ios/SnapCount/LocalData/LocalExpressionPersistence.swift:376-383,416`). Production defaults remain `.current`, so behavior is unchanged.
- The Hosted round-trip test uses a fixed `Asia/Shanghai` zone (`ios/SnapCountTests/LocalAIIntegrationRegressionTests.swift:25-32`).
- Proved with host `TZ=UTC` and `TZ=Asia/Shanghai`; both runs pass (outputs below).

### Important 6 — Spec 3.3 described a packet the code did not send

- Rewrote section 3.3 of `docs/spec/模块/iOS本地优先/本地AI陪伴与Planner候选域规格说明.md` to the actual Hosted wire projection: `action`, `current_fact`, single `planner_candidate`, optional `local_memory_context`, preferences, and time fields; `recent_facts`/`provider_mode` are explicitly local/Edge routing metadata and are not sent. Stated that `canonical_text` is required and equals the candidate's `emotion_line`. The LOCAL-AI-003 numbering is untouched. Also corrected the BYOK bullet in 4.2 to the singular candidate.

### Cheap minors

- 7: Replaced the four `catch ... { XCTAssertTrue(true) }` blocks with `catch let error as QwenBYOKError { XCTAssertEqual(error, .invalidResponse) }` (`ios/SnapCountTests/LocalBYOKProviderTests.swift:44-46,82-84,100-102,112-114`). An unexpected error now fails instead of passing.
- 8: Set `head: df50f3c` and reconciled every validation count/status line in `docs/handoff/2026-11-10-本地AI记忆与Planner阶段一开发交接.md` (focused 5/5, full 657/657, Edge 37/37, bundle parse 4/4, Deno unavailable).
- 9: Removed the hand-written `==` from `LocalImageIntakeOutcome`; synthesized `Equatable` now includes `feedbackConfidence` (`ios/SnapCount/LocalData/LocalImageRecognition.swift:154-165`). The two dedup tests now assert stable fields and the intentional `nil` confidence on the persisted replay path (`ios/SnapCountTests/LocalImageRecognitionTests.swift:25-33,73-81`).
- 10: Covered by the single-merge change above.

### Deliberately not addressed (Task 7 / later slices)

- Wallet snapshots appearing in every `LocalFactReader.range()` consumer (`LocalInsightAggregator.hasAnyData`, portability exports) still needs device/export confirmation.
- The result sheet can still show two different feedback angles (base recognition feedback plus Companion feedback card); product judgement.
- `expression-shadow-planner.ts` rewriting `numbers` into number-fact objects in persisted plans; existing consumers tolerate it.
- `LocalExpressionContract.validates` remains a test-only smoke check without number provenance; it is now documented honestly at `ios/SnapCount/LocalData/LocalExpressionContext.swift:26-31`.
- Task 7 device acceptance remains open: real-device Shortcut, Hosted/BYOK on-device comparison, TestFlight, and phone screenshots.

### Verification

Focused suite (integration + expression context + BYOK):

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalAIIntegrationRegressionTests -only-testing:SnapCountTests/LocalExpressionContextTests -only-testing:SnapCountTests/LocalBYOKProviderTests test CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-disable-sandbox'
```

Output:

```text
Executed 34 tests, with 0 failures (0 unexpected) in 1.444 (1.469) seconds
** TEST SUCCEEDED **
```

`-disable-sandbox` is required on this machine; without it the build fails with the known `SwiftUIMacros.StateMacro ... malformed response` error.

Timezone proof:

```text
TZ=UTC xcodebuild ... -only-testing:SnapCountTests/LocalAIIntegrationRegressionTests test CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-disable-sandbox'
TZ=Asia/Shanghai xcodebuild ... -only-testing:SnapCountTests/LocalAIIntegrationRegressionTests test CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-disable-sandbox'
```

Output:

```text
TZ=UTC:            Executed 5 tests, with 0 failures (0 unexpected) in 0.593 (0.599) seconds — ** TEST SUCCEEDED **
TZ=Asia/Shanghai:  Executed 5 tests, with 0 failures (0 unexpected) in 0.745 (0.758) seconds — ** TEST SUCCEEDED **
```

Full simulator XCTest:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-disable-sandbox'
```

Output:

```text
Executed 657 tests, with 0 failures (0 unexpected) in 72.789 (72.911) seconds
** TEST SUCCEEDED **
```

Edge bundle parse:

```text
esbuild parse bundles: 4/4 passed (npm: imports externalized)
```

Edge Node Deno-compatible harness (now includes the cross-end golden fingerprint test):

```text
Edge Node Deno-compatible harness: 37/37 passed
```

Static check:

```text
git diff --check
```

Completed with no output and exit status 0.
