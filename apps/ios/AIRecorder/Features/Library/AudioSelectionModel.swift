import Foundation
import Observation

@MainActor
@Observable
final class AudioSelectionModel {
    private(set) var isSelecting = false
    private(set) var selectedIDs = Set<UUID>()
    private var dragAnchor: UUID?

    func enter() {
        isSelecting = true
    }

    func cancel() {
        isSelecting = false
        selectedIDs.removeAll()
        dragAnchor = nil
    }

    func toggle(_ id: UUID) {
        guard isSelecting else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func beginSelection(at id: UUID, orderedIDs: [UUID]) {
        guard orderedIDs.contains(id) else { return }
        enter()
        dragAnchor = id
        selectedIDs.insert(id)
    }

    func extendSelection(to id: UUID, orderedIDs: [UUID]) {
        guard let dragAnchor,
              let anchorIndex = orderedIDs.firstIndex(of: dragAnchor),
              let currentIndex = orderedIDs.firstIndex(of: id)
        else { return }

        selectedIDs.formUnion(orderedIDs[min(anchorIndex, currentIndex)...max(anchorIndex, currentIndex)])
    }

    func endSelectionDrag() {
        dragAnchor = nil
    }

    func retainExistingIDs(_ ids: Set<UUID>) {
        let retainedIDs = selectedIDs.intersection(ids)
        if selectedIDs != retainedIDs {
            selectedIDs = retainedIDs
        }
        if let dragAnchor, !ids.contains(dragAnchor) {
            self.dragAnchor = nil
        }
    }
}
