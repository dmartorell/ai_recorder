import Foundation
import XCTest
@testable import AIRecorder

@MainActor
final class WorkerCloudBackupClientTests: XCTestCase {
    func testBeginBackupSendsAuthenticatedRequestAndDecodesUpload() async throws {
        let uploadID = UUID()
        let authentication = StubAccessTokenProvider()
        let transport = StubCloudBackupHTTPTransport(
            data: Data("{\"id\":\"\(uploadID.uuidString)\",\"state\":\"uploading\"}".utf8),
            response: HTTPURLResponse(
                url: URL(string: "https://backup.example.test/v1/audio-backups")!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let client = WorkerCloudBackupClient(
            baseURL: URL(string: "https://backup.example.test")!,
            authentication: authentication,
            transport: transport
        )

        let upload = try await client.beginBackup(
            .init(
                localAudioID: UUID(uuidString: "B5F1799A-92AB-43D1-951D-8E1DAC1B67D5")!,
                byteCount: 1_024,
                sha256: "aabbcc"
            )
        )

        XCTAssertEqual(upload, CloudBackupUpload(id: uploadID, state: .uploading))
        XCTAssertEqual(transport.request?.url?.path, "/v1/audio-backups")
        XCTAssertEqual(transport.request?.httpMethod, "POST")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let payload = try JSONSerialization.jsonObject(with: transport.request!.httpBody!) as? [String: Any]
        XCTAssertEqual(payload?["local_audio_id"] as? String, "B5F1799A-92AB-43D1-951D-8E1DAC1B67D5")
        XCTAssertEqual(payload?["byte_count"] as? Int, 1_024)
        XCTAssertEqual(payload?["sha256"] as? String, "aabbcc")
        XCTAssertEqual(payload?["transcription_language"] as? String, "spanish_english")
    }

    func testBeginBackupEncodesSelectedTranscriptionLanguage() async throws {
        let transport = StubCloudBackupHTTPTransport(
            data: Data("{\"id\":\"\(UUID().uuidString)\",\"state\":\"uploading\"}".utf8),
            response: HTTPURLResponse(url: URL(string: "https://backup.example.test/v1/audio-backups")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
        )
        let client = WorkerCloudBackupClient(
            baseURL: URL(string: "https://backup.example.test")!,
            authentication: StubAccessTokenProvider(),
            transport: transport
        )

        _ = try await client.beginBackup(.init(localAudioID: UUID(), byteCount: 1, sha256: "abc", transcriptionLanguage: .english))

        let payload = try JSONSerialization.jsonObject(with: transport.request!.httpBody!) as? [String: Any]
        XCTAssertEqual(payload?["transcription_language"] as? String, "english")
    }

    func testTranscriptionStatusUsesTheAuthorizedBackupEndpoint() async throws {
        let backupID = UUID()
        let transport = StubCloudBackupHTTPTransport(
            data: Data("{\"state\":\"queued\"}".utf8),
            response: HTTPURLResponse(
                url: URL(string: "https://backup.example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let client = WorkerCloudBackupClient(
            baseURL: URL(string: "https://backup.example.test")!,
            authentication: StubAccessTokenProvider(),
            transport: transport
        )

        let status = try await client.transcriptionStatus(id: backupID)

        XCTAssertEqual(status, .init(state: .queued))
        XCTAssertEqual(transport.request?.url?.path, "/v1/audio-backups/\(backupID.uuidString)/transcription")
        XCTAssertEqual(transport.request?.httpMethod, "GET")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
    }

    func testRetryTranscriptionUsesTheAuthorizedRetryEndpoint() async throws {
        let backupID = UUID()
        let transport = StubCloudBackupHTTPTransport(data: Data(), response: HTTPURLResponse(url: URL(string: "https://backup.example.test")!, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        let client = WorkerCloudBackupClient(baseURL: URL(string: "https://backup.example.test")!, authentication: StubAccessTokenProvider(), transport: transport)

        try await client.retryTranscription(id: backupID)

        XCTAssertEqual(transport.request?.url?.path, "/v1/audio-backups/\(backupID.uuidString)/transcription/retry")
        XCTAssertEqual(transport.request?.httpMethod, "POST")
    }

    func testBeginBackupRejectsAnUnsuccessfulWorkerResponse() async throws {
        let transport = StubCloudBackupHTTPTransport(
            data: Data(),
            response: HTTPURLResponse(
                url: URL(string: "https://backup.example.test/v1/audio-backups")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let client = WorkerCloudBackupClient(
            baseURL: URL(string: "https://backup.example.test")!,
            authentication: StubAccessTokenProvider(),
            transport: transport
        )

        do {
            _ = try await client.beginBackup(.init(localAudioID: UUID(), byteCount: 1, sha256: "abc"))
            XCTFail("Expected an unsuccessful response error")
        } catch let error as CloudBackupClientError {
            XCTAssertEqual(error, .unsuccessfulResponse(statusCode: 401))
        }
    }
}

@MainActor
private final class StubAccessTokenProvider: CloudAccessTokenProviding {
    func accessToken() async throws -> String { "test-access-token" }
}

@MainActor
private final class StubCloudBackupHTTPTransport: CloudBackupHTTPTransport {
    private let data: Data
    private let response: URLResponse
    private(set) var request: URLRequest?

    init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (data, response)
    }
}
