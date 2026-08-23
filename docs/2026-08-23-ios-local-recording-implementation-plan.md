# iOS Local Recording Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first native iPhone slice that captures, recovers, lists, plays, annotates, and explicitly deletes local audio without network access.

**Architecture:** A main-actor `@Observable` coordinator owns the user-visible capture state and delegates media work to an injected AVFoundation engine. `AVCaptureAudioDataOutput` supplies sample buffers to an `AVAssetWriter` configured for AAC-LC M4A with ten-second movie fragments, so an interrupted file remains playable through its last completed fragment. SwiftData stores editable metadata, markers, interruption and route events, while the immutable M4A file remains the source of truth.

**Tech Stack:** Swift 6.2, SwiftUI, Observation, SwiftData, AVFoundation, AVFAudio, XCTest, iOS 17+

---

## Scope and technical gate

This plan implements only the local iPhone slice. It excludes authentication, upload, Supabase, R2, transcription, generated analysis, waveform rendering, manual pause, lock-screen controls, WAV, manual input selection, and import from Voice Memos.

The fragmented-M4A recovery test in Task 4 is a hard gate. Apple documents that movie fragments make unexpectedly interrupted media playable through the last fragment. The task must prove that behavior for audio-only `.m4a` on the repository's physical iPhone before UI work proceeds. If the copied in-progress file is not playable, stop and revise the writer architecture and this plan. Do not silently fall back to `AVAudioRecorder`, because that would invalidate the recovery requirement.

Apple references:

- [Author fragmented MPEG-4 content with AVAssetWriter](https://developer.apple.com/videos/play/wwdc2020/10011/)
- [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
- [Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)
- [AVAudioApplication record permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/recordpermission-swift.property)
- [Volume capacity for important usage](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey)

## Target file structure

```text
apps/ios/
├── AIRecorder.xcodeproj/
├── AIRecorder/
│   ├── App/
│   │   ├── AIRecorderApp.swift
│   │   ├── AppDependencies.swift
│   │   ├── AppRoute.swift
│   │   └── RootView.swift
│   ├── Capture/
│   │   ├── AudioCaptureEngine.swift
│   │   ├── AudioLevelMeter.swift
│   │   ├── AudioSessionController.swift
│   │   ├── CaptureCoordinator.swift
│   │   ├── CaptureEvent.swift
│   │   ├── CapturePhase.swift
│   │   ├── FragmentedM4AWriter.swift
│   │   └── SystemAudioCaptureEngine.swift
│   ├── Features/
│   │   ├── AudioDetail/
│   │   │   ├── AudioDetailView.swift
│   │   │   ├── AudioMetadataEditor.swift
│   │   │   └── LocalPlaybackModel.swift
│   │   ├── Library/
│   │   │   ├── AudioRow.swift
│   │   │   └── LibraryView.swift
│   │   ├── Preparation/
│   │   │   └── PreparationView.swift
│   │   ├── Recording/
│   │   │   ├── InputLevelView.swift
│   │   │   └── RecordingView.swift
│   │   └── Settings/
│   │       ├── AppLanguage.swift
│   │       ├── SettingsModel.swift
│   │       └── SettingsView.swift
│   ├── Persistence/
│   │   ├── AudioItem.swift
│   │   ├── AudioRepository.swift
│   │   ├── CaptureEventRecord.swift
│   │   ├── LocalAudioState.swift
│   │   └── Marker.swift
│   ├── Storage/
│   │   ├── AudioFileStore.swift
│   │   ├── AudioVerifier.swift
│   │   ├── RecoveryService.swift
│   │   ├── StorageMonitor.swift
│   │   └── StoragePolicy.swift
│   ├── Support/
│   │   ├── BatteryMonitor.swift
│   │   ├── DurationFormatter.swift
│   │   └── IdleTimerController.swift
│   └── Resources/
│       └── Localizable.xcstrings
├── AIRecorderTests/
│   ├── Capture/
│   ├── Persistence/
│   ├── Storage/
│   └── Support/
└── AIRecorderUITests/
    └── LocalRecordingFlowUITests.swift
```

## Task 1: Scaffold the native project

**Files:**
- Create: `apps/ios/AIRecorder.xcodeproj/`
- Create: `apps/ios/AIRecorder/App/AIRecorderApp.swift`
- Create: `apps/ios/AIRecorder/App/RootView.swift`
- Create: `apps/ios/AIRecorder/Resources/Localizable.xcstrings`
- Create: `apps/ios/AIRecorderTests/`
- Create: `apps/ios/AIRecorderUITests/`

- [ ] **Step 1: Create the Xcode project**

In Xcode 26.3 choose **File → New → Project → iOS App** with these exact values:

```text
Product Name: AIRecorder
Team: the local development team
Organization Identifier: com.danielmartorell
Interface: SwiftUI
Language: Swift
Testing System: XCTest
Storage: None
Include Tests: enabled
Location: apps/ios
Minimum Deployment: iOS 17.0
```

Move generated app sources under `apps/ios/AIRecorder/App/` and generated tests under the target folders shown above. Keep the Xcode groups synchronized with the filesystem.

- [ ] **Step 2: Configure recording capabilities**

In the app target, add **Background Modes → Audio, AirPlay, and Picture in Picture**. Add this usage description to the target Info settings:

```text
Privacy - Microphone Usage Description = AI Recorder needs microphone access to record audio offline.
```

Set Swift language mode to Swift 6 and default actor isolation to `MainActor` for the app and test targets.

- [ ] **Step 3: Add a compiling root**

Create `AIRecorderApp.swift`:

```swift
import SwiftUI

@main
struct AIRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

Create `RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Audio Yet",
                systemImage: "waveform",
                description: Text("Recordings you create appear here.")
            )
            .navigationTitle("Audio")
        }
    }
}
```

- [ ] **Step 4: Create the String Catalog**

Create `Localizable.xcstrings` with source language English and Spanish translations for the three strings above. Do not add a third localization.

- [ ] **Step 5: Verify the scaffold**

Run:

```bash
xcodebuild \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  build test
```

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`.

- [ ] **Step 6: Prepare the checkpoint**

Run `git diff --check`. Proposed commit, only after explicit user approval:

```text
chore: scaffold iOS recorder app
```

## Task 2: Define the persistent local domain

**Files:**
- Create: `apps/ios/AIRecorder/Persistence/LocalAudioState.swift`
- Create: `apps/ios/AIRecorder/Persistence/AudioItem.swift`
- Create: `apps/ios/AIRecorder/Persistence/Marker.swift`
- Create: `apps/ios/AIRecorder/Persistence/CaptureEventRecord.swift`
- Modify: `apps/ios/AIRecorder/App/AIRecorderApp.swift`
- Test: `apps/ios/AIRecorderTests/Persistence/AudioItemTests.swift`

- [ ] **Step 1: Write failing model tests**

Cover these behaviors in `AudioItemTests`:

```swift
import XCTest
@testable import AIRecorder

final class AudioItemTests: XCTestCase {
    func testFallbackTitleUsesStartDateUntilCustomTitleExists() {
        let date = Date(timeIntervalSince1970: 1_787_560_320)
        let item = AudioItem(id: UUID(), startedAt: date, fileName: "source.m4a")

        XCTAssertNil(item.customTitle)
        let madrid = TimeZone(secondsFromGMT: 2 * 60 * 60)!
        XCTAssertEqual(
            item.displayTitle(locale: Locale(identifier: "es_ES"), timeZone: madrid),
            "Audio - 24 ago 2026, 10:32 h"
        )

        item.customTitle = "Conversación con Ana"
        XCTAssertEqual(
            item.displayTitle(locale: Locale(identifier: "en_US"), timeZone: madrid),
            "Conversación con Ana"
        )
    }

    func testNewAudioStartsAsCapturingAndOnlyOnDevice() {
        let item = AudioItem(id: UUID(), startedAt: .now, fileName: "source.m4a")

        XCTAssertEqual(item.localState, .capturing)
        XCTAssertFalse(item.hasVerifiedCloudAudio)
    }
}
```

The fixed epoch is 24 August 2026 at 08:32 UTC; the injected GMT+02:00 timezone makes the expected local start time 10:32 without depending on the simulator timezone.

- [ ] **Step 2: Run the focused test and observe failure**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/AudioItemTests
```

Expected: failure because the persistence types do not exist.

- [ ] **Step 3: Implement stable SwiftData models**

Use these persisted concepts:

```swift
enum LocalAudioState: String, Codable, Sendable {
    case capturing
    case finalizing
    case available
    case recovered
    case needsRecovery
}

enum CaptureEventKind: String, Codable, Sendable {
    case interruptionBegan
    case interruptionEnded
    case routeChanged
    case storageWarning
    case automaticFinalization
}
```

`AudioItem` must have a stable UUID independent of title, `startedAt`, optional `endedAt`, optional `customTitle`, `context`, stable `fileName`, duration in integer milliseconds, raw local-state storage, `endedUnexpectedly`, and `hasVerifiedCloudAudio`. Use cascade relationships for markers and events, but do not add a generic delete API to the model.

`Marker` stores a stable UUID, integer audio-timeline milliseconds, and creation date. `CaptureEventRecord` stores stable UUID, kind, wall-clock start/end dates, and audio-timeline milliseconds. Do not store transcript or generated content.

Use locale-aware `Date.FormatStyle` components for fallback titles. Never persist the fallback title. Add `.modelContainer(for: [AudioItem.self, Marker.self, CaptureEventRecord.self])` to `AIRecorderApp` after the models compile.

- [ ] **Step 4: Run model tests**

Run the focused command from Step 2. Expected: pass.

- [ ] **Step 5: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: add local audio persistence model
```

## Task 3: Implement protected file storage and capacity policy

**Files:**
- Create: `apps/ios/AIRecorder/Storage/AudioFileStore.swift`
- Create: `apps/ios/AIRecorder/Storage/StoragePolicy.swift`
- Create: `apps/ios/AIRecorder/Storage/StorageMonitor.swift`
- Test: `apps/ios/AIRecorderTests/Storage/AudioFileStoreTests.swift`
- Test: `apps/ios/AIRecorderTests/Storage/StoragePolicyTests.swift`

- [ ] **Step 1: Write failing storage policy tests**

Test a policy with these fixed values:

```swift
let policy = StoragePolicy(
    encodedBitsPerSecond: 128_000,
    containerOverheadFraction: 0.10,
    safetyReserveBytes: 512 * 1_024 * 1_024,
    warningLeadTime: .seconds(30 * 60)
)
```

Verify that capacity at or below the 512 MiB reserve returns `.critical`, capacity above the reserve returns a conservative duration, and the estimate never exceeds `(available - reserve) / encodedBytesPerSecondWithOverhead`.

- [ ] **Step 2: Write failing file-store tests**

Using a temporary directory, verify:

- `makeOriginalAudioURL(id:)` returns `<UUID>.m4a`.
- Calling it repeatedly returns the same path.
- A metadata title change cannot affect the path.
- The file is created with `.completeUnlessOpen` protection.
- No method deletes a nonempty source without `confirmPermanentDeletion(id:)`.

- [ ] **Step 3: Implement storage types**

`AudioFileStore` owns an `OriginalAudio/` directory under Application Support and accepts an injected root URL for tests. It creates the directory with `.completeUnlessOpen`, excludes it from backup only if product policy later explicitly chooses that behavior, and exposes deletion only through an explicit confirmation-token API.

`StorageMonitor` reads `volumeAvailableCapacityForImportantUsage` from the Application Support volume. `StoragePolicy` returns:

```swift
enum StorageAssessment: Equatable, Sendable {
    case sufficient(estimatedDuration: Duration)
    case warning(estimatedDuration: Duration)
    case critical
}
```

Use binary byte units and integer arithmetic to avoid optimistic rounding. Display estimates as approximate whole minutes.

- [ ] **Step 4: Run focused tests**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/StoragePolicyTests \
  -only-testing:AIRecorderTests/AudioFileStoreTests
```

Expected: pass.

- [ ] **Step 5: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: add protected local audio storage
```

## Task 4: Prove crash-recoverable fragmented M4A writing

**Files:**
- Create: `apps/ios/AIRecorder/Capture/FragmentedM4AWriter.swift`
- Create: `apps/ios/AIRecorderTests/Capture/AudioSampleBufferFactory.swift`
- Test: `apps/ios/AIRecorderTests/Capture/FragmentedM4AWriterTests.swift`
- Create after proof: `docs/adr/0003-use-fragmented-m4a-for-local-capture.md`

- [ ] **Step 1: Write a failing normal-finalization test**

Generate deterministic mono PCM sample buffers at 48 kHz, append twelve seconds of silence and a one-kilohertz tone, finish writing, then load the file with `AVURLAsset`. Assert that it has one audible track and duration within 100 ms of twelve seconds.

- [ ] **Step 2: Write the interrupted-file test**

Append twenty-two seconds of generated audio with media timestamps, wait until the writer has emitted at least two ten-second fragments, copy the still-open M4A to `interrupted-copy.m4a`, and cancel the original writer without finalization. Verify the copy with `AVURLAsset` and `AVAssetReader`:

```swift
XCTAssertGreaterThanOrEqual(try await asset.load(.duration).seconds, 19.5)
XCTAssertFalse(try await asset.loadTracks(withMediaType: .audio).isEmpty)
XCTAssertNoThrow(try AVAssetReader(asset: asset))
```

This copy simulates the bytes available after abrupt process death without allowing `finishWriting()` to repair the file.

- [ ] **Step 3: Implement the writer**

`FragmentedM4AWriter` must:

- Create `AVAssetWriter(outputURL:fileType: .m4a)`.
- Configure an audio `AVAssetWriterInput` for AAC-LC, 48 kHz, one or two channels, and 128 kbps per channel capped at 192 kbps total.
- Set `movieFragmentInterval` and `initialMovieFragmentInterval` to ten seconds before writing starts.
- Start its media session at zero.
- Retimestamp incoming buffers onto a continuous audio timeline so interruption gaps do not become silent media duration.
- Keep every `CMSampleBuffer` operation on one private serial queue.
- Return only `Sendable` snapshots outside that queue.
- Expose `finish()` and `cancelForTesting()`; do not expose destructive repair.

- [ ] **Step 4: Run the writer tests**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/FragmentedM4AWriterTests
```

Expected: both tests pass.

- [ ] **Step 5: Prove recovery on the physical iPhone**

Install a temporary harness that starts the same writer, records for at least 25 seconds, and displays the file URL. Terminate the app from Xcode without calling `finish()`, relaunch, and verify that playback reaches at least the last completed ten-second fragment. Repeat once while the screen is locked.

Record device model, iOS version, recovered duration, and result in the ADR. The paired repository device is currently an iPhone 12.

- [ ] **Step 6: Record the validated decision**

Create `docs/adr/0003-use-fragmented-m4a-for-local-capture.md` only after Steps 4–5 pass. State that fragmented AAC-LC M4A was selected because normal completion produces a standard file while abrupt termination remains playable through the last completed fragment. Include the tested ten-second interval and physical-device result.

- [ ] **Step 7: Enforce the gate**

If either interrupted-file test fails, stop. Do not continue to Task 5 and do not weaken the recovery acceptance criterion.

- [ ] **Step 8: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: prove recoverable fragmented audio writing
```

## Task 5: Build the capture engine and system event stream

**Files:**
- Create: `apps/ios/AIRecorder/Capture/AudioCaptureEngine.swift`
- Create: `apps/ios/AIRecorder/Capture/AudioSessionController.swift`
- Create: `apps/ios/AIRecorder/Capture/AudioLevelMeter.swift`
- Create: `apps/ios/AIRecorder/Capture/CaptureEvent.swift`
- Create: `apps/ios/AIRecorder/Capture/SystemAudioCaptureEngine.swift`
- Test: `apps/ios/AIRecorderTests/Capture/AudioLevelMeterTests.swift`
- Test: `apps/ios/AIRecorderTests/Capture/SystemEventMappingTests.swift`

- [ ] **Step 1: Define an injectable interface**

Use a narrow interface whose events contain no AVFoundation objects:

```swift
struct CaptureSnapshot: Equatable, Sendable {
    let audioDuration: Duration
    let normalizedInputLevel: Float
    let inputName: String
}

enum CaptureEngineEvent: Equatable, Sendable {
    case started(CaptureSnapshot)
    case progressed(CaptureSnapshot)
    case interruptionBegan(Date)
    case interruptionEnded(Date, shouldResume: Bool)
    case routeChanged(Date, inputName: String)
    case storageBecameCritical
    case failed(CaptureFailure)
}

protocol AudioCaptureEngine: AnyObject {
    var events: AsyncStream<CaptureEngineEvent> { get }
    func start(outputURL: URL) async throws
    func finish() async throws -> CapturedAudioSummary
}
```

- [ ] **Step 2: Write failing level and notification-mapping tests**

Verify RMS normalization for silence, half-scale and clipped PCM samples. Feed synthetic interruption dictionaries and route-change reasons into pure mapping functions; assert `.shouldResume` handling and stable input names.

- [ ] **Step 3: Implement the audio session**

Configure `AVAudioSession` with category `.record`, mode `.default`, and options that allow iOS-routed Bluetooth inputs where supported. Activate only when capture starts and deactivate after finalization. Use `AVAudioApplication.shared.recordPermission` and `AVAudioApplication.requestRecordPermission(completionHandler:)`, not the deprecated `AVAudioSession` permission API.

Observe interruption and route notifications through `NotificationCenter` async sequences. Resume only when `.shouldResume` is present. A route change emits an event and rebuilds the capture input if necessary without replacing the writer or output URL.

- [ ] **Step 4: Implement the system engine**

Use `AVCaptureSession`, `AVCaptureDeviceInput`, and `AVCaptureAudioDataOutput`. The sample-buffer delegate runs on one serial queue, calculates level, retimestamps through `FragmentedM4AWriter`, and emits throttled UI snapshots no faster than ten times per second. Never move `CMSampleBuffer` across actors or queues.

- [ ] **Step 5: Run focused tests**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/AudioLevelMeterTests \
  -only-testing:AIRecorderTests/SystemEventMappingTests
```

Expected: pass.

- [ ] **Step 6: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: add AVFoundation capture engine
```

## Task 6: Add repository, verification, and launch recovery

**Files:**
- Create: `apps/ios/AIRecorder/Persistence/AudioRepository.swift`
- Create: `apps/ios/AIRecorder/Storage/AudioVerifier.swift`
- Create: `apps/ios/AIRecorder/Storage/RecoveryService.swift`
- Test: `apps/ios/AIRecorderTests/Persistence/AudioRepositoryTests.swift`
- Test: `apps/ios/AIRecorderTests/Storage/AudioVerifierTests.swift`
- Test: `apps/ios/AIRecorderTests/Storage/RecoveryServiceTests.swift`

- [ ] **Step 1: Write failing repository tests**

Use an in-memory SwiftData container. Verify:

- `beginCapture` persists an `AudioItem` before returning its file URL.
- `addMarker` saves immediately.
- `markFinalizing`, `markAvailable`, `markRecovered`, and `markNeedsRecovery` follow valid state transitions.
- User title and context edits never change `fileName`.
- Deletion requires an explicit permanent-deletion confirmation value.

- [ ] **Step 2: Write failing verification tests**

Verify that `AudioVerifier` rejects missing, empty, trackless and zero-duration files; accepts normal and interrupted fragmented M4A fixtures; and returns measured duration and channel count without modifying the file.

- [ ] **Step 3: Write failing recovery tests**

Given an item left in `.capturing` or `.finalizing`:

- A playable nonempty file becomes `.recovered` with `endedUnexpectedly = true`.
- Markers beyond verified duration are removed; valid markers remain.
- An existing unplayable file becomes `.needsRecovery` and is never deleted.
- A missing or truly empty file removes only the empty metadata record.

- [ ] **Step 4: Implement repository and recovery services**

Keep SwiftData access on the main actor. `RecoveryService` runs once after model-container creation and before the library is shown. It may read assets asynchronously, but all model mutations return to the main actor. It never rewrites the M4A.

- [ ] **Step 5: Run focused tests**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/AudioRepositoryTests \
  -only-testing:AIRecorderTests/AudioVerifierTests \
  -only-testing:AIRecorderTests/RecoveryServiceTests
```

Expected: pass.

- [ ] **Step 6: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: recover interrupted local recordings
```

## Task 7: Implement the owned capture coordinator

**Files:**
- Create: `apps/ios/AIRecorder/Capture/CapturePhase.swift`
- Create: `apps/ios/AIRecorder/Capture/CaptureCoordinator.swift`
- Create: `apps/ios/AIRecorder/App/AppDependencies.swift`
- Test: `apps/ios/AIRecorderTests/Capture/CaptureCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests with a fake engine**

Cover this state machine:

```text
idle → preparing → recording → interrupted → recording
idle → preparing → recording → finalizing → available
recording → finalizing → needsRecovery
recording → automatic finalization → available
```

Also verify:

- The Audio record exists before `engine.start` is called.
- Start failure with no bytes removes only the empty item.
- A marker uses current audio duration and is rejected during interruption.
- Finalize confirmation does not stop capture until confirmed.
- Critical storage triggers finalization.
- Low battery only emits a warning.
- Duplicate taps cannot start or finish twice.

- [ ] **Step 2: Implement an explicit phase enum**

```swift
enum CapturePhase: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case interrupted(startedAt: Date)
    case finalizing(reason: FinalizationReason)
    case available(audioID: UUID)
    case needsRecovery(audioID: UUID)
}
```

`CaptureCoordinator` is `@MainActor @Observable`, owns no view, and receives engine, repository, storage monitor, battery monitor and idle-timer controller through `AppDependencies`. Keep phase values `Equatable` to avoid redundant SwiftUI invalidations.

- [ ] **Step 3: Implement lifecycle side effects**

Starting disables automatic display sleep only while the app is foreground-active. Finalization, failure and leaving the capture screen restore the idle timer and deactivate the audio session. Scene backgrounding does not stop capture. Explicit device lock is never counteracted.

- [ ] **Step 4: Run focused tests**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  -only-testing:AIRecorderTests/CaptureCoordinatorTests
```

Expected: pass.

- [ ] **Step 5: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: orchestrate local capture lifecycle
```

## Task 8: Build the library and preparation flow

**Files:**
- Modify: `apps/ios/AIRecorder/App/RootView.swift`
- Create: `apps/ios/AIRecorder/App/AppRoute.swift`
- Create: `apps/ios/AIRecorder/Features/Library/LibraryView.swift`
- Create: `apps/ios/AIRecorder/Features/Library/AudioRow.swift`
- Create: `apps/ios/AIRecorder/Features/Preparation/PreparationView.swift`
- Create: `apps/ios/AIRecorder/Support/BatteryMonitor.swift`
- Test: `apps/ios/AIRecorderTests/Support/DurationFormatterTests.swift`

- [ ] **Step 1: Implement type-safe navigation**

Use `NavigationStack` with a `Hashable` `AppRoute` for preparation, recording, audio detail, and settings. The app owns one `@State` `CaptureCoordinator` and injects it into child views; child views use `@Bindable` only when they require bindings.

- [ ] **Step 2: Build a stable reverse-chronological library**

Use SwiftData `@Query` sorted by `startedAt` descending. `ForEach` uses `AudioItem.id`, never indices or title. Each unary `AudioRow` shows display title, localized date, duration and one local state. Use `ContentUnavailableView` for an empty library.

- [ ] **Step 3: Build preparation checks**

Show microphone permission, active input, battery, free capacity, fixed `AAC-LC · M4A` format and conservative available duration. The record `Button` is disabled only for denied permission, no input, active capture, or critical storage. Denied permission presents a button using `openURL` to the app's system Settings page.

- [ ] **Step 4: Add accessible labels**

Rows combine title, duration and state for VoiceOver. The record button has a label and hint explaining that capture begins immediately. Use Dynamic Type text styles and no fixed text frames.

- [ ] **Step 5: Run all unit tests and build**

```bash
xcodebuild \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2' \
  build test
```

Expected: pass.

- [ ] **Step 6: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: add local audio library and preparation
```

## Task 9: Build the active recording screen

**Files:**
- Create: `apps/ios/AIRecorder/Features/Recording/RecordingView.swift`
- Create: `apps/ios/AIRecorder/Features/Recording/InputLevelView.swift`
- Create: `apps/ios/AIRecorder/Support/IdleTimerController.swift`
- Create: `apps/ios/AIRecorder/Support/DurationFormatter.swift`
- Test: `apps/ios/AIRecorderUITests/LocalRecordingFlowUITests.swift`

- [ ] **Step 1: Build narrow updating subviews**

Use separate view types for elapsed duration, input level, active input, warnings, marker button and finalize button so ten-hertz level changes do not invalidate the entire screen. Use a dark background and a persistent red recording indicator. `InputLevelView` is a level bar, not an audio waveform.

- [ ] **Step 2: Implement marker feedback**

Use a `Button` with accessibility label `Add marker` and a hint that it marks the current audio time. Drive `.sensoryFeedback(.selection, trigger:)` from the marker count. Disable it during interruption and announce that the microphone is unavailable.

- [ ] **Step 3: Implement finalization confirmation**

Use `.confirmationDialog` with `Continue recording` as cancel and `Finalize` as destructive. Opening the dialog must not alter capture. Confirmation transitions to finalizing, waits for writer completion and verification, then navigates to detail.

- [ ] **Step 4: Surface failures without hiding audio**

Show interruption, route change, no-input-level, low-battery, low-storage and automatic-finalization messages as distinct states. A needs-recovery result navigates to its detail view and remains in the library.

- [ ] **Step 5: Add a launch-argument UI test mode**

Under `-ui-testing`, inject a fake engine and in-memory model container. The UI test starts capture, verifies the active state, adds two markers, opens then cancels finalization, finalizes, and verifies the resulting library row. Production builds must never select the fake engine without the launch argument.

- [ ] **Step 6: Run UI and unit tests**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2'
```

Expected: all tests pass.

- [ ] **Step 7: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: add accessible recording controls
```

## Task 10: Add local playback, metadata editing, and safe deletion

**Files:**
- Create: `apps/ios/AIRecorder/Features/AudioDetail/LocalPlaybackModel.swift`
- Create: `apps/ios/AIRecorder/Features/AudioDetail/AudioDetailView.swift`
- Create: `apps/ios/AIRecorder/Features/AudioDetail/AudioMetadataEditor.swift`
- Test: `apps/ios/AIRecorderTests/Features/LocalPlaybackModelTests.swift`
- Test: `apps/ios/AIRecorderUITests/LocalRecordingFlowUITests.swift`

- [ ] **Step 1: Write playback model tests**

Inject a player protocol around `AVPlayer`. Verify play/pause, ±10-second clamped seeking, marker seeking, current-time updates, end-of-file reset, and teardown of periodic time observers.

- [ ] **Step 2: Implement local playback**

`LocalPlaybackModel` is `@MainActor @Observable`. It accepts the immutable source URL, exposes duration and position, and never writes the asset. The detail screen has play/pause, a native `Slider`, ten-second skips and marker buttons. Do not draw a waveform.

- [ ] **Step 3: Implement optional metadata editing**

Present `AudioMetadataEditor` with `.sheet(item:)`. It edits only `customTitle` and `context`, validates a trimmed title, saves through `AudioRepository`, and dismisses itself. Clearing a custom title restores the dynamic localized fallback without renaming the file.

- [ ] **Step 4: Implement explicit permanent deletion**

For this local-only slice, every item lacks verified cloud audio. First explain that no cloud copy exists. A second alert names the Audio and exposes `Delete permanently`. Only the second action asks the repository for a deletion token, deletes the M4A, then deletes SwiftData metadata. If file deletion fails, retain metadata and show the error.

- [ ] **Step 5: Extend UI tests**

Verify metadata editing preserves the row identity and that cancellation at either deletion step retains the item. Verify the final destructive action removes both row and fixture file in UI-test mode.

- [ ] **Step 6: Run tests**

Run the full simulator suite. Expected: pass.

- [ ] **Step 7: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: add local playback and safe deletion
```

## Task 11: Add Spanish and English in-app language selection

**Files:**
- Create: `apps/ios/AIRecorder/Features/Settings/AppLanguage.swift`
- Create: `apps/ios/AIRecorder/Features/Settings/SettingsModel.swift`
- Create: `apps/ios/AIRecorder/Features/Settings/SettingsView.swift`
- Modify: `apps/ios/AIRecorder/Resources/Localizable.xcstrings`
- Modify: `apps/ios/AIRecorder/App/RootView.swift`
- Test: `apps/ios/AIRecorderTests/Features/SettingsModelTests.swift`

- [ ] **Step 1: Write language and fallback-title tests**

Verify Spanish and English locale mapping, persistence across model recreation, fallback relocalization, and preservation of a user-authored title.

- [ ] **Step 2: Implement settings state**

```swift
enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"
    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }
}
```

Persist selection with `@AppStorage` in `SettingsModel`, marked `@ObservationIgnored` inside the `@Observable` type. Inject its locale at the app root with `.environment(\.locale, settings.locale)`.

- [ ] **Step 3: Complete the String Catalog**

Translate every user-facing string into Spanish and English. Add translator comments for ambiguous actions such as Record, Finalize, Marker, Recovered and Delete permanently. Use interpolation rather than concatenation for dates, duration and item names.

- [ ] **Step 4: Audit accessibility**

Run both languages at the largest accessibility Dynamic Type size and with VoiceOver. Confirm all controls are `Button`, `Slider`, `TextField`, `TextEditor` or native equivalents; every icon-only control has label and hint; status is not communicated by color alone; and destructive confirmations name their target.

- [ ] **Step 5: Run full tests**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2'
```

Expected: pass in both language launch configurations.

- [ ] **Step 6: Prepare the checkpoint**

Proposed commit after approval:

```text
feat: localize recorder in Spanish and English
```

## Task 12: Validate reliability on the physical iPhone

**Files:**
- Create: `docs/testing/ios-local-recording-validation.md`
- Modify only if commands change: `README.md`

- [ ] **Step 1: Install a Release build on the paired iPhone 12**

Use Xcode signing for the configured team and run:

```bash
xcodebuild \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -configuration Release \
  -destination 'platform=iOS,id=5B910197-BF28-51B8-B8A7-7630202F9896' \
  build
```

Expected: Release build succeeds. Install through Xcode or `devicectl` using the resulting `.app`.

- [ ] **Step 2: Run the 30-minute development check**

In airplane mode, begin capture, add markers before and after locking, leave the screen locked for most of the run, finalize, relaunch and play through marker positions. Record actual duration, file size, battery delta, marker error and verification result.

- [ ] **Step 3: Run interruption and route tests**

Run separate short captures for an actual audio-session interruption and for external-input removal. Confirm automatic resumption only when iOS permits it, frozen audio-timeline duration during interruption, recorded events, visible warnings and continued playable output.

- [ ] **Step 4: Run abrupt-termination recovery**

After at least 25 seconds, terminate the process without finalization. Relaunch and verify one recovered Audio, unexpected-ending status, playback through the last fragment and pruning only of markers beyond recovered duration. Confirm that no file is automatically deleted.

- [ ] **Step 5: Run storage and battery scenarios**

Use injected debug thresholds to exercise warning and critical storage behavior without filling the phone. Verify automatic storage finalization and battery warning without battery-triggered finalization. Remove threshold overrides before Release validation.

- [ ] **Step 6: Run the two-hour reliability milestone**

Record a real two-hour, two-speaker session in airplane mode with the screen locked for most of the duration. Finalize, relaunch, play beginning/middle/end and all markers, and verify duration, channels, file size and absence of unexplained gaps.

- [ ] **Step 7: Document evidence**

In `docs/testing/ios-local-recording-validation.md`, record app commit, device model, iOS version, exact scenario, expected result, actual result and pass/fail for every run. Do not include recorded audio, transcript content, signed URLs or personal data.

- [ ] **Step 8: Run the complete affected suite**

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2'

git diff --check
```

Expected: all tests pass and `git diff --check` produces no output.

- [ ] **Step 9: Prepare the final checkpoint**

Proposed commit after approval:

```text
test: validate local recording reliability
```

## Self-review

- The plan covers offline capture, continuous local writing, fragmented crash recovery, immediate marker persistence, interruptions, route changes, background and locked-screen operation, display wake behavior, storage estimates and emergency finalization, battery warnings, library, playback, metadata, localization and explicit deletion.
- It preserves the distinction between Audio metadata and immutable Original Audio.
- It does not introduce cloud, transcript, AI, waveform, collaboration, import or destructive editing.
- All runtime services have injected seams; the media writer has an executable recovery gate before UI investment.
- SwiftUI state is owned with `@State` and `@Observable`; views receive narrow values or `@Bindable` only when editing.
- Collection identity uses persisted UUIDs and does not derive identity from mutable titles.
- No new third-party dependency is required.
