import AppKit
import CoreGraphics
import Foundation

/// Live display discovery using ONLY public APIs:
/// CGGetActiveDisplayList, CGDisplayVendorNumber/ModelNumber/SerialNumber,
/// CGDisplayPixelsWide/High, CGMainDisplayID, NSScreen for human names.
public final class DisplayDetector: DisplayDetecting, Sendable {
    public init() {}

    public func activeDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var fetched: UInt32 = 0
        guard CGGetActiveDisplayList(count, &ids, &fetched) == .success else {
            return []
        }
        let mainID = CGMainDisplayID()
        return ids.prefix(Int(fetched)).map { id in
            DisplayInfo(
                id: id,
                name: displayName(for: id) ?? "Display \(id)",
                vendorNumber: vendorNumber(for: id),
                modelNumber: modelNumber(for: id),
                serialNumber: serialNumber(for: id),
                nativePixelWidth: Int(CGDisplayPixelsWide(id)),
                nativePixelHeight: Int(CGDisplayPixelsHigh(id)),
                isMain: id == mainID
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
