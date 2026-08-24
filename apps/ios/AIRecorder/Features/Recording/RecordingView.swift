import SwiftUI

struct RecordingView: View {
    let coordinator: CaptureCoordinator
    @Environment(\.locale) private var locale
    @State private var showingFinalize = false

    var body: some View {
        VStack(spacing: 28) {
            Label("Recording", systemImage: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)

            Text(coordinator.currentItem?.displayTitle(locale: locale) ?? String(localized: "Audio", locale: locale))
                .font(.headline)

            Text(duration(coordinator.currentAudioPositionMilliseconds))
                .font(.system(.largeTitle, design: .monospaced))
                .monospacedDigit()
                .accessibilityLabel("Recorded duration")

            Text(coordinator.inputName)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Active input")

            if let automaticFinalizationMessage = coordinator.automaticFinalizationMessage {
                Label {
                    Text(automaticFinalizationMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            } else if let resourceWarning = coordinator.resourceWarning {
                Label {
                    Text(resourceWarning)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if coordinator.noInputLevelWarning {
                Label("No input level detected. Capture will continue.", systemImage: "mic.slash")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button {
                coordinator.addMarker()
            } label: {
                Label("Add marker", systemImage: "bookmark.fill")
            }
            .accessibilityHint(coordinator.phase == .recording ? "Marks the current audio time" : "Unavailable while Capture is finalizing")
            .disabled(coordinator.phase != .recording || coordinator.isStartingRecorder)
            .sensoryFeedback(.selection, trigger: coordinator.markerConfirmation)

            Button("Finalize", role: .destructive) { showingFinalize = true }
                .buttonStyle(.bordered)
                .disabled(coordinator.phase != .recording || coordinator.isStartingRecorder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("Capture")
        .confirmationDialog("Finalize this Audio?", isPresented: $showingFinalize) {
            Button("Finalize", role: .destructive) { Task { await coordinator.finalize() } }
            Button("Continue recording", role: .cancel) { }
        } message: { Text("Capture continues until you confirm.") }
    }

    private func duration(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1_000
        return String(format: "%02d:%02d", locale: locale, seconds / 60, seconds % 60)
    }
}
