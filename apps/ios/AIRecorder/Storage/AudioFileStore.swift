import Foundation

struct PermanentDeletionConfirmation: Sendable {
    fileprivate init() { }
}

struct AudioFileStore: Sendable {
    let rootDirectory: URL

    init(rootDirectory: URL) { self.rootDirectory = rootDirectory }

    static func applicationStore() throws -> AudioFileStore {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("OriginalAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        return AudioFileStore(rootDirectory: root)
    }

    func url(for id: UUID) -> URL { rootDirectory.appendingPathComponent("\(id.uuidString).m4a") }

    func prepare(for id: UUID) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
    }

    func cloudBackupPartURL(backupID: UUID, partNumber: Int) throws -> URL {
        let directory = rootDirectory
            .appendingPathComponent("CloudBackupParts", isDirectory: true)
            .appendingPathComponent(backupID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        return directory.appendingPathComponent("part-\(partNumber)")
    }

    func removeCloudBackupPart(backupID: UUID, partNumber: Int) {
        let url = rootDirectory
            .appendingPathComponent("CloudBackupParts", isDirectory: true)
            .appendingPathComponent(backupID.uuidString, isDirectory: true)
            .appendingPathComponent("part-\(partNumber)")
        try? FileManager.default.removeItem(at: url)
    }

    func removeCloudBackupParts(for backupID: UUID) {
        let url = rootDirectory
            .appendingPathComponent("CloudBackupParts", isDirectory: true)
            .appendingPathComponent(backupID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
    }

    func confirmPermanentDeletion(id: UUID) -> PermanentDeletionConfirmation {
        PermanentDeletionConfirmation()
    }

    func delete(_ id: UUID, confirmation: PermanentDeletionConfirmation) throws {
        let url = url(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
