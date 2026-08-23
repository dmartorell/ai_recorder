import SwiftUI
import AVFAudio
import UIKit

struct PreparationView: View {
    @Bindable var coordinator: CaptureCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Preparation") {
                    LabeledContent("Microphone", value: permissionText)
                    LabeledContent("Input", value: coordinator.inputName)
                    LabeledContent("Format", value: "AAC-LC · M4A")
                }
                if coordinator.microphonePermission == .denied {
                    Section {
                        Text("Microphone access is required. Enable it in Settings.")
                        Button("Open Settings") { showingSettings = true }
                    }
                }
                Section {
                    Button("Record now", systemImage: "record.circle.fill") {
                        Task { await coordinator.start(); if coordinator.phase == .recording { dismiss() } }
                    }
                    .disabled(coordinator.microphonePermission == .denied)
                }
            }
            .navigationTitle("Prepare")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onOpenURL { _ in }
        }
        .onChange(of: showingSettings) { _, newValue in
            if newValue, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            showingSettings = false
        }
    }

    private var permissionText: String {
        switch coordinator.microphonePermission { case .granted: "Allowed"; case .denied: "Denied"; case .undetermined: "Not requested"; @unknown default: "Unknown" }
    }
}
