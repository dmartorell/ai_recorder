import Foundation
import Supabase

@MainActor
final class SupabaseCloudAuthentication: CloudAuthenticating {
    private let client: SupabaseClient
    private let implicitFlowClient: SupabaseClient
    private let redirectURL = URL(string: "com.danielmartorell.ai-recorder://auth/callback")!

    init(configuration: SupabaseConfiguration) {
        client = Self.makeClient(configuration: configuration, flowType: .pkce)
        implicitFlowClient = Self.makeClient(configuration: configuration, flowType: .implicit)
    }

    func restoreIdentity() async throws -> CloudIdentity? {
        guard let session = try? await client.auth.session else { return nil }
        return CloudIdentity(id: session.user.id, email: session.user.email ?? "")
    }

    func requestMagicLink(email: String) async throws {
        try await client.auth.signInWithOTP(
            email: email,
            redirectTo: redirectURL,
            shouldCreateUser: false
        )
    }

    func completeMagicLink(_ url: URL) async throws -> CloudIdentity? {
        let authenticationClient = Self.usesImplicitGrantRedirect(url) ? implicitFlowClient : client
        let session = try await authenticationClient.auth.session(from: url)
        return CloudIdentity(id: session.user.id, email: session.user.email ?? "")
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    static func usesImplicitGrantRedirect(_ url: URL) -> Bool {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            return false
        }
        let parameters = URLComponents(string: "?\(fragment)")?.queryItems ?? []
        return parameters.contains { $0.name == "access_token" }
    }

    private static func makeClient(configuration: SupabaseConfiguration, flowType: AuthFlowType) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(
                    flowType: flowType,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}

struct SupabaseConfiguration {
    let url: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) -> Self? {
        guard let url = bundle.url(forResource: "Supabase", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: String],
              let urlString = values["SUPABASE_URL"],
              let apiURL = URL(string: urlString),
              let key = values["SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty
        else { return nil }
        return Self(url: apiURL, publishableKey: key)
    }
}
