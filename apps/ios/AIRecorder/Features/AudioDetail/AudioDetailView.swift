import SwiftUI
import AVFoundation
import AVFAudio

struct AudioDetailView: View {
    let item: AudioItem
    let files: AudioFileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var playback: LocalPlaybackModel
    @State private var showingDelete = false
    @State private var playbackError: String?
    @State private var deleteError: String?
    @State private var didDelete = false

    init(item: AudioItem, files: AudioFileStore) {
        self.item = item
        self.files = files
        _playback = State(initialValue: LocalPlaybackModel(
            player: AVPlayerPlaybackPlayer(url: files.url(for: item.id))
        ))
    }

    var body: some View {
        Form {
            Section("Audio") {
                Text(item.displayTitle()).font(.headline)
                LabeledContent("Date", value: item.startedAt.formatted(date: .long, time: .shortened))
                LabeledContent("Duration", value: duration)
                LabeledContent("State", value: item.localState == .needsRecovery ? "Needs recovery" : "Only on this iPhone")
            }
            Section("Playback") {
                HStack {
                    Button {
                        startPlaybackFromBeginning()
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .accessibilityLabel("Reiniciar reproducción")
                    .accessibilityHint("Starts playback from the beginning")

                    Button(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") {
                        togglePlayback()
                    }
                    .accessibilityHint("Plays the local Original Audio")
                }
                if let playbackError { Text(playbackError).foregroundStyle(.red) }
            }
            if !item.markers.isEmpty {
                Section("Markers") {
                    ForEach(item.markers.sorted { $0.positionMilliseconds < $1.positionMilliseconds }) { marker in
                        Button {
                            seekToMarker(marker.positionMilliseconds)
                        } label: {
                            Label(markerTime(marker.positionMilliseconds), systemImage: "bookmark.fill")
                        }
                        .accessibilityLabel("Marker at \(markerTime(marker.positionMilliseconds))")
                        .accessibilityHint("Seeks playback to this marker")
                    }
                }
            }
            Section {
                Button("Delete permanently", role: .destructive) { showingDelete = true }
            }
            if let deleteError { Text(deleteError).foregroundStyle(.red) }
        }
        .navigationTitle("Audio")
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if playback.isCurrentItem(notification.object as Any) {
                playback.handlePlaybackEnded()
            }
        }
        .confirmationDialog("Delete permanently?", isPresented: $showingDelete) {
            Button("Delete permanently", role: .destructive) { deleteAudio() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("No cloud copy exists. This local Original Audio cannot be recovered.") }
        .onDisappear {
            if !didDelete {
                playback.handlePlaybackEnded()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        .task {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .spokenAudio)
                try audioSession.setActive(true)
            } catch {
                playbackError = "Playback failed: \(error.localizedDescription)"
            }
        }
    }

    private var duration: String {
        let seconds = item.durationMilliseconds / 1000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func markerTime(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1_000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func togglePlayback() {
        do {
            try activatePlaybackSession()
            playback.togglePlayback()
            playbackError = nil
        } catch {
            playbackError = "Playback failed: \(error.localizedDescription)"
        }
    }

    private func startPlaybackFromBeginning() {
        do {
            try activatePlaybackSession()
            playback.restartPlayback()
            playbackError = nil
        } catch {
            playbackError = "Playback failed: \(error.localizedDescription)"
        }
    }

    private func seekToMarker(_ milliseconds: Int) {
        do {
            try activatePlaybackSession()
            playback.seek(to: Double(milliseconds) / 1_000)
            playbackError = nil
        } catch {
            playbackError = "Playback failed: \(error.localizedDescription)"
        }
    }

    private func activatePlaybackSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio)
        try audioSession.setActive(true)
    }

    private func deleteAudio() {
        do {
            didDelete = true
            try files.delete(item.id)
            modelContext.delete(item)
            try modelContext.save()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
