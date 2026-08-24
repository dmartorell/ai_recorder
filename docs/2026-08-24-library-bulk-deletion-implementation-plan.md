# Library Bulk Deletion Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a journalist select multiple local Audio items in the library, including by vertical drag across selection controls, then explicitly and safely delete all selected Original Audio files.

**Architecture:** A focused `@Observable` selection model owns selection mode, selected stable Audio identifiers, and the active drag range. `LibraryView` remains responsible for presentation, while `AudioRepository` performs the existing explicit file-then-metadata deletion once for each selected Audio. A two-alert flow preserves the approved permanent-loss safeguard for Audio without verified cloud backup.

**Tech Stack:** Swift 6, SwiftUI, Observation, SwiftData, XCTest, XCUITest, iOS 17+.

---

## Interaction contract

- The library toolbar exposes `Select` / `Seleccionar` only when no Capture is active.
- Entering selection mode displays a circular selection control before every library row and changes the toolbar action to `Cancel` / `Cancelar`.
- Tapping a control toggles exactly that Audio.
- A vertical drag that begins on a selection control selects every row crossed. It never starts from the rest of the row, so ordinary library scrolling remains unchanged.
- While that drag remains over selection controls near the top or bottom edge, the library autoscrolls and continues selecting newly crossed rows.
- A trailing bottom toolbar shows the selected count and a destructive trash button only when at least one Audio is selected.
- Trash presents two alerts: first warns that the selected count has no verified cloud backup; second names the count and requires `Delete permanently` / `Eliminar permanentemente`. Cancellation at either step retains all Audio.
- Confirmation deletes every selected Original Audio and its metadata. If one deletion fails, retain that Audio and surface the failure count; never remove metadata after a file-deletion failure.
- All new visible strings are translated in English and Spanish.

## Target file structure

```text
apps/ios/AIRecorder/
├── Features/Library/
│   ├── AudioSelectionModel.swift
│   ├── LibraryAudioRow.swift
│   └── LibraryView.swift
├── App/
│   └── RootView.swift
└── Resources/
    └── Localizable.xcstrings
apps/ios/AIRecorderTests/
└── Features/Library/
    └── AudioSelectionModelTests.swift
apps/ios/AIRecorderTests/UI/
└── LocalRecordingFlowUITests.swift
```

### Task 1: Add selection state with stable identity

**Files:**
- Create: `apps/ios/AIRecorder/Features/Library/AudioSelectionModel.swift`
- Test: `apps/ios/AIRecorderTests/Features/Library/AudioSelectionModelTests.swift`

- [ ] **Step 1: Write failing model tests**

Cover selecting one UUID, toggling it off, selecting an inclusive ordered UUID range, retaining selected UUIDs that remain in a supplied library ID set, and clearing mode and selection together.

```swift
func testSelectingInclusiveRangeAddsEveryAudioBetweenEndpoints() {
    let ids = [UUID(), UUID(), UUID(), UUID()]
    let model = AudioSelectionModel()

    model.beginSelection(at: ids[1], orderedIDs: ids)
    model.extendSelection(to: ids[3], orderedIDs: ids)

    XCTAssertEqual(model.selectedIDs, Set(ids[1...3]))
}
```

- [ ] **Step 2: Run the focused test and observe failure**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/AudioSelectionModelTests
```

Expected: failure because `AudioSelectionModel` does not exist.

- [ ] **Step 3: Implement `AudioSelectionModel`**

Make it `@MainActor @Observable final`. Store `isSelecting`, `selectedIDs: Set<UUID>`, and a private drag anchor. Its public operations are `enter()`, `cancel()`, `toggle(_:)`, `beginSelection(at:orderedIDs:)`, `extendSelection(to:orderedIDs:)`, and `retainExistingIDs(_:)`. Range extension must use the supplied ordered IDs, not mutable titles or list offsets as identity.

- [ ] **Step 4: Run the focused test**

Run the command from Step 2. Expected: pass.

### Task 2: Extract stable library rows and implement select mode

**Files:**
- Create: `apps/ios/AIRecorder/Features/Library/LibraryAudioRow.swift`
- Create: `apps/ios/AIRecorder/Features/Library/LibraryView.swift`
- Modify: `apps/ios/AIRecorder/App/RootView.swift`

- [ ] **Step 1: Move the existing library `List` from `RootView` into `LibraryView`**

Pass only the queried `[AudioItem]`, locale, selection model, and action closures. Preserve reverse chronology and `AudioItem.id` identity. Keep navigation and all persistence actions outside rows.

- [ ] **Step 2: Add the selection control**

`LibraryAudioRow` receives `isSelecting`, `isSelected`, a toggle `Button`, and the existing open-detail action. In selection mode the leading control is a circular `Button` using `circle` or `checkmark.circle.fill`; it has an accessibility label that includes the Audio title and an accessibility value of `Selected` or `Not selected`. Tapping any other part of the row still opens the detail only outside selection mode.

- [ ] **Step 3: Add selection toolbar actions**

Own `@State private var selection = AudioSelectionModel()` in `RootView`. Add `Select` when not selecting and `Cancel` when selecting. Entering selection disables row-detail opening, while cancellation clears all selected IDs. Do not allow select mode while `coordinator.isCapturing` is true.

- [ ] **Step 4: Run the app and manually verify**

Build for the simulator, enter selection mode, toggle several circles, cancel, and confirm that library navigation and a Capture still work outside selection mode.

### Task 3: Add drag-range selection and edge-only autoscroll

**Files:**
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryView.swift`
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryAudioRow.swift`
- Test: `apps/ios/AIRecorderTests/Features/Library/AudioSelectionModelTests.swift`

- [ ] **Step 1: Add pure tests for ordered range changes**

Add tests that begin a range at the third Audio, extend upward to the first Audio, then downward to the fourth Audio. Assert that all crossed UUIDs are selected and no UUID outside the ordered range is selected.

- [ ] **Step 2: Track only selection-control frames**

Use a named library coordinate space and a `PreferenceKey` whose value maps `UUID` to each leading selection control's `CGRect`. Each control publishes its own frame with `GeometryReader`; the full row must not install the gesture.

- [ ] **Step 3: Attach one zero-distance `DragGesture` to each selection control**

On drag start, find the control frame containing the initial location and call `beginSelection`. On every change, find the control frame containing the current location and call `extendSelection`. On end, clear only the transient drag anchor. Use `simultaneousGesture` only on the selection control, never on the `List`, so scrolling from row content remains native.

- [ ] **Step 4: Add edge autoscroll**

Wrap the list in `ScrollViewReader`. While a selection drag is active and its location is inside the top or bottom 44-point edge zone of the named coordinate space, run one main-actor task that periodically scrolls to the adjacent visible `AudioItem.id`. Recompute frames after every scroll and extend the range to the control currently under the drag point. Cancel the task on drag end, selection cancellation, view disappearance, and when the drag leaves both edge zones.

- [ ] **Step 5: Run focused model tests and perform a simulator check**

Verify drag begins only from circles, select mode allows range selection, normal vertical scroll still works from the row body, and edge dragging autoscrolls without selecting unrelated Audio.

### Task 4: Add the safe bulk-deletion flow

**Files:**
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryView.swift`
- Modify: `apps/ios/AIRecorder/App/RootView.swift`
- Modify: `apps/ios/AIRecorder/Resources/Localizable.xcstrings`
- Test: `apps/ios/AIRecorderTests/UI/LocalRecordingFlowUITests.swift`

- [ ] **Step 1: Add a bottom trash action**

When selection is nonempty, display a safe-area bottom toolbar with `Text("%lld selected", selection.selectedIDs.count)` and a destructive trash `Button`. Its accessibility label states the selected count. The button only opens confirmation; it does not delete.

- [ ] **Step 2: Add the two confirmations**

The first alert states that `N` selected local Audio items have no verified cloud copy and that deletion is permanent. Its destructive action opens a second alert. The second alert names `N` and exposes `Delete permanently`; its cancellation leaves selection intact. Both use native `.alert(_:isPresented:actions:message:)`.

- [ ] **Step 3: Delete safely through the repository**

At final confirmation, take a snapshot of the selected IDs, resolve current `AudioItem`s from the query, then call the repository's existing explicit confirmation-token deletion for each item. Continue after individual failures, preserving failed records. Clear only successfully deleted IDs. Exit selection mode if no selected IDs remain. Show an error alert that reports the number of Audio items retained because deletion failed.

- [ ] **Step 4: Translate all new strings**

Add English and Spanish translations, including plural-safe interpolated count strings for select, cancel, selected count, permanent-loss warning, final bulk confirmation, and partial failure.

- [ ] **Step 5: Add UI coverage**

Use three UI-test fixtures. Enter select mode, select two Audio items through their circles, tap trash, cancel the first alert and verify three remain; repeat, accept the first alert, cancel the second and verify three remain; repeat, accept both and verify only the unselected Audio remains.

- [ ] **Step 6: Run the complete suite**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2'

git diff --check
```

Expected: all unit and UI tests pass; `git diff --check` has no output.

- [ ] **Step 7: Prepare the checkpoint**

Proposed commit after explicit user approval:

```text
feat: select and delete local audio in bulk
```

## Self-review

- Stable selection identity is persisted `AudioItem.id`; titles and indexes are never identities.
- Selection drag is scoped to leading controls, preserving normal library scroll behavior.
- Edge autoscroll only runs while the selection-control drag is active.
- Two destructive confirmations preserve the approved unbacked local-deletion rule.
- Deletion remains file-first through `AudioRepository`; failures retain metadata and Original Audio.
- The scope introduces no cloud, transcript, collaboration, or automatic-deletion behavior.
