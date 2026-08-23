import SwiftUI
import SwiftData

struct RootView: View {
    @Bindable var coordinator: CaptureCoordinator
    let recoveryService: RecoveryService
    @Query(sort: \AudioItem.startedAt, order: .reverse) private var items: [AudioItem]
    @State private var showingPreparation = false
    @State private var selectedItem: AudioItem?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No Audio Yet", systemImage: "waveform", description: Text("Recordings you create appear here."))
                } else {
                    List(items) { item in
                        Button { selectedItem = item } label: {
                            VStack(alignment: .leading) {
                                Text(item.displayTitle())
                                HStack {
                                    Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    Spacer()
                                    Text(duration(item.durationMilliseconds))
                                    Text(state(item.localState))
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Audio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Record", systemImage: "mic.fill") { showingPreparation = true }
                        .accessibilityHint("Capture starts immediately after permission is granted")
                }
            }
            .sheet(isPresented: $showingPreparation) { PreparationView(coordinator: coordinator) }
            .sheet(item: $selectedItem) { AudioDetailView(item: $0, files: coordinator.files) }
            .task { await recoveryService.recoverInterruptedItems() }
            .navigationDestination(for: UUID.self) { id in
                if let item = items.first(where: { $0.id == id }) { AudioDetailView(item: item, files: coordinator.files) }
            }
        }
    }

    private func duration(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func state(_ state: LocalAudioState) -> String {
        switch state { case .available: "Only on this iPhone"; case .needsRecovery: "Needs recovery"; case .capturing: "Capturing"; case .finalizing: "Finalizing"; case .recovered: "Recovered" }
    }
}
