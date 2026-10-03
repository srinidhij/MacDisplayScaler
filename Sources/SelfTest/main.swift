import CoreGraphics
import Foundation
import SimpleHiDPIScalerCore

/// CLT-compatible test runner (no XCTest.framework required).
/// Mirrors Tests/SimpleHiDPIScalerTests/*.swift assertion-for-assertion.
/// Exit 0 = all pass, exit 1 = failure. Run: `swift run SelfTest`
var failures = 0
func check(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS \(label)")
    } else {
        print("FAIL \(label)")
        failures += 1
    }
}

// MARK: - Fakes (same as RollbackTests)

final class FakeModeManager: DisplayModeManaging, @unchecked Sendable {
    var available: [DisplayModeInfo]
    var current: DisplayModeInfo?
    var applied: [DisplayModeInfo] = []
    init(available: [DisplayModeInfo], current: DisplayModeInfo?) {
        self.available = available; self.current = current
    }
    func allModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] { available }
    func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeInfo? { current }
    func setMode(_ mode: DisplayModeInfo, for displayID: CGDirectDisplayID) -> Int32 {
        guard available.contains(mode) else { return -1 }
        applied.append(mode); current = mode; return 0
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
    func clear() { launchDefaultMode = nil; lastDisplayID = nil; lastSelectedLogicalWidth = nil }
}

// MARK: - Mode selection

let native = DisplayModeInfo(width: 3440, height: 1440, pixelWidth: 3440, pixelHeight: 1440, refreshRate: 120, ioModeID: 1)
let hidpi3008 = DisplayModeInfo(width: 3008, height: 1264, pixelWidth: 6016, pixelHeight: 2528, refreshRate: 60, ioModeID: 2)
let hidpi2560 = DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 5120, pixelHeight: 2160, refreshRate: 60, ioModeID: 3)
let plain2560 = DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 2560, pixelHeight: 1080, refreshRate: 60, ioModeID: 4)
let allModes = [native, hidpi3008, hidpi2560, plain2560]
let dell = DisplayInfo(id: 99, name: "DELL U3425WE", vendorNumber: 0x10AC, nativePixelWidth: 3440, nativePixelHeight: 1440)

let scaler = ScalingManager()
let opts = scaler.scalingOptions(for: dell, availableModes: allModes)
check(opts.count == 3, "modeSelection: three rows")
check(opts[0].matchedMode?.width == 3440, "modeSelection: native maps")
check(opts[1].matchedMode?.width == 3008 && (opts[1].matchedMode?.isHiDPI ?? false), "modeSelection: larger maps to HiDPI")
check(opts[2].matchedMode?.width == 2560 && (opts[2].matchedMode?.isHiDPI ?? false), "modeSelection: prefers HiDPI over plain")

let onlyNative = scaler.scalingOptions(for: dell, availableModes: [native])
check(onlyNative[0].matchedMode != nil && onlyNative[1].matchedMode == nil && onlyNative[2].matchedMode == nil,
      "modeSelection: unavailable rows are nil (never invented)")

let rounded = [DisplayModeInfo(width: 3008, height: 1269, pixelWidth: 6016, pixelHeight: 2538, refreshRate: 60)]
check(scaler.bestMode(forLogicalWidth: 3008, availableModes: rounded, preferHiDPI: true) != nil,
      "modeSelection: tolerates GPU rounding")

let dupes = [
    DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 5120, pixelHeight: 2160, refreshRate: 60),
    DisplayModeInfo(width: 2560, height: 1080, pixelWidth: 5120, pixelHeight: 2160, refreshRate: 120),
]
check(scaler.bestMode(forLogicalWidth: 2560, availableModes: dupes, preferHiDPI: true)?.refreshRate == 120,
      "modeSelection: prefers highest refresh")
check(hidpi2560.isHiDPI && !native.isHiDPI, "modeSelection: isHiDPI derived from pixels")

let plainOnlyOpts = scaler.scalingOptions(for: dell, availableModes: [native, plain2560])
check(!plainOnlyOpts[1].isAvailable && !plainOnlyOpts[2].isAvailable,
      "modeSelection: plain low-res never matches scaling rows (regression)")
let wasOptIn = PrivateHiDPIGateway.optInEnabled
PrivateHiDPIGateway.setOptIn(false)
if case .failure(let e) = PrivateHiDPIGateway.enableCustomHiDPI(logicalWidth: 2560, logicalHeight: 1080, displayID: 1) {
    check(e == .optInRequired, "privateGateway: refuses without opt-in")
} else {
    check(false, "privateGateway: refuses without opt-in")
}
PrivateHiDPIGateway.setOptIn(wasOptIn)
check(PrivateHiDPIGateway.gatingDecisionForTests(optIn: false, available: true) == .optInRequired, "privateGateway: gating opt-in off")
check(PrivateHiDPIGateway.gatingDecisionForTests(optIn: true, available: false) == .unavailable, "privateGateway: gating unavailable")
check(PrivateHiDPIGateway.gatingDecisionForTests(optIn: true, available: true) == nil, "privateGateway: gating would-proceed")

// MARK: - Identification

check(DisplayInfo(id: 7, name: "DELL U3425WE", vendorNumber: 0x10AC, nativePixelWidth: 3440, nativePixelHeight: 1440).looksLikeDellU3425WE,
      "ident: vendor+res match")
check(DisplayInfo(id: 7, name: "Dell U3425WE (DisplayPort)", nativePixelWidth: 3440, nativePixelHeight: 1440).looksLikeDellU3425WE,
      "ident: name+res match when hub masks vendor")
check(!DisplayInfo(id: 7, name: "DELL U3425WE", vendorNumber: 0x10AC, nativePixelWidth: 2560, nativePixelHeight: 1440).looksLikeDellU3425WE,
      "ident: rejects wrong resolution")
let lg = DisplayInfo(id: 8, name: "LG UltraWide", vendorNumber: 0x1E6D, nativePixelWidth: 3440, nativePixelHeight: 1440)
check(!lg.looksLikeDellU3425WE && lg.isLikelyExternalUltrawide, "ident: LG not misidentified as Dell")
let multi = [
    DisplayInfo(id: 1, name: "Built-in", nativePixelWidth: 3024, nativePixelHeight: 1964, isMain: true),
    DisplayInfo(id: 2, name: "DELL U3425WE", vendorNumber: 0x10AC, nativePixelWidth: 3440, nativePixelHeight: 1440),
    DisplayInfo(id: 3, name: "LG UltraWide", vendorNumber: 0x1E6D, nativePixelWidth: 3440, nativePixelHeight: 1440),
]
check(multi.filter { $0.looksLikeDellU3425WE }.map(\.id) == [2], "ident: multi-display picks only Dell")
check(!DisplayInfo(id: 1, name: "Built-in", nativePixelWidth: 3440, nativePixelHeight: 1440, isMain: true).isLikelyExternalUltrawide,
      "ident: main never counts as external")

// MARK: - Rollback

let rb = RollbackManager()
var restored = false
rb.arm(rollback: { restored = true }, timeoutSeconds: 10)
var earlyFire = false
for _ in 1..<10 { if rb.tickForTests() { earlyFire = true } }
check(!earlyFire && !restored, "rollback: silent for first 9 ticks")
check(rb.tickForTests() && restored, "rollback: fires on 10th tick")
check(!rb.tickForTests(), "rollback: fires exactly once")

let rb2 = RollbackManager()
var restored2 = false
rb2.arm(rollback: { restored2 = true }, timeoutSeconds: 10)
rb2.confirm()
for _ in 1...12 { _ = rb2.tickForTests() }
check(!restored2, "rollback: confirm cancels")

let display = DisplayInfo(id: 42, name: "DELL U3425WE", vendorNumber: 0x10AC, nativePixelWidth: 3440, nativePixelHeight: 1440)
let fakes = FakeModeManager(available: [native, hidpi2560], current: native)
let manager = DisplayManager(detector: FakeDetector(displays: [display]), modes: fakes, store: FakeStore(), logger: AppLogger())
check(manager.applyMode(hidpi2560, for: 42) == 0 && fakes.current == hidpi2560, "manager: apply")
check(manager.restoreLaunchDefault(for: 42) == 0 && fakes.current == native, "manager: restore launch default")

let phantom = DisplayModeInfo(width: 9999, height: 9999, pixelWidth: 9999, pixelHeight: 9999, refreshRate: 60)
let fakes2 = FakeModeManager(available: [native], current: native)
let manager2 = DisplayManager(detector: FakeDetector(displays: [display]), modes: fakes2, store: FakeStore(), logger: AppLogger())
check(manager2.applyMode(phantom, for: 42) != 0 && fakes2.applied.isEmpty && fakes2.current == native,
      "manager: phantom mode never reaches hardware")

let defaults = UserDefaults(suiteName: "test.simplehidpiscaler.\(UUID().uuidString)")!
let store = ConfigurationStore(defaults: defaults)
check(store.launchDefaultMode == nil, "store: empty initially")
store.launchDefaultMode = native
store.lastDisplayID = 42
store.lastSelectedLogicalWidth = 2560
check(store.launchDefaultMode?.width == 3440 && store.lastDisplayID == 42 && store.lastSelectedLogicalWidth == 2560,
      "store: round-trips")
store.clear()
check(store.launchDefaultMode == nil && store.lastDisplayID == nil, "store: clears")

print(failures == 0 ? "ALL SELFTESTS PASSED" : "\(failures) SELFTEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
