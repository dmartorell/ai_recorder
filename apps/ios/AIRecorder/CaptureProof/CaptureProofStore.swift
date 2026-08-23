import Foundation

struct CaptureProofStore {
    private enum Key {
        static let captureWasActive = "captureProof.captureWasActive"
        static let captureStartedAt = "captureProof.captureStartedAt"
        static let currentFileName = "captureProof.currentFileName"
    }

    private let rootDirectory: URL
    private let defaults: UserDefaults

    init(rootDirectory: URL, defaults: UserDefaults = .standard) {
        self.rootDirectory = rootDirectory
        self.defaults = defaults
    }

    var outputURL: URL {
        proofDirectory.appendingPathComponent(
            defaults.string(forKey: Key.currentFileName) ?? "current.m4a",
            isDirectory: false
        )
    }

    private var proofDirectory: URL {
        rootDirectory.appendingPathComponent("CaptureProof", isDirectory: true)
    }

    static func applicationStore() throws -> CaptureProofStore {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return CaptureProofStore(rootDirectory: applicationSupport)
    }

    var captureWasActive: Bool {
        defaults.bool(forKey: Key.captureWasActive)
    }

    var captureStartedAt: Date? {
        defaults.object(forKey: Key.captureStartedAt) as? Date
    }

    func prepareForCapture() throws {
        try FileManager.default.createDirectory(
            at: proofDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )

        defaults.set("\(UUID().uuidString).m4a", forKey: Key.currentFileName)
        defaults.set(true, forKey: Key.captureWasActive)
        defaults.set(Date(), forKey: Key.captureStartedAt)
    }

    func markCaptureHandled() {
        defaults.removeObject(forKey: Key.captureWasActive)
        defaults.removeObject(forKey: Key.captureStartedAt)
    }
}
