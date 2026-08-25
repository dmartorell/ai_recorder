# Library Location Icons Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace stable local/cloud location text in iPhone library rows with accessible SF Symbols, retaining text for operational statuses.

**Architecture:** `LibraryAudioStatus` remains the single pure mapping from an `AudioItem` to library presentation. It adds an optional ordered SF Symbol list only for the three stable location states. `LibraryAudioRow` renders that list as decorative images while retaining the pre-existing localized status string in the row button’s combined accessibility label. `RootView` and `LibraryView` pass the status enum rather than resolving it prematurely to text.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XCUITest.

---

## Target file structure

```text
apps/ios/AIRecorder/
├── App/
│   └── RootView.swift
└── Features/
    └── Library/
        ├── LibraryAudioRow.swift
        ├── LibraryAudioStatus.swift
        └── LibraryView.swift
apps/ios/AIRecorderTests/
├── Features/
│   └── LibraryAudioStatusTests.swift
└── UI/
    └── LocalRecordingFlowUITests.swift
docs/plans/
└── 2026-08-25-library-location-icons-design.md
```

### Task 1: Model stable location symbols

**Files:**
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryAudioStatus.swift`
- Test: `apps/ios/AIRecorderTests/Features/LibraryAudioStatusTests.swift`

- [ ] **Step 1: Write the failing symbol-mapping test**

Add this test to `LibraryAudioStatusTests`:

```swift
func testStableLocationStatusesExposeOrderedSFSymbols() {
    XCTAssertEqual(LibraryAudioStatus.onlyOnThisIPhone.locationSymbolNames, ["iphone"])
    XCTAssertEqual(LibraryAudioStatus.cloudOnly.locationSymbolNames, ["icloud"])
    XCTAssertEqual(LibraryAudioStatus.backedUpInCloud.locationSymbolNames, ["iphone", "icloud"])
}

func testOperationalStatusesDoNotExposeLocationSymbols() {
    XCTAssertNil(LibraryAudioStatus.uploading.locationSymbolNames)
    XCTAssertNil(LibraryAudioStatus.uploadFailed.locationSymbolNames)
    XCTAssertNil(LibraryAudioStatus.needsRecovery.locationSymbolNames)
}
```

- [ ] **Step 2: Run the focused tests and observe failure**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/LibraryAudioStatusTests
```

Expected: compilation failure because `locationSymbolNames` does not exist.

- [ ] **Step 3: Add the optional ordered symbol mapping**

Add this computed property to `LibraryAudioStatus`, without changing `localizedString` or `libraryAudioStatus(for:)`:

```swift
var locationSymbolNames: [String]? {
    switch self {
    case .onlyOnThisIPhone:
        ["iphone"]
    case .cloudOnly:
        ["icloud"]
    case .backedUpInCloud:
        ["iphone", "icloud"]
    case .needsRecovery,
         .capturing,
         .finalizing,
         .recovered,
         .endedByInterruption,
         .endedByUnavailableInput,
         .uploadFailed,
         .uploading,
         .uploadPaused:
        nil
    }
}
```

Do not add new localization strings. The existing `localizedString` values remain the accessibility meaning for the icons.

- [ ] **Step 4: Run the focused tests and confirm they pass**

Run the command from Step 2. Expected: all `LibraryAudioStatusTests` pass.

### Task 2: Render symbols without degrading row accessibility

**Files:**
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryAudioRow.swift`
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryView.swift`
- Modify: `apps/ios/AIRecorder/App/RootView.swift`

- [ ] **Step 1: Pass `LibraryAudioStatus` through the library hierarchy**

Change the `state` closure type in both `LibraryView` and `LibraryAudioRow` from:

```swift
let state: (AudioItem) -> LocalizedStringResource
```

to:

```swift
let state: (AudioItem) -> LibraryAudioStatus
```

In `RootView`, replace the `state` helper with:

```swift
private func state(_ item: AudioItem) -> LibraryAudioStatus {
    libraryAudioStatus(for: item)
}
```

- [ ] **Step 2: Add the status presentation view**

In `LibraryAudioRow`, replace `Text(state(item))` with:

```swift
libraryStatus(state(item))
```

Add this view builder inside `LibraryAudioRow`:

```swift
@ViewBuilder
private func libraryStatus(_ status: LibraryAudioStatus) -> some View {
    if let symbolNames = status.locationSymbolNames {
        HStack(spacing: 4) {
            ForEach(symbolNames, id: \.self) { symbolName in
                Image(systemName: symbolName)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(status.localizedString))
    } else {
        Text(status.localizedString)
    }
}
```

Keep the enclosing caption font, secondary foreground style, and `Button` `.accessibilityElement(children: .combine)`. The symbols are informational and must not become separate controls. The `ForEach` uses stable SF Symbol names as identity.

- [ ] **Step 3: Build the app**

```bash
xcodebuild build \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2'
```

Expected: `BUILD SUCCEEDED`.

### Task 3: Guard the accessible cloud-only row

**Files:**
- Modify: `apps/ios/AIRecorderTests/UI/LocalRecordingFlowUITests.swift`

- [ ] **Step 1: Update the cloud-only library assertion**

In `testVerifiedCloudBackupAllowsNormalLocalDeletionAndKeepsCloudOnlyRow`, replace:

```swift
XCTAssertTrue(app.staticTexts["Cloud only"].waitForExistence(timeout: 5))
```

with:

```swift
XCTAssertTrue(audioRow.label.contains("Cloud only"))
```

Keep the assertions that detail exposes `Local audio`, `Cloud audio`, and `Processing` before deletion, and that these detail labels do not appear after returning to the library. The changed assertion proves that the visual icon still contributes its localized meaning to the accessible row label.

- [ ] **Step 2: Run the focused UI test**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderUITests/LocalRecordingFlowUITests/testVerifiedCloudBackupAllowsNormalLocalDeletionAndKeepsCloudOnlyRow
```

Expected: PASS. The fixture row remains after local deletion, visually shows only the cloud symbol, and its button label includes `Cloud only`.

### Task 4: Verify the completed slice

**Files:**
- Verify: all files above

- [ ] **Step 1: Run the full iOS suite**

```bash
xcodebuild test -quiet \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2'

git diff --check
```

Expected: all tests pass and `git diff --check` produces no output.

- [ ] **Step 2: Inspect the three locations with VoiceOver**

On an iPhone or simulator, inspect library fixtures representing local only, cloud only, and local plus verified cloud. Verify `iphone`, `icloud`, and `iphone` then `icloud` respectively. With VoiceOver enabled, each row must announce the existing localized location meaning, not SF Symbol names. Verify `Uploading`, `Upload paused`, and `Upload failed` remain text.

- [ ] **Step 3: Prepare the checkpoint**

Do not commit unless the user explicitly approves it. Proposed commit:

```text
feat: use icons for library audio locations
```

## Self-review

- Task 1 maps precisely the three approved stable location states and leaves every operational status textual.
- Task 2 keeps state derivation pure, preserves the existing row interaction, and hides visual SF Symbols from VoiceOver in favor of the localized status meaning.
- Task 3 verifies the library row’s accessibility label after cloud-only deletion without changing detail’s independent diagnostic labels.
- The plan adds no asset, dependency, persistence field, cloud behavior, or deletion behavior.
