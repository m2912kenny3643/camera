import SwiftUI

struct ZoomWheel: View {
    @ObservedObject var camera: CameraController
    let railWidth: CGFloat
    let close: () -> Void
    @State private var previousTouch: CGPoint?
    @State private var gestureZoom: CGFloat?
    @State private var snap: CGFloat?
    @State private var dismissTask: Task<Void, Never>?
    var body: some View {
        GeometryReader { proxy in
            let dial = ZoomDialGeometry(size: proxy.size)
            ZStack(alignment: .bottomTrailing) {
                Canvas { context, size in
                    context.fill(Path(ellipseIn: CGRect(x: dial.center.x - dial.radius, y: dial.center.y - dial.radius, width: dial.radius * 2, height: dial.radius * 2)), with: .color(Color(white: 0.08)))
                    for i in -16...80 {
                        let value = pow(2, CGFloat(i) / 16)
                        guard camera.zoomRange.contains(value) else { continue }
                        let angle = dial.angle(for: value, selected: camera.zoom)
                        let point = dial.point(angle: angle, inset: 8)
                        guard point.x < size.width - 2, point.y > 8, point.y < size.height - 8 else { continue }
                        let major = i % 16 == 0
                        var tick = Path(); tick.move(to: point)
                        tick.addLine(to: dial.point(angle: angle, inset: major ? 24 : 17))
                        context.stroke(tick, with: .color(.white.opacity(major ? 0.95 : 0.45)), lineWidth: major ? 1.5 : 0.65)
                        if major && abs(value - camera.zoom) > 0.08 {
                            let anchor = dial.point(angle: angle, inset: 43)
                            guard anchor.x < size.width - 20 else { continue }
                            var c = context; c.translateBy(x: anchor.x, y: anchor.y)
                            c.rotate(by: .radians(Double(angle - .pi)))
                            c.draw(Text(String(format: "%g", Double(value))).font(.system(size: 15, weight: .semibold)).foregroundColor(.white), at: .zero)
                            if let focal = camera.equivalentFocalLength(at: value) {
                                c.draw(Text("≈\(Int(focal.rounded()))MM").font(.system(size: 8)).foregroundColor(.gray), at: CGPoint(x: 3, y: 14))
                            }
                        }
                    }
                    let tip = dial.point(angle: .pi, inset: 4)
                    var p = Path(); p.move(to: CGPoint(x: tip.x, y: tip.y - 4)); p.addLine(to: CGPoint(x: tip.x + 11, y: tip.y)); p.addLine(to: CGPoint(x: tip.x, y: tip.y + 4)); p.closeSubpath()
                    context.fill(p, with: .color(.yellow))
                    let label = CGPoint(x: tip.x + 38, y: tip.y - 4)
                    context.draw(Text(String(format: "%g×", Double((camera.zoom * 10).rounded() / 10))).font(.system(size: 18, weight: .semibold)).foregroundColor(.yellow), at: label)
                    if let focal = camera.equivalentFocalLength(at: camera.zoom) {
                        context.draw(Text("≈\(Int(focal.rounded()))MM").font(.system(size: 10)).foregroundColor(.yellow), at: CGPoint(x: label.x, y: label.y + 17))
                    }
                }.mask(alignment: .bottomTrailing) { Rectangle().frame(width: railWidth, height: max(0, proxy.size.height - 80)) }.allowsHitTesting(false)
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .frame(width: min(railWidth, proxy.size.width * 0.19), height: max(0, proxy.size.height - 80))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("zoom.dial")).onChanged { drag in
                        dismissTask?.cancel()
                        let previous = previousTouch ?? drag.startLocation
                        let value = dial.zoom(start: gestureZoom ?? camera.zoom,
                                              rotation: dial.rotation(from: previous, to: drag.location), range: camera.zoomRange)
                        previousTouch = drag.location
                        gestureZoom = value
                        let stop = [CGFloat(0.5), 1, 2].first { camera.zoomRange.contains($0) && abs(log2(value / $0)) < 0.035 }
                        if stop != snap, stop != nil { UISelectionFeedbackGenerator().selectionChanged() }
                        snap = stop; camera.setZoom(stop ?? value)
                    }.onEnded { _ in previousTouch = nil; gestureZoom = nil; scheduleDismiss() })
                    .accessibilityLabel("縮放轉盤").accessibilityIdentifier("zoom.wheel")
                    .accessibilityValue(String(format: "%.2f", Double(camera.zoom)))
                    .accessibilityAdjustableAction { direction in
                        camera.setZoom(camera.zoom * (direction == .increment ? 1.1 : 1 / 1.1)); scheduleDismiss()
                    }
            }.coordinateSpace(name: "zoom.dial").clipped().onAppear { scheduleDismiss() }.onDisappear { dismissTask?.cancel() }
        }
    }
    private func scheduleDismiss() {
        dismissTask?.cancel()
        // Screenshots and accessibility snapshots can take longer than the idle delay.
        // Only the explicitly enabled simulator fixture holds this timer; real capture stays at 2s.
        if camera.isUIFixture && ProcessInfo.processInfo.environment["R6_UI_HOLD_ZOOM"] == "1" { return }
        dismissTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            close()
        }
    }
}
