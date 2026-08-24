import Foundation
import XCTest
@testable import AIRecorder

@MainActor
final class CloudIdentityCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CloudIdentityCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirstRestoredAccountBindsLocalLibrary() async {
        let account = CloudIdentity(id: UUID(), email: "journalist@example.test")
        let authentication = FakeCloudAuthentication(restoredIdentity: account)
        let coordinator = CloudIdentityCoordinator(
            authentication: authentication,
            ownerStore: CloudLibraryOwnerStore(defaults: defaults)
        )

        await coordinator.restoreSession()

        XCTAssertEqual(coordinator.identity, account)
        XCTAssertEqual(coordinator.state, .authenticated)
    }

    func testDifferentRestoredAccountCannotUseBoundLibrary() async {
        let owner = CloudIdentity(id: UUID(), email: "owner@example.test")
        let other = CloudIdentity(id: UUID(), email: "other@example.test")
        let store = CloudLibraryOwnerStore(defaults: defaults)
        XCTAssertEqual(store.bind(owner), .bound)
        let coordinator = CloudIdentityCoordinator(
            authentication: FakeCloudAuthentication(restoredIdentity: other),
            ownerStore: store
        )

        await coordinator.restoreSession()

        XCTAssertNil(coordinator.identity)
        XCTAssertEqual(coordinator.state, .accountMismatch)
    }

    func testMagicLinkRequestDoesNotCreateSession() async {
        let authentication = FakeCloudAuthentication()
        let coordinator = CloudIdentityCoordinator(
            authentication: authentication,
            ownerStore: CloudLibraryOwnerStore(defaults: defaults)
        )

        await coordinator.requestMagicLink(email: "journalist@example.test")

        XCTAssertEqual(authentication.requestedEmail, "journalist@example.test")
        XCTAssertEqual(coordinator.state, .magicLinkSent)
        XCTAssertNil(coordinator.identity)
    }

    func testMagicLinkCompletionBindsAccount() async {
        let account = CloudIdentity(id: UUID(), email: "journalist@example.test")
        let authentication = FakeCloudAuthentication(completedIdentity: account)
        let coordinator = CloudIdentityCoordinator(
            authentication: authentication,
            ownerStore: CloudLibraryOwnerStore(defaults: defaults)
        )

        await coordinator.handleMagicLink(URL(string: "com.danielmartorell.ai-recorder://auth/callback")!)

        XCTAssertEqual(coordinator.identity, account)
        XCTAssertEqual(coordinator.state, .authenticated)
    }
}

@MainActor
private final class FakeCloudAuthentication: CloudAuthenticating {
    var restoredIdentity: CloudIdentity?
    var completedIdentity: CloudIdentity?
    var requestedEmail: String?

    init(restoredIdentity: CloudIdentity? = nil, completedIdentity: CloudIdentity? = nil) {
        self.restoredIdentity = restoredIdentity
        self.completedIdentity = completedIdentity
    }

    func restoreIdentity() async throws -> CloudIdentity? { restoredIdentity }

    func requestMagicLink(email: String) async throws { requestedEmail = email }

    func completeMagicLink(_ url: URL) async throws -> CloudIdentity? { completedIdentity }

    func signOut() async throws { restoredIdentity = nil }
}
