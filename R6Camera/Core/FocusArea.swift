import Foundation
import CoreGraphics

enum FocusAreaMode: String, CaseIterable, Codable, Identifiable {
    case spot = "重點自動對焦", point = "單點自動對焦"
    case expanded = "擴展自動對焦區域：四點", surround = "擴展自動對焦區域：環繞"
    case flexible1 = "彈性區域自動對焦1", flexible2 = "彈性區域自動對焦2", flexible3 = "彈性區域自動對焦3"
    case whole = "全區域自動對焦"
    var id: String { rawValue }
    var isFlexible: Bool { [.flexible1, .flexible2, .flexible3].contains(self) }
    var number: String { switch self { case .flexible1: return "1"; case .flexible2: return "2"; case .flexible3: return "3"; default: return "" } }
}

/// Software acquisition regions in the oriented image (top-left origin), not sensor AF cells.
struct FocusArea: Codable, Equatable {
    var mode: FocusAreaMode = .whole
    private var pointCenter = CGPoint(x: 0.5, y: 0.5)
    private var zone1 = CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.4)
    private var zone2 = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.6)
    private var zone3 = CGRect(x: 0.2, y: 0.375, width: 0.6, height: 0.25)
    var wholeAreaTracking = true
    var center: CGPoint {
        let r = bounds
        return CGPoint(x: r.midX, y: r.midY)
    }
    var bounds: CGRect {
        if mode == .whole { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        if mode.isFlexible { return Self.clamped(zone) }
        let side: CGFloat = mode == .spot ? 0.025 : mode == .point ? 0.05 : 0.15
        return Self.clamped(CGRect(x: pointCenter.x - side / 2, y: pointCenter.y - side * 2 / 3,
                                   width: side, height: side * 4 / 3))
    }
    private var zone: CGRect {
        get { switch mode { case .flexible2: return zone2; case .flexible3: return zone3; default: return zone1 } }
        set { switch mode { case .flexible2: zone2 = newValue; case .flexible3: zone3 = newValue; default: zone1 = newValue } }
    }
    /// Ordered cells let expansion acquire the central point before surrounding points.
    var cells: [CGRect] {
        let r = bounds
        guard mode == .expanded || mode == .surround else { return [r] }
        let w = r.width / 3, h = r.height / 3
        var offsets = [(1, 1), (1, 0), (0, 1), (2, 1), (1, 2)]
        if mode == .surround { offsets += [(0, 0), (2, 0), (0, 2), (2, 2)] }
        return offsets.map { CGRect(x: r.minX + CGFloat($0.0) * w, y: r.minY + CGFloat($0.1) * h, width: w, height: h) }
    }
    func contains(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && cells.contains { $0.insetBy(dx: -0.000001, dy: -0.000001).contains(point) }
    }
    func acquisitionRank(_ point: CGPoint) -> Int? {
        cells.firstIndex { $0.insetBy(dx: -0.000001, dy: -0.000001).contains(point) }
    }
    mutating func move(to point: CGPoint) {
        guard mode != .whole, point.x.isFinite, point.y.isFinite else { return }
        let r = bounds
        let moved = Self.clamped(CGRect(x: point.x - r.width / 2, y: point.y - r.height / 2, width: r.width, height: r.height))
        if mode.isFlexible { zone = moved }
        else { pointCenter = CGPoint(x: moved.midX, y: moved.midY) }
    }
    mutating func resize(width: CGFloat, height: CGFloat) {
        guard mode.isFlexible, width.isFinite, height.isFinite else { return }
        let c = center
        zone = Self.clamped(CGRect(x: c.x - width / 2, y: c.y - height / 2, width: width, height: height))
    }
    mutating func resetShape() {
        let defaults = FocusArea()
        switch mode {
        case .flexible1: zone1 = defaults.zone1
        case .flexible2: zone2 = defaults.zone2
        case .flexible3: zone3 = defaults.zone3
        default: pointCenter = defaults.pointCenter
        }
    }
    private static func clamped(_ rect: CGRect) -> CGRect {
        let w = rect.width.isFinite ? min(1, max(0.025, rect.width)) : 0.3
        let h = rect.height.isFinite ? min(1, max(0.025, rect.height)) : 0.4
        let x = rect.minX.isFinite ? min(1 - w, max(0, rect.minX)) : (1 - w) / 2
        let y = rect.minY.isFinite ? min(1 - h, max(0, rect.minY)) : (1 - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
