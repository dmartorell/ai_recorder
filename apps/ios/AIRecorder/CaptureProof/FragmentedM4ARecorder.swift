@preconcurrency import AVFoundation
import CoreMedia
import Foundation

final class FragmentedM4ARecorder: NSObject, @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case noAudioInput
        case inputRouteUnavailable
        case inputRouteUnverified(String)
        case cannotConfigureInput
        case cannotConfigureOutput
        case cannotConfigureWriter
        case cannotStartWriter
        case noAudioWritten
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioInput:
                "No audio input is available."
            case .inputRouteUnavailable:
                "The active audio input is unavailable."
            case let .inputRouteUnverified(name):
                "The active audio input could not be verified: \(name)."
            case .cannotConfigureInput:
                "The audio input could not be configured."
            case .cannotConfigureOutput:
                "The audio output could not be configured."
            case .cannotConfigureWriter:
                "The M4A writer could not be configured."
            case .cannotStartWriter:
                "The M4A writer could not start."
            case .noAudioWritten:
                "No audio samples were captured."
            case let .writerFailed(message):
                "The M4A writer failed: \(message)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.danielmartorell.AIRecorder.capture-proof")
    private let eventStream: AsyncStream<CaptureRecorderEvent>
    private var eventContinuation: AsyncStream<CaptureRecorderEvent>.Continuation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var captureSession: AVCaptureSession?
    private var captureDeviceInput: AVCaptureDeviceInput?
    private var selectedCaptureDeviceID: String?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var interruptionHandled = false
    private var stopRequested = false
    private var nextPresentationTime = CMTime.zero

    override init() {
        var continuation: AsyncStream<CaptureRecorderEvent>.Continuation?
        eventStream = AsyncStream { continuation = $0 }
        eventContinuation = continuation
        super.init()
    }

    var events: AsyncStream<CaptureRecorderEvent> { eventStream }

    func start(outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.configureAndStart(outputURL: outputURL)
                    continuation.resume()
                } catch {
                    self.captureSession?.stopRunning()
                    self.captureSession = nil
                    self.writer?.cancelWriting()
                    self.resetWriterState()
                    self.deactivateAudioSession()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.finishOnQueue(continuation: continuation)
            }
        }
    }

    private func availableAudioDevices() -> [AVCaptureDevice] {
        var devices: [AVCaptureDevice] = []
        if let routedDevice = AVCaptureDevice.default(for: .audio) {
            devices.append(routedDevice)
        }
        for device in AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices where !devices.contains(where: { $0.uniqueID == device.uniqueID }) {
            devices.append(device)
        }
        return devices
    }

    private func configureAndStart(outputURL: URL) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
        try audioSession.setActive(true)

        let route = CaptureNotificationMapper.currentInputRoute(audioSession)
        let devices = availableAudioDevices()
        let selection = CaptureInputSelector.select(route: route, devices: devices.map {
            CaptureInputDevice(uniqueID: $0.uniqueID, name: $0.localizedName)
        })
        let selectedDevice: CaptureInputDevice
        switch selection {
        case .unavailable:
            throw RecorderError.inputRouteUnavailable
        case let .unverified(name):
            throw RecorderError.inputRouteUnverified(name)
        case let .matched(device):
            selectedDevice = device
        }
        guard let device = availableAudioDevices().first(where: { $0.uniqueID == selectedDevice.uniqueID }) else {
            throw RecorderError.inputRouteUnverified(selectedDevice.name)
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        let deviceInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(deviceInput) else {
            session.commitConfiguration()
            throw RecorderError.cannotConfigureInput
        }
        session.addInput(deviceInput)

        let dataOutput = AVCaptureAudioDataOutput()
        guard session.canAddOutput(dataOutput) else {
            session.commitConfiguration()
            throw RecorderError.cannotConfigureOutput
        }
        session.addOutput(dataOutput)
        dataOutput.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()

        let channelCount = max(1, min(2, audioSession.inputNumberOfChannels))
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: min(192_000, 128_000 * channelCount),
        ]

        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let assetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        assetWriterInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(assetWriterInput) else {
            throw RecorderError.cannotConfigureWriter
        }
        assetWriter.add(assetWriterInput)

        let fragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        assetWriter.initialMovieFragmentInterval = fragmentInterval
        assetWriter.movieFragmentInterval = fragmentInterval

        guard assetWriter.startWriting() else {
            throw RecorderError.writerFailed(assetWriter.error?.localizedDescription ?? "unknown error")
        }

        captureSession = session
        captureDeviceInput = deviceInput
        selectedCaptureDeviceID = device.uniqueID
        writer = assetWriter
        writerInput = assetWriterInput
        sessionStarted = false
        interruptionHandled = false
        stopRequested = false
        nextPresentationTime = .zero
        installNotificationObservers()
        session.startRunning()
    }

    private func finishOnQueue(continuation: CheckedContinuation<Void, Error>) {
        stopRequested = true
        captureSession?.stopRunning()
        captureSession = nil
        captureDeviceInput = nil
        selectedCaptureDeviceID = nil
        removeNotificationObservers()

        guard sessionStarted, let writer, let writerInput else {
            self.writer?.cancelWriting()
            resetWriterState()
            deactivateAudioSession()
            continuation.resume(throwing: RecorderError.noAudioWritten)
            return
        }

        writerInput.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else {
                continuation.resume(throwing: RecorderError.writerFailed("recorder was released"))
                return
            }
            self.queue.async {
                self.completeFinish(continuation: continuation)
            }
        }
    }

    private func completeFinish(continuation: CheckedContinuation<Void, Error>) {
        guard let writer else {
            continuation.resume(throwing: RecorderError.writerFailed("writer was released"))
            return
        }

        let status = writer.status
        let error = writer.error
        resetWriterState()
        deactivateAudioSession()

        if status == .completed {
            continuation.resume()
        } else {
            continuation.resume(
                throwing: RecorderError.writerFailed(error?.localizedDescription ?? "status \(status.rawValue)")
            )
        }
    }

    private func resetWriterState() {
        writer = nil
        writerInput = nil
        captureDeviceInput = nil
        selectedCaptureDeviceID = nil
        sessionStarted = false
        interruptionHandled = false
        stopRequested = false
        nextPresentationTime = .zero
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func installNotificationObservers() {
        let center = NotificationCenter.default
        notificationTokens = [
            CaptureNotificationMapper.observeAudioInterruptions(center: center) { [weak self] notification in
                self?.queue.async {
                    guard let self,
                          let date = CaptureNotificationMapper.interruptionBeganDate(notification) else { return }
                    self.handleInterruption(date)
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
                self?.queue.async {
                    guard let self, !self.interruptionHandled else { return }
                    self.handleRouteChange(notification)
                }
            },
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: captureSession, queue: nil) { [weak self] notification in
                self?.queue.async {
                    guard let self,
                          let date = CaptureNotificationMapper.captureInterruptionBeganDate(notification) else { return }
                    self.handleInterruption(date)
                }
            },
            center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: captureSession, queue: nil) { [weak self] _ in
                self?.queue.async {
                    guard let self, !self.stopRequested else { return }
                    self.handleInterruption(.now)
                }
            }
        ]
    }

    private func handleInterruption(_ date: Date) {
        guard !interruptionHandled else { return }
        interruptionHandled = true
        captureSession?.stopRunning()
        eventContinuation?.yield(.interruptionBegan(date))
    }

    private func handleRouteChange(_ notification: Notification) {
        guard !interruptionHandled,
              let session = captureSession,
              let route = CaptureNotificationMapper.routeInput(notification),
              case let .matched(selected) = CaptureInputSelector.select(
                  route: route,
                  devices: availableAudioDevices().map {
                      CaptureInputDevice(uniqueID: $0.uniqueID, name: $0.localizedName)
                  }
              ),
              let device = availableAudioDevices().first(where: { $0.uniqueID == selected.uniqueID })
        else {
            handleUnavailableInput(.now)
            return
        }

        if selectedCaptureDeviceID != selected.uniqueID {
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                if let oldInput = captureDeviceInput { session.removeInput(oldInput) }
                guard session.canAddInput(newInput) else {
                    session.commitConfiguration()
                    handleUnavailableInput(.now)
                    return
                }
                session.addInput(newInput)
                session.commitConfiguration()
                captureDeviceInput = newInput
                selectedCaptureDeviceID = selected.uniqueID
            } catch {
                handleUnavailableInput(.now)
                return
            }
        }
        eventContinuation?.yield(.routeChanged(.now, inputName: route.name))
    }

    private func handleUnavailableInput(_ date: Date) {
        guard !interruptionHandled else { return }
        interruptionHandled = true
        captureSession?.stopRunning()
        eventContinuation?.yield(.inputBecameUnavailable(date))
    }

    private func removeNotificationObservers() {
        let center = NotificationCenter.default
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll()
    }
}

extension FragmentedM4ARecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if let channel = connection.audioChannels.first {
            let normalizedLevel = max(0, min(1, (channel.averagePowerLevel + 50) / 50))
            eventContinuation?.yield(.inputLevelChanged(normalizedLevel))
        }

        guard CMSampleBufferDataIsReady(sampleBuffer),
              let writer,
              let writerInput,
              writer.status == .writing
        else {
            return
        }

        if !sessionStarted {
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }

        guard writerInput.isReadyForMoreMediaData else { return }
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let sampleDuration = duration.isValid && duration > .zero
            ? duration
            : CMTime(value: 1, timescale: 48_000)
        var timing = CMSampleTimingInfo(
            duration: sampleDuration,
            presentationTimeStamp: nextPresentationTime,
            decodeTimeStamp: .invalid
        )
        var retimedBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimedBuffer
        ) == noErr,
        let retimedBuffer else { return }
        writerInput.append(retimedBuffer)
        nextPresentationTime = nextPresentationTime + sampleDuration
    }
}
