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

    func record(_ event: CaptureEvent, for item: AudioItem) throws {
        let record = CaptureEventRecord(
            kind: event.kind,
            startedAt: event.date,
            audioPositionMilliseconds: event.audioPositionMilliseconds,
            inputName: event.inputName,
            audio: item
        )
        context.insert(record)
        item.events.append(record)
        try context.save()
    }

    func markFinalizing(_ item: AudioItem) throws {
        guard item.localState == .capturing else { throw CaptureItemError.invalidState }
        item.localState = .finalizing
        try context.save()
    }

    func markAvailable(_ item: AudioItem, durationMilliseconds: Int, endedAt: Date = .now) throws {
        guard item.localState == .finalizing else { throw CaptureItemError.invalidState }
        item.durationMilliseconds = max(0, durationMilliseconds)
        item.endedAt = endedAt
        item.localState = .available
        try context.save()
    }

    func markRecovered(_ item: AudioItem, durationMilliseconds: Int, endedAt: Date = .now) throws {
        guard item.localState == .capturing || item.localState == .finalizing else {
            throw CaptureItemError.invalidState
        }
        item.durationMilliseconds = max(0, durationMilliseconds)
        item.endedAt = endedAt
        item.endedUnexpectedly = true
        item.localState = .recovered
        try context.save()
    }

    func markNeedsRecovery(_ item: AudioItem) throws {
        guard item.localState == .capturing || item.localState == .finalizing else {
            throw CaptureItemError.invalidState
        }
        item.localState = .needsRecovery
        try context.save()
    }

    @discardableResult
    func addMarker(to item: AudioItem, positionMilliseconds: Int) throws -> Marker {
        guard item.localState == .capturing else { throw CaptureItemError.invalidState }
        let marker = Marker(positionMilliseconds: positionMilliseconds, audio: item)
        context.insert(marker)
        item.markers.append(marker)
        try context.save()
        return marker
    }

    func delete(_ item: AudioItem) throws {
        try files.delete(item.id)
        context.delete(item)
        try context.save()
    }
}
