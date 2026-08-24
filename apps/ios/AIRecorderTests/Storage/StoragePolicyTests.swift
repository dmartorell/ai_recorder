import Foundation
import XCTest
@testable import AIRecorder

final class StoragePolicyTests: XCTestCase {
    private let policy = StoragePolicy(
        encodedBitsPerSecond: 128_000,
        containerOverheadFraction: 0.10,
        safetyReserveBytes: 512 * 1_024 * 1_024,
        warningLeadTime: .seconds(30 * 60)
    )

    func testReserveOrLessIsCritical() {
        XCTAssertEqual(policy.assess(availableBytes: 512 * 1_024 * 1_024), .critical)
    }

    func testEstimateNeverExceedsConservativeCapacity() {
        let available: Int64 = 2 * 1_024 * 1_024 * 1_024
        let assessment = policy.assess(availableBytes: available)
        guard case let .sufficient(duration) = assessment else { return XCTFail("Expected sufficient capacity") }
        let seconds = duration.components.seconds
        XCTAssertLessThanOrEqual(seconds, (available - policy.safetyReserveBytes) / policy.encodedBytesPerSecondWithOverhead)
    }

    func testCapacityWithinWarningLeadTimeReturnsWarning() {
        let bytesPerSecond = policy.encodedBytesPerSecondWithOverhead
        let available = policy.safetyReserveBytes + bytesPerSecond * 60 * 10
        guard case .warning = policy.assess(availableBytes: available) else {
            return XCTFail("Expected warning")
        }
    }
}
