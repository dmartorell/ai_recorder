import SwiftUI
import SwiftData

struct RootView: View {
    let coordinator: CaptureCoordinator
    let recoveryService: RecoveryService
    let settings: SettingsModel
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioItem.startedAt, order: .reverse) private var items: [AudioItem]
    @State private var showingPreparation = false
    @State private var showingSettings = false
    @State private var selectedItem: AudioItem?
    @State private var itemPendingDeletion: AudioItem?
    @State private var showingUnbackedDeletionWarning = false
    @State private var showingPermanentDeletion = false
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No Audio Yet", systemImage: "waveform", description: Text("Recordings you create appear here."))
                } else {
                    List(items) { item in
                        Button { selectedItem = item } label: {
                            VStack(alignment: .leading) {
                                Text(item.displayTitle(locale: locale))
                                HStack {
                                    Text(item.startedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                    Spacer()
                                    Text(duration(item.durationMilliseconds))
                                    Text(state(item))
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                itemPendingDeletion = item
                                showingUnbackedDeletionWarning = true
                            }
                            .accessibilityLabel("Delete \(item.displayTitle(locale: locale))")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("Audio")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gear") { showingSettings = true }
                        .accessibilityHint("Choose the app language")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Record", systemImage: "mic.fill") { showingPreparation = true }
                        .accessibilityHint("Capture starts immediately after permission is granted")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingPreparation) {
                PreparationView(coordinator: coordinator)
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedItem) {
                AudioDetailView(item: $0, files: coordinator.files)
                    .presentationDetents([.large])
            }
            .alert("Delete local Audio?", isPresented: $showingUnbackedDeletionWarning) {
                Button("Delete", role: .destructive) {
                    showingPermanentDeletion = true
                }
                Button("Cancel", role: .cancel) { itemPendingDeletion = nil }
            } message: {
                Text("No verified cloud copy exists. Deleting this Original Audio is permanent.")
            }
            .alert(
                "Delete \(itemPendingDeletion?.displayTitle(locale: locale) ?? "") permanently?",
                isPresented: $showingPermanentDeletion
            ) {
                Button("Delete permanently", role: .destructive) { deletePendingAudio() }
                Button("Cancel", role: .cancel) { itemPendingDeletion = nil }
            } message: {
                Text("This removes the local Original Audio and its metadata.")
            }
            .alert(
                "Could not delete local Audio",
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { deletionError = nil }
            } message: {
                Text(deletionError ?? "")
            }
            .task { await recoveryService.recoverInterruptedItems() }
            .navigationDestination(for: UUID.self) { id in
                if let item = items.first(where: { $0.id == id }) { AudioDetailView(item: item, files: coordinator.files) }
            }
        }
    }

    private func deletePendingAudio() {
        guard let item = itemPendingDeletion else { return }
        let repository = AudioRepository(context: modelContext, files: coordinator.files)

        do {
            let confirmation = repository.confirmationForPermanentDeletion(of: item)
            try repository.delete(item, confirmation: confirmation)
            itemPendingDeletion = nil
        } catch {
            deletionError = "Could not delete local Audio: \(error.localizedDescription)"
        }
    }

    private func duration(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        return String(format: "%02d:%02d", locale: locale, seconds / 60, seconds % 60)
    }

    private func state(_ item: AudioItem) -> LocalizedStringResource {
        if item.captureEndedByInterruption { return "Ended by interruption" }
        if item.captureEndedByUnavailableInput { return "Ended: input unavailable" }
        switch item.localState {
        case .available: return "Only on this iPhone"
        case .needsRecovery: return "Needs recovery"
        case .capturing: return "Capturing"
        case .finalizing: return "Finalizing"
        case .recovered: return "Recovered"
        }
    }
}
