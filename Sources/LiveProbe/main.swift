import CoreGraphics
import Foundation
import IOKit
import SimpleHiDPIScalerCore

// Live experiment driver. Usage:
//   LiveProbe dump
//   LiveProbe restore <displayID> [max]      re-apply native 3440x1440 1x (lowest refresh, or highest with `max`)
//   LiveProbe test <displayID> <w> <h>       enable virtual, switch to w x h 2x, hold, tear down

func allModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    return (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
}

func describe(_ m: CGDisplayMode) -> String {
    "\(m.width)x\(m.height)@\(m.pixelWidth)x\(m.pixelHeight) \(Int(m.refreshRate))Hz io=\(m.ioDisplayModeID)"
}

func activeIDs() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetOnlineDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

/// The timing actually sent over the cable, read from the display engine's
/// IORegistry entry (matched by EDID vendor/product/serial). CG modes only
/// describe a mirror slave as "looks like@backing"; this shows whether the
/// panel gets its native size and which refresh rate. nil for displays with
/// no cable (virtuals, built-in panels).
func linkTiming(_ id: CGDirectDisplayID) -> String? {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iter) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iter) }
    while case let service = IOIteratorNext(iter), service != 0 {
        defer { IOObjectRelease(service) }
        func prop(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        func int(_ dict: [String: Any]?, _ key: String) -> Int? { (dict?[key] as? NSNumber)?.intValue }
        let product = (prop("DisplayAttributes") as? [String: Any])?["ProductAttributes"] as? [String: Any]
        guard int(product, "LegacyManufacturerID") == Int(CGDisplayVendorNumber(id)),
              int(product, "ProductID") == Int(CGDisplayModelNumber(id)),
              int(product, "SerialNumber") == Int(CGDisplaySerialNumber(id)),
              let modeID = (prop("DPTimingModeId") as? NSNumber)?.intValue,
              let timing = (prop("TimingElements") as? [[String: Any]])?.first(where: { int($0, "ID") == modeID }),
              let h = timing["HorizontalAttributes"] as? [String: Any],
              let v = timing["VerticalAttributes"] as? [String: Any],
              let width = int(h, "Active"), let height = int(v, "Active")
        else { continue }
        let hz = Double(int(v, "PreciseSyncRate") ?? int(v, "SyncRate") ?? 0) / 65536
        return "\(width)x\(height) \(String(format: "%.2f", hz))Hz"
    }
    return nil
}

func dump(modes: Bool) {
    for id in activeIDs() {
        let cur = CGDisplayCopyDisplayMode(id).map(describe) ?? "?"
        let link = linkTiming(id).map { " link=\($0)" } ?? ""
        print("id=\(id) vendor=0x\(String.init(CGDisplayVendorNumber(id), radix: 16)) model=0x\(String.init(CGDisplayModelNumber(id), radix: 16)) active=\(CGDisplayIsActive(id) != 0) mirror=\(CGDisplayIsInMirrorSet(id) != 0) main=\(CGDisplayIsMain(id) != 0) builtin=\(CGDisplayIsBuiltin(id) != 0) current=\(cur)\(link)")
        if modes {
            let all = allModes(id)
            print("  \(all.count) modes, \(all.filter { $0.pixelWidth > $0.width }.count) HiDPI")
            for m in all where m.pixelWidth > m.width || m.width >= 2400 { print("   ", describe(m)) }
        }
    }
}

/// Mode change inside a display-configuration transaction (valid on mirror sets).
func configureMode(_ id: CGDirectDisplayID, _ m: CGDisplayMode) -> CGError {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return .failure }
    let e = CGConfigureDisplayWithDisplayMode(cfg, id, m, nil)
    guard e == .success else { CGCancelDisplayConfiguration(cfg); return e }
    return CGCompleteDisplayConfiguration(cfg, .forSession)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "dump":
    dump(modes: true)
case "restore":
    let id = CGDirectDisplayID(args[2])!
    let target = allModes(id).filter { $0.width == 3440 && $0.height == 1440 && $0.pixelWidth == 3440 }
        .sorted { args.count > 3 ? $0.refreshRate > $1.refreshRate : $0.refreshRate < $1.refreshRate }.first
    guard let t = target else { print("no native mode"); exit(1) }
    print("restoring", describe(t), "->", configureMode(id, t).rawValue)
case "test":
    let phys = CGDirectDisplayID(args[2])!
    let w = Int(args[3])!, h = Int(args[4])!
    PrivateHiDPIGateway.setOptIn(true) // probe-only domain; app setting untouched
    print("== before"); dump(modes: false)
    switch PrivateHiDPIGateway.enable(physicalDisplayID: phys, logicalModes: [(w, h, 120), (w, h, 60)]) {
    case .failure(let e): print("enable failed:", e); exit(2)
    case .success(let r):
        let v = CGDirectDisplayID(r.virtualDisplayID)
        // Safety net: always tear down and restore, even if later steps hang.
        DispatchQueue.global().asyncAfter(deadline: .now() + 40) {
            print("!! watchdog teardown"); PrivateHiDPIGateway.disable(physicalDisplayID: phys); exit(3)
        }
        Thread.sleep(forTimeInterval: 2)
        print("== mirrored, virtual=\(v)"); dump(modes: false)
        let vm = (CGDisplayCopyAllDisplayModes(v, nil) as? [CGDisplayMode]) ?? []
        print("virtual modes: \(vm.count), HiDPI: \(vm.filter { $0.pixelWidth > $0.width }.count)")
        for m in vm { print("  vmode", describe(m)) }
        if let t = vm.first(where: { $0.width == w && $0.height == h && $0.pixelWidth > $0.width }) {
            print("configureMode ->", configureMode(v, t).rawValue)
        } else { print("no 2x candidate enumerated for \(w)x\(h)") }
        Thread.sleep(forTimeInterval: 2)
        print("== after switch"); dump(modes: false)
        print("holding 15s — look at the screen"); Thread.sleep(forTimeInterval: 15)
        PrivateHiDPIGateway.disable(physicalDisplayID: phys)
        Thread.sleep(forTimeInterval: 2)
        print("== after teardown"); dump(modes: false)
        exit(0)
    }
default:
    print("usage: dump | restore <id> [max] | test <id> <w> <h>")
}
