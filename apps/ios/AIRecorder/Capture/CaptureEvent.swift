import AVFAudio
import Foundation

enum CaptureRecorderEvent: Equatable, Sendable {
    case interruptionBegan(Date)
    case interruptionEnded(Date, shouldResume: Bool)
    case routeChanged(Date, inputName: String)
}

struct CaptureEvent: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case interruptionBegan
        case interruptionEnded
        case routeChanged
    }

    let kind: Kind
    let date: Date
    let audioPositionMilliseconds: Int
    let inputName: String?
    let shouldResume: Bool
}

enum CaptureNotificationMapper {
    static func interruptionBeganDate(_ notification: Notification, now: Date = .now) -> Date? {
        guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: type) == .began else { return nil }
        return now
    }

    static func interruptionEnded(_ notification: Notification, now: Date = .now) -> (date: Date, shouldResume: Bool)? {
        guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: type) == .ended else { return nil }
        let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        return (now, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
    }

    static func routeInputName(_ notification: Notification, fallback: String = "No input") -> String? {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: reasonValue) != nil else { return nil }
        let session = notification.object as? AVAudioSession
        return session?.currentRoute.inputs.first?.portName ?? fallback
    }
}
