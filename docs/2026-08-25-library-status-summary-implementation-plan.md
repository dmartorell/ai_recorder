# Library Status Summary Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce every iPhone library row to title, date, duration, and one truthful prioritized status while retaining detailed local, cloud, and processing state in Audio detail.

**Architecture:** Keep status derivation pure in `LibraryAudioStatus.swift`. `LibraryAudioRow` consumes one synthesized `LocalizedStringResource`, so no row renders the three diagnostic state layers. `AudioDetailView` remains the operational view and continues rendering the independent local, cloud, and processing states.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, XCUITest.

---

## Target file structure

```text
apps/ios/AIRecorder/
├── Features/
│   ├── AudioDetail/
│   │   └── AudioDetailView.swift
│   └── Library/
│       ├── LibraryAudioRow.swift
│       └── LibraryAudioStatus.swift
└── Resources/
    └── Localizable.xcstrings
apps/ios/AIRecorderTests/
├── Features/
│   └── LibraryAudioStatusTests.swift
└── UI/
    └── LocalRecordingFlowUITests.swift
```

### Task 1: Derive one prioritized library status

**Files:**
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryAudioStatus.swift`
- Test: `apps/ios/AIRecorderTests/Features/LibraryAudioStatusTests.swift`

- [ ] **Step 1: Write failing status-priority tests**

Add these tests. They lock the library contract independently of SwiftUI layout.

```swift
func testFailedCloudBackupOutranksAvailableLocalAudio() {
    let item = AudioItem(fileName: "source.m4a")
    item.localState = .available
    item.cloudBackupState = .failed

    XCTAssertEqual(libraryAudioStatus(for: item), .uploadFailed)
}

func testPausedCloudBackupOutranksVerifiedLocalAudio() {
    let item = AudioItem(fileName: "source.m4a")
    item.localState = .available
    item.cloudBackupState = .paused

    XCTAssertEqual(libraryAudioStatus(for: item), .uploadPaused)
}

func testCloudOnlyOutranksBackedUpStatus() {
    let item = AudioItem(fileName: "source.m4a")
    item.localState = .available
    item.cloudBackupState = .backedUp
    item.localOriginalAudioRemovedAt = .now

    XCTAssertEqual(libraryAudioStatus(for: item), .cloudOnly)
}

func testBackedUpAudioOutranksOnlyOnThisIPhone() {
    let item = AudioItem(fileName: "source.m4a")
    item.localState = .available
    item.cloudBackupState = .backedUp

    XCTAssertEqual(libraryAudioStatus(for: item), .backedUpInCloud)
}
```

- [ ] **Step 2: Run the focused test and observe failure**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/LibraryAudioStatusTests
```

Expected: compilation failure because `.uploadFailed` and `.uploadPaused` do not exist.

- [ ] **Step 3: Add status cases and priority**

Add `.uploadFailed`, `.uploading`, and `.uploadPaused` to `LibraryAudioStatus`, with localized resources `Upload failed`, `Uploading`, and `Upload paused`. Make `libraryAudioStatus(for:)` return exactly one status in this order:

```swift
if item.cloudBackupState == .failed { return .uploadFailed }
if item.cloudBackupState == .uploading || item.cloudBackupState == .verifying { return .uploading }
if item.cloudBackupState == .paused || item.cloudBackupState == .signInToResume { return .uploadPaused }
if item.localOriginalAudioRemovedAt != nil { return .cloudOnly }
if item.cloudBackupState == .backedUp { return .backedUpInCloud }
```

After those cloud-derived states, retain the existing interruption, unavailable-input, and `LocalAudioState` mapping. Do not add a persistence field for processing because the current app has no cloud-processing job state. A future processing state can be inserted ahead of `.cloudOnly` in this pure function.

- [ ] **Step 4: Run the focused test and confirm it passes**

Run the command from Step 2. Expected: all `LibraryAudioStatusTests` pass.

### Task 2: Make the library row compact

**Files:**
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryAudioRow.swift`
- Test: `apps/ios/AIRecorderTests/UI/LocalRecordingFlowUITests.swift`

- [ ] **Step 1: Write a failing UI assertion for the compact row**

In `testVerifiedCloudBackupAllowsNormalLocalDeletionAndKeepsCloudOnlyRow`, after returning to the library, add:

```swift
let row = app.buttons.matching(
    NSPredicate(format: "label CONTAINS[c] 'Recording -'")
).firstMatch
XCTAssertTrue(row.label.contains("Cloud only"))
XCTAssertFalse(app.staticTexts["Local audio"].exists)
XCTAssertFalse(app.staticTexts["Processing"].exists)
```

Keep the existing assertion that the row remains after local deletion.

- [ ] **Step 2: Run the focused UI test and observe failure**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderUITests/LocalRecordingFlowUITests/testVerifiedCloudBackupAllowsNormalLocalDeletionAndKeepsCloudOnlyRow
```

Expected: failure because the library row still displays `AudioStateSummaryView` with local, cloud, and processing labels.

- [ ] **Step 3: Remove the diagnostic state summary from the row**

Delete `AudioStateSummaryView` from `LibraryAudioRow.swift` and remove its use beneath the row button. Preserve the existing row button, its combined accessibility element, stable `AudioItem.id` list identity, selection control, and swipe deletion action.

The row label remains:

```swift
Text(item.displayTitle(locale: locale))
Text(item.startedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
Text(duration(item.durationMilliseconds))
Text(state(item))
```

Do not make the status separately tappable.

- [ ] **Step 4: Run the focused UI test and confirm it passes**

Run the command from Step 2. Expected: the row opens Audio detail, returns as `Cloud only` after local deletion, and has no local/cloud/processing diagnostic labels in the library.

### Task 3: Keep diagnostic state in Audio detail

**Files:**
- Modify: `apps/ios/AIRecorder/Features/AudioDetail/AudioDetailView.swift`
- Test: `apps/ios/AIRecorderTests/UI/LocalRecordingFlowUITests.swift`
- Modify: `apps/ios/AIRecorder/Resources/Localizable.xcstrings`

- [ ] **Step 1: Write a failing UI assertion for detail state**

In `testVerifiedCloudBackupAllowsNormalLocalDeletionAndKeepsCloudOnlyRow`, after `audioRow.tap()` and before deleting, assert:

```swift
XCTAssertTrue(app.staticTexts["Local audio"].waitForExistence(timeout: 5))
XCTAssertTrue(app.staticTexts["Cloud audio"].exists)
XCTAssertTrue(app.staticTexts["Processing"].exists)
```

- [ ] **Step 2: Run the focused UI test and observe failure if the detail has been simplified accidentally**

Run the command from Task 2, Step 2. Expected before implementation: it passes only if detail still retains all three labels. If it already passes, the test is a regression guard and no production change is needed in this task.

- [ ] **Step 3: Preserve independent detail labels**

Keep these three `LabeledContent` rows in `CloudBackupSection`:

```swift
LabeledContent("Local audio") { Text(audioStatePresentation(for: item).localAudio.localizedString) }
LabeledContent("Cloud audio") { Text(audioStatePresentation(for: item).cloudAudio.localizedString) }
LabeledContent("Processing") { Text(audioStatePresentation(for: item).processing.localizedString) }
```

Ensure every new visible status has English and Spanish translations in `Localizable.xcstrings`. Do not add cloud playback, transcription, or processing persistence in this task.

- [ ] **Step 4: Run the focused UI test and confirm it passes**

Run the command from Task 2, Step 2. Expected: three diagnostic states are visible in detail only.

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

Expected: all tests pass and `git diff --check` produces no output.

- [ ] **Step 2: Manually inspect the compact library**

Run the app on the simulator. Verify each row contains title, date, duration, and one status. Verify tapping the row opens detail and the detail shows local, cloud, and processing independently.

- [ ] **Step 3: Prepare the checkpoint**

Proposed commit after explicit user approval:

```text
feat: simplify library audio status
```

## Self-review

- Task 1 covers the approved status-priority order using pure tests.
- Task 2 removes only diagnostic clutter from library rows without changing navigation or deletion behavior.
- Task 3 preserves the separate operational states in detail.
- The plan does not add processing infrastructure, cloud playback, or any new dependency.
