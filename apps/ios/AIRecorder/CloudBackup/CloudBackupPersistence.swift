import Foundation
import SwiftData

@MainActor
protocol CloudBackupPersisting: AnyObject {
    func saveBackupAssociation(for item: AudioItem, backupID: UUID, state: CloudBackupState) throws
    func saveBackupState(for item: AudioItem, state: CloudBackupState) throws
    func pendingBackups() throws -> [AudioItem]
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

    func saveBackupState(for item: AudioItem, state: CloudBackupState) throws {
        item.cloudBackupState = state
        try context.save()
    }

    func pendingBackups() throws -> [AudioItem] {
        try context.fetch(FetchDescriptor<AudioItem>()).filter { $0.cloudBackupState.preventsLocalDeletion }
    }
}

@MainActor
final class CloudBackupRecoveryService {
    private let persistence: any CloudBackupPersisting
    private let coordinator: CloudBackupCoordinator

    init(persistence: any CloudBackupPersisting, coordinator: CloudBackupCoordinator) {
        self.persistence = persistence
        self.coordinator = coordinator
    }

    func recoverPendingBackups() async {
        guard let items = try? persistence.pendingBackups() else { return }
        for item in items {
            await coordinator.resumeBackup(for: item)
        }
    }
}
