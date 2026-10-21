import SwiftUI

struct CameraView: View {
    @StateObject private var camera = CameraController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: Panel?
    @State private var quick: CameraControl?
    @State private var zoomOpen = false
    @State private var info = true
    @State private var magnification = false
    @State private var pinchStart: CGFloat?
    enum Panel: String, Identifiable { case menu, playback; var id: String { rawValue } }
    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.height / 385, proxy.size.width / 820)
            VStack(spacing: 0) {
                ZStack {
                    viewfinder
                    if quick == nil { hud(unit: unit) }
                    if zoomOpen { ZoomWheel(camera: camera) { zoomOpen = false } }
                    if let quick { QuickControlView(camera: camera, initial: quick) { self.quick = nil } }
                }.clipped()
                exposureBar.frame(height: max(36, 43 * unit))
            }.font(.system(size: max(11, 14 * unit), weight: .medium)).background(.black).foregroundStyle(.white)
        }
        .preferredColorScheme(.dark).onAppear { camera.start() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { camera.start() } else { camera.stop() } }
        .onChange(of: panel) { _, panel in camera.captureEnabled = panel == nil }
        .fullScreenCover(item: $panel) { item in
            switch item {
            case .menu: CameraSettingsView(camera: camera)
            case .playback: GalleryView(urls: camera.galleryURLs())
            }
        }
        .alert("相機提示", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            Button("確定") { camera.error = nil }
            Button("開啟設定") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
        } message: { Text(camera.error ?? "") }
    }
    private var viewfinder: some View {
        GeometryReader { g in
            ZStack {
                CameraPreview(camera: camera)
                if let frame = camera.styledFrame {
                    Image(decorative: frame, scale: 1).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(magnification && camera.settings.autofocus == .manual ? 3 : 1)
                        .blendMode(camera.settings.peaking && camera.settings.autofocus == .manual ? .screen : .normal).allowsHitTesting(false)
                }
                if let fixture = camera.uiFixture {
                    Image(uiImage: fixture).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).allowsHitTesting(false)
                }
                Color.clear.contentShape(Rectangle()).onTapGesture { point in
                    camera.reviewImage = nil
                    camera.tap(at: ViewfinderGeometry.normalized(point, imageAspect: camera.frameAspect, size: g.size))
                }.simultaneousGesture(MagnifyGesture().onChanged { value in
                    if pinchStart == nil { pinchStart = camera.zoom }
                    camera.setZoom((pinchStart ?? camera.zoom) * value.magnification)
                }.onEnded { _ in pinchStart = nil })
                if camera.settings.grid && info { GridLines().stroke(.white.opacity(0.3), lineWidth: 0.5).allowsHitTesting(false) }
                if camera.settings.autofocus != .manual {
                    TrackingOverlay(result: camera.tracking, eyes: camera.settings.eyes, aspect: camera.frameAspect).allowsHitTesting(false)
                }
                if let image = camera.reviewImage { Image(uiImage: image).resizable().scaledToFit().background(.black).allowsHitTesting(false) }
                if camera.countdown > 0 { Text("\(camera.countdown)").font(.system(size: 64, weight: .bold)).shadow(radius: 5) }
                if !camera.isRunning && !camera.isUIFixture { Text(camera.status).font(.caption).padding(12).background(.black.opacity(0.8)) }
            }.clipped()
        }
    }
    private func hud(unit: CGFloat) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .top) {
                Button { open(.mode) } label: { Text(camera.settings.program.rawValue).font(.system(size: 31 * unit, weight: .bold)).frame(minWidth: 40) }
                Spacer()
                if info && camera.settings.histogram {
                    HistogramView(values: camera.histogram).frame(width: 92, height: 33)
                }
                if camera.pendingPhotos > 0 { Text("寫入 \(camera.pendingPhotos)").font(.caption2) }
                Image(systemName: camera.battery < 0.2 ? "battery.25percent" : "battery.75percent").foregroundStyle(camera.battery >= 0 && camera.battery < 0.2 ? .red : .white)
                Text(camera.remainingShots.map(String.init) ?? "—").monospacedDigit()
                Button { open(.autofocus) } label: {
                    Text("Q").font(.system(size: 23 * unit, weight: .semibold)).frame(width: 38, height: 33).overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1))
                }.accessibilityIdentifier("quick.open").padding(.leading, 8)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3 * unit) {
                    CameraMarkButton(title: "自動對焦區域", action: { open(.area) }) { CanonGlyph(kind: .area) }
                    Button { open(.autofocus) } label: { Text(camera.settings.autofocus.rawValue).font(.system(size: 11 * unit, weight: .semibold)).frame(minHeight: 27) }
                    if info {
                        Spacer(minLength: 0)
                        CameraMarkButton(title: "影像畫質", action: { open(.format) }) { CanonGlyph(kind: .quality, label: camera.settings.format == .raw ? "R" : "L") }
                        CameraMarkButton(title: "驅動模式", action: { open(.drive) }) { CanonGlyph(kind: .drive, label: camera.settings.drive.rawValue) }
                        Text(camera.settings.drive.delay > 0 ? "\(camera.settings.drive.delay)s" : "").font(.caption2)
                        Spacer(minLength: 0)
                        Button("INFO") { info.toggle() }.font(.system(size: 10)).frame(minHeight: 30)
                    }
                }.frame(width: 63 * unit, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 3 * unit) {
                    if info && !zoomOpen {
                        CameraMarkButton(title: "白平衡", action: { open(.whiteBalance) }) { Text(camera.settings.whiteBalance.rawValue).font(.system(size: 13, weight: .bold)).padding(2).overlay(Rectangle().stroke(.white)) }
                        CameraMarkButton(title: "相片風格", action: { open(.style) }) { CanonGlyph(kind: .style, label: camera.settings.style.cameraCode) }
                        CameraMarkButton(title: "測光模式", action: { open(.meter) }) { CanonGlyph(kind: .meter) }
                        CameraMarkButton(title: "要偵測的主體", action: { open(.subject) }) { CanonGlyph(kind: .subject, label: camera.settings.subjects.rawValue) }
                    }
                    Spacer(minLength: 0)
                    if camera.tracking.locked || camera.tracking.touchPoint != nil {
                        Button { camera.unlockTracking() } label: { Image(systemName: "xmark").frame(width: 38, height: 30).background(.black.opacity(0.5)) }.accessibilityLabel("解除觸控對焦").accessibilityIdentifier("focus.unlock")
                    }
                    if camera.settings.autofocus == .manual { Button { magnification.toggle() } label: { Image(systemName: "plus.magnifyingglass").frame(width: 38, height: 30) } }
                    Button { quick = nil; zoomOpen.toggle() } label: {
                        Text(String(format: "%g×", Double((camera.zoom * 10).rounded() / 10))).font(.system(size: 14, weight: .medium)).frame(width: 40, height: 40).background(.black.opacity(0.25)).overlay(Circle().stroke(.white, lineWidth: 1))
                    }.accessibilityIdentifier("zoom.open")
                }.frame(width: 66 * unit)
            }
            if camera.tracking.lost { Text("目標遺失 · 請重新點選").font(.caption2).padding(3).background(.black.opacity(0.65)) }
            if !info { Button("INFO") { info.toggle() }.font(.caption2) }
        }.padding(.horizontal, 12).padding(.vertical, 7).buttonStyle(.plain).shadow(color: .black, radius: 1, x: 0, y: 1)
    }
    private var exposureBar: some View {
        HStack(spacing: 10) {
            Button { camera.cancelCapture(); panel = .playback } label: { Image(systemName: "play.rectangle").font(.system(size: 23)).frame(width: 44) }
            Spacer(minLength: 1)
            Button(CameraSettings.shutterLabel(camera.actualShutter)) { open(.shutter) }.monospacedDigit()
            Text(String(format: "F%.1f", camera.aperture)).foregroundStyle(.gray).padding(.horizontal, 7)
            Button { open(.exposure) } label: { ExposureScale(value: camera.settings.exposureBias).frame(width: 145, height: 26) }
            Button("ISO \(Int(camera.actualISO))") { open(.iso) }.monospacedDigit()
            Button { camera.toggleExposureLock() } label: { Text("✱").foregroundStyle(camera.exposureLocked ? .yellow : .gray) }.accessibilityLabel("自動曝光鎖")
            Spacer(minLength: 1)
            Button("MENU") { camera.cancelCapture(); panel = .menu }.font(.system(size: 13, weight: .medium)).padding(5).overlay(Rectangle().stroke(.white))
        }.padding(.horizontal, 10).background(.black).buttonStyle(.plain).lineLimit(1).minimumScaleFactor(0.7)
    }
    private func open(_ control: CameraControl) { zoomOpen = false; quick = control }
}

private struct TrackingOverlay: View {
    let result: TrackingResult
    let eyes: EyePriority
    let aspect: CGFloat
    var body: some View {
        GeometryReader { g in
            let image = ViewfinderGeometry.imageRect(imageAspect: aspect, in: g.size)
            if let point = result.touchPoint {
                Rectangle().stroke(Color.blue, lineWidth: 1.5).frame(width: 36, height: 36).position(ViewfinderGeometry.display(point, imageAspect: aspect, size: g.size))
            } else if let target = result.selected, !result.lost {
                let rect = result.locked ? target.focusBounds(eyes) : target.bounds
                Rectangle().stroke(result.locked ? Color.blue : Color.white, lineWidth: 1.5)
                    .frame(width: max(10, rect.width * image.width), height: max(10, rect.height * image.height))
                    .position(x: image.minX + rect.midX * image.width, y: image.minY + rect.midY * image.height)
            }
        }
    }
}
private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in for f in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
            p.move(to: CGPoint(x: rect.width * f, y: 0)); p.addLine(to: CGPoint(x: rect.width * f, y: rect.height))
            p.move(to: CGPoint(x: 0, y: rect.height * f)); p.addLine(to: CGPoint(x: rect.width, y: rect.height * f))
        } }
    }
}
private struct ExposureScale: View {
    let value: Double
    var body: some View {
        VStack(spacing: 0) {
            Text("−3..2..1..0..1..2..3+").font(.system(size: 9, weight: .medium, design: .monospaced))
            GeometryReader { g in Rectangle().fill(.white).frame(width: 3, height: 8).position(x: g.size.width * CGFloat((min(3, max(-3, value)) + 3) / 6), y: 4) }.frame(height: 8)
        }
    }
}
private struct HistogramView: View {
    let values: [Float]
    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let width = size.width / CGFloat(values.count)
            for (i, value) in values.enumerated() {
                let height = size.height * CGFloat(value)
                context.fill(Path(CGRect(x: CGFloat(i) * width, y: size.height - height, width: width, height: height)), with: .color(.white.opacity(0.8)))
            }
        }.background(.black.opacity(0.5))
    }
}
