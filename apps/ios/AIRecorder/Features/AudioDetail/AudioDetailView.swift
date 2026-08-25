import AVFoundation
import AVFAudio
import SwiftData
import SwiftUI

struct AudioDetailView: View {
    let item: AudioItem
    let files: AudioFileStore
    let cloudBackup: CloudBackupCoordinator

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @State private var playback: LocalPlaybackModel
    @State private var metadataItem: AudioItem?
    @State private var showingUnbackedDeletionWarning = false
    @State private var showingBackedUpDeletion = false
    @State private var showingPermanentDeletion = false
    @State private var playbackError: String?
    @State private var deletionError: String?
    @State private var showingBackupConfirmation = false
    @State private var showingBackupCancellation = false

    init(item: AudioItem, files: AudioFileStore, cloudBackup: CloudBackupCoordinator) {
        self.item = item
        self.files = files
        self.cloudBackup = cloudBackup
        _playback = State(initialValue: LocalPlaybackModel(
            player: AVPlayerPlaybackPlayer(url: files.url(for: item.id)),
            durationSeconds: Double(item.durationMilliseconds) / 1_000
        ))
    }

    var body: some View {
        Form {
            AudioInformationSection(item: item, locale: locale)
            CloudBackupSection(
                item: item,
                eligibility: BackupEligibility.forBackup(of: item, files: files),
                coordinator: cloudBackup,
                requestBackup: requestBackup,
                requestCancellation: { showingBackupCancellation = true }
            )
            if item.localOriginalAudioRemovedAt == nil {
                PlaybackSection(playback: playback, durationSeconds: durationSeconds)
            } else {
                Section("Playback") {
                    Text("Local Original Audio was removed. Cloud playback is available on the web.")
                        .foregroundStyle(.secondary)
                }
            }

            if !item.markers.isEmpty {
                MarkerSection(markers: item.markers, playback: playback)
            }

            Section {
                Button("Edit metadata") { metadataItem = item }
                if item.localOriginalAudioRemovedAt == nil {
                    Button("Delete", role: .destructive, action: requestDeletion)
                        .disabled(item.cloudBackupState.preventsLocalDeletion)
                        .accessibilityHint(deletionHint)
                    if item.cloudBackupState.preventsLocalDeletion {
                        Text("Cancel cloud backup before deleting local Audio.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let playbackError {
                Section { Text(playbackError).foregroundStyle(.red) }
            }
            if let deletionError {
                Section { Text(deletionError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Audio")
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if playback.isCurrentItem(notification.object as Any) {
                playback.handlePlaybackEnded()
            }
        }
        .sheet(item: $metadataItem) { editableItem in
            AudioMetadataEditor(item: editableItem, files: files)
        }
        .confirmationDialog("Back up Original Audio?", isPresented: $showingBackupConfirmation) {
            Button("Back up") { Task { await cloudBackup.confirmBackup(for: item) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This uploads a private cloud copy. The local Original Audio stays on this iPhone.")
        }
        .confirmationDialog("Cancel cloud backup?", isPresented: $showingBackupCancellation) {
            Button("Cancel upload", role: .destructive) {
                Task { try? await cloudBackup.cancelBackup(for: item) }
            }
            Button("Keep uploading", role: .cancel) { }
        } message: {
            Text("The local Original Audio stays on this iPhone.")
        }
        .alert("Delete local Audio?", isPresented: $showingBackedUpDeletion) {
            Button("Delete local audio", role: .destructive) { deleteAudio() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The verified cloud copy remains available after local deletion.")
        }
        .alert("Delete local Audio?", isPresented: $showingUnbackedDeletionWarning) {
            Button("Delete", role: .destructive) {
                showingPermanentDeletion = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("No verified cloud copy exists. Deleting this Original Audio is permanent.")
        }
        .alert("Delete \(item.displayTitle(locale: locale)) permanently?", isPresented: $showingPermanentDeletion) {
            Button("Delete", role: .destructive) { deleteAudio() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the local Original Audio and its metadata.")
        }
        .onDisappear {
            playback.tearDown()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        .task(id: item.cloudBackupID) {
            configurePlaybackSession()
            if item.cloudBackupState.preventsLocalDeletion {
                await cloudBackup.resumeBackup(for: item)
            }
            await cloudBackup.refreshTranscriptionStatus(for: item)
        }
    }

    private var durationSeconds: Double {
        Double(item.durationMilliseconds) / 1_000
    }

    private var deletionHint: LocalizedStringResource {
        item.cloudBackupState.preventsLocalDeletion
            ? "Cancel the cloud backup before deleting the local Original Audio."
            : "Deletes the local Original Audio after confirmation."
    }

    private func requestBackup() {
        Task {
            await cloudBackup.requestBackup(for: item)
            showingBackupConfirmation = cloudBackup.pendingConfirmationAudioID == item.id
        }
    }

    private func configurePlaybackSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
        } catch {
            playbackError = "Playback failed: \(error.localizedDescription)"
        }
    }

    private func requestDeletion() {
        if item.hasVerifiedCloudAudio {
            showingBackedUpDeletion = true
        } else {
            showingUnbackedDeletionWarning = true
        }
    }

    private func deleteAudio() {
        let repository = AudioRepository(context: modelContext, files: files)
        do {
            let confirmation = repository.confirmationForPermanentDeletion(of: item)
            try repository.delete(item, confirmation: confirmation)
            dismiss()
        } catch {
            deletionError = "Could not delete local Audio: \(error.localizedDescription)"
        }
    }
}

private struct AudioInformationSection: View {
    let item: AudioItem
    let locale: Locale

    var body: some View {
        Section("Audio") {
            Text(item.displayTitle(locale: locale)).font(.headline)
            LabeledContent("Date") {
                Text(item.startedAt, format: .dateTime.day().month(.wide).year().hour().minute())
            }
            LabeledContent("Duration", value: formattedDuration(Double(item.durationMilliseconds) / 1_000, locale: locale))
        }
    }
}

private struct CloudBackupSection: View {
    let item: AudioItem
    let eligibility: BackupEligibility
    let coordinator: CloudBackupCoordinator
    let requestBackup: () -> Void
    let requestCancellation: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Section("Cloud backup") {
            LabeledContent("Local audio") { Text(audioStatePresentation(for: item).localAudio.localizedString) }
            LabeledContent("Cloud audio") { Text(audioStatePresentation(for: item).cloudAudio.localizedString) }
            LabeledContent("Transcription") { Text(audioStatePresentation(for: item).transcription.localizedString) }
            LabeledContent("Summary") { Text(audioStatePresentation(for: item).summary.localizedString) }
            if item.cloudBackupID == nil {
                Picker("Transcription language", selection: Binding(get: { item.transcriptionLanguage }, set: { item.transcriptionLanguage = $0; try? modelContext.save() })) {
                    Text("Spanish").tag(TranscriptionLanguage.spanish)
                    Text("English").tag(TranscriptionLanguage.english)
                    Text("Spanish and English").tag(TranscriptionLanguage.spanishEnglish)
                }
            }

            if item.cloudBackupState == .failed {
                Button("Retry upload") { Task { await coordinator.resumeBackup(for: item) } }
                    .accessibilityHint("Retries this cloud backup without creating another Original Audio.")
                    .accessibilityIdentifier("cloud-backup-retry")
            } else if canRequestBackup {
                Button("Back up Original Audio", action: requestBackup)
                    .accessibilityHint("Uploads a private cloud copy. The local Original Audio stays on this iPhone.")
                    .accessibilityIdentifier("cloud-backup-request")
            }
            if item.cloudBackupState.preventsLocalDeletion {
                Button("Cancel cloud backup", role: .destructive, action: requestCancellation)
                    .accessibilityHint("Keeps the local Original Audio and stops this upload.")
                    .accessibilityIdentifier("cloud-backup-cancel")
            }
            if let errorMessage = coordinator.errorMessage {
                CloudBackupErrorText(message: errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var canRequestBackup: Bool {
        eligibility == .eligible && item.cloudBackupID == nil && item.cloudBackupState != .backedUp
    }

}

private struct CloudBackupErrorText: View {
    let message: CloudBackupErrorMessage

    var body: some View {
        switch message {
        case let .localized(resource): Text(resource)
        case let .text(text): Text(text)
        }
    }
}

private struct PlaybackSection: View {
    let playback: LocalPlaybackModel
    let durationSeconds: Double

    var body: some View {
        Section("Playback") {
            HStack {
                Text(formattedDuration(playback.positionSeconds))
                    .monospacedDigit()
                Spacer()
                Text(formattedDuration(durationSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formattedDuration(playback.positionSeconds)) of \(formattedDuration(durationSeconds))")

            Slider(
                value: Binding(
                    get: { playback.positionSeconds },
                    set: { playback.previewPosition(at: $0) }
                ),
                in: 0...max(durationSeconds, 0.001),
                onEditingChanged: { isEditing in
                    if isEditing {
                        playback.beginScrubbing()
                    } else {
                        playback.endScrubbing()
                    }
                }
            ) {
                Text("Playback position")
            }
            .accessibilityValue("\(formattedDuration(playback.positionSeconds)) of \(formattedDuration(durationSeconds))")
            .animation(
                playback.isScrubbing ? nil : .linear(duration: 0.1),
                value: playback.positionSeconds
            )

            HStack {
                Button { playback.skip(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                        .frame(width: 68, height: 68)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Back 10 seconds")
                .accessibilityHint("Seeks backward in the local Original Audio")
                .accessibilityIdentifier("playback-back-10")

                Spacer()

                Button { playback.togglePlayback() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 68, height: 68)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                .accessibilityHint("Plays or pauses the local Original Audio")
                .accessibilityIdentifier("playback-toggle")

                Spacer()

                Button { playback.skip(by: 10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.title)
                        .frame(width: 68, height: 68)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Forward 10 seconds")
                .accessibilityHint("Seeks forward in the local Original Audio")
                .accessibilityIdentifier("playback-forward-10")
            }
        }
    }
}

private struct MarkerSection: View {
    let markers: [Marker]
    let playback: LocalPlaybackModel

    var body: some View {
        Section("Markers") {
            ForEach(markers.sorted { $0.positionMilliseconds < $1.positionMilliseconds }) { marker in
                Button {
                    playback.seek(to: Double(marker.positionMilliseconds) / 1_000)
                } label: {
                    Label(formattedDuration(Double(marker.positionMilliseconds) / 1_000), systemImage: "bookmark.fill")
                }
                .accessibilityHint("Seeks playback to this marker")
            }
        }
    }
}

private func formattedDuration(_ seconds: Double, locale: Locale = .current) -> String {
    let totalSeconds = max(0, Int(seconds.rounded(.down)))
    return String(format: "%02d:%02d", locale: locale, totalSeconds / 60, totalSeconds % 60)
}
