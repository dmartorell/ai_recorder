import Foundation
import SwiftData

@Model
final class CaptureEventRecord {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var startedAt: Date
    var endedAt: Date?
    var audioPositionMilliseconds: Int
    var inputName: String?
    var audio: AudioItem?

    init(
        id: UUID = UUID(),
        kind: CaptureEvent.Kind,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        audioPositionMilliseconds: Int,
        inputName: String? = nil,
        audio: AudioItem? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioPositionMilliseconds = audioPositionMilliseconds
        self.inputName = inputName
        self.audio = audio
    }

    var kind: CaptureEvent.Kind {
        get { CaptureEvent.Kind(rawValue: kindRawValue) ?? .routeChanged }
        set { kindRawValue = newValue.rawValue }
    }
}
