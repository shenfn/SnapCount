# Task 5 report — delivery surface alignment

## Status

Implemented and self-reviewed the shared local intake delivery composition for AppState, Shortcut, notification bodies, expanded Shortcut display text, and the in-app result sheet.

## Delivered

- Added `LocalIntakeNotificationFeedback` as the provider-independent normalized feedback seam.
- Centralized companion-first precedence, fixed fact retention, confidence fallback, exact-line de-duplication, line compaction, and the 160-character notification budget in `LocalIntakeNotificationText`.
- AppState and Shortcut now call the same `LocalIntakeNotificationText.merge` seam.
- Removed Shortcut's duplicate trimming, parsing, merge, and clipping implementations.
- Kept pending, archived, failure, amount, merchant, category, source, and summary wording from the fixed base text.
- Kept the result sheet's composed notification block and feedback card together. The first visible message is passed to `NativeAIFeedbackCard` so a repeated emotion line is suppressed.
- Updated the existing Shortcut contract assertion to match the shared companion-first output.

## TDD RED

Command run before the shared seam implementation:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalIntakeNotificationTextTests test CODE_SIGNING_ALLOWED=NO
```

Output included:

```text
Cannot find 'LocalIntakeNotificationFeedback' in scope
Extra arguments at positions #2, #3 in call
Cannot convert value of type 'String' to expected argument type 'LocalIntakeNotificationInput'
Testing cancelled because the build failed.
```

The new public seam tests therefore failed to compile before implementation.

## TDD GREEN

Focused composition and Shortcut coverage:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalIntakeNotificationTextTests -only-testing:SnapCountTests/SnapCountTests/testShortcutNotificationPrependsCompanionWhenServerOnlyReturnsReceiptFacts -only-testing:SnapCountTests/SnapCountTests/testShortcutNotificationUsesFeedbackEmotionWhenCompanionIsMissing test CODE_SIGNING_ALLOWED=NO
```

Output:

```text
Executed 17 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

Full iOS simulator XCTest:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
```

Result from the generated xcresult summary:

```text
passedTests: 647
failedTests: 0
skippedTests: 0
result: Passed
```

Static check:

```text
git diff --check
```

Completed with no output and exit status 0.

## Concerns

- Full tests emitted existing simulator accessibility duplicate-class and API handler runtime warnings. No test failed.
- Untracked `.build/` and `tools/persona-lab/` were preserved and are not part of the commit.


## Reviewer round 1/5 fixes

The reviewer identified three delivery-boundary regressions and they were corrected.

- `LocalIntakeResultPresentation.primaryMessage` now returns a primary line only when the exact feedback emotion line appears in the composed notification block. Badge and companion lines no longer suppress or duplicate the card emotion.
- `LocalImageIntakeOutcome` carries the source feedback confidence through recognition and AppState. AppState filters confidence below `0.5` before returning feedback or composing the delivery text, while retaining the fixed receipt facts.
- Shortcut archived and pending delivery now uses the normalized Hosted/BYOK Companion feedback when a composed result exists. It falls back to the recognition outcome only when no composed result exists, and low-confidence outcome feedback is filtered before Shortcut display.

Covering focused XCTest command:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalIntakeNotificationTextTests test CODE_SIGNING_ALLOWED=NO
```

Output:

```text
Executed 18 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

Covering recognition and delivery regression command:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SnapCountTests/LocalImageRecognitionTests -only-testing:SnapCountTests/LocalIntakeNotificationTextTests test CODE_SIGNING_ALLOWED=NO
```

Result from the generated xcresult summary:

```text
passedTests: 41
failedTests: 0
skippedTests: 0
result: Passed
```

`git diff --check` passed after the fixes.

Full simulator regression after reviewer fixes:

```text
xcodebuild -project ios/SnapCount.xcodeproj -scheme SnapCount -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
```

Output:

```text
Executed 650 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```
