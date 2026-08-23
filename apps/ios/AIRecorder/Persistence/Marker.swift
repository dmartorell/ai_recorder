import Foundation
import SwiftData

@Model
final class Marker {
    @Attribute(.unique) var id: UUID
    var positionMilliseconds: Int
    var createdAt: Date
    var audio: AudioItem?

    init(
        id: UUID = UUID(),
        positionMilliseconds: Int,
        createdAt: Date = .now,
        audio: AudioItem? = nil
    ) {
        self.id = id
        self.positionMilliseconds = max(0, positionMilliseconds)
        self.createdAt = createdAt
        self.audio = audio
    }
}
