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
    private(set) var activeInputName = CaptureEvent.noInputName

    private var recordingStartedAt: Date?
    private var positionBaseMilliseconds = 0
    private var positionTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var interruptionFinalizationTask: Task<Void, Never>?

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
        activeInputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? CaptureEvent.noInputName
    }

    var files: AudioFileStore { repository.files }
    var microphonePermission: AVAudioApplication.recordPermission { AVAudioApplication.shared.recordPermission }
    var inputName: String { activeInputName }
    var automaticFinalizationMessage: String? {
        guard phase == .finalizing,
              let event = currentItem?.events.max(by: { $0.startedAt < $1.startedAt })
        else { return nil }
        if event.kind == .interruptionBegan {
            return "Audio interruption ended this Capture. Finalizing playable audio…"
        }
        if event.kind == .routeChanged, event.inputName == CaptureEvent.noInputName {
            return "The audio input became unavailable. Finalizing playable audio…"
        }
        return nil
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
            activeInputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? CaptureEvent.noInputName
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
        try? repository.save()
        await completeFinalization(of: item, endedUnexpectedly: false)
    }

    private func startEventConsumption() {
        guard eventTask == nil else { return }
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
            beginAutomaticFinalization(
                of: item,
                event: CaptureEvent(
                    kind: .interruptionBegan,
                    date: date,
                    audioPositionMilliseconds: currentAudioPositionMilliseconds,
                    inputName: nil
                )
            )
        case let .routeChanged(date, inputName):
            guard phase == .recording else { return }
            activeInputName = inputName
            try? repository.record(CaptureEvent(kind: .routeChanged, date: date, audioPositionMilliseconds: currentAudioPositionMilliseconds, inputName: inputName), for: item)
        case let .inputBecameUnavailable(date):
            activeInputName = CaptureEvent.noInputName
            beginAutomaticFinalization(
                of: item,
                event: CaptureEvent(
                    kind: .routeChanged,
                    date: date,
                    audioPositionMilliseconds: currentAudioPositionMilliseconds,
                    inputName: activeInputName
                )
            )
        }
    }

    private func beginAutomaticFinalization(of item: AudioItem, event: CaptureEvent) {
        guard phase == .recording else { return }
        positionBaseMilliseconds = currentAudioPositionMilliseconds
        stopPositionUpdates()
        phase = .finalizing
        item.localState = .finalizing
        item.endedUnexpectedly = true
        do {
            try repository.record(event, for: item)
        } catch {
            errorMessage = error.localizedDescription
        }
        interruptionFinalizationTask = Task { [weak self] in
            await self?.completeFinalization(of: item, endedUnexpectedly: true)
        }
    }

    private func completeFinalization(of item: AudioItem, endedUnexpectedly: Bool) async {
        let outputURL = repository.files.url(for: item.id)
        do {
            try await recorder.finish()
        } catch {
            if endedUnexpectedly {
                await recoverVerifiedFragment(of: item, at: outputURL, finishError: error)
            } else {
                markNeedsRecovery(item, error: error)
                stopLiveUpdates()
            }
            return
        }

        do {
            let summary = try await inspector.inspect(outputURL)
            try persistVerified(summary, for: item, state: .available, endedUnexpectedly: endedUnexpectedly)
            phase = .available(item.id)
        } catch {
            markNeedsRecovery(item, error: error)
        }
        stopLiveUpdates()
        interruptionFinalizationTask = nil
    }

    private func recoverVerifiedFragment(of item: AudioItem, at url: URL, finishError: Error) async {
        do {
            let summary = try await inspector.inspect(url)
            try persistVerified(summary, for: item, state: .recovered, endedUnexpectedly: true)
            phase = .available(item.id)
        } catch {
            markNeedsRecovery(item, error: finishError)
        }
        stopLiveUpdates()
        interruptionFinalizationTask = nil
    }

    private func persistVerified(
        _ summary: CapturedAudioSummary,
        for item: AudioItem,
        state: LocalAudioState,
        endedUnexpectedly: Bool
    ) throws {
        let durationMilliseconds = max(0, Int((summary.duration * 1_000).rounded()))
        repository.pruneMarkers(after: durationMilliseconds, from: item)
        markerCount = item.markers.count
        item.durationMilliseconds = durationMilliseconds
        currentAudioPositionMilliseconds = durationMilliseconds
        item.endedAt = .now
        item.endedUnexpectedly = endedUnexpectedly
        item.localState = state
        try repository.save()
    }

    private func markNeedsRecovery(_ item: AudioItem, error: Error) {
        item.localState = .needsRecovery
        try? repository.save()
        phase = .needsRecovery(item.id, error.localizedDescription)
    }

    private var canBeginCapture: Bool {
        switch phase {
        case .idle, .available, .needsRecovery, .failed: true
        case .preparing, .recording, .finalizing: false
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
    }
}
