import Foundation

enum LevelSize: String, Codable, CaseIterable { case large = "大", small = "小" }

struct LevelReading: Equatable {
    var roll: Double
    var pitch: Double
    var isLevel: Bool { abs(roll) <= 1 && abs(pitch) <= 1 }
}

struct LevelFilter {
    private(set) var reading: LevelReading?
    private var lastTime: Double?
    mutating func reset() { reading = nil; lastTime = nil }
    /// Fixed UIInterfaceOrientation.landscapeRight: Island left, +device-X up.
    mutating func update(x: Double, y: Double, z: Double, at time: Double) -> LevelReading? {
        guard x.isFinite, y.isFinite, z.isFinite, time.isFinite,
              hypot(x, y) > 0.1 else { reset(); return nil }
        let degrees = 180 / Double.pi
        let raw = LevelReading(roll: atan2(y, -x) * degrees,
                               pitch: atan2(-z, hypot(x, y)) * degrees)
        if let lastTime, let old = reading, time > lastTime {
            let alpha = 1 - exp(-(time - lastTime) / 0.15)
            let delta = atan2(sin((raw.roll - old.roll) / degrees), cos((raw.roll - old.roll) / degrees)) * degrees
            reading = LevelReading(roll: old.roll + alpha * delta,
                                   pitch: old.pitch + alpha * (raw.pitch - old.pitch))
        } else { reading = raw }
        lastTime = time
        return reading
    }
}
