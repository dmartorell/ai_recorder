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

    func testOnlyCaptureSessionInterruptionBeginningMapsToFinalizationEvent() {
        let date = Date(timeIntervalSince1970: 123)
        let began = Notification(name: AVCaptureSession.wasInterruptedNotification)
        let ended = Notification(name: AVCaptureSession.interruptionEndedNotification)

        XCTAssertEqual(CaptureNotificationMapper.captureInterruptionBeganDate(began, now: date), date)
        XCTAssertNil(CaptureNotificationMapper.captureInterruptionBeganDate(ended, now: date))
    }
}
