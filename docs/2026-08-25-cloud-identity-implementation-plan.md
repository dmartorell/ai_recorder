# Cloud Identity Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the invited journalist authenticate with a Supabase email magic link, bind this iPhone’s local Audio library to the first signed-in account, and identify the locally verified Original Audio eligible for future backup.

**Architecture:** An injected `CloudAuthenticating` boundary isolates Supabase Auth from the observable, main-actor identity coordinator. The coordinator persists only the bound account UUID locally and rejects a session for any other account. A pure eligibility type inspects the local Audio state and Original Audio file without initiating network work; Capture and all local workflows remain independent.

**Tech Stack:** Swift 6, SwiftUI, Observation, SwiftData, XCTest, Supabase Swift SDK, XcodeGen.

---

### Task 1: Add the tested local identity and eligibility seams

**Files:**
- Create: `apps/ios/AIRecorder/CloudIdentity/CloudIdentity.swift`
- Create: `apps/ios/AIRecorder/CloudIdentity/CloudLibraryOwnerStore.swift`
- Create: `apps/ios/AIRecorder/CloudBackup/BackupEligibility.swift`
- Test: `apps/ios/AIRecorderTests/Features/CloudIdentityCoordinatorTests.swift`
- Test: `apps/ios/AIRecorderTests/Features/BackupEligibilityTests.swift`

- [ ] Write failing tests for first-owner binding, rejection of another account, reuse of the bound account, and eligibility of closed, nonempty available/recovered Original Audio.
- [ ] Implement the value types and a UserDefaults-backed owner store; no Audio metadata or source file is changed.
- [ ] Run the two focused test suites.

### Task 2: Add an injectable identity coordinator

**Files:**
- Create: `apps/ios/AIRecorder/CloudIdentity/CloudAuthenticating.swift`
- Create: `apps/ios/AIRecorder/CloudIdentity/CloudIdentityCoordinator.swift`
- Test: `apps/ios/AIRecorderTests/Features/CloudIdentityCoordinatorTests.swift`

- [ ] Extend the failing tests with session restoration, magic-link request, completion, and account-mismatch outcomes using a fake authenticator.
- [ ] Implement an `@MainActor @Observable` coordinator that restores a valid session, asks for a magic link, completes an app-opened link, and binds only the first account.
- [ ] Run the focused coordinator tests.

### Task 3: Integrate Supabase Auth and local configuration

**Files:**
- Modify: `apps/ios/project.yml`
- Create: `apps/ios/AIRecorder/CloudIdentity/SupabaseCloudAuthentication.swift`
- Create: `apps/ios/Config/Supabase.plist.example`
- Modify: `.gitignore`
- Modify: `apps/ios/AIRecorder/App/Info.plist`
- Modify: `apps/ios/AIRecorder/App/AIRecorderApp.swift`

- [ ] Add the approved `supabase-swift` package and regenerate the Xcode project.
- [ ] Read a bundled, ignored `Supabase.plist` containing the URL and publishable key; use an unavailable implementation when it is absent so local Capture remains operational.
- [ ] Register the exact `com.danielmartorell.ai-recorder` URL scheme and pass opening links to the coordinator.
- [ ] Run a simulator build/typecheck.

### Task 4: Present cloud-identity setup accessibly

**Files:**
- Create: `apps/ios/Features/CloudIdentity/CloudIdentityView.swift`
- Modify: `apps/ios/AIRecorder/App/RootView.swift`
- Modify: `apps/ios/AIRecorder/Features/Settings/SettingsView.swift`
- Modify: `apps/ios/AIRecorder/Resources/Localizable.xcstrings`
- Test: `apps/ios/AIRecorderTests/UI/LocalRecordingFlowUITests.swift`

- [ ] Add localized Settings presentation for session reuse, email magic-link request, pending-email feedback, failure, and sign-out.
- [ ] Keep the cloud setup entry outside Capture and leave library, recovery, playback, and deletion available without a session or network.
- [ ] Add UI coverage for opening cloud setup while local capture controls remain available, then run focused tests.

### Task 5: Verify and review

- [ ] Run the iOS unit and UI suite plus `git diff --check`.
- [ ] Review the completed diff with `/code-review` and resolve findings.
- [ ] Commit the focused implementation to the current branch.
