import AVFAudio
import AVFoundation
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
    private(set) var storageAssessment: StorageAssessment = .critical
    private(set) var isLowBatteryWarning = false
    private(set) var resourceWarning: String?
    private(set) var inputLevel: Float?
    private(set) var noInputLevelWarning = false

    private var recordingStartedAt: Date?
    private var positionBaseMilliseconds = 0
    private var positionTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var interruptionFinalizationTask: Task<Void, Never>?
    private var resourceTask: Task<Void, Never>?

    private let repository: AudioRepository
    private let storageMonitor: any StorageMonitoring
    private let batteryMonitor: any BatteryMonitoring
    private let recorder: any CaptureRecorder
    private let inspector: any AudioInspector
    private let permissionProvider: @Sendable () async -> Bool

    init(
        repository: AudioRepository,
        recorder: any CaptureRecorder = FragmentedM4ARecorder(),
        inspector: any AudioInspector = OriginalAudioInspector(),
        storageMonitor: (any StorageMonitoring)? = nil,
        batteryMonitor: (any BatteryMonitoring)? = nil,
        permissionProvider: @escaping @Sendable () async -> Bool = {
            AVAudioApplication.shared.recordPermission == .granted
        }
    ) {
        self.repository = repository
        self.recorder = recorder
        self.inspector = inspector
        self.storageMonitor = storageMonitor ?? StorageMonitor(volumeURL: repository.files.rootDirectory)
        self.batteryMonitor = batteryMonitor ?? BatteryMonitor()
        self.permissionProvider = permissionProvider
        activeInputName = Self.currentInputName()
    }

    var files: AudioFileStore { repository.files }
    var microphonePermission: AVAudioApplication.recordPermission { AVAudioApplication.shared.recordPermission }
    var inputName: String { activeInputName }
    var availableDuration: Duration? {
        switch storageAssessment {
        case let .sufficient(duration), let .warning(duration): duration
        case .critical: nil
        }
    }

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

    func refreshResources() {
        storageAssessment = storageMonitor.refresh()
        isLowBatteryWarning = batteryMonitor.refresh()
    }

    func requestPermission() async {
        guard microphonePermission == .undetermined else { return }
        _ = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
    }

    func start() async {
        guard canBeginCapture else { return }
        storageAssessment = storageMonitor.refresh()
        guard storageAssessment != .critical else {
            phase = .failed("Not enough free storage to start Capture.")
            resourceWarning = "Free storage is below the safe recording threshold."
            return
        }
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
            activeInputName = Self.currentInputName()
            startPositionUpdates()
            startEventConsumption()
            startResourceMonitoring()
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
        case let .inputLevelChanged(level):
            inputLevel = max(0, min(1, level))
            noInputLevelWarning = false
        case .inputLevelUnavailable:
            noInputLevelWarning = true
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

    private static func currentInputName() -> String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
            ?? AVCaptureDevice.default(for: .audio)?.localizedName
            ?? CaptureEvent.noInputName
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

    private func startResourceMonitoring() {
        resourceTask?.cancel()
        resourceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                let assessment = self.storageMonitor.refresh()
                self.storageAssessment = assessment
                self.isLowBatteryWarning = self.batteryMonitor.refresh()
                switch assessment {
                case .sufficient:
                    self.resourceWarning = self.isLowBatteryWarning ? "Battery is low. Capture will continue." : nil
                case .warning:
                    self.resourceWarning = "Free storage is getting low."
                case .critical:
                    self.resourceWarning = "Capture is finalizing to preserve playable Original Audio."
                    if self.phase == .recording, let item = self.currentItem {
                        self.beginAutomaticFinalization(
                            of: item,
                            event: CaptureEvent(
                                kind: .automaticFinalization,
                                date: .now,
                                audioPositionMilliseconds: self.currentAudioPositionMilliseconds,
                                inputName: nil
                            )
                        )
                    }
                }
            }
        }
    }

    private func stopLiveUpdates() {
        stopPositionUpdates()
        resourceTask?.cancel()
        resourceTask = nil
    }
}
