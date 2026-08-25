import SwiftUI
import SwiftData

struct RootView: View {
    let coordinator: CaptureCoordinator
    let recoveryService: RecoveryService
    let cloudBackupRecoveryService: CloudBackupRecoveryService
    let settings: SettingsModel
    let cloudIdentity: CloudIdentityCoordinator
    let cloudBackup: CloudBackupCoordinator
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioItem.startedAt, order: .reverse) private var items: [AudioItem]
    @State private var selection: AudioSelectionModel
    @State private var showingPreparation = false
    @State private var showingSettings = false
    @State private var showingCloudIdentity = false
    @State private var shouldShowCloudIdentityAfterSettingsDismissal = false
    @State private var selectedItem: AudioItem?
    @State private var itemPendingDeletion: AudioItem?
    @State private var showingUnbackedDeletionWarning = false
    @State private var showingBackedUpDeletion = false
    @State private var showingPermanentDeletion = false
    @State private var deletionError: String?

    init(coordinator: CaptureCoordinator, recoveryService: RecoveryService, cloudBackupRecoveryService: CloudBackupRecoveryService, settings: SettingsModel, cloudIdentity: CloudIdentityCoordinator, cloudBackup: CloudBackupCoordinator) {
        self.coordinator = coordinator
        self.recoveryService = recoveryService
        self.cloudBackupRecoveryService = cloudBackupRecoveryService
        self.settings = settings
        self.cloudIdentity = cloudIdentity
        self.cloudBackup = cloudBackup
        _selection = State(initialValue: AudioSelectionModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No Audio Yet", systemImage: "waveform", description: Text("Recordings you create appear here."))
                } else {
                    LibraryView(
                        items: items,
                        locale: locale,
                        selection: selection,
                        onOpen: { selectedItem = $0 },
                        onRequestSingleDeletion: requestDeletion,
                        onDeleteSelected: deleteSelectedAudio,
                        duration: duration,
                        state: state
                    )
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
                    if selection.isSelecting {
                        Button("Cancel") { selection.cancel() }
                    } else if !coordinator.isCapturing {
                        Button("Select") { selection.enter() }
                            .accessibilityHint("Select multiple Audio items to delete")
                    }
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !selection.isSelecting {
                        Button("Record", systemImage: "mic.fill") { showingPreparation = true }
                            .accessibilityHint("Capture starts immediately after permission is granted")
                    }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: presentCloudIdentityAfterSettingsDismissal) {
                SettingsView(settings: settings, onConfigureCloudBackup: configureCloudBackup)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingCloudIdentity) {
                CloudIdentityView(coordinator: cloudIdentity)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingPreparation) {
                PreparationView(coordinator: coordinator)
                    .presentationDetents([.large])
            }
            .sheet(item: $selectedItem) {
                AudioDetailView(item: $0, files: coordinator.files, cloudBackup: cloudBackup)
                    .presentationDetents([.large])
            }
            .alert("Delete local Audio?", isPresented: $showingBackedUpDeletion) {
                Button("Delete local audio", role: .destructive) { deletePendingAudio() }
                Button("Cancel", role: .cancel) { itemPendingDeletion = nil }
            } message: {
                Text("The verified cloud copy remains available after local deletion.")
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
            .background {
                CloudBackupLifecycleView(
                    recoveryService: recoveryService,
                    cloudBackupRecoveryService: cloudBackupRecoveryService,
                    cloudIdentity: cloudIdentity,
                    cloudBackup: cloudBackup
                )
            }
            .navigationDestination(for: UUID.self) { id in
                if let item = items.first(where: { $0.id == id }) {
                    AudioDetailView(item: item, files: coordinator.files, cloudBackup: cloudBackup)
                }
            }
        }
    }

    private func configureCloudBackup() {
        shouldShowCloudIdentityAfterSettingsDismissal = true
        showingSettings = false
    }

    private func presentCloudIdentityAfterSettingsDismissal() {
        guard shouldShowCloudIdentityAfterSettingsDismissal else { return }
        shouldShowCloudIdentityAfterSettingsDismissal = false
        showingCloudIdentity = true
    }

    private func requestDeletion(_ item: AudioItem) {
        guard !item.cloudBackupState.preventsLocalDeletion else {
            deletionError = "Cancel the cloud backup before deleting the local Original Audio."
            return
        }
        itemPendingDeletion = item
        if item.hasVerifiedCloudAudio {
            showingBackedUpDeletion = true
        } else {
            showingUnbackedDeletionWarning = true
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

    private func deleteSelectedAudio(_ selectedIDs: Set<UUID>) -> Set<UUID> {
        let repository = AudioRepository(context: modelContext, files: coordinator.files)
        var failedIDs = Set<UUID>()

        for item in items where selectedIDs.contains(item.id) {
            do {
                let confirmation = repository.confirmationForPermanentDeletion(of: item)
                try repository.delete(item, confirmation: confirmation)
            } catch {
                failedIDs.insert(item.id)
            }
        }
        return failedIDs
    }

    private func duration(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        return String(format: "%02d:%02d", locale: locale, seconds / 60, seconds % 60)
    }

    private func state(_ item: AudioItem) -> LibraryAudioStatus {
        libraryAudioStatus(for: item)
    }

}

private struct CloudBackupLifecycleView: View {
    let recoveryService: RecoveryService
    let cloudBackupRecoveryService: CloudBackupRecoveryService
    let cloudIdentity: CloudIdentityCoordinator
    let cloudBackup: CloudBackupCoordinator
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .task {
                cloudBackupRecoveryService.start()
                cloudBackupRecoveryService.setAppIsActive(scenePhase == .active)
                await recoveryService.recoverInterruptedItems()
                await cloudIdentity.restoreSession()
                guard cloudIdentity.state == .authenticated else { return }
                await cloudBackupRecoveryService.recoverPendingBackups()
                await cloudBackup.refreshTranscriptionStatuses()
            }
            .onChange(of: scenePhase) { _, newPhase in
                cloudBackupRecoveryService.setAppIsActive(newPhase == .active)
                guard newPhase == .active, cloudIdentity.state == .authenticated else { return }
                Task { await cloudBackup.refreshTranscriptionStatuses() }
            }
    }
}
