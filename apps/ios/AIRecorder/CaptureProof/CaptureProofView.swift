import SwiftUI

struct CaptureProofView: View {
    let model: CaptureProofModel

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                actionSection
                evidenceSection
            }
            .navigationTitle("Capture Recovery Proof")
        }
        .task {
            await model.inspectOnLaunch()
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            switch model.phase {
            case .idle:
                Label("Ready", systemImage: "mic")
            case .recording:
                Label("Recording", systemImage: "record.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityValue("Capture is active")
            case .inspecting:
                ProgressView("Inspecting Original Audio")
            case let .available(summary, recovered):
                Label(
                    recovered ? "Interrupted Capture Recovered" : "Capture Finalized",
                    systemImage: recovered ? "cross.case.fill" : "checkmark.circle.fill"
                )
                LabeledContent("Duration", value: summary.duration.formatted(.number.precision(.fractionLength(2))) + " s")
                LabeledContent("Channels", value: summary.channelCount.formatted())
            case let .needsRecovery(message):
                Label("Needs recovery", systemImage: "exclamationmark.triangle.fill")
                Text(message)
            case let .failed(message):
                Label("Capture failed", systemImage: "xmark.octagon.fill")
                Text(message)
            }
        }
    }

    private var actionSection: some View {
        Section("Actions") {
            switch model.phase {
            case .recording:
                Button("Finalize Capture", role: .destructive) {
                    Task { await model.finalizeCapture() }
                }
                .accessibilityHint("Stops Capture and verifies Original Audio")
            case .available:
                Button("Play Original Audio", systemImage: "play.fill") {
                    Task { await model.playOriginalAudio() }
                }
                .accessibilityHint("Plays the finalized or recovered local file")

                if let playbackStatus = model.playbackStatus {
                    Text(playbackStatus)
                }

                Button("Start New Capture", systemImage: "mic.fill") {
                    Task { await model.startCapture() }
                }
                .accessibilityHint("Replaces the previous proof file and starts immediately")
            case .inspecting:
                EmptyView()
            case .idle, .needsRecovery, .failed:
                Button("Start Capture", systemImage: "mic.fill") {
                    Task { await model.startCapture() }
                }
                .accessibilityHint("Starts recording immediately")
            }
        }
    }

    private var evidenceSection: some View {
        Section("Test Evidence") {
            if let captureStartedAt = model.captureStartedAt {
                LabeledContent("Started", value: captureStartedAt.formatted(date: .numeric, time: .standard))
            }
            Text(model.outputPath)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
            Text("For the interruption test, record for at least 25 seconds, terminate the process without Finalize, then relaunch. Repeat while the iPhone is locked.")
                .font(.footnote)
        }
    }
}

#Preview {
    CaptureProofView(
        model: CaptureProofModel(
            store: CaptureProofStore(rootDirectory: FileManager.default.temporaryDirectory)
        )
    )
}
