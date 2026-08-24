import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("App language", selection: $settings.appLanguage) {
                        Text("Spanish").tag(AppLanguage.spanish)
                        Text("English").tag(AppLanguage.english)
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Language")
                } footer: {
                    Text("Generated titles and interface text update immediately. Your titles stay unchanged.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
