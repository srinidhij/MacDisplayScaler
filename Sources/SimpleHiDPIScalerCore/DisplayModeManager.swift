import CoreGraphics
import Foundation
import IOKit.graphics

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

    /// Modes at the panel's own resolution, every refresh rate. macOS marks
    /// them with kDisplayModeNativeFlag; without the flag, the largest 1x modes.
    /// Independent of the current mode, so it also works while the panel is
    /// mirrored or left at a lower mode.
    public static func nativeModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let all = (CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode]) ?? []
        let flagged = all.filter { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 && $0.isUsableForDesktopGUI() }
        if !flagged.isEmpty { return flagged }
        let plain = all.filter { $0.width == $0.pixelWidth && $0.isUsableForDesktopGUI() }
        guard let largest = plain.map({ $0.pixelWidth * $0.pixelHeight }).max() else { return [] }
        return plain.filter { $0.pixelWidth * $0.pixelHeight == largest }
    }

    // MARK: - Internal

    private func findLiveMode(matching wanted: DisplayModeInfo, for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        guard let cfModes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return nil
        }
        // IO mode IDs are per display, so an ID match alone can land on an
        // unrelated mode of another display: the geometry must match too.
        let sameGeometry = cfModes.filter {
            $0.width == wanted.width
                && $0.height == wanted.height
                && $0.pixelWidth == wanted.pixelWidth
                && $0.pixelHeight == wanted.pixelHeight
        }
        if let ioID = wanted.ioModeID, let exact = sameGeometry.first(where: { $0.ioDisplayModeID == ioID }) {
            return exact
        }
        return sameGeometry.first(where: { abs($0.refreshRate - wanted.refreshRate) < 1 }) ?? sameGeometry.first
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
