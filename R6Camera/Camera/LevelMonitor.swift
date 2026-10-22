import CoreMotion
import Combine

final class LevelMonitor: ObservableObject {
    @Published private(set) var reading: LevelReading?
    private let manager = CMMotionManager()
    private var filter = LevelFilter()
    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            guard error == nil, let motion else { self.filter.reset(); self.reading = nil; return }
            let g = motion.gravity
            self.reading = self.filter.update(x: g.x, y: g.y, z: g.z, at: motion.timestamp)
        }
    }
    func stop() { manager.stopDeviceMotionUpdates(); filter.reset(); reading = nil }
    deinit { manager.stopDeviceMotionUpdates() }
}
