import CoreGraphics
import Foundation

/// Facade over detection + modes + config + rollback + logging.
/// The UI talks only to this object (via the DisplayManaging protocol).
public final class DisplayManager: DisplayManaging, @unchecked Sendable {
    private let detector: DisplayDetecting
    private let modes: DisplayModeManaging
    private let store: ConfigurationStoring
    private let logger: AppLogger

    private let lock = NSLock()
    private var cached: [DisplayInfo] = []

    public init(
        detector: DisplayDetecting = DisplayDetector(),
        modes: DisplayModeManaging = DisplayModeManager(),
        store: ConfigurationStoring = ConfigurationStore(),
        logger: AppLogger = .shared
    ) {
        self.detector = detector
        self.modes = modes
        self.store = store
        self.logger = logger
        refreshDisplays()
        // Capture the launch-time mode once so "Restore Defaults" is the
        // mode macOS had before we touched anything. Taken from an external
        // panel: the built-in display's mode means nothing on the Dell.
        if store.launchDefaultMode == nil,
           let first = cached.first(where: { !$0.isOwnVirtual && !$0.isBuiltin }),
           let current = modes.currentMode(for: first.id)
        {
            var mutableStore = store
            mutableStore.launchDefaultMode = current
        }
    }

    public var displays: [DisplayInfo] {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    public func refreshDisplays() {
        let found = detector.activeDisplays()
        lock.lock()
        cached = found
        lock.unlock()
    }

    public func modes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        modes.allModes(for: displayID)
    }

    public func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeInfo? {
        modes.currentMode(for: displayID)
    }

    /// Applies a mode AFTER verifying it exists. Caller owns the 10-second
    /// confirm/rollback (see MenuBar UI + RollbackManager).
    @discardableResult
    public func applyMode(_ mode: DisplayModeInfo, for displayID: CGDirectDisplayID) -> Int32 {
        let previous = modes.currentMode(for: displayID)
        let code = self.modes.setMode(mode, for: displayID)
        logger.logDisplayChange(displayID: displayID, previous: previous, selected: mode, resultCode: code)
        return code
    }

    /// Re-applies the launch-time mode saved in ConfigurationStore.
    /// Falls back to the mode macOS reports as current when nothing was saved.
    @discardableResult
    public func restoreLaunchDefault(for displayID: CGDirectDisplayID) -> Int32 {
        var mutableStore = store
        if mutableStore.launchDefaultMode == nil {
            mutableStore.launchDefaultMode = modes.currentMode(for: displayID)
        }
        guard let target = mutableStore.launchDefaultMode else {
            return Int32(CGError.failure.rawValue)
        }
        let previous = modes.currentMode(for: displayID)
        let code = modes.setMode(target, for: displayID)
        logger.logDisplayChange(displayID: displayID, previous: previous, selected: target, resultCode: code)
        return code
    }
}
