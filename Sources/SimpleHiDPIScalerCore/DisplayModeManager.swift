import CoreGraphics
import Foundation

/// Live mode enumeration + switching using ONLY public Quartz Display Services:
///
/// - CGDisplayCopyAllDisplayModes(id, nil)
/// - CGDisplayMode width/height/pixelWidth/pixelHeight/refreshRate
/// - CGDisplayMode ioDisplayModeID (to re-identify a mode later)
/// - CGDisplayMode.isUsableForDesktopGUI()
/// - CGDisplayCopyDisplayMode (current mode)
/// - CGDisplaySetDisplayMode (apply)
///
/// IMPORTANT SAFETY PROPERTY (documented by Apple): the mode set with
/// CGDisplaySetDisplayMode persists only for the life of the calling process;
/// when the app quits, macOS reverts to the permanent System Settings mode.
/// That gives us a free fail-safe on top of our own 10-second rollback.
public final class DisplayModeManager: DisplayModeManaging, Sendable {
    public init() {}

    public func allModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        guard let cfModes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return []
        }
        return cfModes.map(DisplayModeInfo.init(cgMode:)).sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI && !rhs.isHiDPI }
            return lhs.refreshRate > rhs.refreshRate
        }
    }

    public func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeInfo? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return DisplayModeInfo(cgMode: mode)
    }

    @discardableResult
    public func setMode(_ mode: DisplayModeInfo, for displayID: CGDirectDisplayID) -> Int32 {
        // VERIFY the selected mode still exists before touching hardware.
        guard let target = findLiveMode(matching: mode, for: displayID) else {
            return Int32(CGError.failure.rawValue) // kCGErrorFailure
        }
        let err = CGDisplaySetDisplayMode(displayID, target, nil)
        return Int32(err.rawValue)
    }

    // MARK: - Internal

    private func findLiveMode(matching wanted: DisplayModeInfo, for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        guard let cfModes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return nil
        }
        // Prefer exact IO mode ID; fall back to geometry match.
        if let ioID = wanted.ioModeID {
            if let exact = cfModes.first(where: { $0.ioDisplayModeID == ioID }) {
                return exact
            }
        }
        return cfModes.first(where: {
            $0.width == wanted.width
                && $0.height == wanted.height
                && $0.pixelWidth == wanted.pixelWidth
                && $0.pixelHeight == wanted.pixelHeight
        })
    }
}

extension DisplayModeInfo {
    init(cgMode: CGDisplayMode) {
        self.init(
            width: cgMode.width,
            height: cgMode.height,
            pixelWidth: cgMode.pixelWidth,
            pixelHeight: cgMode.pixelHeight,
            refreshRate: cgMode.refreshRate,
            ioModeID: cgMode.ioDisplayModeID,
            usableForDesktopGUI: cgMode.isUsableForDesktopGUI()
        )
    }
}
