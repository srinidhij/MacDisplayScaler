import Foundation
import OSLog

/// Local-only logger. Writes to the unified log (subsystem
/// com.simplehidpiscaler.app) and to ~/Library/Logs/SimpleHiDPIScaler.log.
///
/// Logged fields: display ID, selected mode, previous mode, result/error.
/// NEVER logged: user name, paths under Documents/Desktop, EDID blobs,
/// serial numbers, network data (there is no network code at all).
public final class AppLogger: Sendable {
    public static let shared = AppLogger()

    private let log = Logger(subsystem: "com.simplehidpiscaler.app", category: "display")
    private let lock = NSLock()

    public init() {}

    public var logFileURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/SimpleHiDPIScaler.log", isDirectory: false)
    }

    public func info(_ message: String) {
        log.info("\(message, privacy: .public)")
        append("[INFO] \(message)")
    }

    public func error(_ message: String) {
        log.error("\(message, privacy: .public)")
        append("[ERROR] \(message)")
    }

    /// Structured display-change record required by the spec.
    public func logDisplayChange(
        displayID: UInt32,
        previous: DisplayModeInfo?,
        selected: DisplayModeInfo?,
        resultCode: Int32
    ) {
        let prev = previous.map { "\($0.logicalLabel)@\($0.pixelLabel) \($0.refreshRate)Hz" } ?? "unknown"
        let sel = selected.map { "\($0.logicalLabel)@\($0.pixelLabel) \($0.refreshRate)Hz hidpi=\($0.isHiDPI)" } ?? "unknown"
        let msg = "display=\(displayID) previous=[\(prev)] selected=[\(sel)] result=\(resultCode)"
        if resultCode == 0 {
            info(msg)
        } else {
            error(msg)
        }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: logFileURL)
    }

    // MARK: - Private

    private func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        guard let data = stamped.data(using: .utf8) else { return }
        let url = logFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url)
        }
    }
}
