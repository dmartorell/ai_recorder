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
            ZStack(alignment: .top) {
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
                                        Text(state(item))
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .disabled(coordinator.isInterrupted)
                .opacity(coordinator.isInterrupted ? 0.45 : 1)

                if coordinator.isInterrupted {
                    interruptionBanner
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("Audio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Record", systemImage: "mic.fill") { showingPreparation = true }
                        .accessibilityHint("Capture starts immediately after permission is granted")
                        .disabled(coordinator.isInterrupted)
                }
            }
            .sheet(isPresented: $showingPreparation) {
                PreparationView(coordinator: coordinator)
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedItem) {
                AudioDetailView(item: $0, files: coordinator.files)
                    .presentationDetents([.large])
            }
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

    private func state(_ item: AudioItem) -> String {
        if item.id == coordinator.currentItem?.id, coordinator.isInterrupted {
            return "Recording interrupted"
        }
        switch item.localState {
        case .available: return "Only on this iPhone"
        case .needsRecovery: return "Needs recovery"
        case .capturing: return "Capturing"
        case .finalizing: return "Finalizing"
        case .recovered: return "Recovered"
        }
    }

    private var interruptionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Recording interrupted", systemImage: "pause.circle.fill")
                .font(.headline)
            Text("Waiting to resume… Your recording is still safe.")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .foregroundStyle(.primary)
        .background(.orange.opacity(0.9), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
