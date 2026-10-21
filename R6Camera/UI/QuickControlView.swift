import SwiftUI

struct QuickControlView: View {
    @ObservedObject var camera: CameraController
    let initial: CameraControl
    let close: () -> Void
    @State private var selection: CameraControl?
    private let left: [CameraControl] = [.autofocus, .format, .drive, .mode]
    private let right: [CameraControl] = [.whiteBalance, .style, .subject, .eye]
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                HStack(alignment: .top) {
                    VStack(spacing: 3) { ForEach(left) { cell($0) } }
                    Spacer()
                    VStack(spacing: 3) {
                        Button(action: close) { Image(systemName: "arrow.uturn.backward").frame(width: 64, height: 30).overlay(Rectangle().stroke(.white.opacity(0.5))) }
                            .accessibilityIdentifier("quick.close")
                        ForEach(right) { cell($0) }
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
                CameraControlEditor(camera: camera, control: selection ?? initial, close: close)
                    .frame(width: min(610, g.size.width - 165), height: min(g.size.height - 16, editorHeight))
            }.padding(8)
        }.foregroundStyle(.white).buttonStyle(.plain).background(.black.opacity(0.32))
    }
    private var editorHeight: CGFloat {
        switch selection ?? initial {
        case .eye, .style, .subject: return 280
        case .whiteBalance: return camera.settings.whiteBalance == .custom ? 270 : 230
        default: return 190
        }
    }
    private func cell(_ control: CameraControl) -> some View {
        Button { selection = control } label: {
            Group {
                switch control {
                case .format: CanonGlyph(kind: .quality, label: camera.settings.format == .raw ? "R" : "L")
                case .drive: CanonGlyph(kind: .drive, label: camera.settings.drive.rawValue)
                case .style: CanonGlyph(kind: .style, label: camera.settings.style.cameraCode)
                case .eye: CanonGlyph(kind: .eye)
                default: Text(control.value(camera.settings)).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
                .frame(width: 64, height: 28).background(.black.opacity(0.7))
                .overlay(Rectangle().stroke((selection ?? initial) == control ? .yellow : .white.opacity(0.6), lineWidth: (selection ?? initial) == control ? 2 : 1))
        }.accessibilityLabel(control.rawValue).accessibilityIdentifier("quick.\(control)")
    }
}
