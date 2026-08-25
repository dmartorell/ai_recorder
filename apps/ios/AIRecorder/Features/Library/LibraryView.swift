import SwiftUI

struct LibrarySelectionControlFramesPreferenceKey: PreferenceKey {
    static let defaultValue = [UUID: CGRect]()

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct LibraryViewportPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct LibraryView: View {
    let items: [AudioItem]
    let locale: Locale
    let selection: AudioSelectionModel
    let onOpen: (AudioItem) -> Void
    let onRequestSingleDeletion: (AudioItem) -> Void
    let onDeleteSelected: (Set<UUID>) -> Set<UUID>
    let duration: (Int) -> String
    let state: (AudioItem) -> LibraryAudioStatus

    @State private var selectionControlFrames = [UUID: CGRect]()
    @State private var viewportFrame = CGRect.zero
    @State private var dragLocation: CGPoint?
    @State private var autoscrollTask: Task<Void, Never>?
    @State private var showingBulkDeletionWarning = false
    @State private var showingBulkPermanentDeletion = false
    @State private var bulkDeletionFailureCount = 0

    var body: some View {
        ScrollViewReader { scrollProxy in
            List(items) { item in
                LibraryAudioRow(
                    item: item,
                    locale: locale,
                    isSelecting: selection.isSelecting,
                    isSelected: selection.selectedIDs.contains(item.id),
                    onToggle: { selection.toggle(item.id) },
                    onOpen: { onOpen(item) },
                    onSelectionDragChanged: { startLocation, location in
                        selectionDragChanged(startLocation: startLocation, location: location, scrollProxy: scrollProxy)
                    },
                    onSelectionDragEnded: endSelectionDrag,
                    duration: duration,
                    state: state
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !selection.isSelecting, item.localOriginalAudioRemovedAt == nil {
                        Button("Delete", role: .destructive) {
                            onRequestSingleDeletion(item)
                        }
                        .accessibilityLabel("Delete \(item.displayTitle(locale: locale))")
                    }
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: LibraryViewportPreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            }
            .onPreferenceChange(LibrarySelectionControlFramesPreferenceKey.self) { frames in
                selectionControlFrames = frames
                extendSelectionToCurrentDragLocation()
            }
            .onPreferenceChange(LibraryViewportPreferenceKey.self) { viewportFrame = $0 }
            .safeAreaInset(edge: .bottom) {
                if !selection.selectedIDs.isEmpty {
                    bulkDeleteToolbar
                }
            }
            .onChange(of: selection.isSelecting) { _, isSelecting in
                if !isSelecting { stopAutoscrolling() }
            }
            .onDisappear(perform: stopAutoscrolling)
        }
        .alert("Delete \(selection.selectedIDs.count) local Audio items?", isPresented: $showingBulkDeletionWarning) {
            Button("Delete", role: .destructive) {
                showingBulkPermanentDeletion = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("No verified cloud copy exists for the selected Audio. Deletion is permanent.")
        }
        .alert("Delete \(selection.selectedIDs.count) Audio items permanently?", isPresented: $showingBulkPermanentDeletion) {
            Button("Delete permanently", role: .destructive) {
                deleteSelectedAudio()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the selected local Original Audio files and their metadata.")
        }
        .alert("Could not delete selected Audio", isPresented: Binding(
            get: { bulkDeletionFailureCount > 0 },
            set: { if !$0 { bulkDeletionFailureCount = 0 } }
        )) {
            Button("OK", role: .cancel) { bulkDeletionFailureCount = 0 }
        } message: {
            Text("\(bulkDeletionFailureCount) Audio items were retained because deletion failed.")
        }
    }

    private var bulkDeleteToolbar: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(selection.selectedIDs.count) selected")
                if selectedItemsContainActiveBackup {
                    Text("Cancel cloud backup before deleting local Audio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if selectedItemsContainCloudOnlyAudio {
                    Text("Cloud-only Audio has no local copy to delete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                showingBulkDeletionWarning = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Delete \(selection.selectedIDs.count) selected Audio items")
            .disabled(selectedItemsCannotBeDeleted)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var selectedItemsCannotBeDeleted: Bool {
        selectedItemsContainActiveBackup || selectedItemsContainCloudOnlyAudio
    }

    private var selectedItemsContainActiveBackup: Bool {
        items.contains {
            selection.selectedIDs.contains($0.id) && $0.cloudBackupState.preventsLocalDeletion
        }
    }

    private var selectedItemsContainCloudOnlyAudio: Bool {
        items.contains {
            selection.selectedIDs.contains($0.id) && $0.localOriginalAudioRemovedAt != nil
        }
    }

    private func selectionDragChanged(
        startLocation: CGPoint,
        location: CGPoint,
        scrollProxy: ScrollViewProxy
    ) {
        guard selection.isSelecting else { return }
        if dragLocation == nil,
           let id = selectionControlID(containing: startLocation) {
            selection.beginSelection(at: id, orderedIDs: orderedIDs)
        }
        dragLocation = location
        extendSelectionToCurrentDragLocation()
        updateAutoscrolling(using: scrollProxy)
    }

    private func endSelectionDrag() {
        dragLocation = nil
        selection.endSelectionDrag()
        stopAutoscrolling()
    }

    private var orderedIDs: [UUID] { items.map(\.id) }

    private func selectionControlID(containing location: CGPoint) -> UUID? {
        selectionControlFrames.first { $0.value.contains(location) }?.key
    }

    private func extendSelectionToCurrentDragLocation() {
        guard let dragLocation,
              let id = selectionControlID(containing: dragLocation)
        else { return }
        selection.extendSelection(to: id, orderedIDs: orderedIDs)
    }

    private func updateAutoscrolling(using scrollProxy: ScrollViewProxy) {
        guard dragLocation != nil, edgeDirection != nil else {
            stopAutoscrolling()
            return
        }
        guard autoscrollTask == nil else { return }

        autoscrollTask = Task { @MainActor in
            while !Task.isCancelled, let direction = edgeDirection {
                guard let nextID = adjacentVisibleID(in: direction) else { break }
                withAnimation(.linear(duration: 0.12)) {
                    scrollProxy.scrollTo(nextID, anchor: direction == .top ? .top : .bottom)
                }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                extendSelectionToCurrentDragLocation()
            }
            autoscrollTask = nil
        }
    }

    private func stopAutoscrolling() {
        autoscrollTask?.cancel()
        autoscrollTask = nil
    }

    private enum EdgeDirection { case top, bottom }

    private var edgeDirection: EdgeDirection? {
        guard let dragLocation, !viewportFrame.isEmpty else { return nil }
        let edgeZone: CGFloat = 44
        if dragLocation.y <= viewportFrame.minY + edgeZone { return .top }
        if dragLocation.y >= viewportFrame.maxY - edgeZone { return .bottom }
        return nil
    }

    private func adjacentVisibleID(in direction: EdgeDirection) -> UUID? {
        let visibleIDs = selectionControlFrames
            .filter { $0.value.maxY >= viewportFrame.minY && $0.value.minY <= viewportFrame.maxY }
            .sorted { $0.value.minY < $1.value.minY }
            .map(\.key)
        guard let edgeID = direction == .top ? visibleIDs.first : visibleIDs.last,
              let index = orderedIDs.firstIndex(of: edgeID)
        else { return nil }

        let adjacentIndex = direction == .top ? index - 1 : index + 1
        guard orderedIDs.indices.contains(adjacentIndex) else { return nil }
        return orderedIDs[adjacentIndex]
    }

    private func deleteSelectedAudio() {
        let selectedIDs = selection.selectedIDs
        let failedIDs = onDeleteSelected(selectedIDs)
        selection.retainExistingIDs(failedIDs)
        if failedIDs.isEmpty {
            selection.cancel()
        } else {
            bulkDeletionFailureCount = failedIDs.count
        }
    }
}
