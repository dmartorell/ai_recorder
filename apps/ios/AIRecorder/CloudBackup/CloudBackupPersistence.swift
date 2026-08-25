import Foundation
import Network
import SwiftData

@MainActor
protocol CloudBackupPersisting: AnyObject {
    func saveBackupAssociation(for item: AudioItem, backupID: UUID, state: CloudBackupState) throws
    func clearBackupAssociation(for item: AudioItem) throws
    func saveBackupState(for item: AudioItem, state: CloudBackupState) throws
    func saveTranscriptionState(for item: AudioItem, state: TranscriptionState) throws
    func pendingBackups() throws -> [AudioItem]
    func backedUpAudio() throws -> [AudioItem]
}

@MainActor
final class SwiftDataCloudBackupPersistence: CloudBackupPersisting {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func saveBackupAssociation(for item: AudioItem, backupID: UUID, state: CloudBackupState) throws {
        item.cloudBackupID = backupID
        item.cloudBackupState = state
        try context.save()
    }

    func clearBackupAssociation(for item: AudioItem) throws {
        item.cloudBackupID = nil
        item.cloudBackupState = .notBackedUp
        try context.save()
    }

    func saveBackupState(for item: AudioItem, state: CloudBackupState) throws {
        item.cloudBackupState = state
        try context.save()
    }

    func saveTranscriptionState(for item: AudioItem, state: TranscriptionState) throws {
        item.transcriptionState = state
        try context.save()
    }

    func pendingBackups() throws -> [AudioItem] {
        try context.fetch(FetchDescriptor<AudioItem>()).filter { $0.cloudBackupState.isIncomplete }
    }

    func backedUpAudio() throws -> [AudioItem] {
        try context.fetch(FetchDescriptor<AudioItem>()).filter { $0.cloudBackupState == .backedUp }
    }
}

@MainActor
protocol CloudBackupConnectivityMonitoring: AnyObject {
    func start(onConnectivityChanged: @escaping @MainActor (Bool) -> Void)
}

@MainActor
final class NetworkCloudBackupConnectivityMonitor: CloudBackupConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    private var started = false

    func start(onConnectivityChanged: @escaping @MainActor (Bool) -> Void) {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in onConnectivityChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.airecorder.cloud-backup-connectivity"))
    }
}

@MainActor
final class CloudBackupRecoveryService {
    private let persistence: any CloudBackupPersisting
    private let coordinator: CloudBackupCoordinator
    private let connectivity: any CloudBackupConnectivityMonitoring
    private var isRecovering = false
    private var isAppActive = false

    init(persistence: any CloudBackupPersisting, coordinator: CloudBackupCoordinator, connectivity: any CloudBackupConnectivityMonitoring = NetworkCloudBackupConnectivityMonitor()) {
        self.persistence = persistence
        self.coordinator = coordinator
        self.connectivity = connectivity
    }

    func start() {
        connectivity.start { [weak self] isConnected in
            guard let self else { return }
            if isConnected, self.isAppActive {
                Task { @MainActor in await self.recoverPendingBackups() }
            } else if !isConnected {
                self.handleConnectivityLoss()
            }
        }
    }

    func setAppIsActive(_ isActive: Bool) {
        isAppActive = isActive
        guard isActive else { return }
        Task { @MainActor in await recoverPendingBackups() }
    }

    func handleConnectivityLoss() {
        guard let items = try? persistence.pendingBackups() else { return }
        for item in items where item.cloudBackupState.preventsLocalDeletion && item.cloudBackupState != .paused {
            try? persistence.saveBackupState(for: item, state: .paused)
        }
    }

    func recoverPendingBackups() async {
        guard !isRecovering, let items = try? persistence.pendingBackups() else { return }
        isRecovering = true
        defer { isRecovering = false }
        for item in items where item.cloudBackupState != .signInToResume {
            await coordinator.resumeBackup(for: item)
        }
    }
}
