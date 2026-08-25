# Library Row Metadata Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display automatic Audio titles as localized date and time only, and standardize compact library-row metadata as duration, short date, and synthesized status.

**Architecture:** `AudioItem.displayTitle(locale:timeZone:)` remains the sole automatic-title formatter and continues to return a custom title unchanged. `LibraryAudioRow` owns only presentation order, using the locale passed by `RootView`; it does not derive titles, statuses, or dates itself.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, XCUITest.

---

### Task 1: Remove the automatic title prefix

**Files:**
- Modify: `apps/ios/AIRecorder/Persistence/AudioItem.swift`
- Modify: `apps/ios/AIRecorder/Resources/Localizable.xcstrings`
- Test: `apps/ios/AIRecorderTests/Persistence/AudioRepositoryTests.swift`

- [ ] **Step 1: Replace the fallback-title regression assertion**

In `testMetadataEditsDoNotChangeFileNameAndClearingTitleRestoresFallback`, replace:

```swift
XCTAssertTrue(item.displayTitle().hasPrefix("Audio - "))
```

with:

```swift
XCTAssertFalse(item.displayTitle().contains("Audio -"))
XCTAssertFalse(item.displayTitle().contains("Recording -"))
```

Add a deterministic formatting test:

```swift
func testFallbackTitleContainsOnlyLocalizedDateAndTime() {
    let item = AudioItem(
        startedAt: Date(timeIntervalSince1970: 1_787_560_320),
        fileName: "source.m4a"
    )
    let madrid = TimeZone(secondsFromGMT: 2 * 60 * 60)!

    XCTAssertEqual(
        item.displayTitle(locale: Locale(identifier: "es_ES"), timeZone: madrid),
        "24 ago 2026, 10:32"
    )
    XCTAssertEqual(
        item.displayTitle(locale: Locale(identifier: "en_US"), timeZone: madrid),
        "Aug 24, 2026, 10:32 AM"
    )
}
```

- [ ] **Step 2: Run the focused test and observe failure**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/AudioRepositoryTests
```

Expected: the new fallback-title assertions fail because the formatter still uses the `Audio - %@` localized template.

- [ ] **Step 3: Return the date-time formatter output directly**

In `AudioItem.displayTitle(locale:timeZone:)`, retain the custom-title guard and formatter configuration, but replace the `Bundle` lookup and `String(format:)` return with:

```swift
return formatter.string(from: startedAt)
```

Remove the obsolete `Audio - %@` catalog entry only if no source reference remains. Do not persist the fallback title.

- [ ] **Step 4: Run the focused test and confirm it passes**

Run the command from Step 2. Expected: all `AudioRepositoryTests` pass.

### Task 2: Order compact library-row metadata

**Files:**
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryAudioRow.swift`
- Test: `apps/ios/AIRecorderTests/UI/LocalRecordingFlowUITests.swift`

- [ ] **Step 1: Add a short-date formatter with explicit locales**

Add a private helper to `LibraryAudioRow.swift`:

```swift
private func shortLibraryDate(_ date: Date, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter.string(from: date)
}
```

- [ ] **Step 2: Write a failing unit test for short dates**

Create `apps/ios/AIRecorderTests/Features/LibraryRowMetadataTests.swift` with:

```swift
import XCTest
@testable import AIRecorder

final class LibraryRowMetadataTests: XCTestCase {
    func testShortDateUsesLocaleOrdering() {
        let date = Date(timeIntervalSince1970: 1_787_560_320)

        XCTAssertEqual(
            shortLibraryDate(date, locale: Locale(identifier: "es_ES")),
            "24/8/26"
        )
        XCTAssertEqual(
            shortLibraryDate(date, locale: Locale(identifier: "en_US")),
            "8/24/26"
        )
    }
}
```

If Apple’s locale formatter omits leading zeroes, retain its locale-native output. The product requirement is locale ordering, not forced zero padding.

- [ ] **Step 3: Run the focused test and observe failure**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/LibraryRowMetadataTests
```

Expected: compilation failure because `shortLibraryDate` does not exist.

- [ ] **Step 4: Make the helper visible to the test target**

Remove `private` from `shortLibraryDate` while keeping it in `LibraryAudioRow.swift`. Do not add a formatter dependency or move date derivation into `RootView`.

- [ ] **Step 5: Replace the row’s second-line layout**

Replace the current second-line `HStack` contents with:

```swift
HStack {
    Text(duration(item.durationMilliseconds))
    Text(shortLibraryDate(item.startedAt, locale: locale))
    Spacer()
    Text(state(item))
}
.font(.caption)
.foregroundStyle(.secondary)
```

Keep title on the first line. The trailing `Spacer()` is required so the synthesized status stays on the right. Do not add another status, action, or line.

- [ ] **Step 6: Run the focused tests and confirm they pass**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/LibraryRowMetadataTests \
  -only-testing:AIRecorderTests/AudioRepositoryTests
```

Expected: both test suites pass.

### Task 3: Verify interaction and localization

**Files:**
- Modify: `apps/ios/AIRecorderTests/UI/LocalRecordingFlowUITests.swift`

- [ ] **Step 1: Update automatic-row queries**

Replace UI-test predicates that match `Recording -` with a predicate matching the fixture duration and status instead:

```swift
let audioRow = app.buttons.matching(
    NSPredicate(format: "label CONTAINS[c] '00:02'")
).firstMatch
```

Keep UI-test custom-title assertions unchanged because user-authored titles do not change.

- [ ] **Step 2: Run the UI tests that open a fixture row**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderUITests/LocalRecordingFlowUITests/testMetadataAndTwoStepDeletionKeepAudioUntilFinalConfirmation \
  -only-testing:AIRecorderUITests/LocalRecordingFlowUITests/testVerifiedCloudBackupAllowsNormalLocalDeletionAndKeepsCloudOnlyRow
```

Expected: both tests pass, confirming that a compact row still opens detail and deletion behavior is unchanged.

### Task 4: Verify the completed slice

**Files:**
- Verify: all files above

- [ ] **Step 1: Run the full iOS suite**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2'

git diff --check
```

Expected: all tests pass and `git diff --check` has no output.

- [ ] **Step 2: Manually inspect both languages**

Launch with `-app-language es` and `-app-language en`. Verify the automatic title format, short-date ordering, status alignment, full-row navigation, and unchanged full date/time in detail.

- [ ] **Step 3: Prepare the checkpoint**

Proposed commit after explicit user approval:

```text
feat: simplify library row metadata
```

## Self-review

- The plan preserves custom titles and dynamic fallback relocalization.
- The list uses a single localized short-date formatter and does not invent a persisted display value.
- The status remains synthesized and trailing.
- The detail screen remains unchanged except for receiving the shorter fallback title.
- The plan adds no cloud, processing, or deletion behavior.
