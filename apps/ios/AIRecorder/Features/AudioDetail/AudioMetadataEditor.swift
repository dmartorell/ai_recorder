import SwiftUI
import SwiftData

struct AudioMetadataEditor: View {
    let item: AudioItem
    let files: AudioFileStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @State private var title: String
    @State private var context: String

    init(item: AudioItem, files: AudioFileStore) {
        self.item = item
        self.files = files
        _title = State(initialValue: item.customTitle ?? "")
        _context = State(initialValue: item.context)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text(item.displayTitle(locale: locale)))
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("metadata-title")
                } footer: {
                    Text("Leave the title empty to use the generated title.")
                }

                Section("Context") {
                    TextEditor(text: $context)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Edit Metadata")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        item.customTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.context = context
        do {
            try AudioRepository(context: modelContext, files: files).save()
            dismiss()
        } catch {
            // The editor remains open so the journalist can retry without losing edits.
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
