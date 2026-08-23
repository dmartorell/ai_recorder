import Foundation

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

    func delete(_ id: UUID) throws {
        let url = url(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
