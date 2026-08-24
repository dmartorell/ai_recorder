import Foundation

struct CloudLibraryOwnerStore {
    private let defaults: UserDefaults
    private let key = "cloudLibraryOwnerID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bind(_ identity: CloudIdentity) -> CloudLibraryBindingResult {
        guard let value = defaults.string(forKey: key) else {
            defaults.set(identity.id.uuidString, forKey: key)
            return .bound
        }
        return value == identity.id.uuidString ? .alreadyBound : .differentOwner
    }

    func clear() { defaults.removeObject(forKey: key) }
}
