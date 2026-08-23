import Foundation

struct AudioVerifier: Sendable {
    private let inspector: any AudioInspector

    init(inspector: any AudioInspector = OriginalAudioInspector()) {
        self.inspector = inspector
    }

    func verify(_ url: URL) async throws -> CapturedAudioSummary {
        try await inspector.inspect(url)
    }
}
