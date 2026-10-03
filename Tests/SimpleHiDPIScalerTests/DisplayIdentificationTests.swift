import XCTest
@testable import SimpleHiDPIScalerCore

/// Display identification: Dell U3425WE heuristic + multi-display behaviour.
final class DisplayIdentificationTests: XCTestCase {
    func testDetectsDellU3425WEByVendorAndResolution() {
        let d = DisplayInfo(id: 7, name: "DELL U3425WE", vendorNumber: 0x10AC,
                            nativePixelWidth: 3440, nativePixelHeight: 1440)
        XCTAssertTrue(d.looksLikeDellU3425WE)
    }

    func testDetectsByNameEvenWithOddVendor() {
        // Some docks/hubs mask the vendor ID; name + resolution still matches.
        let d = DisplayInfo(id: 7, name: "Dell U3425WE (DisplayPort)", vendorNumber: nil,
                            nativePixelWidth: 3440, nativePixelHeight: 1440)
        XCTAssertTrue(d.looksLikeDellU3425WE)
    }

    func testRejectsWrongResolution() {
        let d = DisplayInfo(id: 7, name: "DELL U3425WE", vendorNumber: 0x10AC,
                            nativePixelWidth: 2560, nativePixelHeight: 1440)
        XCTAssertFalse(d.looksLikeDellU3425WE)
    }

    func testRejectsNonDellUltrawide() {
        let d = DisplayInfo(id: 8, name: "LG UltraWide", vendorNumber: 0x1E6D,
                            nativePixelWidth: 3440, nativePixelHeight: 1440)
        XCTAssertFalse(d.looksLikeDellU3425WE, "LG panel must not be misidentified as the Dell")
        XCTAssertTrue(d.isLikelyExternalUltrawide)
    }

    func testDoesNotAssumeSingleExternalDisplay() {
        // Two externals: Dell + LG. Heuristic must pick only the Dell.
        let displays = [
            DisplayInfo(id: 1, name: "Built-in", nativePixelWidth: 3024, nativePixelHeight: 1964, isMain: true),
            DisplayInfo(id: 2, name: "DELL U3425WE", vendorNumber: 0x10AC, nativePixelWidth: 3440, nativePixelHeight: 1440),
            DisplayInfo(id: 3, name: "LG UltraWide", vendorNumber: 0x1E6D, nativePixelWidth: 3440, nativePixelHeight: 1440),
        ]
        let matches = displays.filter { $0.looksLikeDellU3425WE }
        XCTAssertEqual(matches.map(\.id), [2])
    }

    func testMainDisplayIsNotExternalUltrawide() {
        let main = DisplayInfo(id: 1, name: "Built-in", nativePixelWidth: 3440, nativePixelHeight: 1440, isMain: true)
        XCTAssertFalse(main.isLikelyExternalUltrawide)
    }
}
