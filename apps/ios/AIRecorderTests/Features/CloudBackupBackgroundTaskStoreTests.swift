import Foundation
import XCTest
@testable import AIRecorder

@MainActor
final class CloudBackupBackgroundTaskStoreTests: XCTestCase {
    func testPersistsOnlyPartTaskMetadataForRelaunchRecovery() throws {
        let suiteName = "CloudBackupBackgroundTaskStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "tasks"
        let localAudioID = UUID()
        let context = CloudBackupPartContext(localAudioID: localAudioID, backupID: UUID(), partNumber: 3)
        let store = CloudBackupBackgroundTaskStore(defaults: defaults, key: key)
        store.save(.init(context: context, filePath: "/private/parts/part-3", taskIdentifier: 42, eTag: nil))

        let restored = CloudBackupBackgroundTaskStore(defaults: defaults, key: key)

        XCTAssertEqual(restored.record(for: context)?.context.localAudioID, localAudioID)
        XCTAssertEqual(restored.record(for: context)?.taskIdentifier, 42)
        XCTAssertEqual(restored.record(taskIdentifier: 42)?.context, context)
        XCTAssertEqual(restored.record(for: context)?.filePath, "/private/parts/part-3")
        XCTAssertNil(restored.record(for: context)?.eTag)
        XCTAssertFalse(String(data: try XCTUnwrap(defaults.data(forKey: key)), encoding: .utf8)!.contains("https://"))
    }
}
