# Task 4 report — Hosted/BYOK provider parity

## Status

Implemented and self-reviewed the shared client-side provider result boundary for Hosted and BYOK local Companion generation.

## Contract delivered

- Added `LocalCompanionResultNormalizer` as the shared internal normalizer used by both `HostedAICompanionProvider` and `QwenBYOKCompanionProvider`.
- Both providers now produce the same `feedback-v1` key set and the same defaults for domain, band, icon, badge, tone, confidence score, and source.
- Empty companion text becomes `nil`, and null or absent feedback remains `nil`. A result with neither output is valid and is not persisted.
- Feedback confidence is parsed from numeric or numeric-string values, clamped to `0...1`, and omitted below `0.5`.
- Malformed feedback objects and malformed typed fields are rejected as `QwenBYOKError.invalidResponse` at both provider boundaries.
- Band validation, icon/badge caps, line caps, newline normalization, and exact recent-line de-duplication are shared across providers.
- Persistence still receives only `LocalCompanionResult`, so raw provider responses are not stored.

## TDD evidence

### RED

Before the implementation, the focused XCTest target failed to compile with the seam tests. The exact failures were `Cannot find 'LocalCompanionResultNormalizer' in scope`, async XCTest autoclosure errors, and the resulting type inference error for the new normalizer assertions.

Command:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalBYOKProviderTests test
```

### GREEN

After implementation and test fixes:

```text
Test Suite 'LocalBYOKProviderTests' passed
Executed 15 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

Focused target command:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalBYOKProviderTests test
```

Additional check:

```text
git diff --check
```

completed with no output and exit status 0.

## Tests added

The public provider seam tests cover Hosted and BYOK valid output, null feedback, low confidence, malformed feedback, empty companion handling, exact companion/emotion de-duplication, length and band normalization, and identical normalized feedback schema keys.
