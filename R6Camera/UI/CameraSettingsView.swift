import SwiftUI

struct CameraSettingsView: View {
    @ObservedObject var camera: CameraController
    let quick: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    private let tabs = ["拍攝", "AF", "顯示", "設定", "我的選單"]
    private let colors: [Color] = [.red, .purple, .yellow, .orange, .green]
    private static let shutterSpeeds: [Double] = [8000.0, 4000, 2000, 1000, 500, 250, 125, 60, 30, 15, 8, 4, 2, 1].map { 1.0 / $0 }

    private func setting<T>(_ keyPath: WritableKeyPath<CameraSettings, T>) -> Binding<T> {
        Binding(get: { camera.settings[keyPath: keyPath] }, set: { value in camera.update { $0[keyPath: keyPath] = value } })
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !quick {
                    HStack(spacing: 0) {
                        ForEach(tabs.indices, id: \.self) { index in
                            Button { tab = index } label: {
                                Text(tabs[index]).font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .foregroundStyle(tab == index ? .black : colors[index])
                                    .background(tab == index ? colors[index] : .black)
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
                .pickerStyle(.menu)
                .tint(quick ? .yellow : colors[tab])
            }
            .navigationTitle(quick ? "Q · 速控" : "MENU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("返回拍攝") { dismiss() } } }
        }.preferredColorScheme(.dark)
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
                    Picker("快門", selection: setting(\.shutterSeconds)) {
                        ForEach(Self.shutterSpeeds, id: \.self) {
                            Text(CameraSettings.shutterLabel($0)).tag($0)
                        }
                    }
                    Text("超出鏡頭支援範圍時會限制至實際可用值；拍攝畫面顯示實測值。").font(.caption).foregroundStyle(.secondary)
                }
                if camera.settings.controlsISO {
                    Picker("ISO", selection: setting(\.iso)) {
                        ForEach([50.0, 100, 200, 400, 800, 1600, 3200], id: \.self) { Text("\(Int($0))").tag($0) }
                    }
                }
                LabeledContent("曝光補償", value: String(format: "%+.1f EV", camera.settings.exposureBias))
                Slider(value: setting(\.exposureBias), in: -3...3, step: 1.0/3)
                Toggle("自動曝光鎖", isOn: Binding(get: { camera.exposureLocked }, set: { _ in camera.toggleExposureLock() }))
            }
            Section("影像與色彩") {
                Picker("影像畫質", selection: setting(\.format)) {
                    Text("HEIF").tag(PhotoFormat.heif)
                    Text("JPEG").tag(PhotoFormat.jpeg)
                    if camera.supportsRAW { Text("RAW＋JPEG").tag(PhotoFormat.raw) }
                }
                if !camera.supportsRAW { Text("目前鏡頭配置不支援 RAW。").font(.caption).foregroundStyle(.secondary) }
                Picker("白平衡", selection: setting(\.whiteBalance)) {
                    ForEach(WhiteBalance.allCases) { Text($0.rawValue).tag($0) }
                }
                if camera.settings.whiteBalance == .custom {
                    LabeledContent("色溫", value: "\(Int(camera.settings.kelvin)) K")
                    Slider(value: setting(\.kelvin), in: 2500...10000, step: 100)
                }
                Picker("相片風格 · 近似", selection: setting(\.style)) {
                    ForEach(PictureStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                if !quick {
                    parameter("對比", \.contrast)
                    parameter("飽和度", \.saturation)
                    parameter("銳利度", \.sharpness, range: 0...4)
                    parameter("色調", \.hue)
                    Text("風格是自行調校的近似效果；RAW 不套用風格。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("驅動") {
                Picker("拍攝模式", selection: setting(\.drive)) {
                    ForEach(DriveMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("鎖定目前鏡頭", isOn: setting(\.lockLens))
                Text("連拍以裝置實際處理速度為準，不模擬 R6 III 的每秒張數。鎖鏡頭時縮放可能採用裁切。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var autofocus: some View {
        Group {
            Section("自動對焦／主體追蹤") {
                Picker("對焦操作", selection: setting(\.autofocus)) {
                    ForEach(AutofocusMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("要偵測的主體", selection: setting(\.subjects)) {
                    ForEach(SubjectMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("眼睛偵測", selection: setting(\.eyes)) {
                    ForEach(EyePriority.allCases) { Text($0.rawValue).tag($0) }
                }
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
            Picker("拍後檢視", selection: setting(\.reviewSeconds)) {
                Text("關閉").tag(0)
                Text("2 秒").tag(2)
                Text("4 秒").tag(4)
            }
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
}
