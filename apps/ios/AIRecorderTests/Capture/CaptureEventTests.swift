import AVFoundation
import XCTest
@testable import AIRecorder

final class CaptureEventTests: XCTestCase {
    func testCaptureSessionInterruptionNotificationsMapToRecorderEvents() {
        let date = Date(timeIntervalSince1970: 123)
        let began = Notification(name: AVCaptureSession.wasInterruptedNotification)
        let ended = Notification(name: AVCaptureSession.interruptionEndedNotification)

        XCTAssertEqual(CaptureNotificationMapper.captureInterruptionBeganDate(began, now: date), date)
        let mappedEnd = CaptureNotificationMapper.captureInterruptionEnded(ended, now: date)
        XCTAssertEqual(mappedEnd?.date, date)
        XCTAssertTrue(mappedEnd?.shouldResume == true)
    }
}
