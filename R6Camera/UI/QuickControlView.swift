import SwiftUI

struct QuickControlView: View {
    @ObservedObject var camera: CameraController
    let initial: CameraControl
    let select: (CameraControl) -> Void
    let close: () -> Void
    private let left: [CameraControl] = [.mode, .area, .autofocus, .format, .drive]
    private let right: [CameraControl] = [.whiteBalance, .style, .meter, .subject, .eye]
    var body: some View {
        GeometryReader { g in
            let control = initial
            ZStack(alignment: .bottom) {
                if control.isLivePalette {
                HStack(alignment: .top) {
                    VStack(spacing: 3) { ForEach(left) { cell($0) } }
                    Spacer()
                    VStack(spacing: 3) {
                        Button(action: close) { Image(systemName: "arrow.uturn.backward").frame(width: 64, height: 30).overlay(Rectangle().stroke(.white.opacity(0.5))) }
                            .accessibilityIdentifier("quick.close")
                        ForEach(right) { cell($0) }
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
                CameraControlEditor(camera: camera, control: control, palette: true, close: close)
                    .id(control).frame(width: g.size.width - 150, height: paletteHeight)
                } else {
                    CameraControlEditor(camera: camera, control: control, close: close).id(control)
                        .padding(.horizontal, 28).padding(.vertical, 4)
                }
            }.padding(8).background(control.isLivePalette ? Color.clear : .black)
        }.foregroundStyle(.white).buttonStyle(.plain)
    }
    private var paletteHeight: CGFloat {
        switch initial {
        case .drive, .whiteBalance: return 140
        case .exposure: return 130
        default: return 100
        }
    }
    private func cell(_ control: CameraControl) -> some View {
        Button { select(control) } label: {
            Group {
                switch control {
                case .format: CanonGlyph(kind: .quality, label: camera.settings.format == .raw ? "R" : "L")
                case .drive: CanonGlyph(kind: .drive, label: camera.settings.drive.code)
                case .area: CanonGlyph(kind: .area)
                case .mode: Text(camera.settings.program.rawValue).font(.system(size: 31, weight: .bold))
                case .style: CanonGlyph(kind: .style, label: camera.settings.effective.style.cameraCode)
                case .meter: CanonGlyph(kind: .meter)
                case .eye: CanonGlyph(kind: .eye)
                default: Text(control.value(camera.settings)).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
                .frame(width: 64, height: control == .mode ? 42 : 28).background(.black.opacity(0.7))
                .overlay(Rectangle().stroke(initial == control ? .yellow : .white.opacity(0.6), lineWidth: initial == control ? 2 : 1))
        }.accessibilityLabel(control.rawValue).accessibilityIdentifier("quick.\(control)")
    }
}
