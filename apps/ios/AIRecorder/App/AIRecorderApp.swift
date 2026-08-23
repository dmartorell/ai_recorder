import SwiftUI

@main
struct AIRecorderApp: App {
    private let model: CaptureProofModel?
    private let startupError: String?

    init() {
        do {
            let store = try CaptureProofStore.applicationStore()
            model = CaptureProofModel(store: store)
            startupError = nil
        } catch {
            model = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                CaptureProofView(model: model)
            } else {
                ContentUnavailableView(
                    "Capture Proof Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(startupError ?? "Unknown startup error")
                )
            }
        }
    }
}
