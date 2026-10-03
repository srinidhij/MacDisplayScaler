import Foundation

/// Public-API-only scaling policy.
///
/// The three desired logical sizes from the spec (3440x1440, ~3008x1264,
/// ~2560x1080) are treated as *preferences*, not guarantees: we return the
/// closest mode macOS/the GPU actually exposes and mark rows unavailable
/// when nothing is close. We never synthesize pixel buffers ourselves —
/// that is what would require private APIs (see PrivateHiDPIGateway).
public final class ScalingManager: ScalingManaging, Sendable {
    /// Desired logical options for a 3440x1440 panel, in UI order.
    /// Tolerances handle GPUs that expose e.g. 3008x1269 instead of 3008x1264.
    public struct DesiredOption: Sendable {
        public let title: String
        public let width: Int
        public let height: Int
    }

    public static let ultrawide3440Desired: [DesiredOption] = [
        DesiredOption(title: "Native", width: 3440, height: 1440),
        DesiredOption(title: "Larger", width: 3008, height: 1264),
        DesiredOption(title: "Much Larger", width: 2560, height: 1080),
    ]

    /// Max relative dimension error that still counts as "the same" logical mode.
    private let tolerance: Double = 0.03 // 3%
    private let desired: [DesiredOption]

    public init(desired: [DesiredOption] = ScalingManager.ultrawide3440Desired) {
        self.desired = desired
    }

    public func scalingOptions(for display: DisplayInfo, availableModes: [DisplayModeInfo]) -> [ScalingOption] {
        // Non-ultrawide panels: surface a compact generic list instead of
        // forcing ultrawide geometry onto them.
        let wants = desired
        return wants.map { want in
            // Native may be a plain 1x mode. Larger / Much Larger must be true
            // HiDPI (backing pixels > logical) so the physical timing stays at
            // 3440x1440. A plain 2560x1080 mode is NOT scaling — it drops the
            // panel to 2560x1080 — so it must never match those rows.
            let requireHiDPI = want.title != "Native"
            let match = bestMode(
                forLogicalWidth: want.width,
                logicalHeight: want.height,
                availableModes: availableModes,
                preferHiDPI: true,
                requireHiDPI: requireHiDPI
            )
            return ScalingOption(
                title: want.title,
                logicalWidth: want.width,
                logicalHeight: want.height,
                matchedMode: match
            )
        }
    }

    public func bestMode(
        forLogicalWidth logicalWidth: Int,
        availableModes: [DisplayModeInfo],
        preferHiDPI: Bool
    ) -> DisplayModeInfo? {
        // Height unknown in this overload: accept any height with matching width.
        let candidates = availableModes.filter {
            $0.usableForDesktopGUI && abs($0.width - logicalWidth) <= Int(Double(logicalWidth) * tolerance) + 8
        }
        guard !candidates.isEmpty else { return nil }
        return rank(candidates, preferHiDPI: preferHiDPI)
    }

    // MARK: - Private

    private func bestMode(
        forLogicalWidth logicalWidth: Int,
        logicalHeight: Int,
        availableModes: [DisplayModeInfo],
        preferHiDPI: Bool,
        requireHiDPI: Bool = false
    ) -> DisplayModeInfo? {
        let candidates = availableModes.filter {
            guard $0.usableForDesktopGUI else { return false }
            if requireHiDPI, !$0.isHiDPI { return false }
            let dw = abs($0.width - logicalWidth) <= max(8, Int(Double(logicalWidth) * tolerance))
            let dh = abs($0.height - logicalHeight) <= max(8, Int(Double(logicalHeight) * tolerance))
            return dw && dh
        }
        guard !candidates.isEmpty else { return nil }
        return rank(candidates, preferHiDPI: preferHiDPI)
    }

    /// Prefer HiDPI, then highest refresh, then largest backing store.
    private func rank(_ candidates: [DisplayModeInfo], preferHiDPI: Bool) -> DisplayModeInfo? {
        candidates.sorted { a, b in
            if preferHiDPI, a.isHiDPI != b.isHiDPI { return a.isHiDPI && !b.isHiDPI }
            if a.refreshRate != b.refreshRate { return a.refreshRate > b.refreshRate }
            return (a.pixelWidth * a.pixelHeight) > (b.pixelWidth * b.pixelHeight)
        }.first
    }
}
