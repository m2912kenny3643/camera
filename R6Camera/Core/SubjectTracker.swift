import Foundation
import CoreGraphics

enum SubjectKind: String, Codable {
    case person, dog, cat, bird, horse, car, motorcycle, airplane, train
    var isAnimal: Bool { [.dog, .cat, .bird, .horse].contains(self) }
    var isVehicle: Bool { [.car, .motorcycle, .airplane, .train].contains(self) }
    var title: String {
        switch self {
        case .person: return "人物"
        case .dog: return "狗"
        case .cat: return "貓"
        case .bird: return "鳥"
        case .horse: return "馬"
        case .car: return "汽車"
        case .motorcycle: return "機車"
        case .airplane: return "飛機"
        case .train: return "火車"
        }
    }
    static func fromModelLabel(_ label: String) -> SubjectKind? {
        switch label {
        case "motorbike", "motorcycle": return .motorcycle
        case "aeroplane", "airplane": return .airplane
        default: return SubjectKind(rawValue: label)
        }
    }
}

/// All geometry uses the oriented camera image, normalized to 0...1, origin TOP LEFT.
struct SubjectDetection: Identifiable {
    var id = UUID()
    var kind: SubjectKind
    var bounds: CGRect
    var confidence: Float
    /// Anatomical left/right, not screen left/right. Only actual detected eyes are populated.
    var leftEye: CGPoint?
    var rightEye: CGPoint?
    var headBounds: CGRect?
    func eye(_ priority: EyePriority) -> CGPoint? {
        switch priority {
        case .off: return nil
        case .left: return leftEye ?? rightEye
        case .right: return rightEye ?? leftEye
        case .automatic: return leftEye ?? rightEye
        }
    }
    func focusPoint(_ priority: EyePriority) -> CGPoint {
        let rect = headBounds ?? bounds
        return eye(priority) ?? CGPoint(x: rect.midX, y: rect.midY)
    }
    func focusBounds(_ priority: EyePriority) -> CGRect {
        if let eye = eye(priority) {
            let side = min(0.035, max(0.012, bounds.width * 0.12))
            return CGRect(x: eye.x - side / 2, y: eye.y - side / 2, width: side, height: side)
        }
        return headBounds ?? bounds
    }
}

enum FocusAction: Equatable {
    /// Scene AF keeps the preview usable without following a candidate's coordinates.
    case none, scene, hold
    case single(CGPoint), continuous(CGPoint)
}
struct FocusConfiguration: Equatable {
    let mode: AutofocusMode
    let subjects: SubjectMode
    let eyes: EyePriority
    init(_ settings: CameraSettings) {
        let effective = settings.effective
        mode = effective.autofocus; subjects = effective.subjects; eyes = effective.eyes
    }
}

struct TrackingResult {
    var observedAt: Double?
    var epoch: UInt64?
    var frameSequence: UInt64?
    var candidates: [SubjectDetection] = []
    var selected: SubjectDetection?
    var locked = false
    var missing = false
    var lost = false
    var touchPoint: CGPoint?
    var focusAction: FocusAction = .none
    var configuration: FocusConfiguration?
}

/// Identity association and explicit lock are separate from physical lens AF.
struct SubjectTracker {
    private(set) var result = TrackingResult()
    private var lastSeen: Double = 0
    private var challenger: SubjectDetection?
    private var challengerSince: Double = 0

    mutating func reset() {
        self = SubjectTracker()
    }
    mutating func unlock() { reset(); result.focusAction = .scene }
    mutating func select(at point: CGPoint, eyes: EyePriority = .automatic, mode: AutofocusMode = .servo) {
        guard let subject = result.candidates.filter({ $0.bounds.contains(point) })
            .min(by: { $0.bounds.area < $1.bounds.area }) else {
            result.selected = nil
            result.locked = false
            result.missing = false
            result.lost = false
            result.touchPoint = point
            result.focusAction = .single(point)
            return
        }
        result.selected = subject
        result.locked = true
        result.missing = false
        result.lost = false
        result.touchPoint = nil
        result.focusAction = mode == .single ? .single(subject.focusPoint(eyes)) : .continuous(subject.focusPoint(eyes))
    }
    mutating func update(_ detections: [SubjectDetection], at now: Double,
                         settings: CameraSettings) -> TrackingResult {
        let candidates = detections.filter { settings.subjects.accepts($0.kind) && $0.confidence >= 0.35 }
        result.focusAction = .none
        result.candidates = candidates
        if settings.autofocus == .manual { reset(); return result }
        if result.touchPoint != nil { return result }
        if let previous = result.selected {
            let matches = candidates.filter { $0.kind == previous.kind }
                .map { ($0, Self.associationScore(previous, $0)) }
                .filter { $0.1 > 0.15 }.sorted { $0.1 > $1.1 }
            if result.locked && matches.count > 1 && matches[0].1 - matches[1].1 < 0.15 {
                // Geometric identity is ambiguous at a crossing. Require a fresh user choice.
                result.locked = false
                result.selected = nil
                result.missing = false
                result.lost = true
                result.focusAction = .scene
                return result
            }
            if var match = matches.first?.0 {
                match.id = previous.id
                result.selected = match
                lastSeen = now
                result.missing = false
                result.lost = false
                if result.locked {
                    result.focusAction = settings.autofocus == .single ? .none : .continuous(match.focusPoint(settings.eyes))
                    return result
                }
            } else {
                result.missing = true
                if result.locked { result.focusAction = .hold }
                if now - lastSeen <= settings.trackingStickiness && result.locked { return result }
                if result.locked {
                    result.locked = false
                    result.lost = true
                    result.selected = nil
                    result.missing = false
                    result.focusAction = .scene
                    return result
                }
                result.selected = nil
            }
        }
        // Scene AF has no candidate coordinates. Only explicit selection enables subject AF.
        result.focusAction = .scene
        result.lost = false
        let best = candidates.max { rank($0) < rank($1) }
        if result.selected == nil {
            result.selected = best
            lastSeen = now
            result.missing = false
        } else if let best, let selected = result.selected,
                  Self.intersectionOverUnion(best.bounds, selected.bounds) < 0.1,
                  rank(best) > rank(selected) * 1.4 {
            if let old = challenger, old.kind == best.kind,
               Self.matchScore(old.bounds, best.bounds) > 0.15 {
                if now - challengerSince >= (1.2 - settings.switchSensitivity) {
                    result.selected = best
                    challenger = nil
                    lastSeen = now
                }
            } else { challenger = best; challengerSince = now }
        } else { challenger = nil }
        return result
    }
    private func rank(_ detection: SubjectDetection) -> Double {
        let distance = hypot(detection.bounds.midX - 0.5, detection.bounds.midY - 0.5)
        return Double(detection.confidence) * Double(detection.bounds.area.squareRoot()) / (0.25 + distance)
    }
    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        return intersection.area / max(a.area + b.area - intersection.area, 0.000001)
    }
    static func matchScore(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = intersectionOverUnion(a, b)
        let distance = hypot(a.midX - b.midX, a.midY - b.midY)
        // A near-center gate helps small eyes/subjects without joining distant lookalikes.
        return max(overlap, distance < 0.08 ? 0.3 * (1 - distance / 0.08) : 0)
    }
    private static func associationScore(_ a: SubjectDetection, _ b: SubjectDetection) -> CGFloat {
        let body = matchScore(a.bounds, b.bounds)
        if let first = a.headBounds, let second = b.headBounds {
            return max(body, matchScore(first, second))
        }
        return body
    }
}

extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
    /// Vision's bottom-left rectangle -> top-left camera rectangle.
    var fromVision: CGRect { CGRect(x: minX, y: 1 - maxY, width: width, height: height) }
}

enum ViewfinderGeometry {
    static let photoAspect: CGFloat = 4.0 / 3
    static func photoRect(in size: CGSize) -> CGRect {
        imageRect(imageAspect: photoAspect, in: size)
    }
    static func imageRect(imageAspect: CGFloat, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, imageAspect > 0 else { return .zero }
        if size.width / size.height > imageAspect {
            let width = size.height * imageAspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        let height = size.width / imageAspect
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }
    static func normalizedIfInside(_ point: CGPoint, imageAspect: CGFloat, size: CGSize) -> CGPoint? {
        let rect = imageRect(imageAspect: imageAspect, in: size)
        guard !rect.isEmpty, rect.contains(point) else { return nil }
        return normalized(point, imageAspect: imageAspect, size: size)
    }
    static func display(_ point: CGPoint, imageAspect: CGFloat, size: CGSize) -> CGPoint {
        let rect = imageRect(imageAspect: imageAspect, in: size)
        return CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
    static func normalized(_ point: CGPoint, imageAspect: CGFloat, size: CGSize) -> CGPoint {
        let rect = imageRect(imageAspect: imageAspect, in: size)
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: min(1, max(0, (point.x - rect.minX) / rect.width)),
                       y: min(1, max(0, (point.y - rect.minY) / rect.height)))
    }
}
