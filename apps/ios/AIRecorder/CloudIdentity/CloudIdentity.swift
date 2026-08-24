import Foundation

struct CloudIdentity: Equatable, Sendable {
    let id: UUID
    let email: String
}

enum CloudIdentityState: Equatable {
    case signedOut
    case restoring
    case requestingMagicLink
    case magicLinkSent
    case authenticated
    case accountMismatch
    case unavailable
    case failed
}

enum CloudLibraryBindingResult: Equatable {
    case bound
    case alreadyBound
    case differentOwner
}
