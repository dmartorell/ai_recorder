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
        }
    }
}

func libraryAudioStatus(for item: AudioItem) -> LibraryAudioStatus {
    if item.captureEndedByInterruption { return .endedByInterruption }
    if item.captureEndedByUnavailableInput { return .endedByUnavailableInput }
    if item.cloudBackupState == .backedUp { return .backedUpInCloud }

    switch item.localState {
    case .available: return .onlyOnThisIPhone
    case .needsRecovery: return .needsRecovery
    case .capturing: return .capturing
    case .finalizing: return .finalizing
    case .recovered: return .recovered
    }
}
