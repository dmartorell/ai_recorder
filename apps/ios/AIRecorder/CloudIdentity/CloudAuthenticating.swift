import Foundation

@MainActor
protocol CloudAccessTokenProviding: AnyObject {
    func accessToken() async throws -> String
}

@MainActor
protocol CloudAuthenticating: CloudAccessTokenProviding {

    func restoreIdentity() async throws -> CloudIdentity?
    func requestMagicLink(email: String) async throws
    func completeMagicLink(_ url: URL) async throws -> CloudIdentity?
    func signOut() async throws
}

enum CloudAuthenticationError: LocalizedError, Equatable {
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
    func accessToken() async throws -> String { throw CloudAuthenticationError.notConfigured }
    func restoreIdentity() async throws -> CloudIdentity? { nil }
    func requestMagicLink(email: String) async throws { throw CloudAuthenticationError.notConfigured }
    func completeMagicLink(_ url: URL) async throws -> CloudIdentity? { throw CloudAuthenticationError.notConfigured }
    func signOut() async throws { }
}
