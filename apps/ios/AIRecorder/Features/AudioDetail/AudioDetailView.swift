import AVFoundation
import AVFAudio
import SwiftData
import SwiftUI

struct AudioDetailView: View {
    let item: AudioItem
    let files: AudioFileStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @State private var playback: LocalPlaybackModel
    @State private var metadataItem: AudioItem?
    @State private var showingUnbackedDeletionWarning = false
    @State private var showingPermanentDeletion = false
    @State private var playbackError: String?
    @State private var deletionError: String?

    init(item: AudioItem, files: AudioFileStore) {
        self.item = item
        self.files = files
        _playback = State(initialValue: LocalPlaybackModel(
            player: AVPlayerPlaybackPlayer(url: files.url(for: item.id)),
            durationSeconds: Double(item.durationMilliseconds) / 1_000
        ))
    }

    var body: some View {
        Form {
            AudioInformationSection(item: item, state: state, locale: locale)
            CloudBackupEligibilitySection(eligibility: BackupEligibility.forBackup(of: item, files: files))
            PlaybackSection(playback: playback, durationSeconds: durationSeconds)

            if !item.markers.isEmpty {
                MarkerSection(markers: item.markers, playback: playback)
            }

            Section {
                Button("Edit metadata") { metadataItem = item }
                Button("Delete", role: .destructive) {
                    showingUnbackedDeletionWarning = true
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
        .task { configurePlaybackSession() }
    }

    private var durationSeconds: Double {
        Double(item.durationMilliseconds) / 1_000
    }

    private var state: LocalizedStringResource {
        if item.captureEndedByInterruption { return "Ended by interruption" }
        if item.captureEndedByUnavailableInput { return "Ended: input unavailable" }
        return item.localState == .needsRecovery ? "Needs recovery" : "Only on this iPhone"
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
    let state: LocalizedStringResource
    let locale: Locale

    var body: some View {
        Section("Audio") {
            Text(item.displayTitle(locale: locale)).font(.headline)
            LabeledContent("Date") {
                Text(item.startedAt, format: .dateTime.day().month(.wide).year().hour().minute())
            }
            LabeledContent("Duration", value: formattedDuration(Double(item.durationMilliseconds) / 1_000, locale: locale))
            LabeledContent("State") { Text(state) }
        }
    }
}

private struct CloudBackupEligibilitySection: View {
    let eligibility: BackupEligibility

    var body: some View {
        Section("Cloud backup") {
            LabeledContent("Backup eligibility") { Text(status) }
        }
    }

    private var status: LocalizedStringResource {
        switch eligibility {
        case .eligible: "Ready for cloud backup"
        case .captureIsActive: "Available after Capture finishes"
        case .originalAudioIsUnverified: "Original Audio needs recovery"
        case .originalAudioIsMissing: "Original Audio is missing"
        case .originalAudioIsEmpty: "Original Audio is empty"
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
