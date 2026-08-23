import Foundation

enum LocalAudioState: String, Codable, Sendable {
    case capturing, finalizing, available, recovered, needsRecovery
}
