import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsModel
    let onConfigureCloudBackup: () -> Void
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

                Section("Cloud backup") {
                    Button("Configure cloud backup", action: onConfigureCloudBackup)
                        .accessibilityHint("Sign in with an email magic link without affecting local Audio")
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
