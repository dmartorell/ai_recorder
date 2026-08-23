import Foundation
import SwiftData

@MainActor
final class RecoveryService {
    private let context: ModelContext
    private let files: AudioFileStore
    private let inspector: any AudioInspector

    init(context: ModelContext, files: AudioFileStore, inspector: any AudioInspector = OriginalAudioInspector()) {
        self.context = context
        self.files = files
        self.inspector = inspector
    }

    func recoverInterruptedItems() async {
        let descriptor = FetchDescriptor<AudioItem>(predicate: #Predicate { item in
            item.localStateRawValue == "capturing" || item.localStateRawValue == "finalizing"
        })
        guard let items = try? context.fetch(descriptor) else { return }

        for item in items {
            let url = files.url(for: item.id)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values?.fileSize, size > 0 else {
                context.delete(item)
                continue
            }

            do {
                let summary = try await inspector.inspect(url)
                item.durationMilliseconds = Int((summary.duration * 1_000).rounded())
                item.endedAt = .now
                item.endedUnexpectedly = true
                item.localState = .recovered
            } catch {
                item.localState = .needsRecovery
            }
        }
        try? context.save()
    }
}
