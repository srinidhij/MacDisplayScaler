import XCTest
@testable import SimpleHiDPIScalerCore

/// Saved-default targeting and what happens to an active virtual after
/// display changes (unplug, System Settings changes, slow refresh).
final class DisplayChangeTests: XCTestCase {
    private let builtin = DisplayInfo(id: 1, name: "Built-in Retina Display", vendorNumber: 0x610, modelNumber: 0xA050,
                                      serialNumber: 1, nativePixelWidth: 2940, nativePixelHeight: 1912,
                                      isMain: true, isBuiltin: true)
    // While mirrored the Dell has no screen name; it is found by vendor + native size.
    private let dell = DisplayInfo(id: 3, name: "Display 3", vendorNumber: 0x10AC, modelNumber: 0xA243,
                                   serialNumber: 808736844, nativePixelWidth: 3440, nativePixelHeight: 1440)
    private let ownVirtual = DisplayInfo(id: 4, name: "SimpleHiDPI 3", vendorNumber: 0x5348, modelNumber: 0x4849,
                                         nativePixelWidth: 5120, nativePixelHeight: 2160)

    func testMirroredDellWithGenericNameStillMatches() {
        XCTAssertTrue(dell.isDellUWQHD)
    }

    func testSavedDefaultTargetsOnlyItsDisplay() {
        // The test runner's own defaults domain; clearing the size removes every key.
        let store = PrivateDefaultStore()
        store.size = nil
        defer { store.size = nil }
        XCTAssertNil(store.target(in: [builtin, dell]), "nothing saved targets nothing")
        store.size = (2560, 1080)
        XCTAssertEqual(store.target(in: [builtin, dell])?.id, 3, "a default saved without a display belongs to the Dell")
        XCTAssertNil(store.target(in: [builtin, ownVirtual]), "never the built-in or a virtual")
        store.displayKey = dell.identityKey
        let dellNewID = DisplayInfo(id: 9, name: "DELL U3425WE", vendorNumber: 0x10AC, modelNumber: 0xA243,
                                    serialNumber: 808736844, nativePixelWidth: 3440, nativePixelHeight: 1440)
        XCTAssertEqual(store.target(in: [builtin, dellNewID])?.id, 9, "follows the panel across display IDs")
        let otherDell = DisplayInfo(id: 5, name: "DELL U3425WE", vendorNumber: 0x10AC, modelNumber: 0xA243,
                                    serialNumber: 1234, nativePixelWidth: 3440, nativePixelHeight: 1440)
        XCTAssertNil(store.target(in: [builtin, otherDell]), "another panel of the same model is not the target")
        store.size = nil
        XCTAssertNil(store.displayKey, "clearing the size clears its display")
    }

    func testReconcileActions() {
        XCTAssertEqual(PrivateHiDPIGateway.reconcileAction(online: false, mirrorsVirtual: false, belowNativeRefresh: false),
                       .teardownPanelGone)
        XCTAssertEqual(PrivateHiDPIGateway.reconcileAction(online: true, mirrorsVirtual: false, belowNativeRefresh: false),
                       .teardownUnmirrored)
        XCTAssertEqual(PrivateHiDPIGateway.reconcileAction(online: true, mirrorsVirtual: true, belowNativeRefresh: true),
                       .recreateForRefresh)
        XCTAssertNil(PrivateHiDPIGateway.reconcileAction(online: true, mirrorsVirtual: true, belowNativeRefresh: false))
    }
}
