# Task 1 report — contract and evidence model

## Delivered

- Added `local-expression-contract.ts` with bounded evidence references, number provenance, canonical FNV-1a 64-bit claim fingerprints, and deterministic rejection reasons.
- Added Edge contract tests for current-fact evidence, memory-only evidence, stable fingerprints, current-fact number leakage, and unsupported evidence fallback.
- Propagated evidence and per-number provenance through Planner briefs and context packets. Planner candidates without explicit evidence no longer reach a provider.
- Added Swift-side evidence parsing and fingerprint validation. Hosted/BYOK planner payloads attach amount provenance only to `current_fact` candidates. Memory candidates send no current-fact numbers.
- Kept `occurred_at`, `order_finished_at`, and `client_captured_at` in the payload contract and documented their event-versus-capture semantics.
- Added the scenario mapping note at `docs/spec/执行记录/LOCAL-AI-003-ContractEvidence-TDD.md`.

## TDD RED / GREEN

### RED

Command

```text
deno test --no-check supabase/functions/ingest-receipt/local-expression-contract_test.ts
```

Output

```text
zsh:1: command not found: deno
```

The repository environment has no Deno CLI. The tests were still authored against the public Deno seam before implementation and executed through the available Node/esbuild harness.

### GREEN

Command

```text
node_modules/.bin/esbuild supabase/functions/ingest-receipt/local-expression-contract_test.ts --bundle --format=esm --platform=node --outfile=/tmp/local-expression-contract_test.mjs
node --input-type=module -e 'globalThis.Deno={test:(name,fn)=>Promise.resolve(fn()).then(()=>console.log("ok",name)).catch((error)=>{console.error(error);process.exitCode=1})}; await import("file:///tmp/local-expression-contract_test.mjs")'
```

Output

```text
ok local candidate contract fingerprints claims and validates current-fact evidence
ok memory candidate cannot inherit current-fact number provenance
ok unsupported evidence returns deterministic fallback reason
```

Command

```text
node_modules/.bin/esbuild supabase/functions/ingest-receipt/context-packet_test.ts --bundle --format=esm --platform=node --outfile=/tmp/context-packet_test.mjs
node --input-type=module -e '...Deno test harness...'
```

Output

```text
tests=20 failures=0
```

Command

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalExpressionContextTests test
```

Output

```text
Executed 5 tests, with 0 failures
** TEST SUCCEEDED **
```

The fixed cross-client fingerprint assertion is `fnv1a64:510d871ebff57f0f` for the Swift and Edge claim `local_expense_current_fact / 这笔便利店消费已记录，金额为¥12.80。`.

## Commit

`1edc21b feat(local-ai): add evidence-bound planner contract`, followed by a small TypeScript provenance typing fix in the final worktree commit.

## Concerns

- Deno-native execution and `deno check` remain unavailable in this environment. Edge TypeScript files were syntax-bundled with esbuild, and contract/context tests ran through a Deno-compatible Node harness.
- The branch retains unrelated pre-existing WIP in `AppState.swift`, intake UI files, `SnapCountUploadService.swift`, and `NativeAIFeedbackCard.swift`, plus untracked `.build/` and `tools/persona-lab/`. They were not staged or reset.
