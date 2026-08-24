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
                    LabeledContent("Free storage", value: storageText)
                    LabeledContent("Available recording", value: durationText)
                    if coordinator.isLowBatteryWarning {
                        Label("Battery is low. Capture will continue.", systemImage: "battery.25percent")
                            .foregroundStyle(.orange)
                    }
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
                    .disabled(coordinator.microphonePermission == .denied || coordinator.availableDuration == nil)
                }
                if let resourceWarning = coordinator.resourceWarning {
                    Section {
                        Label(resourceWarning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Prepare")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { coordinator.refreshResources() }
            .onOpenURL { _ in }
        }
        .onChange(of: showingSettings) { _, newValue in
            if newValue, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            showingSettings = false
        }
    }

    private var storageText: String {
        switch coordinator.storageAssessment {
        case .sufficient, .warning: "Available"
        case .critical: "Below safe threshold"
        }
    }

    private var durationText: String {
        guard let duration = coordinator.availableDuration else { return "Unavailable" }
        return "≈ \(max(0, duration.components.seconds / 60)) min"
    }

    private var permissionText: String {
        switch coordinator.microphonePermission { case .granted: "Allowed"; case .denied: "Denied"; case .undetermined: "Not requested"; @unknown default: "Unknown" }
    }
}
