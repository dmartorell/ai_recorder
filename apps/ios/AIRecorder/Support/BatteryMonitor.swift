import UIKit

@MainActor
protocol BatteryMonitoring: AnyObject {
    var level: Float { get }
    var isLowBattery: Bool { get }
    @discardableResult func refresh() -> Bool
}

@MainActor
final class BatteryMonitor: BatteryMonitoring {
    private let device: UIDevice
    let lowBatteryThreshold: Float
    private(set) var level: Float
    private(set) var isLowBattery: Bool

    init(device: UIDevice = .current, lowBatteryThreshold: Float = 0.20) {
        self.device = device
        self.lowBatteryThreshold = lowBatteryThreshold
        self.level = device.batteryLevel
        self.isLowBattery = device.batteryLevel >= 0 && device.batteryLevel <= lowBatteryThreshold
        device.isBatteryMonitoringEnabled = true
        refresh()
    }

    init(level: Float, lowBatteryThreshold: Float = 0.20) {
        self.device = .current
        self.lowBatteryThreshold = lowBatteryThreshold
        self.level = level
        self.isLowBattery = level >= 0 && level <= lowBatteryThreshold
    }

    @discardableResult
    func refresh() -> Bool {
        let currentLevel = device.batteryLevel
        level = currentLevel
        isLowBattery = currentLevel >= 0 && currentLevel <= lowBatteryThreshold
        return isLowBattery
    }
}
