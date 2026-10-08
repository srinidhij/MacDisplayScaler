import Foundation

/// The user's confirmed private "looks like" size and the display it was
/// confirmed on, applied automatically on launch (so also at login) and when
/// that display reconnects. Written only when the user presses Keep, so a
/// size that was never confirmed can never be auto-applied.
public struct PrivateDefaultStore: @unchecked Sendable {
    private static let widthKey = "privateDefaultWidth"
    private static let heightKey = "privateDefaultHeight"
    private static let displayKeyKey = "privateDefaultDisplay"
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
                defaults.removeObject(forKey: Self.displayKeyKey)
            }
        }
    }

    /// `DisplayInfo.identityKey` of the display the size belongs to. nil for a
    /// size saved before defaults were tied to a display.
    public var displayKey: String? {
        get { defaults.string(forKey: Self.displayKeyKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.displayKeyKey) }
    }

    /// The online display the saved size belongs to, or nil. A size saved
    /// without a display belongs to the Dell (the only panel it could have been
    /// confirmed on), never to the built-in or any other display.
    public func target(in displays: [DisplayInfo]) -> DisplayInfo? {
        guard size != nil else { return nil }
        let physical = displays.filter { !$0.isOwnVirtual }
        if let key = displayKey {
            return physical.first { $0.identityKey == key }
        }
        return physical.first { $0.isDellUWQHD }
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
