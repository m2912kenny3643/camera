import SwiftUI

struct QuickControlView: View {
    @ObservedObject var camera: CameraController
    let close: () -> Void
    @State private var selection: Control = .autofocus
    private let amber = Color(red: 1, green: 0.77, blue: 0.18)
    private enum Control: String, CaseIterable, Identifiable {
        case mode = "拍攝模式", shutter = "快門", iso = "ISO", exposure = "曝光補償"
        case autofocus = "AF 操作", subject = "偵測主體", eye = "眼睛偵測", drive = "驅動"
        case whiteBalance = "白平衡", style = "相片風格", format = "影像畫質", lens = "鏡頭切換"
        var id: String { rawValue }
    }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 8) {
                HStack {
                    Text("Q").font(.system(size: 25, weight: .bold))
                    Text("速控").font(.headline)
                    Spacer()
                    Text(String(format: "F%.1f", camera.aperture)).foregroundStyle(.gray)
                    Button("返回拍攝") { close() }.foregroundStyle(amber)
                }.padding(.horizontal, 12)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: landscape ? 4 : 3), spacing: 5) {
                    ForEach(Control.allCases) { control in
                        Button { selection = control } label: {
                            VStack(spacing: 5) {
                                Text(control.rawValue).font(.system(size: 10)).foregroundStyle(.gray)
                                Text(value(control)).font(.system(size: landscape ? 16 : 14, weight: .bold, design: .monospaced))
                                    .lineLimit(1).minimumScaleFactor(0.65)
                            }
                            .frame(maxWidth: .infinity, minHeight: landscape ? 52 : 64)
                            .background(selection == control ? Color(white: 0.18) : Color(white: 0.055))
                            .overlay(Rectangle().stroke(selection == control ? amber : Color(white: 0.27), lineWidth: selection == control ? 2 : 1))
                            .foregroundStyle(selection == control ? amber : .white)
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(selection.rawValue).foregroundStyle(amber).font(.caption)
                    adjustments
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.09)).overlay(Rectangle().stroke(amber, lineWidth: 1))
                Text("\(camera.settings.subjects.rawValue) · \(camera.settings.eyes.rawValue) · \(camera.settings.autofocus.rawValue)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray)
            }
            .padding(12)
            .frame(maxWidth: landscape ? 720 : 480)
            .background(.black.opacity(0.96))
            .overlay(Rectangle().stroke(Color(white: 0.4)))
            .padding(landscape ? 10 : 18)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(.black.opacity(0.55))
        }.preferredColorScheme(.dark)
    }
    private func value(_ control: Control) -> String {
        switch control {
        case .mode: return camera.settings.program.rawValue
        case .shutter: return camera.settings.controlsShutter ? camera.settings.shutterLabel : "AUTO"
        case .iso: return camera.settings.controlsISO ? "\(Int(camera.settings.iso))" : "AUTO"
        case .exposure: return String(format: "%+.1f", camera.settings.exposureBias)
        case .autofocus: return camera.settings.autofocus.rawValue
        case .subject: return camera.settings.subjects.rawValue
        case .eye: return camera.settings.eyes.rawValue
        case .drive: return camera.settings.drive.rawValue
        case .whiteBalance: return camera.settings.whiteBalance.rawValue
        case .style: return camera.settings.style.rawValue
        case .format: return camera.settings.format.rawValue
        case .lens: return camera.settings.lockLens ? "鎖定" : "自動"
        }
    }
    @ViewBuilder private var adjustments: some View {
        switch selection {
        case .mode:
            choices(ExposureProgram.allCases, current: camera.settings.program, title: { $0.rawValue }) { new in camera.update { $0.program = new } }
        case .autofocus:
            choices(AutofocusMode.allCases, current: camera.settings.autofocus, title: { $0.rawValue }) { new in camera.update { $0.autofocus = new } }
        case .subject:
            choices(SubjectMode.allCases, current: camera.settings.subjects, title: { $0.rawValue }) { new in camera.update { $0.subjects = new } }
        case .eye:
            choices(EyePriority.allCases, current: camera.settings.eyes, title: { $0.rawValue }) { new in camera.update { $0.eyes = new } }
        case .drive:
            choices(DriveMode.allCases, current: camera.settings.drive, title: { $0.rawValue }) { new in camera.update { $0.drive = new } }
        case .whiteBalance:
            choices(WhiteBalance.allCases, current: camera.settings.whiteBalance, title: { $0.rawValue }) { new in camera.update { $0.whiteBalance = new } }
        case .style:
            choices(PictureStyle.allCases, current: camera.settings.style, title: { $0.rawValue }) { new in camera.update { $0.style = new } }
        case .format:
            choices(PhotoFormat.allCases.filter { camera.supportsRAW || $0 != .raw }, current: camera.settings.format, title: { $0.rawValue }) { new in camera.update { $0.format = new } }
        case .lens:
            Button(camera.settings.lockLens ? "解除鏡頭鎖定" : "鎖定目前鏡頭") { camera.update { $0.lockLens.toggle() } }
                .foregroundStyle(.white).frame(minHeight: 34)
        case .exposure:
            Slider(value: Binding(get: { camera.settings.exposureBias }, set: { value in camera.update { $0.exposureBias = value } }), in: -3...3, step: 1.0/3).tint(amber)
        case .shutter:
            choices(CameraSettings.shutterSpeeds,
                    current: camera.settings.shutterSeconds, title: { CameraSettings.shutterLabel($0) }) { new in
                camera.update {
                    $0.shutterSeconds = new
                    if $0.program == .flexible { $0.autoShutter = false }
                    else if $0.program != .manual { $0.program = .shutterPriority }
                }
            }
        case .iso:
            choices(CameraSettings.isoValues, current: camera.settings.iso, title: { "\(Int($0))" }) { new in
                camera.update {
                    $0.iso = new
                    if $0.program == .flexible { $0.autoISO = false } else { $0.program = .manual }
                }
            }
        }
    }
    private func choices<T: Hashable>(_ values: [T], current: T, title: @escaping (T) -> String,
                                     action: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(values, id: \.self) { value in
                    Button { action(value) } label: {
                        Text(title(value)).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10).frame(height: 34)
                            .foregroundStyle(current == value ? .black : .white)
                            .background(current == value ? amber : Color(white: 0.2))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
