import SwiftUI

/// Secondary editor families follow manual pp.100, 275–279, 319, 495 and 516.
struct CameraControlEditor: View {
    @ObservedObject var camera: CameraController
    let control: CameraControl
    let close: () -> Void
    private var accent: Color { control.isAF ? .purple : .yellow }
    private var horizontal: Bool { [.autofocus, .mode, .shutter, .iso, .drive, .format].contains(control) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(control.rawValue).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "arrow.uturn.backward") }.frame(width: 44, height: 36)
                    .accessibilityIdentifier("editor.back")
            }.padding(.horizontal, 16).frame(height: 40)
            Rectangle().fill(accent).frame(height: 2)
            Text(description).font(.system(size: 12)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 28).background(Color(white: 0.22))
            if let range = numericRange {
                VStack(spacing: 12) {
                    Text(control.value(camera.settings)).font(.system(size: 23, weight: .medium, design: .monospaced))
                    Slider(value: numericBinding, in: range, step: step).tint(accent)
                        .accessibilityIdentifier("editor.slider")
                }.padding(20)
            } else if control == .whiteBalance {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(options) { option in choice(option) }
                }.padding(12)
                if camera.settings.whiteBalance == .custom {
                    HStack {
                        Text("\(Int(camera.settings.kelvin)) K").font(.system(size: 13, design: .monospaced))
                        Slider(value: Binding(get: { camera.settings.kelvin }, set: { v in camera.update { $0.kelvin = v } }), in: 2500...10000, step: 100).tint(.yellow)
                    }.padding(.horizontal, 16).padding(.bottom, 8)
                }
            } else if horizontal {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(options) { option in choice(option) } }.padding(12)
                }
            } else {
                ScrollView {
                    VStack(spacing: 2) { ForEach(options) { option in choice(option) } }.padding(12)
                }
            }
            HStack {
                Text("目前：\(control.value(camera.settings))").font(.system(size: 11)).foregroundStyle(.gray)
                Spacer()
                Button(action: close) { Text("SET  確認").padding(.horizontal, 12).frame(height: 32).overlay(Rectangle().stroke(.white.opacity(0.6))) }
                    .accessibilityIdentifier("editor.confirm")
            }.padding(.horizontal, 16).padding(.bottom, 8)
        }
        .foregroundStyle(.white).background(.black.opacity(control == .whiteBalance ? 0.87 : 0.98))
        .overlay(Rectangle().stroke(.white.opacity(0.3)))
        .buttonStyle(.plain)
    }
    private func choice(_ option: CameraChoice) -> some View {
        Button(action: option.action) {
            HStack(spacing: 12) {
                if control == .style, let style = PictureStyle.allCases.first(where: { $0.rawValue == option.title }) {
                    CanonGlyph(kind: .style, label: style.cameraCode)
                }
                if control == .whiteBalance { Image(systemName: option.symbol).font(.system(size: 18)) }
                Text(option.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if !horizontal && control != .whiteBalance { Spacer(minLength: 2) }
                if control == .eye {
                    CanonGlyph(kind: .eye)
                    Text(option.eyeCode).font(.system(size: 11, weight: .bold)).frame(width: 34)
                }
            }
            .foregroundStyle(option.selected ? Color.cyan : .white)
            .padding(.horizontal, 12).frame(minWidth: horizontal ? 86 : 0, minHeight: 34)
            .frame(maxWidth: horizontal ? nil : .infinity)
            .background(option.selected ? Color(white: 0.1) : Color(white: 0.055))
            .overlay(Rectangle().stroke(option.selected ? accent : Color(white: 0.25), lineWidth: option.selected ? 2 : 1))
        }.accessibilityIdentifier("option.\(option.title)")
    }
    private var description: String {
        switch control {
        case .autofocus: return "待選時基本自動對焦；觸控指定追焦，空白處單次對焦"
        case .subject: return "白框提示候選，不控制對焦位置；觸控後指定追焦"
        case .eye: return "指定主體優先：眼睛 → 頭部 → 身體"
        case .style: return "獨立調校的近似風格；RAW 保留原始資料"
        case .manualFocus: return "手動調整鏡頭焦距；不改變倍率"
        case .lens: return "鎖定時可用數位裁切縮放；不強制切換鏡頭"
        case .area: return "固定全區域辨識；觸控指定主體或單次對焦位置，不提供 Canon 彈性區域"
        case .meter: return "使用 iPhone 系統測光，不提供 Canon 權衡／點測光切換"
        default: return control.rawValue
        }
    }
    private func values<T: Hashable>(_ list: [T], selected: T, title: @escaping (T) -> String, action: @escaping (T) -> Void) -> [CameraChoice] {
        list.map { value in CameraChoice(title: title(value), selected: value == selected, action: { action(value) }) }
    }
    private var options: [CameraChoice] {
        let s = camera.settings
        switch control {
        case .mode: return values(ExposureProgram.allCases, selected: s.program, title: { $0.rawValue }) { v in camera.update { $0.program = v } }
        case .autofocus: return values([AutofocusMode.servo, .manual], selected: s.autofocus, title: { $0.rawValue }) { v in camera.update { $0.autofocus = v } }
        case .subject: return values(SubjectMode.allCases, selected: s.subjects, title: { $0.rawValue }) { v in camera.update { $0.subjects = v } }
        case .eye: return values([EyePriority.off, .automatic, .right, .left], selected: s.eyes, title: { $0.rawValue }) { v in camera.update { $0.eyes = v } }
        case .drive: return values(DriveMode.allCases, selected: s.drive, title: { $0.rawValue }) { v in camera.update { $0.drive = v } }
        case .whiteBalance: return values(WhiteBalance.allCases, selected: s.whiteBalance, title: { $0.rawValue }) { v in camera.update { $0.whiteBalance = v } }
        case .style: return values(PictureStyle.allCases, selected: s.style, title: { $0.rawValue }) { v in camera.update { $0.style = v } }
        case .format: return values(PhotoFormat.allCases.filter { camera.supportsRAW || $0 != .raw }, selected: s.format, title: { $0.rawValue }) { v in camera.update { $0.format = v } }
        case .lens: return values([false, true], selected: s.lockLens, title: { $0 ? "鎖定" : "自動" }) { v in camera.update { $0.lockLens = v } }
        case .area, .meter: return [CameraChoice(title: control.value(s), selected: true, action: {})]
        case .shutter:
            var result = values(CameraSettings.shutterSpeeds, selected: s.shutterSeconds, title: CameraSettings.shutterLabel) { v in
                camera.update { $0.shutterSeconds = v; if $0.program == .flexible { $0.autoShutter = false } else if $0.program != .manual { $0.program = .shutterPriority } }
            }
            result.insert(CameraChoice(title: "AUTO", selected: !s.controlsShutter) { camera.update { $0.useAutomaticShutter() } }, at: 0)
            return result
        case .iso:
            var result = values(CameraSettings.isoValues, selected: s.iso, title: { "\(Int($0))" }) { v in
                camera.update { $0.iso = v; if $0.program == .flexible { $0.autoISO = false } else { $0.program = .manual } }
            }
            result.insert(CameraChoice(title: "AUTO", selected: !s.controlsISO) { camera.update { $0.useAutomaticISO() } }, at: 0)
            return result
        default: return []
        }
    }
    private var numericRange: ClosedRange<Double>? {
        switch control {
        case .exposure: return -3...3
        case .kelvin: return 2500...10000
        case .manualFocus, .sensitivity: return 0...1
        case .stickiness: return 0.2...2
        case .sharpness: return 0...4
        case .contrast, .saturation, .hue: return -4...4
        default: return nil
        }
    }
    private var step: Double {
        switch control { case .kelvin: return 100; case .exposure: return 1.0 / 3; case .manualFocus: return 0.01; default: return 0.1 }
    }
    private var numericBinding: Binding<Double> {
        Binding(get: {
            let s = camera.settings
            switch control {
            case .exposure: return s.exposureBias
            case .kelvin: return s.kelvin
            case .manualFocus: return Double(s.manualFocus)
            case .stickiness: return s.trackingStickiness
            case .sensitivity: return s.switchSensitivity
            case .contrast: return s.contrast
            case .saturation: return s.saturation
            case .sharpness: return s.sharpness
            case .hue: return s.hue
            default: return 0
            }
        }, set: { v in camera.update {
            switch control {
            case .exposure: $0.exposureBias = v
            case .kelvin: $0.kelvin = v; $0.whiteBalance = .custom
            case .manualFocus: $0.manualFocus = Float(v); $0.autofocus = .manual
            case .stickiness: $0.trackingStickiness = v
            case .sensitivity: $0.switchSensitivity = v
            case .contrast: $0.contrast = v
            case .saturation: $0.saturation = v
            case .sharpness: $0.sharpness = v
            case .hue: $0.hue = v
            default: break
            }
        } })
    }
}

private struct CameraChoice: Identifiable {
    let title: String
    let selected: Bool
    let action: () -> Void
    var id: String { title }
    var symbol: String {
        switch title { case "AWB": return "a.square"; case "日光": return "sun.max"; case "陰影": return "house"; case "鎢絲燈": return "lightbulb"; default: return "k.square" }
    }
    var eyeCode: String {
        switch title { case "關閉": return "OFF"; case "右眼優先": return "R"; case "左眼優先": return "L"; default: return "AUTO" }
    }
}
