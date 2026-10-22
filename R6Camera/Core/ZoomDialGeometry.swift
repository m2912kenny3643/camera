import Foundation
import CoreGraphics

/// One circle owns the disk, ticks and text. The hub stays outside the right edge.
struct ZoomDialGeometry {
    let size: CGSize
    var radius: CGFloat { size.height * 0.63 }
    var center: CGPoint { CGPoint(x: size.width + radius - size.width * 0.15, y: size.height * 0.55) }
    func angle(for value: CGFloat, selected: CGFloat) -> CGFloat {
        .pi - log2(value / selected) * 0.46
    }
    func point(angle: CGFloat, inset: CGFloat = 0) -> CGPoint {
        CGPoint(x: center.x + (radius - inset) * cos(angle), y: center.y + (radius - inset) * sin(angle))
    }
    func zoom(start: CGFloat, verticalTranslation: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, start * pow(2, verticalTranslation / 100)))
    }
}
