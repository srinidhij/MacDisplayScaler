import Foundation

/// 10-second confirm-or-rollback window.
///
/// Usage: `arm(rollback:)` starts the countdown. The UI ticks it with a
/// Timer and shows "Keep? 9…8…". `confirm()` keeps the new mode.
/// On timeout (or `tickForTests()` returning true) the rollback closure
/// restores the previously saved mode. Thread-safe; rollback fires exactly once.
public final class RollbackManager: RollbackManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var rollbackClosure: (() -> Void)?
    private var remaining: Int = 0
    private var fired = false

    public init() {}

    public var isArmed: Bool {
        lock.lock(); defer { lock.unlock() }
        return rollbackClosure != nil && !fired
    }

    public var secondsRemaining: Int {
        lock.lock(); defer { lock.unlock() }
        return remaining
    }

    public func arm(rollback: @escaping () -> Void, timeoutSeconds: Int = 10) {
        lock.lock()
        rollbackClosure = rollback
        remaining = timeoutSeconds
        fired = false
        lock.unlock()
    }

    public func confirm() {
        lock.lock()
        rollbackClosure = nil
        remaining = 0
        lock.unlock()
    }

    /// Decrements one second. Returns true exactly once when the timeout
    /// elapses (rollback closure invoked outside the lock).
    @discardableResult
    public func tickForTests() -> Bool {
        lock.lock()
        guard let closure = rollbackClosure, !fired else {
            lock.unlock()
            return false
        }
        remaining -= 1
        if remaining <= 0 {
            fired = true
            rollbackClosure = nil
            lock.unlock()
            closure()
            return true
        }
        lock.unlock()
        return false
    }

    /// Production tick entry point (same semantics, clearer name for UI code).
    @discardableResult
    public func tick() -> Bool {
        tickForTests()
    }

    public func cancelForTests() {
        lock.lock()
        rollbackClosure = nil
        remaining = 0
        lock.unlock()
    }
}
