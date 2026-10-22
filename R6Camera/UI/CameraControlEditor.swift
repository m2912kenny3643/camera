import SwiftUI

/// Manual editor families: pending choices, SET to apply, back to cancel.
struct CameraControlEditor: View {
    @ObservedObject var camera: CameraController
    let control: CameraControl
    let close: () -> Void
    let palette: Bool
    @State private var draft: CameraSettings
    init(camera: CameraController, control: CameraControl, palette: Bool = false, close: @escaping () -> Void) {
        self.camera = camera; self.control = control; self.palette = palette; self.close = close
        _draft = State(initialValue: camera.settings)
    }
    private var accent: Color { palette ? .yellow : control.isAF ? Color(red: 0.92, green: 0.1, blue: 0.58) : .red }
    private var horizontal: Bool { palette || [.autofocus, .mode, .shutter, .iso, .drive, .level].contains(control) }
    private var editable: Bool { control.isEditable(camera.settings) }
    var body: some View {
        VStack(spacing: 0) {
            if !palette {
                HStack {
                    Text(control.rawValue).font(.system(size: 19, weight: .semibold)); Spacer()
                    Button(action: close) { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 34) }.accessibilityIdentifier("editor.back")
                }.padding(.horizontal, 20).frame(height: 43)
                Rectangle().fill(accent).frame(height: 2)
            }
            HStack {
                Text(editable ? selectionTitle : "目前模式自動控制此項目"); Spacer()
                if palette { Button(action: close) { Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 28) }.accessibilityIdentifier("editor.back") }
            }.font(.system(size: 13)).padding(.horizontal, 16).frame(minHeight: 30).background(Color(white: palette ? 0.08 : 0.2).opacity(0.9))
            if editable {
                if let range = numericRange {
                    VStack(spacing: 8) {
                        Text(control.value(draft)).font(.system(size: 22, weight: .medium, design: .monospaced))
                        Slider(value: numericBinding, in: range, step: step).tint(accent).accessibilityIdentifier("editor.slider")
                    }.padding(.horizontal, 24).padding(.vertical, 8)
                } else if control == .format { qualityOptions }
                else {
                    ScrollView(horizontal ? .horizontal : .vertical, showsIndicators: false) {
                        if horizontal { HStack(spacing: 6) { ForEach(options) { choice($0) } }.padding(10) }
                        else { VStack(spacing: 3) { ForEach(options) { choice($0) } }.padding(.horizontal, 20).padding(.vertical, 8) }
                    }.frame(maxHeight: palette ? 64 : horizontal ? 80 : .infinity).accessibilityIdentifier("editor.options")
                }
                if control == .whiteBalance && draft.whiteBalance == .custom {
                    HStack { Text("\(Int(draft.kelvin)) K").monospacedDigit(); Slider(value: $draft.kelvin, in: 2500...10000, step: 100).tint(.yellow) }.font(.system(size: 13)).padding(.horizontal, 20)
                }
                if control == .drive && draft.drive == .timerContinuous {
                    Stepper("連拍張數  \(draft.timerCount)", value: $draft.timerCount, in: 2...10).font(.system(size: 13)).padding(.horizontal, 20).accessibilityIdentifier("drive.timerCount").accessibilityValue(String(draft.timerCount))
                }
            } else {
                Text(draft.program == .auto ? "選擇 P／Tv／M／Fv 可調整" : "手動 ISO 的 M 模式顯示測光偏差").font(.system(size: 14)).frame(maxWidth: .infinity, minHeight: 54)
            }
            if !palette { Spacer(minLength: 0) }
            HStack {
                if !palette || control == .drive { Text(detail).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(2) }
                Spacer()
                Button {
                    if editable { camera.update { control.apply(draft, to: &$0) } }
                    close()
                } label: { Text("SET  OK").font(.system(size: 13)).padding(.horizontal, 12).frame(height: 31).overlay(Rectangle().stroke(.white.opacity(0.6))) }.accessibilityIdentifier("editor.confirm")
            }.padding(.horizontal, 20).padding(.vertical, 6)
        }.foregroundStyle(.white).background(Color.black.opacity(palette ? 0.6 : 1)).buttonStyle(.plain)
    }
    private var selectionTitle: String {
        let value = control == .drive && draft.drive.isBurst ? "\(draft.drive.label)（上限 \(Int(draft.drive.fps)) 張／秒）" : control.value(draft)
        return "\(control.rawValue)：\(value)"
    }
    private var qualityOptions: some View {
        VStack(spacing: 12) {
            HStack {
                Text("RAW").frame(width: 72, alignment: .leading)
                qualityChoice("—", selected: draft.format != .raw) { if draft.format == .raw { draft.format = .jpeg } }
                if camera.supportsRAW { qualityChoice("DNG＋JPEG", selected: draft.format == .raw) { draft.format = .raw } }
                Spacer()
            }
            HStack {
                Text("影像").frame(width: 72, alignment: .leading)
                qualityChoice("HEIF", selected: draft.format == .heif) { draft.format = .heif }
                qualityChoice("JPEG", selected: draft.format != .heif) { if draft.format != .raw { draft.format = .jpeg } }; Spacer()
            }
            Text(camera.photoResolution.map { "\($0) · 目前鏡頭最大尺寸" } ?? "影像尺寸依目前鏡頭配置").foregroundStyle(.gray).font(.system(size: 12))
        }.font(.system(size: 16)).padding(24)
    }
    private func qualityChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).padding(10).foregroundStyle(selected ? Color.cyan : .white).overlay(Rectangle().stroke(selected ? accent : .gray, lineWidth: selected ? 2 : 1)) }.accessibilityIdentifier("option.\(title)")
    }
    private func choice(_ option: CameraChoice) -> some View {
        Button(action: option.action) {
            HStack(spacing: 10) {
                if control == .style, let style = PictureStyle.allCases.first(where: { $0.rawValue == option.title }) { CanonGlyph(kind: .style, label: style.cameraCode) }
                if control == .drive, let mode = DriveMode.allCases.first(where: { $0.label == option.title }) { CanonGlyph(kind: .drive, label: mode.code) }
                if control == .whiteBalance { Image(systemName: option.symbol).font(.system(size: 18)) }
                Text(option.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if !horizontal { Spacer(minLength: 2) }
                if control == .eye { CanonGlyph(kind: .eye); Text(option.eyeCode).font(.system(size: 11, weight: .bold)).frame(width: 34) }
                if control == .style { Text(String(format: "%.0f  %+.0f  %+.0f  %+.0f", draft.sharpness, draft.contrast, draft.saturation, draft.hue)).font(.system(size: 12, design: .monospaced)) }
            }.foregroundStyle(option.selected ? Color.cyan : .white).padding(.horizontal, 12).frame(minWidth: horizontal ? 80 : 0, minHeight: 34).frame(maxWidth: horizontal ? nil : .infinity)
                .background(option.selected ? Color.black : Color(white: 0.12)).overlay(Rectangle().stroke(option.selected ? accent : Color(white: 0.3), lineWidth: option.selected ? 2 : 1))
        }.accessibilityIdentifier("option.\(option.title)").accessibilityValue(option.selected ? "已選取" : "")
    }
    private var detail: String {
        switch control {
        case .autofocus: return "ONE SHOT 單次合焦；SERVO 指定主體持續追焦。MF 另行設定。"
        case .subject: return "觸控前白框候選；點選後指定藍框目標"
        case .eye: return "可靠眼睛 → 可靠頭部 → 身體；只顯示一個框"
        case .drive: return "保留所選畫質；依曝光與緩衝狀態降速"
        case .style: return "獨立調校風格；RAW 保留原始資料"
        case .level: return "INFO 切換電子水平儀；感測器不可用時不顯示"
        case .area: return "全區域辨識，觸控指定"
        case .meter: return "iPhone 系統測光"
        default: return "返回取消 · SET 套用"
        }
    }
    private func edit(_ change: (inout CameraSettings) -> Void) { change(&draft) }
    private func values<T: Hashable>(_ list: [T], selected: T, title: @escaping (T) -> String, action: @escaping (T) -> Void) -> [CameraChoice] {
        list.map { value in CameraChoice(title: title(value), selected: value == selected, action: { action(value) }) }
    }
    private var options: [CameraChoice] {
        let s = draft.effective
        switch control {
        case .mode: return values(ExposureProgram.allCases, selected: s.program, title: { $0.rawValue }) { v in edit { $0.program = v } }
        case .autofocus: return values([AutofocusMode.single, .servo], selected: s.autofocus, title: { $0.rawValue }) { v in edit { $0.autofocus = v } }
        case .subject: return values(SubjectMode.allCases, selected: s.subjects, title: { $0.rawValue }) { v in edit { $0.subjects = v } }
        case .eye: return values([EyePriority.off, .automatic, .right, .left], selected: s.eyes, title: { $0.rawValue }) { v in edit { $0.eyes = v } }
        case .drive: return values(DriveMode.allCases, selected: s.drive, title: { $0.label }) { v in edit { $0.drive = v } }
        case .whiteBalance: return values(WhiteBalance.allCases, selected: s.whiteBalance, title: { $0.rawValue }) { v in edit { $0.whiteBalance = v } }
        case .style: return values(PictureStyle.allCases, selected: s.style, title: { $0.rawValue }) { v in edit { $0.style = v } }
        case .lens: return values([false, true], selected: s.lockLens, title: { $0 ? "鎖定" : "自動" }) { v in edit { $0.lockLens = v } }
        case .level: return values(LevelSize.allCases, selected: s.levelSize, title: { $0.rawValue }) { v in edit { $0.levelSize = v } }
        case .area, .meter: return [CameraChoice(title: control.value(s), selected: true, action: {})]
        case .shutter:
            var result = values(CameraSettings.shutterSpeeds, selected: s.shutterSeconds, title: CameraSettings.shutterLabel) { v in edit { $0.shutterSeconds = v; if $0.program == .flexible { $0.autoShutter = false } else if $0.program != .manual { $0.program = .shutterPriority } } }
            result.insert(CameraChoice(title: "AUTO", selected: !s.controlsShutter) { edit { $0.useAutomaticShutter() } }, at: 0); return result
        case .iso:
            var result = values(CameraSettings.isoValues, selected: s.iso, title: { "\(Int($0))" }) { v in edit { $0.selectISO(v) } }
            result.insert(CameraChoice(title: "AUTO", selected: !s.controlsISO) { edit { $0.useAutomaticISO() } }, at: 0); return result
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
    private var step: Double { control == .kelvin ? 100 : control == .exposure ? 1.0/3 : control == .manualFocus ? 0.01 : 0.1 }
    private var numericBinding: Binding<Double> {
        Binding(get: {
            switch control {
            case .exposure: return draft.exposureBias
            case .kelvin: return draft.kelvin
            case .manualFocus: return Double(draft.manualFocus)
            case .stickiness: return draft.trackingStickiness
            case .sensitivity: return draft.switchSensitivity
            case .contrast: return draft.contrast
            case .saturation: return draft.saturation
            case .sharpness: return draft.sharpness
            case .hue: return draft.hue
            default: return 0
            }
        }, set: { v in edit {
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
    var symbol: String { switch title { case "AWB": return "a.square"; case "日光": return "sun.max"; case "陰影": return "house"; case "鎢絲燈": return "lightbulb"; default: return "k.square" } }
    var eyeCode: String { switch title { case "關閉": return "OFF"; case "右眼優先": return "R"; case "左眼優先": return "L"; default: return "AUTO" } }
}
