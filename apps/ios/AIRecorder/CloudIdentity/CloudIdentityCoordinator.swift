import Foundation
import Observation

@MainActor
@Observable
final class CloudIdentityCoordinator {
    private let authentication: any CloudAuthenticating
    private let ownerStore: CloudLibraryOwnerStore

    private(set) var identity: CloudIdentity?
    private(set) var state: CloudIdentityState = .signedOut
    private(set) var errorMessage: String?

    init(authentication: any CloudAuthenticating, ownerStore: CloudLibraryOwnerStore = .init()) {
        self.authentication = authentication
        self.ownerStore = ownerStore
    }

    func restoreSession() async {
        state = .restoring
        do {
            guard let restored = try await authentication.restoreIdentity() else {
                state = .signedOut
                return
            }
            accept(restored)
        } catch {
            state = .signedOut
        }
    }

    func requestMagicLink(email: String) async {
        state = .requestingMagicLink
        errorMessage = nil
        do {
            try await authentication.requestMagicLink(email: email)
            state = .magicLinkSent
        } catch {
            fail(error)
        }
    }

    func handleMagicLink(_ url: URL) async {
        do {
            guard let completed = try await authentication.completeMagicLink(url) else {
                throw CloudAuthenticationError.invalidMagicLink
            }
            accept(completed)
        } catch {
            fail(error)
        }
    }

    func signOut() async {
        do { try await authentication.signOut() } catch { fail(error); return }
        identity = nil
        state = .signedOut
    }

    private func accept(_ candidate: CloudIdentity) {
        switch ownerStore.bind(candidate) {
        case .bound, .alreadyBound:
            identity = candidate
            state = .authenticated
        case .differentOwner:
            identity = nil
            state = .accountMismatch
        }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        state = .failed
    }
}
