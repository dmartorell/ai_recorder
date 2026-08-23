import AVFAudio
import Foundation
import Observation

@MainActor
protocol CaptureRecorder: AnyObject {
    var events: AsyncStream<CaptureRecorderEvent> { get }
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
    let events: AsyncStream<CaptureRecorderEvent> = AsyncStream { $0.finish() }
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
        case interrupted(startedAt: Date)
        case finalizing
        case available(UUID)
        case needsRecovery(UUID, String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var currentItem: AudioItem?
    private(set) var errorMessage: String?
    private(set) var currentAudioPositionMilliseconds = 0
    private(set) var markerCount = 0
    private(set) var markerConfirmation = 0
    private(set) var activeInputName = "No input"

    private var recordingStartedAt: Date?
    private var positionBaseMilliseconds = 0
    private var positionTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

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
        activeInputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "No input"
    }

    var files: AudioFileStore { repository.files }
    var microphonePermission: AVAudioApplication.recordPermission { AVAudioApplication.shared.recordPermission }
    var inputName: String { activeInputName }
    var isInterrupted: Bool {
        if case .interrupted = phase { return true }
        return false
    }

    func requestPermission() async {
        guard microphonePermission == .undetermined else { return }
        _ = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
    }

    func start() async {
        guard canBeginCapture else { return }
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
            recordingStartedAt = .now
            positionBaseMilliseconds = 0
            currentAudioPositionMilliseconds = 0
            markerCount = item.markers.count
            activeInputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "No input"
            startPositionUpdates()
            startEventConsumption()
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

    func addMarker() {
        guard phase == .recording, let item = currentItem else { return }
        do {
            _ = try repository.addMarker(to: item, positionMilliseconds: currentAudioPositionMilliseconds)
            markerCount = item.markers.count
            markerConfirmation += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finalize() async {
        guard phase == .recording, let item = currentItem else { return }
        stopLiveUpdates()
        phase = .finalizing
        item.localState = .finalizing
        do {
            try await recorder.finish()
            let summary = try await inspector.inspect(repository.files.url(for: item.id))
            item.durationMilliseconds = Int((summary.duration * 1_000).rounded())
            currentAudioPositionMilliseconds = item.durationMilliseconds
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

    private func startEventConsumption() {
        eventTask?.cancel()
        eventTask = Task { [weak self, events = recorder.events] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: CaptureRecorderEvent) {
        guard let item = currentItem else { return }
        switch event {
        case let .interruptionBegan(date):
            guard phase == .recording else { return }
            positionBaseMilliseconds = currentAudioPositionMilliseconds
            stopPositionUpdates()
            phase = .interrupted(startedAt: date)
            try? repository.record(CaptureEvent(kind: .interruptionBegan, date: date, audioPositionMilliseconds: currentAudioPositionMilliseconds, inputName: nil, shouldResume: false), for: item)
        case let .interruptionEnded(date, shouldResume):
            guard case .interrupted = phase else { return }
            try? repository.record(CaptureEvent(kind: .interruptionEnded, date: date, audioPositionMilliseconds: currentAudioPositionMilliseconds, inputName: nil, shouldResume: shouldResume), for: item)
            if shouldResume {
                phase = .recording
                recordingStartedAt = date
                startPositionUpdates()
            } else {
                errorMessage = "Recording was interrupted and cannot resume automatically."
            }
        case let .routeChanged(date, inputName):
            activeInputName = inputName
            try? repository.record(CaptureEvent(kind: .routeChanged, date: date, audioPositionMilliseconds: currentAudioPositionMilliseconds, inputName: inputName, shouldResume: false), for: item)
        }
    }

    private var canBeginCapture: Bool {
        switch phase {
        case .idle, .available, .needsRecovery, .failed: true
        case .preparing, .recording, .interrupted, .finalizing: false
        }
    }

    private func startPositionUpdates() {
        stopPositionUpdates()
        positionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, let startedAt = self.recordingStartedAt else { continue }
                self.currentAudioPositionMilliseconds = self.positionBaseMilliseconds + max(0, Int(Date.now.timeIntervalSince(startedAt) * 1_000))
            }
        }
    }

    private func stopPositionUpdates() {
        positionTask?.cancel()
        positionTask = nil
    }

    private func stopLiveUpdates() {
        stopPositionUpdates()
        eventTask?.cancel()
        eventTask = nil
    }
}
