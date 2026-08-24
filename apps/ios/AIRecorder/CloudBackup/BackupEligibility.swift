import Foundation

enum BackupEligibility: Equatable {
    case eligible
    case captureIsActive
    case originalAudioIsUnverified
    case originalAudioIsMissing
    case originalAudioIsEmpty

    static func forBackup(of item: AudioItem, files: AudioFileStore) -> Self {
        switch item.localState {
        case .capturing, .finalizing:
            return .captureIsActive
        case .needsRecovery:
            return .originalAudioIsUnverified
        case .available, .recovered:
            break
        }

        let url = files.url(for: item.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return .originalAudioIsMissing }
        guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 0 else {
            return .originalAudioIsEmpty
        }
        return .eligible
    }
}
