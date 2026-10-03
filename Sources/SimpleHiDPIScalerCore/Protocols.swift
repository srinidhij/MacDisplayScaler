import CoreGraphics
import Foundation

/// Abstraction over connected-display discovery. Lets tests inject fakes.
public protocol DisplayDetecting: Sendable {
    func activeDisplays() -> [DisplayInfo]
    func displayName(for id: CGDirectDisplayID) -> String?
}

/// Abstraction over mode enumeration + switching. The live implementation
/// uses ONLY public Quartz Display Services. The private-API path (if ever
/// enabled) lives behind a separate gateway and is OFF by default.
public protocol DisplayModeManaging: Sendable {
    func allModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo]
    func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeInfo?
    /// Switch to a mode that MUST already exist in `allModes`. Returns CGError code.
    func setMode(_ mode: DisplayModeInfo, for displayID: CGDirectDisplayID) -> Int32
}

/// Chooses which mode to apply given what macOS actually exposes.
/// Never invents modes; returns nil when no suitable mode exists.
public protocol ScalingManaging: Sendable {
    /// Ordered UI choices for a 3440x1440 panel.
    func scalingOptions(for display: DisplayInfo, availableModes: [DisplayModeInfo]) -> [ScalingOption]
    /// Best available mode for a desired logical width (e.g. 2560 for 2560x1080).
    func bestMode(
        forLogicalWidth logicalWidth: Int,
        availableModes: [DisplayModeInfo],
        preferHiDPI: Bool
    ) -> DisplayModeInfo?
}

/// Persists reversible state (never display contents, never PII).
public protocol ConfigurationStoring: Sendable {
    var launchDefaultMode: DisplayModeInfo? { get set }
    var lastDisplayID: CGDirectDisplayID? { get set }
    var lastSelectedLogicalWidth: Int? { get set }
    func clear()
}

/// Owns the 10-second confirm-or-rollback window.
public protocol RollbackManaging: Sendable {
    var isArmed: Bool { get }
    var secondsRemaining: Int { get }
    func arm(rollback: @escaping () -> Void, timeoutSeconds: Int)
    func confirm()
    func tickForTests() -> Bool // returns true if rollback fired; test hook
}

/// High-level facade used by the menu-bar UI.
public protocol DisplayManaging: AnyObject, Sendable {
    var displays: [DisplayInfo] { get }
    func refreshDisplays()
    func modes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo]
    func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeInfo?
    func applyMode(_ mode: DisplayModeInfo, for displayID: CGDirectDisplayID) -> Int32
    func restoreLaunchDefault(for displayID: CGDirectDisplayID) -> Int32
}

// MARK: - ScalingOption

/// One radio-button row in the menu-bar UI.
public struct ScalingOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let logicalWidth: Int
    public let logicalHeight: Int
    /// The concrete mode to apply, or nil when macOS exposes nothing close
    /// (UI then shows the row as unavailable instead of guessing).
    public let matchedMode: DisplayModeInfo?

    public init(title: String, logicalWidth: Int, logicalHeight: Int, matchedMode: DisplayModeInfo?) {
        self.id = "\(logicalWidth)x\(logicalHeight)"
        self.title = title
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.matchedMode = matchedMode
    }

    public var isAvailable: Bool { matchedMode != nil }
}
