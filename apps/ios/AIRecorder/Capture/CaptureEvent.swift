import AVFAudio
import AVFoundation
import Foundation

enum CaptureRecorderEvent: Equatable, Sendable {
    case interruptionBegan(Date)
    case inputLevelChanged(Float)
    case routeChanged(Date, inputName: String)
    case inputBecameUnavailable(Date)
}

struct CaptureInputRoute: Equatable, Sendable {
    let uid: String
    let name: String
    let portType: String
}

struct CaptureInputDevice: Equatable, Sendable {
    let uniqueID: String
    let name: String
}

enum CaptureInputSelection: Equatable, Sendable {
    case matched(CaptureInputDevice)
    case unavailable
    case unverified(routeName: String)
}

enum CaptureInputSelector {
    static func select(route: CaptureInputRoute?, devices: [CaptureInputDevice]) -> CaptureInputSelection {
        guard let route else { return .unavailable }
        guard let device = devices.first(where: { $0.uniqueID == route.uid })
                ?? devices.first(where: { $0.name == route.name })
        else {
            return .unverified(routeName: route.name)
        }
        return .matched(device)
    }
}

struct CaptureEvent: Equatable, Sendable {
    static let noInputName = "No input"

    enum Kind: String, Codable, Sendable {
        case interruptionBegan
        case interruptionEnded // Legacy persisted value. New Captures never emit it.
        case routeChanged
        case storageWarning
        case automaticFinalization
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

    static func currentInputRoute(_ session: AVAudioSession = .sharedInstance()) -> CaptureInputRoute? {
        guard let input = session.currentRoute.inputs.first else { return nil }
        return CaptureInputRoute(uid: input.uid, name: input.portName, portType: input.portType.rawValue)
    }

    static func routeInput(_ notification: Notification) -> CaptureInputRoute? {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: reasonValue) != nil else { return nil }
        return currentInputRoute(notification.object as? AVAudioSession ?? .sharedInstance())
    }

    static func routeInputName(_ notification: Notification) -> String? {
        routeInput(notification)?.name
    }
}
