@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CaptureProofModel {
    enum Phase: Equatable {
        case idle
        case recording
        case inspecting
        case available(summary: CapturedAudioSummary, recovered: Bool)
        case needsRecovery(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var captureStartedAt: Date?
    private(set) var playbackStatus: String?

    private let store: CaptureProofStore
    private let recorder: FragmentedM4ARecorder
    private let inspector: OriginalAudioInspector
    private var player: AVPlayer?
    private var didInspectLaunch = false

    init(
        store: CaptureProofStore,
        recorder: FragmentedM4ARecorder = FragmentedM4ARecorder(),
        inspector: OriginalAudioInspector = OriginalAudioInspector()
    ) {
        self.store = store
        self.recorder = recorder
        self.inspector = inspector
        captureStartedAt = store.captureStartedAt
    }

    func inspectOnLaunch() async {
        guard !didInspectLaunch else { return }
        didInspectLaunch = true

        let interruptedCapture = store.captureWasActive
        guard interruptedCapture || FileManager.default.fileExists(atPath: store.outputURL.path) else {
            return
        }

        phase = .inspecting
        do {
            let summary = try await inspector.inspect(store.outputURL)
            store.markCaptureHandled()
            captureStartedAt = nil
            phase = .available(summary: summary, recovered: interruptedCapture)
        } catch {
            store.markCaptureHandled()
            captureStartedAt = nil
            phase = .needsRecovery(error.localizedDescription)
        }
    }

    func startCapture() async {
        guard phase != .recording else { return }

        do {
            try store.prepareForCapture()
            captureStartedAt = store.captureStartedAt
            try await recorder.start(outputURL: store.outputURL)
            phase = .recording
        } catch {
            store.markCaptureHandled()
            captureStartedAt = nil

            if outputContainsBytes {
                phase = .needsRecovery("\(error.localizedDescription) The nonempty Original Audio was preserved.")
            } else {
                removeEmptyOutputIfPresent()
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func finalizeCapture() async {
        guard phase == .recording else { return }
        phase = .inspecting

        do {
            try await recorder.finish()
            let summary = try await inspector.inspect(store.outputURL)
            store.markCaptureHandled()
            captureStartedAt = nil
            phase = .available(summary: summary, recovered: false)
        } catch {
            phase = .needsRecovery(error.localizedDescription)
        }
    }

    func playOriginalAudio() async {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)

            let asset = AVURLAsset(url: store.outputURL)
            guard try await asset.load(.isPlayable) else {
                playbackStatus = "Original Audio is not playable."
                return
            }

            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            self.player = player
            playbackStatus = "Starting playback"
            player.play()

            try await Task.sleep(for: .milliseconds(500))
            switch player.timeControlStatus {
            case .playing:
                playbackStatus = "Playback active"
            case .waitingToPlayAtSpecifiedRate:
                playbackStatus = "Playback waiting: \(player.reasonForWaitingToPlay?.rawValue ?? "unknown reason")"
            case .paused:
                playbackStatus = playerItem.error?.localizedDescription ?? "Playback did not start."
            @unknown default:
                playbackStatus = "Unknown playback state"
            }
        } catch {
            playbackStatus = "Playback failed: \(error.localizedDescription)"
        }
    }

    var outputPath: String {
        store.outputURL.path
    }

    private var outputContainsBytes: Bool {
        guard let values = try? store.outputURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize
        else {
            return false
        }
        return fileSize > 0
    }

    private func removeEmptyOutputIfPresent() {
        guard FileManager.default.fileExists(atPath: store.outputURL.path),
              !outputContainsBytes
        else {
            return
        }
        try? FileManager.default.removeItem(at: store.outputURL)
    }
}
