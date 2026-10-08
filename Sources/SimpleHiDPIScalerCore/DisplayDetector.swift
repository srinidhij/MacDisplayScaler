import AppKit
import CoreGraphics
import Foundation

/// Live display discovery using ONLY public APIs:
/// CGGetOnlineDisplayList (not Active: a mirror slave, i.e. the physical panel
/// while the private virtual is up, is online but inactive), CGDisplayVendorNumber/ModelNumber/SerialNumber,
/// the native-flagged display mode for the panel's resolution, CGMainDisplayID,
/// CGDisplayIsBuiltin, NSScreen for human names.
public final class DisplayDetector: DisplayDetecting, Sendable {
    public init() {}

    public func activeDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var fetched: UInt32 = 0
        guard CGGetOnlineDisplayList(count, &ids, &fetched) == .success else {
            return []
        }
        let mainID = CGMainDisplayID()
        return ids.prefix(Int(fetched)).map { id in
            // CGDisplayPixelsWide is the current "looks like" width: 2560 for
            // the Dell while it mirrors a 2560x1080 virtual.
            let native = DisplayModeManager.nativeModes(for: id).first
            return DisplayInfo(
                id: id,
                name: displayName(for: id) ?? "Display \(id)",
                vendorNumber: vendorNumber(for: id),
                modelNumber: modelNumber(for: id),
                serialNumber: serialNumber(for: id),
                nativePixelWidth: native?.pixelWidth ?? Int(CGDisplayPixelsWide(id)),
                nativePixelHeight: native?.pixelHeight ?? Int(CGDisplayPixelsHigh(id)),
                isMain: id == mainID,
                isBuiltin: CGDisplayIsBuiltin(id) != 0
            )
        }
    }

    public func displayName(for id: CGDirectDisplayID) -> String? {
        // NSScreen is the only public human-readable name source. Match by
        // device description number; fall back to nil (caller substitutes).
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            if CGDirectDisplayID(number.uint32Value) == id {
                return screen.localizedName
            }
        }
        return nil
    }

    // MARK: - Private helpers (still public APIs)

    private func vendorNumber(for id: CGDirectDisplayID) -> UInt32? {
        let v = CGDisplayVendorNumber(id)
        return v == 0 ? nil : v
    }

    private func modelNumber(for id: CGDirectDisplayID) -> UInt32? {
        let m = CGDisplayModelNumber(id)
        return m == 0 ? nil : m
    }

    private func serialNumber(for id: CGDirectDisplayID) -> UInt32? {
        let s = CGDisplaySerialNumber(id)
        return s == 0 ? nil : s
    }
}
