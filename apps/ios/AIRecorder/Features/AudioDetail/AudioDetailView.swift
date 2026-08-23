import SwiftUI
import AVFoundation
import AVFAudio

struct AudioDetailView: View {
    let item: AudioItem
    let files: AudioFileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showingDelete = false
    @State private var playbackError: String?
    @State private var deleteError: String?
    @State private var didDelete = false

    var body: some View {
        Form {
            Section("Audio") {
                Text(item.displayTitle()).font(.headline)
                LabeledContent("Date", value: item.startedAt.formatted(date: .long, time: .shortened))
                LabeledContent("Duration", value: duration)
                LabeledContent("State", value: item.localState == .needsRecovery ? "Needs recovery" : "Only on this iPhone")
            }
            Section("Playback") {
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") { togglePlayback() }
                    .accessibilityHint("Plays the local Original Audio")
                if let playbackError { Text(playbackError).foregroundStyle(.red) }
            }
            Section {
                Button("Delete permanently", role: .destructive) { showingDelete = true }
            }
            if let deleteError { Text(deleteError).foregroundStyle(.red) }
        }
        .navigationTitle("Audio")
        .confirmationDialog("Delete permanently?", isPresented: $showingDelete) {
            Button("Delete permanently", role: .destructive) { deleteAudio() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("No cloud copy exists. This local Original Audio cannot be recovered.") }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let endedItem = notification.object as? AVPlayerItem,
                  endedItem === player?.currentItem else { return }
            isPlaying = false
            player?.seek(to: .zero)
        }
        .onDisappear {
            stopPlayback(deactivateSession: !didDelete)
        }
    }

    private var duration: String {
        let seconds = item.durationMilliseconds / 1000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
            if player == nil { player = AVPlayer(url: files.url(for: item.id)) }
            player?.play()
            playbackError = nil
            isPlaying = true
        } catch {
            playbackError = "Playback failed: \(error.localizedDescription)"
            isPlaying = false
        }
    }

    private func deleteAudio() {
        do {
            stopPlayback(deactivateSession: true)
            didDelete = true
            try files.delete(item.id)
            modelContext.delete(item)
            try modelContext.save()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func stopPlayback(deactivateSession: Bool) {
        player?.pause()
        player = nil
        isPlaying = false
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
