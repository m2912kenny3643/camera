import SwiftUI

struct FocusAreaGlyph: View {
    let mode: FocusAreaMode
    var body: some View {
        ZStack {
            FocusAreaMark(mode: mode).stroke(lineWidth: 1.2)
            if mode.isFlexible { Text(mode.number).font(.system(size: 10, weight: .bold)) }
        }.frame(width: 30, height: 24).accessibilityHidden(true)
    }
}

private struct FocusAreaMark: Shape {
    let mode: FocusAreaMode
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 3, dy: 3)
        var p = Path()
        if mode == .whole || mode.isFlexible {
            let box = mode == .flexible2 ? r.insetBy(dx: 5, dy: 0) : mode == .flexible3 ? r.insetBy(dx: 0, dy: 3) : r
            let d: CGFloat = 5
            for (x, sx) in [(box.minX, CGFloat(1)), (box.maxX, CGFloat(-1))] {
                for (y, sy) in [(box.minY, CGFloat(1)), (box.maxY, CGFloat(-1))] {
                    p.move(to: CGPoint(x: x, y: y + sy * d)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + sx * d, y: y))
                }
            }
        } else if mode == .spot || mode == .point {
            p.addRect(CGRect(x: r.midX - 5, y: r.midY - 5, width: 10, height: 10))
            if mode == .spot { p.addRect(CGRect(x: r.midX - 2, y: r.midY - 2, width: 4, height: 4)) }
        } else {
            for y in -1...1 { for x in -1...1 where mode == .surround || x == 0 || y == 0 {
                p.addRect(CGRect(x: r.midX + CGFloat(x) * 7 - 2, y: r.midY + CGFloat(y) * 6 - 2, width: 4, height: 4))
            } }
        }
        return p
    }
}

struct FocusAreaOptions: View {
    @Binding var draft: CameraSettings
    let accent: Color
    var body: some View {
        VStack(spacing: 5) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(FocusAreaMode.allCases) { mode in
                        Button { draft.focusArea.mode = mode } label: {
                            FocusAreaGlyph(mode: mode).padding(6)
                                .foregroundStyle(draft.focusArea.mode == mode ? Color.cyan : .white)
                                .overlay(Rectangle().stroke(draft.focusArea.mode == mode ? accent : .gray, lineWidth: 1.5))
                        }.accessibilityLabel(mode.rawValue).accessibilityIdentifier("option.\(mode.rawValue)")
                            .accessibilityValue(draft.focusArea.mode == mode ? "已選取" : "")
                    }
                }.padding(.horizontal, 8).padding(.vertical, 3)
            }
            Toggle("全區域追蹤伺服自動對焦", isOn: $draft.focusArea.wholeAreaTracking)
                .font(.system(size: 12)).tint(accent).accessibilityIdentifier("area.wholeTracking")
            if draft.focusArea.mode.isFlexible {
                HStack { Text("寬"); Slider(value: width, in: 0.1...1, step: 0.025).accessibilityIdentifier("area.width")
                    Text("高"); Slider(value: height, in: 0.1...1, step: 0.025).accessibilityIdentifier("area.height") }.tint(accent)
            }
            if draft.focusArea.mode != .whole {
                HStack {
                    Text("拖曳框移動 · 點選框內主體").font(.system(size: 11)).foregroundStyle(.gray)
                    Spacer()
                    Button("置中") { draft.focusArea.move(to: CGPoint(x: 0.5, y: 0.5)) }.accessibilityIdentifier("area.center")
                    Button("重設") { draft.focusArea.resetShape() }.accessibilityIdentifier("area.reset")
                }.font(.system(size: 12))
            }
        }.padding(.horizontal, 12)
    }
    private var width: Binding<Double> {
        Binding(get: { Double(draft.focusArea.bounds.width) }, set: { draft.focusArea.resize(width: CGFloat($0), height: draft.focusArea.bounds.height) })
    }
    private var height: Binding<Double> {
        Binding(get: { Double(draft.focusArea.bounds.height) }, set: { draft.focusArea.resize(width: draft.focusArea.bounds.width, height: CGFloat($0)) })
    }
}

struct FocusAreaOverlay: View {
    let area: FocusArea
    let aspect: CGFloat
    var body: some View {
        GeometryReader { g in
            let image = ViewfinderGeometry.imageRect(imageAspect: aspect, in: g.size)
            Path { path in
                for cell in area.cells {
                    path.addRect(CGRect(x: image.minX + cell.minX * image.width, y: image.minY + cell.minY * image.height,
                                        width: cell.width * image.width, height: cell.height * image.height))
                }
            }.stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: area.mode.isFlexible ? [6, 3] : []))
        }.allowsHitTesting(false).accessibilityElement(children: .ignore)
            .accessibilityIdentifier("focus.areaFrame").accessibilityLabel(area.mode.rawValue)
            .accessibilityValue(String(format: "%.3f,%.3f,%.3f,%.3f", area.bounds.minX, area.bounds.minY, area.bounds.width, area.bounds.height))
    }
}
