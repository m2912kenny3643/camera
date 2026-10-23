import Foundation

enum DetectionPolicy {
    static func needsBodyModel(subjects: SubjectMode, birdAvailable: Bool) -> Bool {
        subjects != .none && (subjects != .birds || !birdAvailable)
    }
    static func birdFailure(_ error: String, bodyAvailable: Bool) -> String {
        bodyAvailable ? "鳥眼不可用，使用一般身體辨識：\(error)" : "鳥眼及一般身體模型不可用：\(error)"
    }
}
