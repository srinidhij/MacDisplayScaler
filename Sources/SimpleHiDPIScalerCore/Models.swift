import CoreGraphics
import Foundation

/// Physical/logical description of one connected display.
/// Value type so it is unit-testable without touching CoreGraphics.
public struct DisplayInfo: Identifiable, Equatable, Hashable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let vendorNumber: UInt32?
    public let modelNumber: UInt32?
    public let serialNumber: UInt32?
    public let nativePixelWidth: Int
    public let nativePixelHeight: Int
    public let isMain: Bool

    public var sadlyID: String { String(id) }

    public init(
        id: CGDirectDisplayID,
        name: String,
        vendorNumber: UInt32? = nil,
        modelNumber: UInt32? = nil,
        serialNumber: UInt32? = nil,
        nativePixelWidth: Int,
        nativePixelHeight: Int,
        isMain: Bool = false
    ) {
        self.id = id
        self.name = name
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.nativePixelWidth = nativePixelWidth
        self.nativePixelHeight = nativePixelHeight
        self.isMain = isMain
    }

    // MARK: - Identification

    /// Heuristic match for the primary target: Dell U3425WE (3440x1440 ultrawide).
    /// Dell vendor number is 0x10AC. Model/serial vary by firmware/connection,
    /// so we match on vendor + native pixels + name hint, never on ID alone.
    /// Our own private virtual display (vendor "SH", model "HI" — see
    /// PrivateHiDPIGateway). Survives process death, unlike name/map checks.
    public var isOwnVirtual: Bool {
        vendorNumber == 0x5348 && modelNumber == 0x4849
    }

    public var looksLikeDellU3425WE: Bool {
        let isDellVendor = vendorNumber == 0x10AC
        let isUWQHD = nativePixelWidth == 3440 && nativePixelHeight == 1440
        let nameHint = name.localizedCaseInsensitiveContains("U3425WE")
            || name.localizedCaseInsensitiveContains("DELL")
        // Require vendor + resolution; name alone is not trustworthy.
        if name.localizedCaseInsensitiveContains("U3425WE") && isUWQHD {
            return true
        }
        return isDellVendor && isUWQHD && nameHint
    }

    /// Generic "is this plausibly the user's external ultrawide" without
    /// assuming it is the only external display.
    public var isLikelyExternalUltrawide: Bool {
        !isMain && nativePixelWidth >= 3440 && nativePixelHeight == 1440
    }

    /// Dell 34" UWQHD by vendor + resolution alone. Used as a fallback when
    /// mirroring makes NSScreen names generic ("Display 3"): the strict
    /// `looksLikeDellU3425WE` needs a name hint that may be absent, but a
    /// 0x10AC 3440×1440 panel is still almost certainly the user's Dell.
    /// Shown as "possible", never as a positive model identification.
    public var isDellUWQHD: Bool {
        vendorNumber == 0x10AC && nativePixelWidth == 3440 && nativePixelHeight == 1440
    }
}

/// One display mode as reported by macOS. `isHiDPI` is derived from
/// pixel dimensions vs logical dimensions (public API observable behaviour),
/// not from any private flag.
public struct DisplayModeInfo: Equatable, Hashable, Sendable {
    /// Logical ("Looks like") size.
    public let width: Int
    public let height: Int
    /// Backing-store pixel size. For a 2x HiDPI mode this is 2x logical.
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    /// IOKit mode ID, used to re-find the same CGDisplayMode later.
    public let ioModeID: Int32?
    public let usableForDesktopGUI: Bool

    public init(
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        ioModeID: Int32? = nil,
        usableForDesktopGUI: Bool = true
    ) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.ioModeID = ioModeID
        self.usableForDesktopGUI = usableForDesktopGUI
    }

    /// True when the backing store is larger than the logical size,
    /// i.e. macOS renders HiDPI and downsamples/scales to the panel.
    public var isHiDPI: Bool {
        pixelWidth > width || pixelHeight > height
    }

    /// Scale factor, e.g. 2.0 for a classic Retina mode.
    public var scaleFactor: Double {
        guard width > 0 else { return 1.0 }
        return Double(pixelWidth) / Double(width)
    }

    public var logicalLabel: String { "\(width) × \(height)" }
    public var pixelLabel: String { "\(pixelWidth) × \(pixelHeight)" }
}
