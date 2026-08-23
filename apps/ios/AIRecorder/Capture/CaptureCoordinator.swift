import Foundation
import Observation
import AVFAudio

@MainActor
protocol CaptureRecorder: AnyObject {
    func start(outputURL: URL) async throws
    func finish() async throws
}

protocol AudioInspector: Sendable {
    func inspect(_ url: URL) async throws -> CapturedAudioSummary
}

extension FragmentedM4ARecorder: CaptureRecorder {}
extension OriginalAudioInspector: AudioInspector {}

@MainActor
final class UITestCaptureRecorder: CaptureRecorder {
    private var outputURL: URL?

    func start(outputURL: URL) async throws {
        self.outputURL = outputURL
        try Data("ui-test-audio".utf8).write(to: outputURL)
    }

    func finish() async throws { }
}

struct UITestAudioInspector: AudioInspector {
    func inspect(_ url: URL) async throws -> CapturedAudioSummary {
        CapturedAudioSummary(duration: 2.5, channelCount: 1)
    }
}

@MainActor
@Observable
final class CaptureCoordinator {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case finalizing
        case available(UUID)
        case needsRecovery(UUID, String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var currentItem: AudioItem?
    private(set) var errorMessage: String?

    private let repository: AudioRepository
    private let recorder: any CaptureRecorder
    private let inspector: any AudioInspector
    private let permissionProvider: @Sendable () async -> Bool

    init(
        repository: AudioRepository,
        recorder: any CaptureRecorder = FragmentedM4ARecorder(),
        inspector: any AudioInspector = OriginalAudioInspector(),
        permissionProvider: @escaping @Sendable () async -> Bool = {
            AVAudioApplication.shared.recordPermission == .granted
        }
    ) {
        self.repository = repository
        self.recorder = recorder
        self.inspector = inspector
        self.permissionProvider = permissionProvider
    }

    var files: AudioFileStore { repository.files }
    var microphonePermission: AVAudioApplication.recordPermission { AVAudioApplication.shared.recordPermission }
    var inputName: String { AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "No input" }

    func requestPermission() async {
        guard microphonePermission == .undetermined else { return }
        _ = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
    }

    func start() async {
        guard phase == .idle else { return }
        if !(await permissionProvider()) {
            await requestPermission()
            guard await permissionProvider() else {
                phase = .failed("Microphone permission is required to record.")
                return
            }
        }
        phase = .preparing
        do {
            let item = try repository.beginCapture()
            currentItem = item
            try await recorder.start(outputURL: repository.files.url(for: item.id))
            phase = .recording
        } catch {
            if let item = currentItem {
                let values = try? repository.files.url(for: item.id).resourceValues(forKeys: [.fileSizeKey])
                if (values?.fileSize ?? 0) > 0 {
                    item.localState = .needsRecovery
                    try? repository.save()
                    phase = .needsRecovery(item.id, error.localizedDescription)
                } else {
                    try? repository.delete(item)
                    currentItem = nil
                    phase = .failed(error.localizedDescription)
                }
            } else { phase = .failed(error.localizedDescription) }
        }
    }

    func finalize() async {
        guard phase == .recording, let item = currentItem else { return }
        phase = .finalizing
        item.localState = .finalizing
        do {
            try await recorder.finish()
            let summary = try await inspector.inspect(repository.files.url(for: item.id))
            item.durationMilliseconds = Int((summary.duration * 1_000).rounded())
            item.endedAt = .now
            item.localState = .available
            try repository.save()
            phase = .available(item.id)
        } catch {
            item.localState = .needsRecovery
            try? repository.save()
            phase = .needsRecovery(item.id, error.localizedDescription)
        }
    }
}
