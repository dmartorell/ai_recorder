import AVFAudio
import AVFoundation
import Foundation

enum CaptureRecorderEvent: Equatable, Sendable {
    case interruptionBegan(Date)
    case routeChanged(Date, inputName: String)
    case inputBecameUnavailable(Date)
}

struct CaptureEvent: Equatable, Sendable {
    static let noInputName = "No input"

    enum Kind: String, Codable, Sendable {
        case interruptionBegan
        case interruptionEnded // Legacy persisted value. New Captures never emit it.
        case routeChanged
    }

    let kind: Kind
    let date: Date
    let audioPositionMilliseconds: Int
    let inputName: String?
}

enum CaptureNotificationMapper {
    static func observeAudioInterruptions(
        center: NotificationCenter = .default,
        handler: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil,
            using: handler
        )
    }

    static func captureInterruptionBeganDate(_ notification: Notification, now: Date = .now) -> Date? {
        notification.name == AVCaptureSession.wasInterruptedNotification ? now : nil
    }

    static func interruptionBeganDate(_ notification: Notification, now: Date = .now) -> Date? {
        guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: type) == .began else { return nil }
        return now
    }

    static func routeInputName(_ notification: Notification) -> String? {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: reasonValue) != nil else { return nil }
        let session = notification.object as? AVAudioSession
        return session?.currentRoute.inputs.first?.portName
    }
}
