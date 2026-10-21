import SwiftUI

struct CameraSettingsView: View {
    @ObservedObject var camera: CameraController
    let quick: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var selectedRow = "拍攝模式"
    private let tabs = ["拍攝", "AF", "顯示", "設定", "我的選單"]
    private let colors: [Color] = [.red, .purple, .yellow, .orange, .green]

    private func setting<T>(_ keyPath: WritableKeyPath<CameraSettings, T>) -> Binding<T> {
        Binding(get: { camera.settings[keyPath: keyPath] }, set: { value in camera.update { $0[keyPath: keyPath] = value } })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MENU").font(.system(size: 20, weight: .bold, design: .monospaced))
                Spacer()
                Button("返回拍攝") { dismiss() }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 12).frame(height: 34)
                    .overlay(Rectangle().stroke(.white.opacity(0.7)))
            }.buttonStyle(.plain).padding(.horizontal, 18).frame(height: 48)
            VStack(spacing: 0) {
                if !quick {
                    HStack(spacing: 0) {
                        ForEach(tabs.indices, id: \.self) { index in
                            Button {
                                tab = index
                                selectedRow = index == 1 ? "對焦操作" : "拍攝模式"
                            } label: {
                                Text(tabs[index]).font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .foregroundColor(tab == index ? .black : colors[index])
                                    .background(Rectangle().fill(tab == index ? colors[index] : .black))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if quick || tab == 0 { shooting }
                        if quick || tab == 1 { autofocus }
                        if !quick && tab == 2 { display }
                        if !quick && tab == 3 { system }
                        if !quick && tab == 4 { presets }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                }
                .background(.black)
                .tint(quick ? .yellow : colors[tab])
            }
        }.background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private var shooting: some View {
        Group {
            Section("曝光") {
                Picker("拍攝模式", selection: setting(\.program)) {
                    ForEach(ExposureProgram.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                LabeledContent("Av · 光圈先決", value: String(format: "F%.1f 固定", camera.aperture)).foregroundStyle(.gray)
                Text("此鏡頭無可變光圈；Av 不提供實體光圈控制。").font(.caption).foregroundStyle(.secondary)
                if camera.settings.program == .flexible {
                    Toggle("自動快門", isOn: setting(\.autoShutter))
                    Toggle("自動 ISO", isOn: setting(\.autoISO))
                }
                if camera.settings.controlsShutter {
                    menuPicker("快門", values: CameraSettings.shutterSpeeds, selection: setting(\.shutterSeconds), title: CameraSettings.shutterLabel)
                    Text("超出鏡頭支援範圍時會限制至實際可用值；拍攝畫面顯示實測值。").font(.caption).foregroundStyle(.secondary)
                }
                if camera.settings.controlsISO {
                    menuPicker("ISO", values: CameraSettings.isoValues, selection: setting(\.iso), title: { "\(Int($0))" })
                }
                LabeledContent("曝光補償", value: String(format: "%+.1f EV", camera.settings.exposureBias))
                Slider(value: setting(\.exposureBias), in: -3...3, step: 1.0/3)
                Toggle("自動曝光鎖", isOn: Binding(get: { camera.exposureLocked }, set: { _ in camera.toggleExposureLock() }))
            }
            Section("影像與色彩") {
                menuPicker("影像畫質", values: PhotoFormat.allCases.filter { camera.supportsRAW || $0 != .raw }, selection: setting(\.format), title: { $0.rawValue })
                if !camera.supportsRAW { Text("目前鏡頭配置不支援 RAW。").font(.caption).foregroundStyle(.secondary) }
                menuPicker("白平衡", values: WhiteBalance.allCases, selection: setting(\.whiteBalance), title: { $0.rawValue })
                if camera.settings.whiteBalance == .custom {
                    LabeledContent("色溫", value: "\(Int(camera.settings.kelvin)) K")
                    Slider(value: setting(\.kelvin), in: 2500...10000, step: 100)
                }
                menuPicker("相片風格 · 近似", values: PictureStyle.allCases, selection: setting(\.style), title: { $0.rawValue })
                if !quick {
                    parameter("對比", \.contrast)
                    parameter("飽和度", \.saturation)
                    parameter("銳利度", \.sharpness, range: 0...4)
                    parameter("色調", \.hue)
                    Text("風格是自行調校的近似效果；RAW 不套用風格。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("驅動") {
                menuPicker("拍攝模式", values: DriveMode.allCases, selection: setting(\.drive), title: { $0.rawValue })
                Toggle("鎖定目前鏡頭", isOn: setting(\.lockLens))
                Text("連拍以裝置實際處理速度為準，不模擬 R6 III 的每秒張數。鎖鏡頭時縮放可能採用裁切。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var autofocus: some View {
        Group {
            Section("自動對焦／主體追蹤") {
                menuPicker("對焦操作", values: AutofocusMode.allCases, selection: setting(\.autofocus), title: { $0.rawValue })
                menuPicker("要偵測的主體", values: SubjectMode.allCases, selection: setting(\.subjects), title: { $0.rawValue })
                menuPicker("眼睛偵測", values: EyePriority.allCases, selection: setting(\.eyes), title: { $0.rawValue })
                Text("人物、狗／貓可偵測眼睛。鳥、馬與車輛使用主體框；無可靠眼睛位置時退回主體對焦。").font(.caption).foregroundStyle(.secondary)
                Text("點選主體鎖定；失去目標後不自動跳到旁人，請點選重新鎖定。綠框表示鏡頭完成單次 AF 程序，並非眼部銳利度保證。").font(.caption).foregroundStyle(.secondary)
                parameter("遮擋寬限（秒）", \.trackingStickiness, range: 0.2...2)
                parameter("主體切換靈敏度", \.switchSensitivity, range: 0...1)
                Button("解除追蹤鎖定") { camera.unlockTracking() }
            }
            if camera.settings.autofocus == .manual {
                Section("手動對焦") {
                    Slider(value: setting(\.manualFocus), in: 0...1)
                    Toggle("峰值邊緣輔助", isOn: setting(\.peaking))
                    Text("拍攝畫面右下角可切換 3× 顯示放大；不影響成片。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var display: some View {
        Section("拍攝資訊顯示") {
            Toggle("格線", isOn: setting(\.grid))
            Toggle("亮度直方圖", isOn: setting(\.histogram))
            menuPicker("拍後檢視", values: [0, 2, 4], selection: setting(\.reviewSeconds), title: { $0 == 0 ? "關閉" : "\($0) 秒" })
            Text("直方圖以預覽影像計算。INFO 可切換資訊顯示。").font(.caption)
        }
    }
    private var system: some View {
        Section("iPhone 拍攝操作") {
            LabeledContent("原生縮放", value: camera.supportsNativeZoom ? "可用" : "未啟用／不支援")
            Text("實體相機鍵放開拍照，連拍模式按住連拍。相機鍵半按事件尚無已驗證的公開 API，請使用 AF-ON 或點選對焦。").font(.caption)
            Text("照片先存 App，再加入相簿；未允許相簿權限時仍可由回放分享。RAW 與 JPEG 成對保存。").font(.caption)
            Button("開啟 iPhone 設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("重設拍攝設定", role: .destructive) { camera.update { $0 = CameraSettings() }; camera.setZoom(1) }
        }
    }
    private var presets: some View {
        Section("自訂拍攝模式") {
            ForEach(["C1", "C2", "C3"], id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Button("載入") { camera.recallPreset(name) }
                    Button("儲存目前設定") { camera.savePreset(name) }
                }.buttonStyle(.borderless)
            }
        }
    }
    private func parameter(_ title: String, _ path: WritableKeyPath<CameraSettings, Double>, range: ClosedRange<Double> = -4...4) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: String(format: "%.1f", camera.settings[keyPath: path]))
            Slider(value: setting(path), in: range)
        }
    }
    private func menuPicker<T: Hashable>(_ name: String, values: [T], selection: Binding<T>, title: @escaping (T) -> String) -> some View {
        let accent = colors[tab]
        return Menu {
            ForEach(values, id: \.self) { value in
                Button {
                    selectedRow = name
                    selection.wrappedValue = value
                } label: {
                    if selection.wrappedValue == value { Label(title(value), systemImage: "checkmark") }
                    else { Text(title(value)) }
                }
            }
        } label: {
            HStack {
                Text(name).foregroundStyle(.white)
                Spacer()
                Text(title(selection.wrappedValue)).foregroundStyle(selectedRow == name ? accent : .white)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.gray)
            }
            .padding(.horizontal, 12).frame(minHeight: 42)
            .background(selectedRow == name ? accent.opacity(0.13) : Color(white: 0.055))
            .overlay(Rectangle().stroke(selectedRow == name ? accent : Color(white: 0.2), lineWidth: selectedRow == name ? 2 : 1))
        }
        .buttonStyle(.plain).accessibilityIdentifier("menu.\(name)")
    }
}
