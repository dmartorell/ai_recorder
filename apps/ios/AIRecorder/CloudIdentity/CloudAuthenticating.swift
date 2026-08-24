import Foundation

@MainActor
protocol CloudAuthenticating: AnyObject {
    func restoreIdentity() async throws -> CloudIdentity?
    func requestMagicLink(email: String) async throws
    func completeMagicLink(_ url: URL) async throws -> CloudIdentity?
    func signOut() async throws
}

enum CloudAuthenticationError: LocalizedError {
    case notConfigured
    case invalidMagicLink

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Cloud backup is not configured on this app."
        case .invalidMagicLink: "The magic link did not create a session."
        }
    }
}

@MainActor
final class UnavailableCloudAuthentication: CloudAuthenticating {
    func restoreIdentity() async throws -> CloudIdentity? { nil }
    func requestMagicLink(email: String) async throws { throw CloudAuthenticationError.notConfigured }
    func completeMagicLink(_ url: URL) async throws -> CloudIdentity? { throw CloudAuthenticationError.notConfigured }
    func signOut() async throws { }
}
