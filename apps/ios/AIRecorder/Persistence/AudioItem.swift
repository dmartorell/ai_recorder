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
    var localOriginalAudioRemovedAt: Date?
    var cloudBackupStateRawValue: String?
    var cloudBackupID: UUID?
    var transcriptionStateRawValue: String?
    var transcriptionLanguageRawValue: String?
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
        self.localOriginalAudioRemovedAt = nil
        self.cloudBackupStateRawValue = CloudBackupState.notBackedUp.rawValue
        self.cloudBackupID = nil
        self.transcriptionStateRawValue = TranscriptionState.notStarted.rawValue
        self.transcriptionLanguageRawValue = TranscriptionLanguage.spanishEnglish.rawValue
        self.markers = []
        self.events = []
    }

    var localState: LocalAudioState {
        get { LocalAudioState(rawValue: localStateRawValue) ?? .needsRecovery }
        set { localStateRawValue = newValue.rawValue }
    }

    var cloudBackupState: CloudBackupState {
        get { CloudBackupState(rawValue: cloudBackupStateRawValue ?? "") ?? .notBackedUp }
        set {
            cloudBackupStateRawValue = newValue.rawValue
            hasVerifiedCloudAudio = newValue == .backedUp
        }
    }

    var transcriptionState: TranscriptionState {
        get { TranscriptionState(rawValue: transcriptionStateRawValue ?? "") ?? .notStarted }
        set { transcriptionStateRawValue = newValue.rawValue }
    }

    var transcriptionLanguage: TranscriptionLanguage {
        get { TranscriptionLanguage(rawValue: transcriptionLanguageRawValue ?? "") ?? .spanishEnglish }
        set { transcriptionLanguageRawValue = newValue.rawValue }
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
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMMyyyy")

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")

        let date = dateFormatter.string(from: startedAt)
        let time = timeFormatter.string(from: startedAt).replacingOccurrences(of: "\u{202F}", with: " ")
        return "\(date), \(time)"
    }
}
