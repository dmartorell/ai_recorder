import Foundation

@MainActor
protocol CloudBackupHTTPTransport: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

@MainActor
final class URLSessionCloudBackupHTTPTransport: CloudBackupHTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

@MainActor
final class WorkerCloudBackupClient: CloudBackupClient {
    private let baseURL: URL
    private let authentication: any CloudAccessTokenProviding
    private let transport: any CloudBackupHTTPTransport

    init(baseURL: URL, authentication: any CloudAccessTokenProviding, transport: any CloudBackupHTTPTransport = URLSessionCloudBackupHTTPTransport()) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.transport = transport
    }

    func beginBackup(_ backup: CloudBackupRequest) async throws -> CloudBackupUpload {
        try await send(path: "v1/audio-backups", method: "POST", body: BackupRequestBody(backup))
    }

    func beginMultipartUpload(id: UUID) async throws -> CloudBackupMultipartStatus {
        try await send(path: "v1/audio-backups/\(id.uuidString)/multipart", method: "POST", body: Optional<EmptyBody>.none)
    }

    func multipartStatus(id: UUID) async throws -> CloudBackupMultipartStatus {
        try await send(path: "v1/audio-backups/\(id.uuidString)", method: "GET", body: Optional<EmptyBody>.none)
    }

    func signedPartUpload(id: UUID, partNumber: Int, sha256: String) async throws -> CloudBackupPartUpload {
        try await send(path: "v1/audio-backups/\(id.uuidString)/parts/\(partNumber)/url", method: "POST", body: PartSHA256Body(sha256: sha256))
    }

    func confirmPart(id: UUID, partNumber: Int, eTag: String) async throws {
        try await sendEmpty(path: "v1/audio-backups/\(id.uuidString)/parts/\(partNumber)/confirm", method: "POST", body: PartETagBody(etag: eTag))
    }

    func completeMultipartUpload(id: UUID) async throws -> CloudBackupUpload {
        try await send(path: "v1/audio-backups/\(id.uuidString)/complete", method: "POST", body: Optional<EmptyBody>.none)
    }

    func cancelMultipartUpload(id: UUID) async throws {
        try await sendEmpty(path: "v1/audio-backups/\(id.uuidString)/cancel", method: "POST", body: Optional<EmptyBody>.none)
    }

    private func send<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body? = nil) async throws -> Response {
        let request = try await authenticatedRequest(path: path, method: method, body: body)
        let (data, response) = try await transport.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func sendEmpty<Body: Encodable>(path: String, method: String, body: Body? = nil) async throws {
        let request = try await authenticatedRequest(path: path, method: method, body: body)
        let (_, response) = try await transport.data(for: request)
        try validate(response)
    }

    private func authenticatedRequest<Body: Encodable>(path: String, method: String, body: Body?) async throws -> URLRequest {
        let accessToken = try await authentication.accessToken()
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw CloudBackupClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw CloudBackupClientError.unsuccessfulResponse(statusCode: response.statusCode) }
    }
}

private struct BackupRequestBody: Encodable {
    let localAudioID: UUID
    let byteCount: Int
    let sha256: String
    init(_ request: CloudBackupRequest) { localAudioID = request.localAudioID; byteCount = request.byteCount; sha256 = request.sha256 }
    enum CodingKeys: String, CodingKey { case localAudioID = "local_audio_id"; case byteCount = "byte_count"; case sha256 }
}
private struct EmptyBody: Encodable {}
private struct PartSHA256Body: Encodable { let sha256: String }
private struct PartETagBody: Encodable { let etag: String }

enum CloudBackupClientError: LocalizedError, Equatable {
    case invalidResponse
    case unsuccessfulResponse(statusCode: Int)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The cloud backup service returned an invalid response."
        case let .unsuccessfulResponse(statusCode): "The cloud backup service rejected the request (HTTP \(statusCode))."
        }
    }
}
