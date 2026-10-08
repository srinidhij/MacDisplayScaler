import CoreGraphics
import Foundation
import PrivateBridge

/// PRIVATE PROTOTYPE GATEWAY — explicit opt-in, disabled by default.
///
/// Approved by the user after the public-API limitation was demonstrated:
/// on Apple Silicon there is no public way to synthesize HiDPI backing stores
/// for a sub-4K 3440×1440 panel. This gateway implements the BetterDisplay-class
/// route (private virtual display + mirror) behind a loud opt-in + kill-switch.
///
/// Pipeline (see Sources/PrivateBridge/PrivateBridge.m):
///  1. `CGVirtualDisplayDescriptor` + `CGVirtualDisplay` +
///     `CGVirtualDisplaySettings(hiDPI=1)` + `CGVirtualDisplayMode`
///     (private CoreGraphics classes since macOS 10.14, resolved at runtime via
///     NSClassFromString — no link-time dependency, safe if Apple removes them).
///  2. `CGConfigureDisplayMirrorOfDisplay` (**public** mirroring API) mirrors the
///     physical Dell onto the virtual display; the DCP scaler downsamples the 2x
///     backing store to the panel's native 3440×1440.
///
/// Consequences (repeated in README/SECURITY/PRIVACY + in-app warning):
/// - Private/undocumented: can break on any macOS update.
/// - App Store rejection; notarization scrutinized.
/// - It IS a virtual display + mirroring (originally excluded; now allowed only
///   as an explicitly approved prototype).
/// - The panel keeps its fastest native refresh only when it runs at it before
///   mirroring; `enable()` switches it there first.
/// - Kill-switch: disabling destroys the virtual display and unmirrors.
public enum PrivateHiDPIError: Error, Equatable {
    case optInRequired
    case unavailable
    case creationFailed(Int32)
    case mirrorFailed(Int32)

    /// Back-compat with the public-only stub: opt-in off surfaces as refusal.
    public static let refusedPrivateAPI = PrivateHiDPIError.optInRequired
}

/// What to do about an active virtual once display changes have settled.
public enum PrivateReconcileAction: Equatable, Sendable {
    /// The panel went offline (unplugged, powered off, input switched). The
    /// virtual would otherwise stay behind as an invisible extended display.
    case teardownPanelGone
    /// The panel is online but no longer mirrors our virtual (changed in System
    /// Settings): same invisible-display risk.
    case teardownUnmirrored
    /// Still mirrored, but the panel runs below its fastest native refresh
    /// (macOS restored a slower configuration). Re-creating raises it again.
    case recreateForRefresh
}

public struct PrivateHiDPIResult: Sendable, Equatable {
    public let virtualDisplayID: UInt32
    public let physicalDisplayID: UInt32
    public init(virtualDisplayID: UInt32, physicalDisplayID: UInt32) {
        self.virtualDisplayID = virtualDisplayID
        self.physicalDisplayID = physicalDisplayID
    }
}

public enum PrivateHiDPIGateway: Sendable {
    private static let optInKey = "privatePrototypeEnabled"
    private static let lock = NSLock()
    private static var _active: [UInt32: UInt32] = [:] // physical -> virtual
    private static var _creating = false
    /// Panel mode captured before mirroring, re-applied on teardown. Process
    /// exit does NOT revert a mirror configuration, so this is the only restore.
    private static var _savedModes: [UInt32: CGDisplayMode] = [:]
    private static var _sizes: [UInt32: (width: Int, height: Int)] = [:] // physical -> "looks like"
    private static let installTermination: Void = {
        PrivateVirtualDisplaySetTerminationCallback { endedID in
            PrivateHiDPIGateway.virtualEnded(endedID)
        }
    }()

    /// WindowServer ended a virtual (our own destroy, or it died). Prune state.
    static func virtualEnded(_ virtualID: UInt32) {
        lock.lock(); defer { lock.unlock() }
        for (physical, v) in _active where v == virtualID {
            _active.removeValue(forKey: physical)
            _sizes.removeValue(forKey: physical)
            _savedModes.removeValue(forKey: physical)
        }
    }

    /// Looks-like size of the active private display for a physical panel.
    public static func activeSize(forPhysical physical: UInt32) -> (width: Int, height: Int)? {
        lock.lock(); defer { lock.unlock() }
        return _sizes[physical]
    }

    /// Highest-refresh mode at the panel's native resolution. Mirroring keeps
    /// 120 Hz only when the panel already runs at 120 Hz beforehand, else the
    /// pair sticks at 60. The current mode is not a usable starting point: after
    /// a quit macOS leaves the panel at a 1x "looks like" size (2560x1080),
    /// whose fastest refresh is 60 Hz.
    static func fastestNativeMode(for id: CGDirectDisplayID) -> CGDisplayMode? {
        DisplayModeManager.nativeModes(for: id).max { $0.refreshRate < $1.refreshRate }
    }

    /// Decision behind `reconcileAction(forPhysical:)`, separated for tests.
    public static func reconcileAction(
        online: Bool,
        mirrorsVirtual: Bool,
        belowNativeRefresh: Bool
    ) -> PrivateReconcileAction? {
        if !online { return .teardownPanelGone }
        if !mirrorsVirtual { return .teardownUnmirrored }
        return belowNativeRefresh ? .recreateForRefresh : nil
    }

    /// Checks an active physical/virtual pair against the live display state.
    /// nil when nothing is active for `physical` or the pair is healthy.
    public static func reconcileAction(forPhysical physical: UInt32) -> PrivateReconcileAction? {
        guard let virtual = virtualDisplay(forPhysical: physical) else { return nil }
        let id = CGDirectDisplayID(physical)
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        let online = CGGetOnlineDisplayList(32, &ids, &count) == .success && ids.prefix(Int(count)).contains(id)
        var below = false
        if online, let cur = CGDisplayCopyDisplayMode(id), let fast = fastestNativeMode(for: id) {
            below = cur.refreshRate + 0.5 < fast.refreshRate
        }
        return reconcileAction(
            online: online,
            mirrorsVirtual: online && CGDisplayMirrorsDisplay(id) == CGDirectDisplayID(virtual),
            belowNativeRefresh: below
        )
    }

    // MARK: - Opt-in (default OFF)

    public static var optInEnabled: Bool {
        UserDefaults.standard.bool(forKey: optInKey)
    }

    public static func setOptIn(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: optInKey)
    }

    // MARK: - Availability (runtime probe, no side effects)

    /// True when the four private classes + required selectors exist.
    /// Does not require opt-in and creates nothing.
    public static var isAvailable: Bool {
        PrivateVirtualDisplayAvailable() != 0
    }

    public static var activeMap: [UInt32: UInt32] {
        lock.lock(); defer { lock.unlock() }
        return _active
    }

    public static func virtualDisplay(forPhysical physical: UInt32) -> UInt32? {
        lock.lock(); defer { lock.unlock() }
        return _active[physical]
    }

    // MARK: - Lifecycle

    /// Create a hiDPI virtual display for `physicalDisplayID` and mirror the
    /// physical panel onto it. Returns the virtual display ID.
    ///
    /// - Requires `optInEnabled`, else `.optInRequired`.
    /// - Requires `isAvailable`, else `.unavailable`.
    /// - Idempotent per physical display: an existing virtual is reused.
    ///
    /// Each logical size is declared at both 120 Hz and 60 Hz: mirroring a
    /// 120 Hz panel onto a 60 Hz-only virtual fails in the DCP, which was the
    /// observed `mirrorFailed` cause once the Dell ran at 120 Hz.
    public static func enable(
        physicalDisplayID: UInt32,
        logicalModes: [(width: Int, height: Int, refresh: Double)] = [
            (3440, 1440, 120), (3440, 1440, 60),
            (3008, 1264, 120), (3008, 1264, 60),
            (2560, 1080, 120), (2560, 1080, 60),
        ]
    ) -> Result<PrivateHiDPIResult, PrivateHiDPIError> {
        guard optInEnabled else { return .failure(.optInRequired) }
        guard isAvailable else { return .failure(.unavailable) }
        _ = installTermination
        lock.lock()
        if _creating {
            lock.unlock()
            return .failure(.creationFailed(-30)) // creation already in flight
        }
        _creating = true
        if let existing = _active[physicalDisplayID] {
            _creating = false
            lock.unlock()
            return .success(PrivateHiDPIResult(virtualDisplayID: existing, physicalDisplayID: physicalDisplayID))
        }
        lock.unlock()

        defer {
            lock.lock()
            _creating = false
            lock.unlock()
        }

        var widths = logicalModes.map { UInt32($0.width) }
        var heights = logicalModes.map { UInt32($0.height) }
        var refreshes = logicalModes.map { Double($0.refresh) }
        var outID: UInt32 = 0
        let name = "SimpleHiDPI \(physicalDisplayID)"
        // Unique serial per creation: reusing the physical ID collided with
        // virtuals still in teardown limbo, which WindowServer then never
        // brought online (observed creationFailed(-20) storm).
        let serial = UInt32.random(in: 1...UInt32.max)
        let rc: Int32 = name.withCString { namePtr in
            widths.withUnsafeMutableBufferPointer { wPtr in
                heights.withUnsafeMutableBufferPointer { hPtr in
                    refreshes.withUnsafeMutableBufferPointer { rPtr in
                        Int32(PrivateVirtualDisplayCreate(
                            0x5348, // "SH"
                            0x4849, // "HI"
                            serial,
                            namePtr,
                            6880, 2880, // 2x backing for 3440x1440
                            800, 340, // ~34" 21:9 physical size
                            1, // hiDPI
                            wPtr.baseAddress, hPtr.baseAddress, rPtr.baseAddress,
                            Int32(logicalModes.count),
                            &outID
                        ))
                    }
                }
            }
        }
        guard rc == 0, outID != 0 else {
            return .failure(.creationFailed(rc))
        }
        // The virtual needs a moment to come online in WindowServer; mirroring
        // before that fails at CGCompleteDisplayConfiguration (observed -13 on
        // rapid retries). Poll briefly, then mirror exactly once.
        if !waitForDisplayOnline(outID, timeoutSeconds: 2.0) {
            PrivateVirtualDisplayDestroy(outID)
            return .failure(.creationFailed(-20))
        }
        let did = CGDirectDisplayID(physicalDisplayID)
        let savedMode = CGDisplayCopyDisplayMode(did)
        if let fast = fastestNativeMode(for: did), let cur = savedMode,
           cur.width != fast.width || cur.pixelWidth != fast.pixelWidth || cur.refreshRate < fast.refreshRate
        {
            _ = CGDisplaySetDisplayMode(did, fast, nil)
            Thread.sleep(forTimeInterval: 1.0)
        }
        let mirrorRC = Int32(PrivateMirrorPhysicalOntoVirtual(physicalDisplayID, outID))
        guard mirrorRC == 0 else {
            PrivateVirtualDisplayDestroy(outID)
            return .failure(.mirrorFailed(mirrorRC))
        }
        lock.lock()
        _active[physicalDisplayID] = outID
        if let first = logicalModes.first { _sizes[physicalDisplayID] = (first.width, first.height) }
        if let savedMode { _savedModes[physicalDisplayID] = savedMode }
        lock.unlock()
        return .success(PrivateHiDPIResult(virtualDisplayID: outID, physicalDisplayID: physicalDisplayID))
    }

    /// Single teardown primitive: unmirror, wait for the mirror set to clear,
    /// destroy the virtual, then re-apply the panel mode captured before
    /// mirroring. Safe to call when nothing is active. Used by the kill-switch,
    /// the 10-s rollback and restore-defaults.
    public static func disable(physicalDisplayID: UInt32) {
        let (virtual, saved): (UInt32?, CGDisplayMode?) = {
            lock.lock(); defer { lock.unlock() }
            _sizes.removeValue(forKey: physicalDisplayID)
            return (_active.removeValue(forKey: physicalDisplayID),
                    _savedModes.removeValue(forKey: physicalDisplayID))
        }()
        let did = CGDirectDisplayID(physicalDisplayID)
        _ = PrivateMirrorPhysicalOntoVirtual(physicalDisplayID, 0)
        let deadline = Date().addingTimeInterval(2.0)
        while CGDisplayIsInMirrorSet(did) != 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if let v = virtual {
            PrivateVirtualDisplayDestroy(v)
        }
        if let saved {
            _ = CGDisplaySetDisplayMode(did, saved, nil)
        }
    }

    /// Change the "looks like" size of an active private display. The virtual's
    /// mode list is not switchable while mirrored (verified live), so this tears
    /// down (restoring the panel) and re-creates the virtual with only the
    /// requested size, which then becomes its default mode.
    public static func enable(
        physicalDisplayID: UInt32,
        logicalWidth: Int,
        logicalHeight: Int
    ) -> Result<PrivateHiDPIResult, PrivateHiDPIError> {
        if virtualDisplay(forPhysical: physicalDisplayID) != nil {
            disable(physicalDisplayID: physicalDisplayID)
            Thread.sleep(forTimeInterval: 1.0) // let WindowServer finish teardown
        }
        return enable(
            physicalDisplayID: physicalDisplayID,
            logicalModes: [(logicalWidth, logicalHeight, 120), (logicalWidth, logicalHeight, 60)]
        )
    }

    /// Legacy single-mode entry point kept for the test suite + callers that
    /// only need "give me HiDPI or refuse". With opt-in off it refuses; with
    /// opt-in on it ensures the shared virtual exists and reports the requested
    /// logical mode as HiDPI (backing = 2x) without claiming macOS exposed it
    /// natively.
    public static func enableCustomHiDPI(
        logicalWidth: Int,
        logicalHeight: Int,
        displayID: UInt32
    ) -> Result<DisplayModeInfo, PrivateHiDPIError> {
        switch enable(physicalDisplayID: displayID) {
        case .success:
            return .success(DisplayModeInfo(
                width: logicalWidth,
                height: logicalHeight,
                pixelWidth: logicalWidth * 2,
                pixelHeight: logicalHeight * 2,
                refreshRate: 60,
                ioModeID: nil,
                usableForDesktopGUI: true
            ))
        case .failure(let e):
            return .failure(e)
        }
    }

    // MARK: - Helpers

    /// Polls CGGetActiveDisplayList until `displayID` appears (public API).
    static func waitForDisplayOnline(_ displayID: UInt32, timeoutSeconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var count: UInt32 = 0
        while Date() < deadline {
            count = 0
            guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            var fetched: UInt32 = 0
            if CGGetActiveDisplayList(count, &ids, &fetched) == .success,
               ids.prefix(Int(fetched)).contains(CGDirectDisplayID(displayID))
            {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    // MARK: - Test hooks (no hardware side effects)
    /// Gating decision without creating anything. Lets unit tests assert the
    /// opt-in boundary headlessly.
    public static func gatingDecisionForTests(optIn: Bool, available: Bool) -> PrivateHiDPIError? {
        if !optIn { return .optInRequired }
        if !available { return .unavailable }
        return nil // would proceed to creation on real hardware
    }

    public static var disclosure: String {
        """
        PRIVATE PROTOTYPE (opt-in, off by default). Creates a hiDPI virtual \
        display via private CoreGraphics APIs (CGVirtualDisplayDescriptor et \
        al., runtime-resolved) and mirrors the physical display onto it with \
        the public CGConfigureDisplayMirrorOfDisplay; the DCP downsamples 2x \
        to the panel. Breaks on OS updates, no App Store, kill-switch destroys \
        the virtual display and unmirrors.
        """
    }
}
