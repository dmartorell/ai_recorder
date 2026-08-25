import Foundation
import SwiftData
import XCTest
@testable import AIRecorder

@MainActor
final class CloudBackupCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var files: AudioFileStore!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: AudioItem.self, Marker.self, CaptureEventRecord.self, configurations: configuration)
        files = AudioFileStore(rootDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    func testBackupEligibleAudioUploadsOnlyAfterExplicitConfirmation() async throws {
        let item = availableAudio()
        let client = FakeCloudBackupClient()
        let coordinator = CloudBackupCoordinator(client: client, files: files, uploader: FakePartUploader(), persistence: FakeBackupPersistence())

        await coordinator.requestBackup(for: item)
        XCTAssertEqual(coordinator.pendingConfirmationAudioID, item.id)
        XCTAssertTrue(client.requests.isEmpty)

        await coordinator.confirmBackup(for: item)

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.byteCount, 15)
        XCTAssertEqual(client.requests.first?.sha256, "bf639d89a3de0c2e761d336fc7bf954cd615c5a65aad89915421e9e95179507e")
        XCTAssertEqual(client.confirmedPartNumbers, [1])
        XCTAssertEqual(item.cloudBackupState, .backedUp)
    }

    func testBackupRefusesAnIneligibleAudio() async throws {
        let item = AudioItem(fileName: "active.m4a")
        let client = FakeCloudBackupClient()
        let coordinator = CloudBackupCoordinator(client: client, files: files, uploader: FakePartUploader(), persistence: FakeBackupPersistence())

        await coordinator.requestBackup(for: item)

        XCTAssertNil(coordinator.pendingConfirmationAudioID)
        XCTAssertEqual(item.cloudBackupState, .notBackedUp)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testLaunchRecoveryResumesPersistedPendingBackups() async throws {
        let first = availableAudio()
        let second = availableAudio()
        first.cloudBackupID = UUID()
        second.cloudBackupID = UUID()
        first.cloudBackupState = .paused
        second.cloudBackupState = .verifying
        let client = FakeCloudBackupClient()
        let persistence = FakeBackupPersistence(pendingItems: [first, second])
        let coordinator = CloudBackupCoordinator(client: client, files: files, uploader: FakePartUploader(), persistence: persistence)

        await CloudBackupRecoveryService(persistence: persistence, coordinator: coordinator).recoverPendingBackups()

        XCTAssertEqual(Set(client.statusRequests.compactMap { $0 }), Set([first.cloudBackupID, second.cloudBackupID].compactMap { $0 }))
        XCTAssertEqual(first.cloudBackupState, .backedUp)
        XCTAssertEqual(second.cloudBackupState, .backedUp)
    }

    func testResumeConfirmsCompletedBackgroundPartBeforeCompleting() async throws {
        let item = availableAudio()
        let backupID = UUID()
        item.cloudBackupID = backupID
        let client = FakeCloudBackupClient()
        let uploader = FakePartUploader(completedParts: [.init(partNumber: 1, eTag: "completed-etag")])
        let coordinator = CloudBackupCoordinator(client: client, files: files, uploader: uploader, persistence: FakeBackupPersistence())

        await coordinator.resumeBackup(for: item)

        XCTAssertEqual(client.confirmedPartNumbers, [1])
        XCTAssertTrue(client.signedPartNumbers.isEmpty)
        XCTAssertEqual(item.cloudBackupState, .backedUp)
    }

    func testTransientPartFailureRetriesAtMostThreeTimes() async throws {
        let item = availableAudio()
        let uploader = FakePartUploader(failuresBeforeSuccess: 3)
        let coordinator = CloudBackupCoordinator(client: FakeCloudBackupClient(), files: files, uploader: uploader, persistence: FakeBackupPersistence())

        await coordinator.requestBackup(for: item)
        await coordinator.confirmBackup(for: item)

        XCTAssertEqual(uploader.uploadAttempts, 4)
        XCTAssertEqual(item.cloudBackupState, .backedUp)
    }

    func testNetworkInterruptionPausesBackupForLaterRecovery() async throws {
        let item = availableAudio()
        let uploader = FakePartUploader(uploadError: URLError(.networkConnectionLost))
        let coordinator = CloudBackupCoordinator(client: FakeCloudBackupClient(), files: files, uploader: uploader, persistence: FakeBackupPersistence())

        await coordinator.requestBackup(for: item)
        await coordinator.confirmBackup(for: item)

        XCTAssertEqual(uploader.uploadAttempts, 1)
        XCTAssertEqual(item.cloudBackupState, .paused)
    }

    func testLostCompletionResponseVerifiesWithoutUploadingPartsAgain() async throws {
        let item = availableAudio()
        let client = FakeCloudBackupClient()
        client.completeError = URLError(.networkConnectionLost)
        let coordinator = CloudBackupCoordinator(client: client, files: files, uploader: FakePartUploader(), persistence: FakeBackupPersistence())

        await coordinator.requestBackup(for: item)
        await coordinator.confirmBackup(for: item)
        XCTAssertEqual(item.cloudBackupState, .paused)
        XCTAssertEqual(client.signedPartNumbers, [1])

        client.completeError = nil
        await coordinator.resumeBackup(for: item)

        XCTAssertEqual(item.cloudBackupState, .backedUp)
        XCTAssertEqual(client.signedPartNumbers, [1])
    }

    func testConnectivityLossMarksPendingBackupPaused() throws {
        let item = availableAudio()
        item.cloudBackupID = UUID()
        item.cloudBackupState = .uploading
        let persistence = FakeBackupPersistence(pendingItems: [item])
        let coordinator = CloudBackupCoordinator(client: FakeCloudBackupClient(), files: files, uploader: FakePartUploader(), persistence: persistence)
        let connectivity = FakeConnectivityMonitor()
        let service = CloudBackupRecoveryService(persistence: persistence, coordinator: coordinator, connectivity: connectivity)

        service.start()
        connectivity.connectionWasLost()

        XCTAssertEqual(item.cloudBackupState, .paused)
    }

    func testConnectivityRecoveryResumesPausedBackup() async throws {
        let item = availableAudio()
        item.cloudBackupID = UUID()
        item.cloudBackupState = .paused
        let client = FakeCloudBackupClient()
        let completed = expectation(description: "backup completed")
        client.onComplete = { completed.fulfill() }
        let connectivity = FakeConnectivityMonitor()
        let persistence = FakeBackupPersistence(pendingItems: [item])
        let coordinator = CloudBackupCoordinator(client: client, files: files, uploader: FakePartUploader(), persistence: persistence)
        let service = CloudBackupRecoveryService(persistence: persistence, coordinator: coordinator, connectivity: connectivity)

        service.start()
        connectivity.connectionBecameAvailable()
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(item.cloudBackupState, .backedUp)
    }

    private func availableAudio() -> AudioItem {
        let item = AudioItem(fileName: "source.m4a")
        item.localState = .available
        try! files.prepare(for: item.id)
        try! Data("synthetic audio".utf8).write(to: files.url(for: item.id))
        return item
    }
}

private final class FakeCloudBackupClient: CloudBackupClient {
    var requests = [CloudBackupRequest]()
    var confirmedPartNumbers = [Int]()
    var signedPartNumbers = [Int]()
    var statusRequests = [UUID?]()
    private var serverConfirmedParts = Set<Int>()
    private let backupID = UUID()
    private var backupState: CloudBackupState = .uploading
    var completeError: Error?
    var onComplete: (() -> Void)?

    func beginBackup(_ request: CloudBackupRequest) async throws -> CloudBackupUpload {
        requests.append(request)
        return .init(id: backupID, state: .uploading)
    }

    func beginMultipartUpload(id: UUID) async throws -> CloudBackupMultipartStatus {
        status(id: id)
    }

    func multipartStatus(id: UUID) async throws -> CloudBackupMultipartStatus {
        statusRequests.append(id)
        return status(id: id)
    }

    func signedPartUpload(id: UUID, partNumber: Int, sha256: String) async throws -> CloudBackupPartUpload {
        signedPartNumbers.append(partNumber)
        return .init(url: URL(string: "https://backup.example.test/part")!, expiresIn: 900)
    }

    func confirmPart(id: UUID, partNumber: Int, eTag: String) async throws {
        confirmedPartNumbers.append(partNumber)
        serverConfirmedParts.insert(partNumber)
    }
    private func status(id: UUID) -> CloudBackupMultipartStatus {
        .init(id: id, state: backupState, confirmedParts: serverConfirmedParts.sorted().map { .init(partNumber: $0, byteCount: 15) }, partSize: 8 * 1_024 * 1_024)
    }
    func completeMultipartUpload(id: UUID) async throws -> CloudBackupUpload {
        backupState = .backedUp
        if let completeError { throw completeError }
        onComplete?()
        return .init(id: id, state: .backedUp)
    }
    func cancelMultipartUpload(id: UUID) async throws {}
}

private final class FakeBackupPersistence: CloudBackupPersisting {
    private let pendingItems: [AudioItem]

    init(pendingItems: [AudioItem] = []) {
        self.pendingItems = pendingItems
    }

    func saveBackupAssociation(for item: AudioItem, backupID: UUID, state: CloudBackupState) throws {
        item.cloudBackupID = backupID
        item.cloudBackupState = state
    }
    func saveBackupState(for item: AudioItem, state: CloudBackupState) throws { item.cloudBackupState = state }
    func pendingBackups() throws -> [AudioItem] { pendingItems }
}

private final class FakeConnectivityMonitor: CloudBackupConnectivityMonitoring {
    private var onConnectivityChanged: (@MainActor (Bool) -> Void)?

    func start(onConnectivityChanged: @escaping @MainActor (Bool) -> Void) {
        self.onConnectivityChanged = onConnectivityChanged
    }

    func connectionBecameAvailable() {
        onConnectivityChanged?(true)
    }

    func connectionWasLost() {
        onConnectivityChanged?(false)
    }
}

private final class FakePartUploader: CloudBackupPartUploading {
    private var completed: [CloudBackupCompletedPart]
    private var failuresBeforeSuccess: Int
    private let uploadError: Error?
    private(set) var uploadAttempts = 0

    init(completedParts: [CloudBackupCompletedPart] = [], failuresBeforeSuccess: Int = 0, uploadError: Error? = nil) {
        completed = completedParts
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.uploadError = uploadError
    }

    func upload(fileURL: URL, to url: URL, sha256: String, context: CloudBackupPartContext) async throws -> String {
        uploadAttempts += 1
        if let uploadError { throw uploadError }
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw CloudBackupError.partUploadFailed
        }
        return "etag"
    }
    func completedParts(for backupID: UUID) -> [CloudBackupCompletedPart] { completed }
    func discardCompletedPart(_ partNumber: Int, backupID: UUID) { completed.removeAll { $0.partNumber == partNumber } }
}
