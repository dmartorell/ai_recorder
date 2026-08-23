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
    private var captureSession: AVCaptureSession?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var sessionStarted = false

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
        session.startRunning()
    }

    private func finishOnQueue(continuation: CheckedContinuation<Void, Error>) {
        captureSession?.stopRunning()
        captureSession = nil

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
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: presentationTime)
            sessionStarted = true
        }

        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
        }
    }
}
