import XCTest
@testable import SimpleHiDPIScalerCore

/// Mode-selection policy: prefer exposed HiDPI, tolerate GPU rounding,
/// never invent modes.
final class ModeSelectionTests: XCTestCase {
    private func modes() -> [DisplayModeInfo] {
        [
            // Native panel mode (not HiDPI)
            DisplayModeInfo(width: 3440, height: 1440, pixelWidth: 3440, pixelHeight: 1440, refreshRate: 120, ioModeID: 1),
            // HiDPI "looks like 3008x1264" rendered at 2x
            DisplayModeInfo(width: 3008, height: 1264, pixelWidth: 6016, pixelHeight: 2528, refreshRate: 60, ioModeID: 2),
            // HiDPI "looks like 2560x1080"
            DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 5120, pixelHeight: 2160, refreshRate: 60, ioModeID: 3),
            // Plain low-res fallback, same logical size but not HiDPI
            DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 2560, pixelHeight: 1080, refreshRate: 60, ioModeID: 4),
        ]
    }

    private func display() -> DisplayInfo {
        DisplayInfo(id: 99, name: "DELL U3425WE", vendorNumber: 0x10AC,
                    nativePixelWidth: 3440, nativePixelHeight: 1440)
    }

    func testScalingOptionsMapToExposedModes() {
        let s = ScalingManager()
        let opts = s.scalingOptions(for: display(), availableModes: modes())
        XCTAssertEqual(opts.count, 3)
        XCTAssertEqual(opts[0].title, "Native")
        XCTAssertEqual(opts[0].matchedMode?.width, 3440)
        XCTAssertEqual(opts[1].matchedMode?.width, 3008)
        XCTAssertTrue(opts[1].matchedMode?.isHiDPI ?? false)
        XCTAssertEqual(opts[2].matchedMode?.width, 2560)
        XCTAssertTrue(opts[2].matchedMode?.isHiDPI ?? false, "HiDPI preferred over plain when both exist")
    }

    func testUnavailableRowWhenMacOSExposesNothingClose() {
        let s = ScalingManager()
        let onlyNative = [modes()[0]]
        let opts = s.scalingOptions(for: display(), availableModes: onlyNative)
        XCTAssertNotNil(opts[0].matchedMode)
        XCTAssertNil(opts[1].matchedMode, "must not invent 3008x1264 when GPU lists nothing close")
        XCTAssertNil(opts[2].matchedMode)
        XCTAssertFalse(opts[1].isAvailable)
    }

    func testToleratesGPURounding() {
        let s = ScalingManager()
        let rounded = [DisplayModeInfo(width: 3008, height: 1269, pixelWidth: 6016, pixelHeight: 2538, refreshRate: 60)]
        let best = s.bestMode(forLogicalWidth: 3008, availableModes: rounded, preferHiDPI: true)
        XCTAssertNotNil(best, "3%-ish rounding (1264 vs 1269) must still match")
    }

    func testPrefersHighestRefreshAmongDuplicates() {
        let s = ScalingManager()
        let dupes = [
            DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 5120, pixelHeight: 2160, refreshRate: 60),
            DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 5120, pixelHeight: 2160, refreshRate: 120),
        ]
        XCTAssertEqual(s.bestMode(forLogicalWidth: 2560, availableModes: dupes, preferHiDPI: true)?.refreshRate, 120)
    }

    func testHiDPIDerivedFromPixelsNotFlags() {
        XCTAssertTrue(DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 5120, pixelHeight: 2160, refreshRate: 60).isHiDPI)
        XCTAssertFalse(DisplayModeInfo(width: 3440, height: 1440, pixelWidth: 3440, pixelHeight: 1440, refreshRate: 120).isHiDPI)
    }

    func testPlainLowResNeverMatchesScalingRows() {
        // Regression: Dell U3425WE exposed plain 2560x1080@2560x1080 (no HiDPI).
        // Offering it as "Much Larger" drops the panel to 2560x1080 instead of
        // scaling at 3440x1440 — must show as unavailable.
        let s = ScalingManager()
        let plainOnly = [
            DisplayModeInfo(width: 3440, height: 1440, pixelWidth: 3440, pixelHeight: 1440, refreshRate: 60, ioModeID: 1),
            DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 2560, pixelHeight: 1080, refreshRate: 60, ioModeID: 4),
        ]
        let opts = s.scalingOptions(for: display(), availableModes: plainOnly)
        XCTAssertNotNil(opts[0].matchedMode, "Native may be plain 1x")
        XCTAssertNil(opts[1].matchedMode, "Larger must require HiDPI")
        XCTAssertNil(opts[2].matchedMode, "plain 2560x1080 is a resolution change, not scaling")
    }

    func testPrivateGatewayRefusesWithoutOptIn() {
        // Opt-in off (default): must refuse without touching WindowServer.
        let wasOptIn = PrivateHiDPIGateway.optInEnabled
        PrivateHiDPIGateway.setOptIn(false)
        defer { PrivateHiDPIGateway.setOptIn(wasOptIn) }
        if case .failure(let e) = PrivateHiDPIGateway.enableCustomHiDPI(logicalWidth: 2560, logicalHeight: 1080, displayID: 1) {
            XCTAssertEqual(e, .optInRequired)
            XCTAssertEqual(e, .refusedPrivateAPI, "legacy alias preserved")
        } else {
            XCTFail("private path must refuse when opt-in is off")
        }
    }

    func testPrivateGatingDecisions() {
        XCTAssertEqual(PrivateHiDPIGateway.gatingDecisionForTests(optIn: false, available: true), .optInRequired)
        XCTAssertEqual(PrivateHiDPIGateway.gatingDecisionForTests(optIn: false, available: false), .optInRequired)
        XCTAssertEqual(PrivateHiDPIGateway.gatingDecisionForTests(optIn: true, available: false), .unavailable)
        XCTAssertNil(PrivateHiDPIGateway.gatingDecisionForTests(optIn: true, available: true))
    }
}
