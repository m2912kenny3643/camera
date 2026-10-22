import SwiftUI

enum CameraControl: String, CaseIterable, Identifiable {
    case mode = "拍攝模式", shutter = "快門速度", iso = "ISO 感光度", exposure = "曝光補償"
    case autofocus = "自動對焦操作", subject = "要偵測的主體", eye = "眼睛偵測", drive = "驅動模式"
    case whiteBalance = "白平衡", style = "相片風格", format = "影像畫質", lens = "鏡頭切換"
    case kelvin = "色溫", manualFocus = "手動對焦", contrast = "對比", saturation = "飽和度"
    case sharpness = "銳利度", hue = "色調", stickiness = "遮擋寬限", sensitivity = "候選切換靈敏度"
    case area = "自動對焦區域", meter = "測光模式"
    case level = "水平儀顯示大小"
    var id: String { rawValue }
    var isAF: Bool { [.area, .autofocus, .subject, .eye, .manualFocus, .stickiness, .sensitivity].contains(self) }
    func value(_ requested: CameraSettings) -> String {
        let s = requested.effective
        switch self {
        case .mode: return s.program.rawValue
        case .shutter: return s.controlsShutter ? s.shutterLabel : "AUTO"
        case .iso: return s.controlsISO ? "\(Int(s.iso))" : "AUTO"
        case .exposure: return String(format: "%+.1f", s.exposureBias)
        case .autofocus: return s.autofocus.rawValue
        case .subject: return s.subjects.rawValue
        case .eye: return s.eyes.rawValue
        case .drive: return s.drive.label
        case .whiteBalance: return s.whiteBalance.rawValue
        case .style: return s.style.rawValue
        case .format: return s.format.rawValue
        case .lens: return s.lockLens ? "鎖定" : "自動"
        case .kelvin: return "\(Int(s.kelvin)) K"
        case .manualFocus: return String(format: "%.2f", s.manualFocus)
        case .contrast: return String(format: "%+.1f", s.contrast)
        case .saturation: return String(format: "%+.1f", s.saturation)
        case .sharpness: return String(format: "%.1f", s.sharpness)
        case .hue: return String(format: "%+.1f", s.hue)
        case .stickiness: return String(format: "%.1f 秒", s.trackingStickiness)
        case .sensitivity: return String(format: "%.1f", s.switchSensitivity)
        case .area: return "全區域 · 觸控指定"
        case .meter: return "系統測光"
        case .level: return s.levelSize.rawValue
        }
    }
    var isLivePalette: Bool { [.mode, .area, .drive, .whiteBalance, .shutter, .iso, .exposure].contains(self) }
    func isEditable(_ settings: CameraSettings) -> Bool {
        if settings.program == .auto { return [.mode, .drive, .format, .lens, .level].contains(self) }
        return self != .exposure || settings.permitsExposureCompensation
    }
    /// Commit only edited fields; do not overwrite zoom or concurrent changes.
    func apply(_ draft: CameraSettings, to target: inout CameraSettings) {
        switch self {
        case .mode: target.program = draft.program
        case .shutter, .iso:
            target.program = draft.program; target.autoShutter = draft.autoShutter; target.autoISO = draft.autoISO
            target.manualISOAutomatic = draft.manualISOAutomatic
            if self == .shutter { target.shutterSeconds = draft.shutterSeconds } else { target.iso = draft.iso }
        case .exposure: target.exposureBias = draft.exposureBias
        case .autofocus: target.autofocus = draft.autofocus
        case .subject: target.subjects = draft.subjects
        case .eye: target.eyes = draft.eyes
        case .drive: target.drive = draft.drive; target.timerCount = draft.timerCount
        case .whiteBalance, .kelvin: target.whiteBalance = draft.whiteBalance; target.kelvin = draft.kelvin
        case .style: target.style = draft.style
        case .format: target.format = draft.format
        case .lens: target.lockLens = draft.lockLens
        case .manualFocus: target.autofocus = draft.autofocus; target.manualFocus = draft.manualFocus
        case .contrast: target.contrast = draft.contrast
        case .saturation: target.saturation = draft.saturation
        case .sharpness: target.sharpness = draft.sharpness
        case .hue: target.hue = draft.hue
        case .stickiness: target.trackingStickiness = draft.trackingStickiness
        case .sensitivity: target.switchSensitivity = draft.switchSensitivity
        case .level: target.levelSize = draft.levelSize
        case .area, .meter: break
        }
    }
}

/// Clean, code-native camera marks. Shapes are referenced in docs/research/canon-ui-reference.md.
struct CanonGlyph: View {
    enum Kind { case area, style, meter, eye, subject, quality, drive }
    let kind: Kind
    var label = ""
    var body: some View {
        ZStack {
            switch kind {
            case .area:
                FocusCorners().stroke(lineWidth: 1.4).padding(3)
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
