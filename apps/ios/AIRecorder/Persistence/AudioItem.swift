import Foundation
import SwiftData

enum CaptureItemError: Error { case invalidState }

@Model
final class AudioItem {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var customTitle: String?
    var context: String
    var fileName: String
    var durationMilliseconds: Int
    var localStateRawValue: String
    var endedUnexpectedly: Bool
    var hasVerifiedCloudAudio: Bool
    @Relationship(deleteRule: .cascade, inverse: \Marker.audio) var markers: [Marker]
    @Relationship(deleteRule: .cascade, inverse: \CaptureEventRecord.audio) var events: [CaptureEventRecord]

    init(id: UUID = UUID(), startedAt: Date = .now, fileName: String) {
        self.id = id
        self.startedAt = startedAt
        self.fileName = fileName
        self.context = ""
        self.durationMilliseconds = 0
        self.localStateRawValue = LocalAudioState.capturing.rawValue
        self.endedUnexpectedly = false
        self.hasVerifiedCloudAudio = false
        self.markers = []
        self.events = []
    }

    var localState: LocalAudioState {
        get { LocalAudioState(rawValue: localStateRawValue) ?? .needsRecovery }
        set { localStateRawValue = newValue.rawValue }
    }

    var captureEndedByInterruption: Bool {
        endedUnexpectedly && terminalCaptureEvent?.kind == .interruptionBegan
    }

    var captureEndedByUnavailableInput: Bool {
        endedUnexpectedly
            && terminalCaptureEvent?.kind == .routeChanged
            && terminalCaptureEvent?.inputName == CaptureEvent.noInputName
    }

    private var terminalCaptureEvent: CaptureEventRecord? {
        events.max(by: { $0.startedAt < $1.startedAt })
    }

    func displayTitle(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = locale.identifier.hasPrefix("es") ? "d MMM yyyy, HH:mm 'h'" : "MMM d, yyyy, h:mm a"
        return "Audio - \(formatter.string(from: startedAt))"
    }
}
