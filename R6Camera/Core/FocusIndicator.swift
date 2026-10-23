import Foundation

/// Selection/command feedback only. Blue never asserts optical focus confirmation.
enum FocusIndicator: Equatable {
    case point(CGPoint)
    case subject(CGRect, selected: Bool)
    static func resolve(_ result: TrackingResult, settings: CameraSettings) -> FocusIndicator? {
        let effective = settings.effective
        guard effective.autofocus != .manual else { return nil }
        if let point = result.touchPoint { return .point(point) }
        if let target = result.selected, !result.lost {
            return .subject(result.locked ? target.focusBounds(effective.eyes) : target.headBounds ?? target.bounds,
                            selected: result.locked)
        }
        if effective.focusArea.mode != .whole, let point = result.areaFocusPoint { return .point(point) }
        return nil
    }
}
