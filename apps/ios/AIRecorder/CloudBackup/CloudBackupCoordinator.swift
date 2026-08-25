import CryptoKit
import Foundation
import Observation

struct CloudBackupRequest: Equatable, Sendable { let localAudioID: UUID; let byteCount: Int; let sha256: String }
struct CloudBackupUpload: Codable, Equatable, Sendable { let id: UUID; let state: CloudBackupState }
struct CloudBackupMultipartStatus: Codable, Equatable, Sendable {
    let id: UUID
    let state: CloudBackupState
    let confirmedParts: [CloudBackupConfirmedPart]
    let partSize: Int
    enum CodingKeys: String, CodingKey { case id; case state; case confirmedParts = "confirmed_parts"; case partSize = "part_size" }
}
struct CloudBackupConfirmedPart: Codable, Equatable, Sendable { let partNumber: Int; let byteCount: Int; enum CodingKeys: String, CodingKey { case partNumber = "part_number"; case byteCount = "byte_count" } }
struct CloudBackupPartUpload: Codable, Equatable, Sendable { let url: URL; let expiresIn: Int; enum CodingKeys: String, CodingKey { case url; case expiresIn = "expires_in" } }

enum CloudBackupState: String, CaseIterable, Codable, Equatable, Sendable {
    case notBackedUp, uploading, paused, failed, verifying, backedUp
    var preventsLocalDeletion: Bool { self == .uploading || self == .paused || self == .verifying }
    enum CodingKeys: String, CodingKey { case rawValue }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value { case "backed_up": self = .backedUp; case "not_backed_up": self = .notBackedUp; default: guard let state = Self(rawValue: value) else { throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown cloud backup state") }; self = state }
    }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(self == .backedUp ? "backed_up" : rawValue) }
}

@MainActor
protocol CloudBackupClient: AnyObject {
    func beginBackup(_ request: CloudBackupRequest) async throws -> CloudBackupUpload
    func beginMultipartUpload(id: UUID) async throws -> CloudBackupMultipartStatus
    func multipartStatus(id: UUID) async throws -> CloudBackupMultipartStatus
    func signedPartUpload(id: UUID, partNumber: Int, sha256: String) async throws -> CloudBackupPartUpload
    func confirmPart(id: UUID, partNumber: Int, eTag: String) async throws
    func completeMultipartUpload(id: UUID) async throws -> CloudBackupUpload
    func cancelMultipartUpload(id: UUID) async throws
}

@MainActor
final class UnavailableCloudBackupClient: CloudBackupClient {
    func beginBackup(_ request: CloudBackupRequest) async throws -> CloudBackupUpload { throw CloudAuthenticationError.notConfigured }
    func beginMultipartUpload(id: UUID) async throws -> CloudBackupMultipartStatus { throw CloudAuthenticationError.notConfigured }
    func multipartStatus(id: UUID) async throws -> CloudBackupMultipartStatus { throw CloudAuthenticationError.notConfigured }
    func signedPartUpload(id: UUID, partNumber: Int, sha256: String) async throws -> CloudBackupPartUpload { throw CloudAuthenticationError.notConfigured }
    func confirmPart(id: UUID, partNumber: Int, eTag: String) async throws { throw CloudAuthenticationError.notConfigured }
    func completeMultipartUpload(id: UUID) async throws -> CloudBackupUpload { throw CloudAuthenticationError.notConfigured }
    func cancelMultipartUpload(id: UUID) async throws { throw CloudAuthenticationError.notConfigured }
}

enum CloudBackupErrorMessage {
    case localized(LocalizedStringResource)
    case text(String)

    init(_ error: Error) {
        if let authenticationError = error as? CloudAuthenticationError, authenticationError == .notConfigured {
            self = .localized("Cloud backup is not configured on this app.")
        } else {
            self = .text(error.localizedDescription)
        }
    }
}

@MainActor
@Observable
final class CloudBackupCoordinator {
    private let client: any CloudBackupClient
    private let files: AudioFileStore
    private let uploader: any CloudBackupPartUploading
    private let persistence: any CloudBackupPersisting
    private(set) var pendingConfirmationAudioID: UUID?
    private(set) var errorMessage: CloudBackupErrorMessage?

    init(client: any CloudBackupClient, files: AudioFileStore, uploader: any CloudBackupPartUploading = BackgroundURLSessionPartUploader.shared, persistence: any CloudBackupPersisting) {
        self.client = client
        self.files = files
        self.uploader = uploader
        self.persistence = persistence
    }

    func requestBackup(for item: AudioItem) async {
        guard BackupEligibility.forBackup(of: item, files: files) == .eligible else { return }
        pendingConfirmationAudioID = item.id
        errorMessage = nil
    }

    func confirmBackup(for item: AudioItem) async {
        guard pendingConfirmationAudioID == item.id else { return }
        pendingConfirmationAudioID = nil
        var uploadStarted = false
        do {
            let fileURL = files.url(for: item.id)
            let metadata = try await Self.fileMetadata(for: fileURL)
            let backup = try await client.beginBackup(.init(localAudioID: item.id, byteCount: metadata.byteCount, sha256: metadata.sha256))
            try persistence.saveBackupAssociation(for: item, backupID: backup.id, state: .uploading)
            uploadStarted = true
            let status = try await client.beginMultipartUpload(id: backup.id)
            try await resumeUpload(for: item, fileURL: fileURL, metadata: metadata, backupID: backup.id, status: status)
        } catch {
            if uploadStarted { try? persistence.saveBackupState(for: item, state: .failed) }
            errorMessage = .init(error)
        }
    }

    func resumeBackup(for item: AudioItem) async {
        guard let backupID = item.cloudBackupID,
              BackupEligibility.forBackup(of: item, files: files) == .eligible
        else { return }
        do {
            try persistence.saveBackupState(for: item, state: .uploading)
            let fileURL = files.url(for: item.id)
            let metadata = try await Self.fileMetadata(for: fileURL)
            let status = try await client.multipartStatus(id: backupID)
            try await resumeUpload(for: item, fileURL: fileURL, metadata: metadata, backupID: backupID, status: status)
        } catch {
            try? persistence.saveBackupState(for: item, state: .failed)
            errorMessage = .init(error)
        }
    }

    func cancelBackup(for item: AudioItem) async {
        guard let backupID = item.cloudBackupID, item.cloudBackupState.preventsLocalDeletion else { return }
        do {
            try await client.cancelMultipartUpload(id: backupID)
            files.removeCloudBackupParts(for: backupID)
            try persistence.saveBackupState(for: item, state: .notBackedUp)
        } catch {
            errorMessage = .init(error)
        }
    }

    private func resumeUpload(for item: AudioItem, fileURL: URL, metadata: CloudBackupFileMetadata, backupID: UUID, status: CloudBackupMultipartStatus) async throws {
        var status = try await confirmCompletedParts(backupID: backupID, status: status)
        guard status.state != .backedUp else {
            try persistence.saveBackupState(for: item, state: .backedUp)
            files.removeCloudBackupParts(for: backupID)
            return
        }
        try await uploadMissingParts(for: item, fileURL: fileURL, backupID: backupID, metadata: metadata, status: status)
        status = try await client.multipartStatus(id: backupID)
        status = try await confirmCompletedParts(backupID: backupID, status: status)
        try persistence.saveBackupState(for: item, state: .verifying)
        let completed = try await client.completeMultipartUpload(id: backupID)
        try persistence.saveBackupState(for: item, state: completed.state)
        if completed.state == .backedUp { files.removeCloudBackupParts(for: backupID) }
    }

    private func confirmCompletedParts(backupID: UUID, status: CloudBackupMultipartStatus) async throws -> CloudBackupMultipartStatus {
        let confirmed = Set(status.confirmedParts.map(\.partNumber))
        for part in uploader.completedParts(for: backupID) {
            guard !confirmed.contains(part.partNumber) else {
                uploader.discardCompletedPart(part.partNumber, backupID: backupID)
                continue
            }
            try await client.confirmPart(id: backupID, partNumber: part.partNumber, eTag: part.eTag)
            uploader.discardCompletedPart(part.partNumber, backupID: backupID)
            files.removeCloudBackupPart(backupID: backupID, partNumber: part.partNumber)
        }
        return try await client.multipartStatus(id: backupID)
    }

    private func uploadMissingParts(for item: AudioItem, fileURL: URL, backupID: UUID, metadata: CloudBackupFileMetadata, status: CloudBackupMultipartStatus) async throws {
        guard status.partSize >= 5 * 1_024 * 1_024 else { throw CloudBackupError.invalidPartSize }
        let confirmed = Set(status.confirmedParts.map(\.partNumber))
        let count = Int(ceil(Double(metadata.byteCount) / Double(status.partSize)))
        for partNumber in 1...count where !confirmed.contains(partNumber) {
            let part = try await Self.makePart(from: fileURL, backupID: backupID, partNumber: partNumber, partSize: status.partSize, totalByteCount: metadata.byteCount, files: files)
            let destination = try await client.signedPartUpload(id: backupID, partNumber: partNumber, sha256: part.sha256)
            let eTag = try await uploader.upload(fileURL: part.fileURL, to: destination.url, sha256: part.sha256, context: .init(localAudioID: item.id, backupID: backupID, partNumber: partNumber))
            try await client.confirmPart(id: backupID, partNumber: partNumber, eTag: eTag)
            uploader.discardCompletedPart(partNumber, backupID: backupID)
            files.removeCloudBackupPart(backupID: backupID, partNumber: partNumber)
        }
    }

    private nonisolated static func fileMetadata(for url: URL) async throws -> CloudBackupFileMetadata {
        try await Task.detached(priority: .utility) { try hashFile(at: url) }.value
    }

    private nonisolated static func makePart(from sourceURL: URL, backupID: UUID, partNumber: Int, partSize: Int, totalByteCount: Int, files: AudioFileStore) async throws -> CloudBackupFilePart {
        try await Task.detached(priority: .utility) {
            let offset = (partNumber - 1) * partSize
            let byteCount = min(partSize, totalByteCount - offset)
            guard byteCount > 0 else { throw CloudBackupError.invalidPartSize }
            let file = try FileHandle(forReadingFrom: sourceURL)
            defer { try? file.close() }
            try file.seek(toOffset: UInt64(offset))
            guard let data = try file.read(upToCount: byteCount), data.count == byteCount else { throw CloudBackupError.missingOriginalAudio }
            let partURL = try files.cloudBackupPartURL(backupID: backupID, partNumber: partNumber)
            try data.write(to: partURL, options: .atomic)
            return .init(fileURL: partURL, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }.value
    }
}

private struct CloudBackupFileMetadata: Sendable { let byteCount: Int; let sha256: String }
private struct CloudBackupFilePart: Sendable { let fileURL: URL; let sha256: String }
private func hashFile(at url: URL) throws -> CloudBackupFileMetadata { let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }; var hasher = SHA256(); var byteCount = 0; while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data); byteCount += data.count }; guard byteCount > 0 else { throw CloudBackupError.missingOriginalAudio }; return .init(byteCount: byteCount, sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined()) }
func base64SHA256(_ hexadecimal: String) -> String { Data(stride(from: 0, to: hexadecimal.count, by: 2).compactMap { UInt8(hexadecimal[hexadecimal.index(hexadecimal.startIndex, offsetBy: $0)...hexadecimal.index(hexadecimal.startIndex, offsetBy: $0 + 1)], radix: 16) }).base64EncodedString() }

enum CloudBackupError: LocalizedError { case missingOriginalAudio, partUploadFailed, invalidPartSize; var errorDescription: String? { switch self { case .missingOriginalAudio: "The Original Audio is unavailable for cloud backup."; case .partUploadFailed: "A cloud backup part could not be uploaded."; case .invalidPartSize: "The cloud backup service returned an invalid part size." } } }
