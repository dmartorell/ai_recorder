import SwiftUI

struct RecordingView: View {
    @Bindable var coordinator: CaptureCoordinator
    @State private var showingFinalize = false
    @State private var showingMarkerConfirmation = false

    var body: some View {
        VStack(spacing: 28) {
            Label("Recording", systemImage: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)

            Text(coordinator.currentItem?.displayTitle() ?? "Audio")
                .font(.headline)

            Text(duration(coordinator.currentAudioPositionMilliseconds))
                .font(.system(.largeTitle, design: .monospaced))
                .monospacedDigit()
                .accessibilityLabel("Recorded duration")

            Text(coordinator.inputName)
                .foregroundStyle(.secondary)

            Button {
                coordinator.addMarker()
            } label: {
                Label("Add marker", systemImage: "bookmark.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Marks the current audio time")
            .sensoryFeedback(.selection, trigger: coordinator.markerConfirmation)

            if showingMarkerConfirmation {
                Text("Marker added")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Button("Finalize", role: .destructive) { showingFinalize = true }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("Capture")
        .onChange(of: coordinator.markerConfirmation) {
            showingMarkerConfirmation = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                showingMarkerConfirmation = false
            }
        }
        .confirmationDialog("Finalize this Audio?", isPresented: $showingFinalize) {
            Button("Finalize", role: .destructive) { Task { await coordinator.finalize() } }
            Button("Continue recording", role: .cancel) { }
        } message: { Text("Capture continues until you confirm.") }
    }

    private func duration(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1_000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
