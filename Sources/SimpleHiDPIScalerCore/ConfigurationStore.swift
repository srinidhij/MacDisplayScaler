import CoreGraphics
import Foundation

private enum Keys {
    static let launchDefaultWidth = "launchDefaultWidth"
    static let launchDefaultHeight = "launchDefaultHeight"
    static let launchDefaultPixelWidth = "launchDefaultPixelWidth"
    static let launchDefaultPixelHeight = "launchDefaultPixelHeight"
    static let launchDefaultRefresh = "launchDefaultRefresh"
    static let launchDefaultIOID = "launchDefaultIOID"
    static let lastDisplayID = "lastDisplayID"
    static let lastLogicalWidth = "lastLogicalWidth"
}

/// Persists ONLY reversible display state in UserDefaults (app sandbox /
/// group defaults — no files in Documents/Desktop, no keychain, no network).
/// Stores plain integers/doubles; no display contents, no user identity.
public final class ConfigurationStore: ConfigurationStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var launchDefaultMode: DisplayModeInfo? {
        get {
            lock.lock(); defer { lock.unlock() }
            guard defaults.object(forKey: Keys.launchDefaultWidth) != nil else { return nil }
            return DisplayModeInfo(
                width: defaults.integer(forKey: Keys.launchDefaultWidth),
                height: defaults.integer(forKey: Keys.launchDefaultHeight),
                pixelWidth: defaults.integer(forKey: Keys.launchDefaultPixelWidth),
                pixelHeight: defaults.integer(forKey: Keys.launchDefaultPixelHeight),
                refreshRate: defaults.double(forKey: Keys.launchDefaultRefresh),
                ioModeID: defaults.object(forKey: Keys.launchDefaultIOID).map { _ in Int32(defaults.integer(forKey: Keys.launchDefaultIOID)) },
                usableForDesktopGUI: true
            )
        }
        set {
            lock.lock(); defer { lock.unlock() }
            if let m = newValue {
                defaults.set(m.width, forKey: Keys.launchDefaultWidth)
                defaults.set(m.height, forKey: Keys.launchDefaultHeight)
                defaults.set(m.pixelWidth, forKey: Keys.launchDefaultPixelWidth)
                defaults.set(m.pixelHeight, forKey: Keys.launchDefaultPixelHeight)
                defaults.set(m.refreshRate, forKey: Keys.launchDefaultRefresh)
                if let io = m.ioModeID {
                    defaults.set(Int(io), forKey: Keys.launchDefaultIOID)
                } else {
                    defaults.removeObject(forKey: Keys.launchDefaultIOID)
                }
            } else {
                for k in [Keys.launchDefaultWidth, Keys.launchDefaultHeight, Keys.launchDefaultPixelWidth, Keys.launchDefaultPixelHeight, Keys.launchDefaultRefresh, Keys.launchDefaultIOID] {
                    defaults.removeObject(forKey: k)
                }
            }
        }
    }

    public var lastDisplayID: CGDirectDisplayID? {
        get {
            lock.lock(); defer { lock.unlock() }
            guard defaults.object(forKey: Keys.lastDisplayID) != nil else { return nil }
            return CGDirectDisplayID(defaults.integer(forKey: Keys.lastDisplayID))
        }
        set {
            lock.lock(); defer { lock.unlock() }
            if let v = newValue { defaults.set(Int(v), forKey: Keys.lastDisplayID) }
            else { defaults.removeObject(forKey: Keys.lastDisplayID) }
        }
    }

    public var lastSelectedLogicalWidth: Int? {
        get {
            lock.lock(); defer { lock.unlock() }
            guard defaults.object(forKey: Keys.lastLogicalWidth) != nil else { return nil }
            return defaults.integer(forKey: Keys.lastLogicalWidth)
        }
        set {
            lock.lock(); defer { lock.unlock() }
            if let v = newValue { defaults.set(v, forKey: Keys.lastLogicalWidth) }
            else { defaults.removeObject(forKey: Keys.lastLogicalWidth) }
        }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        for k in [Keys.launchDefaultWidth, Keys.launchDefaultHeight, Keys.launchDefaultPixelWidth, Keys.launchDefaultPixelHeight, Keys.launchDefaultRefresh, Keys.launchDefaultIOID, Keys.lastDisplayID, Keys.lastLogicalWidth] {
            defaults.removeObject(forKey: k)
        }
    }
}
