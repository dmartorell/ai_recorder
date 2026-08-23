import Foundation
import SwiftData

@MainActor
final class AudioRepository {
    let context: ModelContext
    let files: AudioFileStore

    init(context: ModelContext, files: AudioFileStore) {
        self.context = context
        self.files = files
    }

    func beginCapture() throws -> AudioItem {
        let item = AudioItem(fileName: "\(UUID().uuidString).m4a")
        try files.prepare(for: item.id)
        context.insert(item)
        try context.save()
        return item
    }

    func save() throws { try context.save() }

    func delete(_ item: AudioItem) throws {
        try files.delete(item.id)
        context.delete(item)
        try context.save()
    }
}
