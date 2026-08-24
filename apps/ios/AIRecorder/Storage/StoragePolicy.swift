import Foundation

enum StorageAssessment: Equatable, Sendable {
    case sufficient(estimatedDuration: Duration)
    case warning(estimatedDuration: Duration)
    case critical
}

struct StoragePolicy: Sendable {
    let encodedBitsPerSecond: Int64
    let containerOverheadFraction: Double
    let safetyReserveBytes: Int64
    let warningLeadTime: Duration

    init(
        encodedBitsPerSecond: Int64 = 128_000,
        containerOverheadFraction: Double = 0.10,
        safetyReserveBytes: Int64 = 512 * 1_024 * 1_024,
        warningLeadTime: Duration = .seconds(30 * 60)
    ) {
        precondition(encodedBitsPerSecond > 0)
        precondition(containerOverheadFraction >= 0)
        precondition(safetyReserveBytes >= 0)
        self.encodedBitsPerSecond = encodedBitsPerSecond
        self.containerOverheadFraction = containerOverheadFraction
        self.safetyReserveBytes = safetyReserveBytes
        self.warningLeadTime = warningLeadTime
    }

    var encodedBytesPerSecondWithOverhead: Int64 {
        let base = Double(encodedBitsPerSecond) / 8
        return max(1, Int64((base * (1 + containerOverheadFraction)).rounded(.up)))
    }

    func assess(availableBytes: Int64) -> StorageAssessment {
        guard availableBytes > safetyReserveBytes else { return .critical }
        let usableBytes = availableBytes - safetyReserveBytes
        let seconds = usableBytes / encodedBytesPerSecondWithOverhead
        let estimate = Duration.seconds(seconds)
        return estimate <= warningLeadTime
            ? .warning(estimatedDuration: estimate)
            : .sufficient(estimatedDuration: estimate)
    }
}

protocol StorageMonitoring: AnyObject {
    var assessment: StorageAssessment { get }
    @discardableResult func refresh() -> StorageAssessment
}

final class UITestStorageMonitor: StorageMonitoring {
    var assessment: StorageAssessment = .sufficient(estimatedDuration: .seconds(24 * 60 * 60))
    func refresh() -> StorageAssessment { assessment }
}

final class StorageMonitor: StorageMonitoring {
    private let volumeURL: URL
    let policy: StoragePolicy
    private(set) var assessment: StorageAssessment

    init(volumeURL: URL, policy: StoragePolicy = StoragePolicy()) {
        self.volumeURL = volumeURL
        self.policy = policy
        self.assessment = .critical
        refresh()
    }

    @discardableResult
    func refresh() -> StorageAssessment {
        let availableBytes: Int64
        do {
            let values = try volumeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            availableBytes = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            availableBytes = 0
        }
        assessment = policy.assess(availableBytes: availableBytes)
        return assessment
    }
}
