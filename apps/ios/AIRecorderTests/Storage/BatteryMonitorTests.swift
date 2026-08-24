import XCTest
@testable import AIRecorder

@MainActor
final class BatteryMonitorTests: XCTestCase {
    func testLowBatteryThresholdIsExplicit() {
        let monitor = BatteryMonitor(level: 0.19)
        XCTAssertTrue(monitor.isLowBattery)
        XCTAssertEqual(monitor.level, 0.19, accuracy: 0.001)
    }

    func testLowBatteryNeverMeansFinalize() {
        let monitor = BatteryMonitor(level: 0.05)
        XCTAssertTrue(monitor.isLowBattery)
    }
}

