import Foundation

/// Cross-queue intent only; AVCaptureSession itself remains owned by sessionQueue.
final class SessionLifecycle {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var requested = false
    func begin(active: Bool) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; requested = active
        return active ? generation : nil
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; requested = false
    }
    func permits(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return requested && generation == token
    }
}
