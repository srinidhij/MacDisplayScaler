import Foundation

/// The user's confirmed private "looks like" size, applied automatically on
/// launch (so also at login). Written only when the user presses Keep, so a
/// size that was never confirmed can never be auto-applied.
public struct PrivateDefaultStore: @unchecked Sendable {
    private static let widthKey = "privateDefaultWidth"
    private static let heightKey = "privateDefaultHeight"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var size: (width: Int, height: Int)? {
        get {
            guard defaults.object(forKey: Self.widthKey) != nil,
                  defaults.object(forKey: Self.heightKey) != nil else { return nil }
            return (defaults.integer(forKey: Self.widthKey), defaults.integer(forKey: Self.heightKey))
        }
        nonmutating set {
            if let v = newValue {
                defaults.set(v.width, forKey: Self.widthKey)
                defaults.set(v.height, forKey: Self.heightKey)
            } else {
                defaults.removeObject(forKey: Self.widthKey)
                defaults.removeObject(forKey: Self.heightKey)
            }
        }
    }

    /// One-time copy of settings from the bare-binary defaults domain
    /// (`SimpleHiDPIScaler`) into the current domain (the .app's bundle id).
    public static func migrateLegacyDomain(_ legacyName: String = "SimpleHiDPIScaler",
                                           into defaults: UserDefaults = .standard) {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleIdentifier != legacyName,
              defaults.object(forKey: "migratedFromLegacyDomain") == nil else { return }
        defaults.set(true, forKey: "migratedFromLegacyDomain")
        guard let legacy = defaults.persistentDomain(forName: legacyName) else { return }
        for (k, v) in legacy where defaults.object(forKey: k) == nil { defaults.set(v, forKey: k) }
    }
}
