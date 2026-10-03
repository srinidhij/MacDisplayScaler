import AppKit
import SimpleHiDPIScalerCore
import SwiftUI

/// Minimal menu-bar app. No dock icon (LSUIElement), no windows on launch,
/// no network, no login items of its own. One MenuBarExtra scene.
@main
struct SimpleHiDPIScalerApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra("SimpleHiDPIScaler", systemImage: "display") {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - View model

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var availableModes: [DisplayModeInfo] = []
    @Published var currentMode: DisplayModeInfo?
    @Published var options: [ScalingOption] = []
    @Published var selectedLogicalWidth: Int?
    @Published var statusMessage: String = ""
    @Published var countdown: Int = 0
    @Published var showsHiDPIOnlyNote = false
    // MARK: - Private prototype (opt-in, off by default)
    @Published var privateOptIn = PrivateHiDPIGateway.optInEnabled
    @Published var privateAvailable = PrivateHiDPIGateway.isAvailable
    @Published var privateActiveVirtualID: UInt32?
    @Published var privateModeActive = false
    @Published var privateBusy = false

    private let manager: DisplayManaging
    private let scaling: ScalingManaging
    private var store: ConfigurationStoring
    private let rollback: RollbackManaging
    private var timer: Timer?
    private var pendingPrevious: DisplayModeInfo?
    private var didAutoEnableThisLaunch = false

    init(
        manager: DisplayManaging = DisplayManager(),
        scaling: ScalingManaging = ScalingManager(),
        store: ConfigurationStoring = ConfigurationStore(),
        rollback: RollbackManaging = RollbackManager()
    ) {
        self.manager = manager
        self.scaling = scaling
        self.store = store
        self.rollback = rollback
        refresh()
    }

    var selectedDisplay: DisplayInfo? {
        displays.first(where: { $0.id == selectedDisplayID })
    }

    /// Physical displays only. Private virtuals are status, never targets:
    /// applying a public 1x mode to a virtual destroys its HiDPI-ness.
    var physicalDisplays: [DisplayInfo] {
        displays.filter { !$0.isOwnVirtual }
    }

    func refresh() {
        manager.refreshDisplays()
        displays = manager.displays
        // Never auto-select a private virtual display as the physical target
        // (in-process map plus name prefix, since stale virtuals from dead
        // processes are not in this process's map).
        let physical = physicalDisplays
        if selectedDisplayID == nil
            || physicalDisplays.first(where: { $0.id == selectedDisplayID }) == nil
        {
            // Prefer exact Dell U3425WE, then any Dell UWQHD (generic names
            // under mirroring), then first external, then main.
            selectedDisplayID = physical.first(where: { $0.looksLikeDellU3425WE })?.id
                ?? physical.first(where: { $0.isDellUWQHD })?.id
                ?? physical.first(where: { !$0.isMain })?.id
                ?? physical.first?.id
                ?? displays.first?.id
        }
        reloadModes()
        maybeAutoEnablePrivate()
    }

    func selectDisplay(_ id: CGDirectDisplayID) {
        if let d = displays.first(where: { $0.id == id }),
           d.isOwnVirtual || PrivateHiDPIGateway.activeMap.values.contains(id)
        {
            statusMessage = "Virtual displays can't be targeted. Select the physical Dell."
            return
        }
        selectedDisplayID = id
        reloadModes()
    }

    func reloadModes() {
        refreshPrivateStatus()
        guard let id = selectedDisplayID else {
            availableModes = []; currentMode = nil; options = []
            return
        }
        // Private virtual active for this physical display: list the synthesized
        // HiDPI modes instead of the panel's exposed list. Physical timing stays
        // at 3440x1440; these rows render at 2x on the virtual and downsample.
        if let virtualID = privateActiveVirtualID {
            privateModeActive = true
            showsHiDPIOnlyNote = false
            availableModes = manager.modes(for: virtualID)
            currentMode = manager.currentMode(for: virtualID)
            options = Self.privateSizes.map { size in
                ScalingOption(title: size.title, logicalWidth: size.width, logicalHeight: size.height,
                              matchedMode: DisplayModeInfo(width: size.width, height: size.height,
                                                           pixelWidth: size.width * 2, pixelHeight: size.height * 2,
                                                           refreshRate: 60))
            }
            if selectedLogicalWidth == nil { selectedLogicalWidth = 3440 }
            return
        }
        privateModeActive = false
        availableModes = manager.modes(for: id)
        currentMode = manager.currentMode(for: id)
        if let display = selectedDisplay {
            options = scaling.scalingOptions(for: display, availableModes: availableModes)
            // Pre-select the row matching the current mode.
            if let cur = currentMode {
                selectedLogicalWidth = options.first(where: {
                    $0.matchedMode?.width == cur.width && $0.matchedMode?.height == cur.height
                })?.logicalWidth ?? options.first(where: { $0.isAvailable })?.logicalWidth
            }
            showsHiDPIOnlyNote = !availableModes.contains(where: { $0.isHiDPI })
        }
    }

    /// Row click. On the private path a size is applied immediately (the old
    /// select-then-Apply flow was hidden behind the Keep countdown); on the
    /// public path it only selects, and Apply commits.
    func choose(_ option: ScalingOption) {
        AppLogger.shared.info("row click \(option.logicalWidth)x\(option.logicalHeight) private=\(privateModeActive) busy=\(privateBusy)")
        selectedLogicalWidth = option.logicalWidth
        if privateModeActive, !privateBusy {
            applySelected()
        }
    }

    func applySelected() {
        // Private path: switch the VIRTUAL display's mode; the mirrored
        // physical panel keeps its 3440x1440 timing while the UI scales.
        if privateModeActive, privateActiveVirtualID != nil,
           let physicalID = selectedDisplayID,
           let width = selectedLogicalWidth,
           let size = Self.privateSizes.first(where: { $0.width == width })
        {
            switchPrivateSize(physicalID: physicalID, size: size)
            return
        }
        guard let id = selectedDisplayID,
              let width = selectedLogicalWidth,
              let option = options.first(where: { $0.logicalWidth == width }),
              let target = option.matchedMode
        else {
            statusMessage = "Pick an available scaling row first."
            return
        }
        // Defense in depth: the public path must never target a virtual display.
        if selectedDisplay?.isOwnVirtual == true
            || PrivateHiDPIGateway.activeMap.values.contains(id)
        {
            statusMessage = "That is a virtual display, not a panel. Select the physical Dell."
            return
        }
        pendingPrevious = manager.currentMode(for: id)
        let code = manager.applyMode(target, for: id)
        if code != 0 {
            statusMessage = "macOS refused the mode (error \(code)). Nothing changed."
            return
        }
        var mutableStore = store
        mutableStore.lastDisplayID = id
        mutableStore.lastSelectedLogicalWidth = width
        store = mutableStore
        currentMode = manager.currentMode(for: id)
        startCountdown(displayID: id)
    }

    func restoreDefaults() {
        guard let id = selectedDisplayID else { return }
        // Kill-switch first: unmirror + destroy any private virtual for this display.
        if PrivateHiDPIGateway.virtualDisplay(forPhysical: id) != nil {
            PrivateHiDPIGateway.disable(physicalDisplayID: id)
            AppLogger.shared.info("display=\(id) private prototype disabled (kill-switch via Restore Defaults)")
        }
        pendingPrevious = manager.currentMode(for: id)
        let code = manager.restoreLaunchDefault(for: id)
        statusMessage = code == 0 ? "Restored macOS launch-time mode." : "Restore failed (error \(code))."
        rollback.confirm()
        stopCountdown()
        refresh()
    }

    func confirmKeep() {
        rollback.confirm()
        stopCountdown()
        statusMessage = "Kept. (Mode also reverts automatically if the app quits — Apple behaviour.)"
    }

    func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func clearLogs() {
        AppLogger.shared.clear()
        statusMessage = "Logs cleared."
    }

    // MARK: - Private prototype (opt-in + kill-switch)

    func refreshPrivateStatus() {
        privateAvailable = PrivateHiDPIGateway.isAvailable
        privateOptIn = PrivateHiDPIGateway.optInEnabled
        if let id = selectedDisplayID {
            privateActiveVirtualID = PrivateHiDPIGateway.virtualDisplay(forPhysical: id)
        } else {
            privateActiveVirtualID = nil
        }
    }

    func togglePrivateOptIn() {
        let next = !PrivateHiDPIGateway.optInEnabled
        PrivateHiDPIGateway.setOptIn(next)
        AppLogger.shared.info("private prototype opt-in=\(next)")
        if !next, let id = selectedDisplayID {
            PrivateHiDPIGateway.disable(physicalDisplayID: id)
            statusMessage = "Private prototype disabled and torn down."
        } else {
            statusMessage = next
                ? "Private prototype enabled. Now use Enable for this display."
                : "Private prototype disabled."
        }
        refresh()
    }

    func enablePrivatePrototype() {
        guard let id = selectedDisplayID else { return }
        guard PrivateHiDPIGateway.optInEnabled else {
            statusMessage = "Enable the opt-in toggle first."
            return
        }
        // Single-flight: rapid retries collide in WindowServer (observed -13).
        guard !rollback.isArmed, countdown == 0 else {
            statusMessage = "Wait for the current countdown to finish first."
            return
        }
        // Never mirror a virtual display onto itself (observed mirrorFailed).
        if selectedDisplay?.isOwnVirtual == true {
            statusMessage = "Select the physical DELL U3425WE, not the SimpleHiDPI virtual."
            return
        }
        if PrivateHiDPIGateway.activeMap.values.contains(id) {
            statusMessage = "That is already a virtual display. Select the physical Dell."
            return
        }
        guard !privateBusy else {
            statusMessage = "Creation already in progress — wait a few seconds."
            return
        }
        pendingPrevious = manager.currentMode(for: id)
        privateBusy = true
        statusMessage = "Creating private virtual display…"
        // Creation polls for the new display (blocking sleeps), so it runs
        // off-main; UI updates resume on MainActor when it completes.
        let size = Self.privateSizes.first(where: { $0.width == selectedLogicalWidth }) ?? Self.privateSizes[1]
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                PrivateHiDPIGateway.enable(physicalDisplayID: id, logicalWidth: size.width, logicalHeight: size.height)
            }.value
            self.privateBusy = false
            switch result {
            case .success(let r):
                AppLogger.shared.info("display=\(id) private virtual=\(r.virtualDisplayID) created+mirrored")
                self.statusMessage = "Private HiDPI active (virtual \(r.virtualDisplayID)). Confirm within \(Self.keepTimeoutSeconds) s."
                self.refresh()
                self.startPrivateCountdown(physicalID: id, virtualID: r.virtualDisplayID, previous: nil, isEnableRollback: true)
            case .failure(let e):
                if case .creationFailed(let code) = e, code == -30 {
                    self.statusMessage = "Creation already in progress — wait a few seconds."
                } else {
                    self.statusMessage = "Private enable failed: \(e). Leave opt-in ON, wait 10 s, retry once."
                }
                AppLogger.shared.error("display=\(id) private enable failed: \(e)")
                self.refreshPrivateStatus()
            }
        }
    }

    /// Seconds the user has to click Keep before the change rolls back.
    static let keepTimeoutSeconds = 30

    /// "Looks like" sizes offered on the private path (2x backing each).
    /// Smaller logical size = larger UI on the 3440x1440 panel.
    static let privateSizes: [(title: String, width: Int, height: Int)] = [
        ("Native", 3440, 1440),
        ("Larger", 3008, 1264),
        ("Larger+", 2752, 1152),
        ("Much Larger", 2560, 1080),
    ]

    /// The virtual's modes can't be switched while mirrored, so a size change
    /// re-creates the virtual. The keep-timeout rollback tears down if not confirmed.
    private func switchPrivateSize(physicalID: CGDirectDisplayID, size: (title: String, width: Int, height: Int)) {
        guard !privateBusy else { return }
        rollback.confirm() // a stale rollback must not fire mid-switch
        stopCountdown()
        privateBusy = true
        statusMessage = "Switching to \(size.width)×\(size.height)…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                PrivateHiDPIGateway.enable(physicalDisplayID: physicalID, logicalWidth: size.width, logicalHeight: size.height)
            }.value
            self.privateBusy = false
            switch result {
            case .success(let r):
                AppLogger.shared.info("display=\(physicalID) private virtual=\(r.virtualDisplayID) size=\(size.width)x\(size.height)")
                self.refresh()
                self.startPrivateCountdown(physicalID: physicalID, virtualID: r.virtualDisplayID, previous: nil, isEnableRollback: true)
            case .failure(let e):
                AppLogger.shared.error("display=\(physicalID) size switch failed: \(e)")
                self.statusMessage = "Size switch failed: \(e). Panel restored."
                self.refresh()
            }
        }
    }

    func disablePrivatePrototype() {
        guard let id = selectedDisplayID else { return }
        PrivateHiDPIGateway.disable(physicalDisplayID: id)
        AppLogger.shared.info("display=\(id) private prototype disabled (kill-switch)")
        rollback.confirm()
        stopCountdown()
        statusMessage = "Private virtual torn down; panel back to standalone."
        refresh()
    }

    /// Auto-enable once per launch when the user has opted in (persisted).
    /// Fresh installs still default to OFF. Always arms the keep-timeout rollback,
    /// so an unattended launch safely tears down instead of sticking.
    private func maybeAutoEnablePrivate() {
        guard !didAutoEnableThisLaunch else { return }
        guard PrivateHiDPIGateway.optInEnabled,
              PrivateHiDPIGateway.isAvailable,
              let id = selectedDisplayID,
              PrivateHiDPIGateway.virtualDisplay(forPhysical: id) == nil,
              !rollback.isArmed,
              countdown == 0 else { return }
        if PrivateHiDPIGateway.activeMap.values.contains(id) { return } // never target a virtual display
        didAutoEnableThisLaunch = true
        enablePrivatePrototype()
    }

    private func startPrivateCountdown(physicalID: CGDirectDisplayID, virtualID: CGDirectDisplayID, previous: DisplayModeInfo?, isEnableRollback: Bool = false) {
        rollback.arm(rollback: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if isEnableRollback {
                    PrivateHiDPIGateway.disable(physicalDisplayID: physicalID)
                    self.statusMessage = "No confirmation — private virtual torn down."
                } else if let prev = previous {
                    _ = self.manager.applyMode(prev, for: virtualID)
                    self.statusMessage = "No confirmation — restored previous virtual mode."
                }
                self.stopCountdown()
                self.refresh()
            }
        }, timeoutSeconds: Self.keepTimeoutSeconds)
        countdown = Self.keepTimeoutSeconds
        if !isEnableRollback {
            statusMessage = "Confirm within \(Self.keepTimeoutSeconds) s or the previous virtual mode returns."
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.rollback.tickForTests() {
                    self.countdown = 0
                    self.stopCountdown()
                    self.refresh()
                } else {
                    self.countdown = self.rollback.secondsRemaining
                }
            }
        }
    }

    // MARK: - Rollback countdown

    private func startCountdown(displayID: CGDirectDisplayID) {
        rollback.arm(rollback: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let prev = self.pendingPrevious {
                    _ = self.manager.applyMode(prev, for: displayID)
                }
                self.statusMessage = "No confirmation — restored previous mode."
                self.stopCountdown()
                self.reloadModes()
            }
        }, timeoutSeconds: Self.keepTimeoutSeconds)
        countdown = Self.keepTimeoutSeconds
        statusMessage = "Confirm within \(Self.keepTimeoutSeconds) s or the previous mode returns."
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.rollback.tickForTests() {
                    self.countdown = 0
                    self.stopCountdown()
                    self.reloadModes()
                } else {
                    self.countdown = self.rollback.secondsRemaining
                }
            }
        }
    }

    private func stopCountdown() {
        timer?.invalidate()
        timer = nil
        if !rollback.isArmed { countdown = 0 }
    }
}

// MARK: - View

struct MenuBarView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SimpleHiDPIScaler").font(.headline)

            if let display = viewModel.selectedDisplay {
                Picker("Display", selection: Binding(
                    get: { viewModel.selectedDisplayID ?? 0 },
                    set: { viewModel.selectDisplay($0) }
                )) {
                    ForEach(viewModel.physicalDisplays, id: \.id) { d in
                        Text("\(d.name) — \(d.nativePixelWidth)×\(d.nativePixelHeight) (ID \(d.id))").tag(d.id)
                    }
                }
                .pickerStyle(.menu)

                Group {
                    Text("Current:").font(.subheadline).bold()
                    + Text(" \(viewModel.currentMode?.logicalLabel ?? "—")")
                    + Text("  @ \(viewModel.currentMode?.pixelLabel ?? "—") px")
                    if let m = viewModel.currentMode {
                        Text("Refresh: \(m.refreshRate == 0 ? "—" : String(format: "%.0f Hz", m.refreshRate))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("HiDPI: \(m.isHiDPI ? "yes (×\(String(format: "%.1f", m.scaleFactor)))" : "no")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if display.looksLikeDellU3425WE {
                        Text("Detected: Dell U3425WE ✓").font(.caption).foregroundStyle(.green)
                    } else if display.isDellUWQHD {
                        Text("Possible Dell 34″ UWQHD (vendor 10AC, name generic while mirrored)").font(.caption).foregroundStyle(.yellow)
                    }
                    Text("ID \(display.id) · \(display.nativePixelWidth)×\(display.nativePixelHeight) px")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Divider()
                Text("Scaling:").font(.subheadline).bold()
                ForEach(viewModel.options) { option in
                    // Whole row is the hit target (a text-only button missed most clicks).
                    Button {
                        viewModel.choose(option)
                    } label: {
                        HStack {
                            Image(systemName: viewModel.selectedLogicalWidth == option.logicalWidth
                                ? "circle.inset.filled" : "circle")
                            Text(option.title)
                            Spacer()
                            Text(option.isAvailable
                                ? "\(option.matchedMode!.logicalLabel)\(option.matchedMode!.isHiDPI ? " HiDPI" : "")"
                                : "not exposed by macOS")
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!option.isAvailable)
                    .opacity(option.isAvailable ? 1.0 : 0.5)
                }

                if viewModel.showsHiDPIOnlyNote && viewModel.privateActiveVirtualID == nil {
                    Text("macOS exposes no HiDPI modes for this display. " +
                         "Public rows stay unavailable by design — or enable the private prototype below.")
                        .font(.caption).foregroundStyle(.orange)
                }

                if viewModel.privateModeActive {
                    Text("Private virtual active — panel timing stays 3440×1440, UI renders at 2x (60 Hz cap).")
                        .font(.caption).foregroundStyle(.purple)
                }

                if viewModel.countdown > 0 {
                    Text("Keep this mode? \(viewModel.countdown)s — or it rolls back.")
                        .font(.callout).bold()
                    Button("Keep") { viewModel.confirmKeep() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Apply") { viewModel.applySelected() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }

                Divider()
                Button("Restore Defaults") { viewModel.restoreDefaults() }
                Button("Open Display Settings") { viewModel.openDisplaySettings() }
                Button("Clear logs") { viewModel.clearLogs() }
                Button("Refresh displays") { viewModel.refresh() }

                Divider()
                Text("Private HiDPI prototype").font(.subheadline).bold()
                Text(viewModel.privateAvailable
                     ? "Private API present."
                     : "Private API not present on this macOS build.")
                    .font(.caption).foregroundStyle(.secondary)
                if !viewModel.privateOptIn {
                    Text("Off by default. Uses private virtual-display APIs + mirroring. Breaks on OS updates, no App Store, 60 Hz cap.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Enable private prototype opt-in") { viewModel.togglePrivateOptIn() }
                } else {
                    Button("Disable private prototype opt-in (kill-switch)") { viewModel.togglePrivateOptIn() }
                    if let virtualID = viewModel.privateActiveVirtualID {
                        Text("Active: virtual \(virtualID) → physical \(display.id).")
                            .font(.caption).foregroundStyle(.purple)
                        Button("Disable for this display (unmirror + destroy)") {
                            viewModel.disablePrivatePrototype()
                        }
                    } else {
                        Button("Enable HiDPI for this display (creates virtual + mirrors)") {
                            viewModel.enablePrivatePrototype()
                        }
                        .disabled(viewModel.privateBusy || viewModel.countdown > 0)
                    }
                }

                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No displays found.")
                Button("Refresh") { viewModel.refresh() }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}
