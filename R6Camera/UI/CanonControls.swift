import SwiftUI

/// Clean, code-native camera marks. Shapes are referenced in docs/research/canon-ui-reference.md.
struct CanonGlyph: View {
    enum Kind { case area, style, meter, eye, subject, quality, drive }
    let kind: Kind
    var label = ""
    var area: FocusAreaMode = .whole
    var body: some View {
        ZStack {
            switch kind {
            case .area:
                FocusAreaGlyph(mode: area)
            case .style:
                Rectangle().stroke(lineWidth: 1)
                HStack(spacing: 2) {
                    StyleMark().fill().frame(width: 13, height: 15)
                    Text(label.isEmpty ? "S" : label).font(.system(size: 15, weight: .bold))
                }.padding(2)
            case .meter:
                Rectangle().stroke(lineWidth: 1).padding(2)
                Circle().stroke(lineWidth: 1.2).frame(width: 11, height: 11)
                Circle().frame(width: 3, height: 3)
            case .eye:
                EyeMark().stroke(lineWidth: 1.2).padding(.horizontal, 2).padding(.vertical, 6)
                Circle().frame(width: 5, height: 5)
            case .subject:
                // Text remains unambiguous where the manual does not establish an exact animal glyph.
                Text(label.isEmpty ? "AUTO" : label).font(.system(size: 10, weight: .bold)).lineLimit(1)
                    .padding(3).overlay(Rectangle().stroke(lineWidth: 1))
            case .quality:
                HStack(spacing: 2) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 17)); p.addQuadCurve(to: CGPoint(x: 15, y: 2), control: CGPoint(x: 0, y: 2))
                        p.addLine(to: CGPoint(x: 15, y: 17)); p.closeSubpath()
                    }.fill().frame(width: 15, height: 20)
                    Text(label.isEmpty ? "L" : label).font(.system(size: 15, weight: .bold))
                }
            case .drive:
                HStack(spacing: 2) {
                    Image(systemName: label.hasPrefix("10") || label == "2" ? "timer" : label.isEmpty ? "rectangle" : "rectangle.on.rectangle").font(.system(size: 18))
                    if !label.isEmpty { Text(label).font(.system(size: 10, weight: .bold)).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                }
            }
        }.frame(width: glyphWidth, height: 24).accessibilityHidden(true)
    }
    private var glyphWidth: CGFloat { if case .drive = kind { return 52 }; return 31 }
}
private struct StyleMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(ellipseIn: CGRect(x: r.midX - 1.6, y: r.midY - 1.6, width: 3.2, height: 3.2))
        for angle in stride(from: CGFloat(0), to: .pi * 2, by: .pi / 2) {
            let x = r.midX + cos(angle) * 5, y = r.midY + sin(angle) * 5
            p.addRect(CGRect(x: x - 1.2, y: y - 1, width: 2.4, height: 2))
        }
        return p
    }
}

struct FocusCorners: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let d = min(r.width, r.height) * 0.27
        for (x, y, dx, dy) in [(r.minX,r.minY,d,d), (r.maxX,r.minY,-d,d), (r.minX,r.maxY,d,-d), (r.maxX,r.maxY,-d,-d)] {
            p.move(to: CGPoint(x: x + dx, y: y)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + dy))
        }
        return p
    }
}
private struct EyeMark: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY))
        }
    }
}

extension PictureStyle {
    var cameraCode: String {
        switch self { case .standard: return "S"; case .portrait: return "P"; case .landscape: return "L"
        case .neutral: return "N"; case .faithful: return "F"; case .mono: return "M" }
    }
}

struct CameraMarkButton<Content: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Button(action: action) { content().frame(minWidth: 42, minHeight: 32).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(title)
    }
}
