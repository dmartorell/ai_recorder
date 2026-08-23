import SwiftUI

struct RecordingView: View {
    @Bindable var coordinator: CaptureCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var showingFinalize = false

    var body: some View {
        VStack(spacing: 28) {
            Label("Recording", systemImage: "record.circle.fill").font(.title2).foregroundStyle(.red)
            Text(coordinator.currentItem?.displayTitle() ?? "Audio").font(.headline)
            Text(coordinator.inputName).foregroundStyle(.secondary)
            Button("Finalize", role: .destructive) { showingFinalize = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .navigationTitle("Capture")
        .confirmationDialog("Finalize this Audio?", isPresented: $showingFinalize) {
            Button("Finalize", role: .destructive) { Task { await coordinator.finalize(); dismiss() } }
            Button("Continue recording", role: .cancel) { }
        } message: { Text("Capture continues until you confirm.") }
    }
}
