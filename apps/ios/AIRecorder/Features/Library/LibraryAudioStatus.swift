import Foundation

enum LibraryAudioStatus: Equatable {
    case onlyOnThisIPhone
    case needsRecovery
    case capturing
    case finalizing
    case recovered
    case endedByInterruption
    case endedByUnavailableInput
    case backedUpInCloud
    case cloudOnly
    case uploadFailed
    case uploading
    case uploadPaused

    var locationSymbolNames: [String]? {
        switch self {
        case .onlyOnThisIPhone:
            ["iphone.gen3"]
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

    var localizedString: LocalizedStringResource {
        switch self {
        case .onlyOnThisIPhone: "Only on this iPhone"
        case .needsRecovery: "Needs recovery"
        case .capturing: "Capturing"
        case .finalizing: "Finalizing"
        case .recovered: "Recovered"
        case .endedByInterruption: "Ended by interruption"
        case .endedByUnavailableInput: "Ended: input unavailable"
        case .backedUpInCloud: "Backed up in cloud"
        case .cloudOnly: "Cloud only"
        case .uploadFailed: "Upload failed"
        case .uploading: "Uploading"
        case .uploadPaused: "Upload paused"
        }
    }
}

enum LocalAudioPresentation: Equatable {
    case available
    case removed
    case capturing
    case finalizing
    case needsRecovery

    var localizedString: LocalizedStringResource {
        switch self {
        case .available: "Available"
        case .removed: "Removed from this iPhone"
        case .capturing: "Capture in progress"
        case .finalizing: "Finalizing"
        case .needsRecovery: "Needs recovery"
        }
    }
}

enum CloudAudioPresentation: Equatable {
    case notBackedUp
    case uploading
    case paused
    case signInToResume
    case failed
    case verifying
    case backedUp

    var localizedString: LocalizedStringResource {
        switch self {
        case .notBackedUp: "Not backed up"
        case .uploading: "Uploading"
        case .paused: "Upload paused"
        case .signInToResume: "Sign in to resume"
        case .failed: "Upload failed"
        case .verifying: "Verifying backup"
        case .backedUp: "Backed up"
        }
    }
}

enum AudioProcessingPresentation: Equatable {
    case notStarted

    var localizedString: LocalizedStringResource { "Not started" }
}

struct AudioStatePresentation: Equatable {
    let localAudio: LocalAudioPresentation
    let cloudAudio: CloudAudioPresentation
    let processing: AudioProcessingPresentation
}

func audioStatePresentation(for item: AudioItem) -> AudioStatePresentation {
    let localAudio: LocalAudioPresentation
    if item.localOriginalAudioRemovedAt != nil {
        localAudio = .removed
    } else {
        switch item.localState {
        case .available, .recovered:
            localAudio = .available
        case .capturing:
            localAudio = .capturing
        case .finalizing:
            localAudio = .finalizing
        case .needsRecovery:
            localAudio = .needsRecovery
        }
    }

    let cloudAudio: CloudAudioPresentation
    switch item.cloudBackupState {
    case .notBackedUp: cloudAudio = .notBackedUp
    case .uploading: cloudAudio = .uploading
    case .paused: cloudAudio = .paused
    case .signInToResume: cloudAudio = .signInToResume
    case .failed: cloudAudio = .failed
    case .verifying: cloudAudio = .verifying
    case .backedUp: cloudAudio = .backedUp
    }

    return .init(localAudio: localAudio, cloudAudio: cloudAudio, processing: .notStarted)
}

func libraryAudioStatus(for item: AudioItem) -> LibraryAudioStatus {
    switch item.cloudBackupState {
    case .failed:
        return .uploadFailed
    case .uploading, .verifying:
        return .uploading
    case .paused, .signInToResume:
        return .uploadPaused
    case .notBackedUp, .backedUp:
        break
    }

    if item.localOriginalAudioRemovedAt != nil { return .cloudOnly }
    if item.cloudBackupState == .backedUp { return .backedUpInCloud }
    if item.captureEndedByInterruption { return .endedByInterruption }
    if item.captureEndedByUnavailableInput { return .endedByUnavailableInput }

    switch item.localState {
    case .available: return .onlyOnThisIPhone
    case .needsRecovery: return .needsRecovery
    case .capturing: return .capturing
    case .finalizing: return .finalizing
    case .recovered: return .recovered
    }
}
