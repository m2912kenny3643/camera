import SwiftUI

struct CameraSettingsView: View {
    @ObservedObject var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var page = 0
    @State private var editor: CameraControl?
    @State private var selected = CameraControl.format.rawValue
    @State private var resetPrompt = false
    private let names = ["拍攝", "AF", "播放", "設定", "自訂", "我的選單"]
    private let symbols = ["camera.fill", "AF", "play.rectangle", "wrench.fill", "camera.badge.ellipsis", "star.fill"]
    private let colors: [Color] = [.red, .purple, .blue, .yellow, .orange, .green]
    private var pages: [[CameraControl]] {
        switch tab {
        case 0: return [[.format, .whiteBalance, .style, .drive, .exposure], [.mode, .shutter, .iso, .kelvin, .lens], [.contrast, .saturation, .sharpness, .hue]]
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
                            Text("待選時基本自動對焦；觸控主體藍框追焦，空白處單次對焦。").font(.system(size: 10)).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            Text("鳥眼／鳥頭模型尚未通過授權與準確度驗收；目前鳥類僅身體辨識。").font(.system(size: 10)).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading)
                            if safePage == 1 { toggleRow("峰值邊緣輔助", path: \.peaking) }
                            menuRow("解除觸控對焦", value: "清除") { camera.unlockTracking() }
                        }
                        if tab == 3 {
                            toggleRow("格線", path: \.grid)
                            toggleRow("亮度直方圖", path: \.histogram)
                            menuRow("螢幕方向", value: "橫向 · 相機鍵朝上") {}
                            menuRow("相機鍵", value: "快門；不使用輕按／滑動") {}
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
                        CameraControlEditor(camera: camera, control: editor) { self.editor = nil }.frame(width: min(610, g.size.width - 90), height: min(300, g.size.height - 30))
                    }
                }
        }.preferredColorScheme(.dark)
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
