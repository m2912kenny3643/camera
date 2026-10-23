import SwiftUI

struct CameraSettingsView: View {
    @ObservedObject var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var page = 0
    @State private var editor: CameraControl?
    @State private var selected = CameraControl.format.rawValue
    @State private var resetPrompt = false
    @State private var birdTest = false
    @State private var calibratePrompt = false
    private let names = ["拍攝", "AF", "播放", "設定", "自訂", "我的選單"]
    private let symbols = ["camera.fill", "AF", "play.rectangle", "wrench.fill", "camera.badge.ellipsis", "star.fill"]
    private let colors: [Color] = [.red, Color(red: 0.92, green: 0.1, blue: 0.58), .blue, .yellow, .orange, .green]
    private var pages: [[CameraControl]] {
        switch tab {
        case 0: return [[.format, .whiteBalance, .style, .drive, .exposure, .level], [.mode, .shutter, .iso, .kelvin, .lens], [.contrast, .saturation, .sharpness, .hue]]
        case 1: return [[.autofocus, .subject, .eye, .stickiness, .sensitivity], [.manualFocus]]
        default: return [[]]
        }
    }
    private var safePage: Int { min(page, pages.count - 1) }
    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(names.indices, id: \.self) { index in
                        Button { tab = index; page = 0; selected = pages[0].first?.rawValue ?? "" } label: {
                            Group {
                                if index == 1 { Text("AF").font(.system(size: 19, weight: .bold)) }
                                else { Image(systemName: symbols[index]).font(.system(size: 20)) }
                            }.frame(width: 64, height: 36)
                                .foregroundStyle(tab == index ? Color.black : colors[index])
                                .background(tab == index ? colors[index] : .black)
                        }.accessibilityLabel(names[index]).accessibilityIdentifier("menu.tab.\(index)")
                    }
                    Spacer()
                    Text("MENU").font(.system(size: 14, weight: .bold)).foregroundStyle(.gray)
                }
                Rectangle().fill(colors[tab]).frame(height: 2)
                HStack(spacing: 5) {
                    ForEach(pages.indices, id: \.self) { index in
                        Button("\(index + 1)") { page = index; selected = pages[index].first?.rawValue ?? "" }.frame(width: 26, height: 23)
                            .background(safePage == index ? colors[tab].opacity(0.75) : .black)
                    }
                    Spacer()
                    Text(names[tab]).font(.system(size: 12))
                    Text("\(safePage + 1)/\(pages.count)").font(.system(size: 12)).frame(width: 43)
                }.padding(.vertical, 4)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(pages[safePage]) { control in
                            menuRow(control.rawValue, value: control.value(camera.settings)) { selected = control.rawValue; editor = control }
                                .accessibilityIdentifier("menu.\(control.rawValue)")
                        }
                        if tab == 1 {
                            menuRow("鳥眼模型功能測試", value: "固定照片") { birdTest = true }.accessibilityIdentifier("bird.test.open")
                            Text("待選時基本自動對焦；觸控主體藍框追焦，空白處單次對焦。").font(.system(size: 10)).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            Text(camera.birdStatus).font(.system(size: 10)).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading)
                            if safePage == 1 { toggleRow("峰值邊緣輔助", path: \.peaking) }
                            menuRow("解除觸控對焦", value: "清除") { camera.unlockTracking() }
                        }
                        if tab == 3 {
                            toggleRow("實驗性兩段硬體快門", path: \.experimentalHardwareShutter)
                                .accessibilityIdentifier("hardwareShutter.experimental")
                                .accessibilityValue(camera.settings.experimentalHardwareShutter ? "開啟" : "關閉")
                            Text(camera.hardwareControlStatus).font(.system(size: 11)).foregroundStyle(.yellow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("輕按返回拍攝頁面並對焦。浮層啟用期間可重複全按；關閉後保留 300ms。這是浮層代理，不能辨別真實半按或按鍵來源，期間音量減仍可能拍攝。音量加不拍；A+ 固定自動對焦模式。").font(.system(size: 11)).foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ShareLink(item: camera.hardwareShutterReport) {
                                Label("分享硬體快門事件 JSON", systemImage: "square.and.arrow.up")
                            }.font(.system(size: 13)).padding(.vertical, 6).accessibilityIdentifier("hardwareShutter.shareReport")
                            menuRow("連拍穩定速度校準", value: camera.isCalibrating ? "取消" : "開始") {
                                if camera.isCalibrating { camera.cancelBurstCalibration() } else { calibratePrompt = true }
                            }.accessibilityIdentifier("burst.calibrate")
                            Text(camera.calibrationStatus).font(.system(size: 11)).foregroundStyle(.yellow).frame(maxWidth: .infinity, alignment: .leading)
                            if let report = camera.burstReportText {
                                ShareLink(item: report) { Label("分享最近連拍量測 JSON", systemImage: "square.and.arrow.up") }
                                    .font(.system(size: 13)).padding(.vertical, 6).accessibilityIdentifier("burst.shareReport")
                            }
                            toggleRow("格線", path: \.grid)
                            toggleRow("亮度直方圖", path: \.histogram)
                            menuRow(CameraControl.level.rawValue, value: camera.settings.levelSize.rawValue) { editor = .level }.accessibilityIdentifier("menu.水平儀顯示大小")
                            Text("固定橫向 · 相機鍵在上緣").font(.system(size: 11)).foregroundStyle(.gray)
                            menuRow("重設拍攝設定", value: "SET") { resetPrompt = true }
                            menuRow("iPhone 權限設定", value: "開啟") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        }
                        if tab == 2 {
                            menuRow("播放照片", value: "返回主畫面後按 ▶") { dismiss() }
                            Text("拍攝後保持即時取景，僅以四邊白框提示；不顯示照片回顯。").font(.system(size: 11)).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                        if tab == 4 || tab == 5 {
                            ForEach(["C1", "C2", "C3"], id: \.self) { name in
                                HStack(spacing: 3) {
                                    menuRow(name, value: "載入") { camera.recallPreset(name) }
                                    Button("儲存目前設定") { camera.savePreset(name) }.font(.system(size: 12)).frame(width: 125, height: 31).background(Color(white: 0.15))
                                }
                            }
                            Text(camera.status).font(.system(size: 11)).foregroundStyle(.gray)
                        }
                    }.padding(.vertical, 5)
                }
                HStack {
                    Button("MENU  返回") { dismiss() }.accessibilityIdentifier("menu.close")
                    Spacer()
                    Text("輕點項目設定").foregroundStyle(.gray).font(.system(size: 10))
                    Button("SET  確認") { editor = pages[safePage].first { $0.rawValue == selected } }.font(.system(size: 12))
                        .disabled(!pages[safePage].contains { $0.rawValue == selected })
                }.font(.system(size: 12)).frame(height: 31)
            }.padding(.horizontal, max(16, g.size.width * 0.06)).padding(.vertical, 8)
                .background(.black).foregroundStyle(.white).buttonStyle(.plain)
                .overlay {
                    if let editor {
                        Color.black.opacity(0.5).onTapGesture { self.editor = nil }
                        CameraControlEditor(camera: camera, control: editor) { self.editor = nil }.id(editor)
                            .frame(width: g.size.width - 56, height: g.size.height - 16)
                            .frame(width: g.size.width, height: g.size.height).background(.black)
                    }
                }
        }.preferredColorScheme(.dark)
            .overlay(alignment: .topTrailing) { HardwareReturnTestButton(camera: camera) }
            .fullScreenCover(isPresented: $birdTest) {
                BirdDiagnosticsView().overlay(alignment: .topTrailing) { HardwareReturnTestButton(camera: camera) }
            }
            .confirmationDialog("校準會實際拍照及存檔。開啟鳥眼，返回取景後，每段按住相機鍵至少10秒；三段通過才保存。", isPresented: $calibratePrompt) {
                Button("開始真機校準") { camera.startBurstCalibration() }
            }
            .confirmationDialog("重設所有拍攝設定？", isPresented: $resetPrompt) {
                Button("重設", role: .destructive) { camera.update { $0 = CameraSettings() }; camera.setZoom(1); camera.unlockTracking() }
            }
    }
    private func menuRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                Text(value).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
            }.font(.system(size: 14, weight: .medium)).padding(.horizontal, 12).frame(height: 31)
                .background(Color(white: selected == title ? 0.05 : 0.115))
                .overlay(Rectangle().stroke(selected == title ? colors[tab] : .clear, lineWidth: 2))
        }
    }
    private func toggleRow(_ title: String, path: WritableKeyPath<CameraSettings, Bool>) -> some View {
        menuRow(title, value: camera.settings[keyPath: path] ? "開啟" : "關閉") { camera.update { $0[keyPath: path].toggle() } }
    }
}
