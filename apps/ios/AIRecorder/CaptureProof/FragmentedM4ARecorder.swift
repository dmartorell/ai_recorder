@preconcurrency import AVFoundation
import CoreMedia
import Foundation

final class FragmentedM4ARecorder: NSObject, @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case noAudioInput
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
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var sessionStarted = false
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

    private func configureAndStart(outputURL: URL) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)

        let session = AVCaptureSession()
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(for: .audio) else {
            session.commitConfiguration()
            throw RecorderError.noAudioInput
        }

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
        writer = assetWriter
        writerInput = assetWriterInput
        sessionStarted = false
        nextPresentationTime = .zero
        installNotificationObservers()
        session.startRunning()
    }

    private func finishOnQueue(continuation: CheckedContinuation<Void, Error>) {
        captureSession?.stopRunning()
        captureSession = nil
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
        sessionStarted = false
        nextPresentationTime = .zero
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func installNotificationObservers() {
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] notification in
                self?.queue.async {
                    guard let self else { return }
                    if let date = CaptureNotificationMapper.interruptionBeganDate(notification) {
                        self.eventContinuation?.yield(.interruptionBegan(date))
                    } else if let ended = CaptureNotificationMapper.interruptionEnded(notification) {
                        if ended.shouldResume { self.captureSession?.startRunning() }
                        self.eventContinuation?.yield(.interruptionEnded(ended.date, shouldResume: ended.shouldResume))
                    }
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] notification in
                self?.queue.async {
                    guard let self,
                          let name = CaptureNotificationMapper.routeInputName(notification) else { return }
                    self.eventContinuation?.yield(.routeChanged(.now, inputName: name))
                }
            },
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: captureSession, queue: nil) { [weak self] notification in
                self?.queue.async {
                    guard let self,
                          let date = CaptureNotificationMapper.captureInterruptionBeganDate(notification) else { return }
                    self.eventContinuation?.yield(.interruptionBegan(date))
                }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: captureSession, queue: nil) { [weak self] notification in
                self?.queue.async {
                    guard let self,
                          let ended = CaptureNotificationMapper.captureInterruptionEnded(notification) else { return }
                    self.captureSession?.startRunning()
                    self.eventContinuation?.yield(.interruptionEnded(ended.date, shouldResume: ended.shouldResume))
                }
            }
        ]
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
