import AVFoundation
import XCTest
@testable import AIRecorder

final class CaptureEventTests: XCTestCase {
    func testAudioInterruptionObserverAcceptsNotificationsFromAnyObject() async {
        let center = NotificationCenter()
        let expectation = expectation(description: "Interruption observed")
        let token = CaptureNotificationMapper.observeAudioInterruptions(center: center) { notification in
            if CaptureNotificationMapper.interruptionBeganDate(notification) != nil {
                expectation.fulfill()
            }
        }

        center.post(
            name: AVAudioSession.interruptionNotification,
            object: NSObject(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )

        await fulfillment(of: [expectation], timeout: 0.1)
        center.removeObserver(token)
    }

    func testCaptureSessionPreservesTheApplicationSelectedAudioRoute() {
        let session = AVCaptureSession()

        FragmentedM4ARecorder.preserveApplicationAudioRoute(for: session)

        XCTAssertTrue(session.usesApplicationAudioSession)
        XCTAssertFalse(session.automaticallyConfiguresApplicationAudioSession)
    }

    func testInputSelectorMatchesTheRoutedDeviceByUniqueIdentifier() {
        let route = CaptureInputRoute(uid: "usb-1", name: "USB Microphone", portType: "USBAudio")
        let devices = [
            CaptureInputDevice(uniqueID: "built-in", name: "Built-in Microphone"),
            CaptureInputDevice(uniqueID: "usb-1", name: "USB Microphone")
        ]

        XCTAssertEqual(
            CaptureInputSelector.select(route: route, devices: devices),
            .matched(devices[1])
        )
    }

    func testInputSelectorFallsBackToMatchingRouteNameWhenUIDNamespacesDiffer() {
        let route = CaptureInputRoute(uid: "port-1", name: "USB Microphone", portType: "USBAudio")
        let device = CaptureInputDevice(uniqueID: "device-1", name: "USB Microphone")

        XCTAssertEqual(
            CaptureInputSelector.select(route: route, devices: [device]),
            .matched(device)
        )
    }

    func testInputSelectorDoesNotFallbackToADeviceWhenRouteCannotBeVerified() {
        let route = CaptureInputRoute(uid: "bluetooth-1", name: "Bluetooth Headset", portType: "BluetoothHFP")
        let devices = [CaptureInputDevice(uniqueID: "built-in", name: "Built-in Microphone")]

        XCTAssertEqual(
            CaptureInputSelector.select(route: route, devices: devices),
            .unverified(routeName: "Bluetooth Headset")
        )
    }

    func testInputSelectorReportsNoInputWithoutAnActiveRoute() {
        XCTAssertEqual(CaptureInputSelector.select(route: nil, devices: []), .unavailable)
    }

    func testOnlyCaptureSessionInterruptionBeginningMapsToFinalizationEvent() {
        let date = Date(timeIntervalSince1970: 123)
        let began = Notification(name: AVCaptureSession.wasInterruptedNotification)
        let ended = Notification(name: AVCaptureSession.interruptionEndedNotification)

        XCTAssertEqual(CaptureNotificationMapper.captureInterruptionBeganDate(began, now: date), date)
        XCTAssertNil(CaptureNotificationMapper.captureInterruptionBeganDate(ended, now: date))
    }
}
