import XCTest
@testable import SimpleHiDPIScalerCore

// MARK: - Fakes

final class FakeModeManager: DisplayModeManaging, @unchecked Sendable {
    var available: [DisplayModeInfo]
    var current: DisplayModeInfo?
    var applied: [DisplayModeInfo] = []
    var refuseAll = false

    init(available: [DisplayModeInfo], current: DisplayModeInfo?) {
        self.available = available
        self.current = current
    }

    func allModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] { available }
    func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeInfo? { current }
    func setMode(_ mode: DisplayModeInfo, for displayID: CGDirectDisplayID) -> Int32 {
        guard !refuseAll, available.contains(mode) else { return -1 }
        applied.append(mode)
        current = mode
        return 0
    }
}

final class FakeDetector: DisplayDetecting, @unchecked Sendable {
    let displays: [DisplayInfo]
    init(displays: [DisplayInfo]) { self.displays = displays }
    func activeDisplays() -> [DisplayInfo] { displays }
    func displayName(for id: CGDirectDisplayID) -> String? { displays.first(where: { $0.id == id })?.name }
}

final class FakeStore: ConfigurationStoring, @unchecked Sendable {
    var launchDefaultMode: DisplayModeInfo?
    var lastDisplayID: CGDirectDisplayID?
    var lastSelectedLogicalWidth: Int?
    func clear() {
        launchDefaultMode = nil; lastDisplayID = nil; lastSelectedLogicalWidth = nil
    }
}

// MARK: - Tests

/// Rollback + reversibility: save-before-apply, verify-exists, restore.
final class RollbackTests: XCTestCase {
    private func native() -> DisplayModeInfo {
        DisplayModeInfo(width: 3440, height: 1440, pixelWidth: 3440, pixelHeight: 1440, refreshRate: 120)
    }

    private func larger() -> DisplayModeInfo {
        DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 5120, pixelHeight: 2160, refreshRate: 60)
    }

    func testRollbackFiresAfterTenTicks() {
        let rb = RollbackManager()
        var restored = false
        rb.arm(rollback: { restored = true }, timeoutSeconds: 10)
        XCTAssertTrue(rb.isArmed)
        for _ in 1..<10 {
            XCTAssertFalse(rb.tickForTests())
            XCTAssertFalse(restored)
        }
        XCTAssertTrue(rb.tickForTests(), "10th tick must fire rollback")
        XCTAssertTrue(restored)
        XCTAssertFalse(rb.isArmed, "rollback fires exactly once")
        XCTAssertFalse(rb.tickForTests(), "second fire must not happen")
    }

    func testConfirmCancelsRollback() {
        let rb = RollbackManager()
        var restored = false
        rb.arm(rollback: { restored = true }, timeoutSeconds: 10)
        rb.confirm()
        XCTAssertFalse(rb.isArmed)
        for _ in 1...12 { _ = rb.tickForTests() }
        XCTAssertFalse(restored, "confirmed mode must be kept")
    }

    func testDisplayManagerRestoresLaunchDefault() {
        let display = DisplayInfo(id: 42, name: "DELL U3425WE", vendorNumber: 0x10AC,
                                  nativePixelWidth: 3440, nativePixelHeight: 1440)
        let fakes = FakeModeManager(available: [native(), larger()], current: native())
        let store = FakeStore()
        let manager = DisplayManager(detector: FakeDetector(displays: [display]),
                                     modes: fakes,
                                     store: store,
                                     logger: AppLogger())
        // Apply a new mode, then restore.
        XCTAssertEqual(manager.applyMode(larger(), for: 42), 0)
        XCTAssertEqual(fakes.current, larger())
        XCTAssertEqual(manager.restoreLaunchDefault(for: 42), 0)
        XCTAssertEqual(fakes.current, native(), "restore must return to the launch-time mode")
    }

    func testRefusesUnknownMode() {
        let phantom = DisplayModeInfo(width: 9999, height: 9999, pixelWidth: 9999, pixelHeight: 9999, refreshRate: 60)
        let fakes = FakeModeManager(available: [native()], current: native())
        fakes.refuseAll = false
        let display = DisplayInfo(id: 42, name: "DELL U3425WE", nativePixelWidth: 3440, nativePixelHeight: 1440)
        let manager = DisplayManager(detector: FakeDetector(displays: [display]),
                                     modes: fakes,
                                     store: FakeStore(),
                                     logger: AppLogger())
        XCTAssertNotEqual(manager.applyMode(phantom, for: 42), 0)
        XCTAssertTrue(fakes.applied.isEmpty, "phantom mode must never reach the display")
        XCTAssertEqual(fakes.current, native())
    }

    func testConfigurationStoreRoundTrips() {
        let defaults = UserDefaults(suiteName: "test.simplehidpiscaler.\(UUID().uuidString)")!
        let store = ConfigurationStore(defaults: defaults)
        XCTAssertNil(store.launchDefaultMode)
        store.launchDefaultMode = native()
        XCTAssertEqual(store.launchDefaultMode?.width, 3440)
        store.lastDisplayID = 42
        store.lastSelectedLogicalWidth = 2560
        XCTAssertEqual(store.lastDisplayID, 42)
        XCTAssertEqual(store.lastSelectedLogicalWidth, 2560)
        store.clear()
        XCTAssertNil(store.launchDefaultMode)
        XCTAssertNil(store.lastDisplayID)
    }
}
