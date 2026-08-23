@preconcurrency import AVFoundation
import CoreMedia
import Foundation

struct CapturedAudioSummary: Equatable, Sendable {
    let duration: TimeInterval
    let channelCount: Int
}

enum OriginalAudioInspectionError: LocalizedError, Equatable {
    case missing
    case empty
    case noAudioTrack
    case zeroDuration

    var errorDescription: String? {
        switch self {
        case .missing:
            "Original Audio is missing."
        case .empty:
            "Original Audio is empty."
        case .noAudioTrack:
            "Original Audio has no playable audio track."
        case .zeroDuration:
            "Original Audio has no playable duration."
        }
    }
}

struct OriginalAudioInspector: Sendable {
    func inspect(_ url: URL) async throws -> CapturedAudioSummary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OriginalAudioInspectionError.missing
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize > 0 else {
            throw OriginalAudioInspectionError.empty
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw OriginalAudioInspectionError.zeroDuration
        }

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw OriginalAudioInspectionError.noAudioTrack
        }

        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        let channelCount = formatDescriptions.compactMap { description in
            CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mChannelsPerFrame
        }.map(Int.init).max() ?? 0

        guard channelCount > 0 else {
            throw OriginalAudioInspectionError.noAudioTrack
        }

        return CapturedAudioSummary(duration: duration, channelCount: channelCount)
    }
}
