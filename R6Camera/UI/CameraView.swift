import SwiftUI

struct CameraView: View {
    @StateObject private var camera = CameraController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: Panel?
    @State private var showingQuick = false
    @State private var infoLevel = 1
    @State private var magnifyStart: CGFloat?
    @State private var mfMagnification = false
    enum Panel: String, Identifiable { case menu, playback; var id: String { rawValue } }
    private let amber = Color(red: 1, green: 0.77, blue: 0.18)

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                topBar
                if landscape {
                    HStack(spacing: 0) {
                        viewfinder
                        sideRail.frame(width: 66)
                    }
                } else {
                    viewfinder
                    portraitControls
                }
                exposureBar
                bottomBar
            }
            .background(Color.black)
            .foregroundStyle(.white)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .preferredColorScheme(.dark)
        }
        .onAppear { camera.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() }
            else { camera.stop() }
        }
        .overlay {
            if showingQuick { QuickControlView(camera: camera) { showingQuick = false } }
        }
        .fullScreenCover(item: $panel) { item in
            switch item {
            case .menu: CameraSettingsView(camera: camera, quick: false)
            case .playback: GalleryView(urls: camera.galleryURLs())
            }
        }
        .alert("相機提示", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            Button("確定") { camera.error = nil }
            Button("開啟設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } message: { Text(camera.error ?? "") }
    }
    private var topBar: some View {
        HStack(spacing: 14) {
            Text(camera.settings.program.rawValue).font(.system(size: 22, weight: .bold))
                .foregroundStyle(amber)
            Text(camera.settings.autofocus.rawValue).font(.caption)
            Spacer(minLength: 4)
            ForEach(["C1", "C2", "C3"], id: \.self) { name in
                Button(name) { camera.recallPreset(name) }
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in camera.savePreset(name) })
                    .accessibilityHint("點一下載入，長按儲存目前設定")
            }
            Image(systemName: camera.battery < 0.2 ? "battery.25percent" : "battery.75percent")
                .foregroundStyle(camera.battery >= 0 && camera.battery < 0.2 ? .red : .white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).frame(height: 42)
    }
    private var viewfinder: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreview(camera: camera)
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        camera.reviewImage = nil
                        camera.tap(at: ViewfinderGeometry.normalized(point, imageAspect: camera.frameAspect, size: geometry.size))
                    }
                    .simultaneousGesture(MagnifyGesture().onChanged { gesture in
                        if magnifyStart == nil { magnifyStart = camera.zoom }
                        camera.setZoom((magnifyStart ?? camera.zoom) * gesture.magnification)
                    }.onEnded { _ in magnifyStart = nil })
                if let frame = camera.styledFrame {
                    Image(decorative: frame, scale: 1)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(mfMagnification && camera.settings.autofocus == .manual ? 3 : 1)
                        .opacity(camera.settings.peaking && camera.settings.autofocus == .manual ? 0.5 : 1)
                        .blendMode(camera.settings.peaking && camera.settings.autofocus == .manual ? .screen : .normal)
                        .allowsHitTesting(false)
                }
                if camera.settings.grid && infoLevel > 0 {
                    GridLines().stroke(.white.opacity(0.3), lineWidth: 0.5).allowsHitTesting(false)
                }
                if infoLevel > 0 && camera.settings.autofocus != .manual {
                    TrackingOverlay(result: camera.tracking, eyePriority: camera.settings.eyes,
                                    singleFocused: camera.singleFocused, autofocus: camera.settings.autofocus,
                                    imageAspect: camera.frameAspect)
                        .allowsHitTesting(false)
                }
                if let image = camera.reviewImage {
                    Image(uiImage: image).resizable().scaledToFit().background(.black)
                        .allowsHitTesting(false)
                }
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            if infoLevel > 0 {
                                Text(camera.settings.format.rawValue)
                                Text(camera.settings.drive.rawValue)
                                Text(String(format: "%.1f×", Double(camera.zoom)))
                            }
                        }
                        Spacer()
                        if camera.settings.histogram && infoLevel > 0 {
                            HistogramView(values: camera.histogram).frame(width: 104, height: 55)
                        }
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            if camera.tracking.lost { Text("目標遺失 · 點選重新鎖定").foregroundStyle(.orange) }
                            else if camera.tracking.missing { Text("暫時遮擋 · 等待目標").foregroundStyle(.orange) }
                            else if let target = camera.tracking.selected, infoLevel > 0 {
                                Text("\(target.kind.title) · \(target.eye(camera.settings.eyes) == nil ? "主體追蹤" : "眼睛追蹤")")
                            }
                            if camera.tracking.locked {
                                Button { camera.unlockTracking() } label: { Label("解除主體鎖定", systemImage: "lock.open") }
                                    .buttonStyle(.plain).foregroundStyle(amber)
                            }
                        }
                        Spacer()
                        Button { showingQuick = true } label: {
                            Text("Q").font(.system(size: 22, weight: .bold)).frame(width: 44, height: 44)
                                .background(.black.opacity(0.65)).overlay(Rectangle().stroke(.white.opacity(0.7)))
                        }.buttonStyle(.plain).accessibilityLabel("速控選單").accessibilityIdentifier("quick.open")
                    }
                }
                .padding(12)
                .shadow(color: .black, radius: 2)
                if camera.countdown > 0 {
                    Text("\(camera.countdown)").font(.system(size: 76, weight: .bold)).shadow(radius: 5)
                }
                if !camera.isRunning {
                    VStack(spacing: 12) {
                        Image(systemName: "camera").font(.largeTitle)
                        Text(camera.status)
                        Button("重新啟動") { camera.start() }.buttonStyle(.bordered)
                    }.padding().background(.black.opacity(0.8))
                }
            }
            .clipped()
        }
    }
    private var sideRail: some View {
        VStack(spacing: 16) {
            Button(camera.settings.whiteBalance.rawValue) { showingQuick = true }
            Button(camera.settings.style.rawValue) { showingQuick = true }
            Button(camera.settings.subjects.rawValue) { showingQuick = true }
            Spacer(minLength: 0)
            Button("AF-ON") { camera.autofocus() }.font(.caption2)
            shutterButton
            Button { camera.toggleExposureLock() } label: {
                Text("✱").font(.title2).foregroundStyle(camera.exposureLocked ? amber : .white)
            }
        }.buttonStyle(.plain).padding(.vertical, 14)
    }
    private var portraitControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 22) {
                ForEach([0.5, 1.0, 2.0], id: \.self) { factor in
                    Button(String(format: "%g×", factor)) { camera.setZoom(factor) }
                        .foregroundStyle(abs(Double(camera.zoom) - factor) < 0.05 ? amber : .white)
                }
                Button { camera.update { $0.lockLens.toggle() } } label: {
                    Image(systemName: camera.settings.lockLens ? "lock.fill" : "lock.open")
                }.foregroundStyle(camera.settings.lockLens ? amber : .white)
            }
            HStack {
                Button { panel = .playback } label: { Image(systemName: "play.rectangle").font(.title2) }.frame(width: 60)
                Spacer()
                shutterButton
                Spacer()
                Button("AF-ON") { camera.autofocus() }.frame(width: 60)
            }
        }.buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 12)
    }
    private var shutterButton: some View {
        ShutterButton {
            if camera.settings.drive == .burst { camera.beginBurst() }
        } ended: {
            if camera.settings.drive == .burst { camera.cancelCapture() }
            else { camera.shutter() }
        } cancelled: {
            camera.cancelCapture()
        }
        .frame(width: 58, height: 58)
        .disabled(!camera.isRunning || camera.countdown > 0)
    }
    private var exposureBar: some View {
        HStack(spacing: 12) {
            Text(CameraSettings.shutterLabel(camera.actualShutter))
            Text(String(format: "F%.1f", camera.aperture)).foregroundStyle(.gray)
            Spacer(minLength: 0)
            Text("−3 · −2 · −1 · ▼ · 1 · 2 · 3").font(.system(size: 10)).foregroundStyle(.gray)
            Text(String(format: "%+.1f", camera.settings.exposureBias)).foregroundStyle(amber)
            Spacer(minLength: 0)
            Text("ISO \(Int(camera.actualISO))")
            if camera.exposureLocked { Text("✱").foregroundStyle(amber) }
        }.lineLimit(1).minimumScaleFactor(0.65)
            .padding(.horizontal, 14).frame(height: 34)
            .background(Color(white: 0.075))
    }
    private var bottomBar: some View {
        HStack {
            Button("MENU") { panel = .menu }
            Button("INFO") { infoLevel = (infoLevel + 1) % 2 }
            Button { panel = .playback } label: { Image(systemName: "play.rectangle") }
            Spacer()
            Text(camera.pendingPhotos > 0 ? "寫入 \(camera.pendingPhotos)" : camera.status)
                .font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
            Button { mfMagnification.toggle() } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(camera.settings.autofocus != .manual)
            Button { camera.toggleExposureLock() } label: { Text("AE ✱") }
                .foregroundStyle(camera.exposureLocked ? amber : .white)
        }.buttonStyle(.plain).padding(.horizontal, 14).frame(height: 42)
    }
}

private struct ShutterButton: View {
    let began: () -> Void
    let ended: () -> Void
    let cancelled: () -> Void
    @State private var pressed = false
    var body: some View {
        Circle().stroke(.white, lineWidth: 3).padding(1)
            .overlay(Circle().fill(pressed ? .gray : .white).padding(7))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                if !pressed { pressed = true; began() }
            }.onEnded { _ in pressed = false; ended() })
            .onDisappear { if pressed { pressed = false; cancelled() } }
            .accessibilityLabel("快門")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { began(); ended() }
    }
}
private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
            path.move(to: CGPoint(x: rect.width * fraction, y: 0))
            path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
            path.move(to: CGPoint(x: 0, y: rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        return path
    }
}
private struct HistogramView: View {
    let values: [Float]
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Rectangle().fill(.white.opacity(0.8)).frame(height: geometry.size.height * CGFloat(value))
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
        }.background(.black.opacity(0.55)).overlay(Rectangle().stroke(.white.opacity(0.4), lineWidth: 0.5))
    }
}

private struct TrackingOverlay: View {
    let result: TrackingResult
    let eyePriority: EyePriority
    let singleFocused: Bool
    let autofocus: AutofocusMode
    let imageAspect: CGFloat
    var body: some View {
        GeometryReader { geometry in
            let image = ViewfinderGeometry.imageRect(imageAspect: imageAspect, in: geometry.size)
            ZStack {
                ForEach(result.candidates) { target in
                    let selected = result.selected.map {
                        $0.kind == target.kind && SubjectTracker.intersectionOverUnion($0.bounds, target.bounds) > 0.5
                    } ?? false
                    if !selected {
                        Rectangle().stroke(.gray.opacity(0.8), lineWidth: 1)
                            .frame(width: target.bounds.width * image.width, height: target.bounds.height * image.height)
                            .position(x: image.minX + target.bounds.midX * image.width,
                                      y: image.minY + target.bounds.midY * image.height)
                    }
                }
                if let selected = result.selected {
                    let color: Color = result.missing ? .orange : singleFocused ? .green : autofocus == .servo ? .cyan : .white
                    Rectangle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: result.missing ? [5, 4] : []))
                        .frame(width: selected.bounds.width * image.width, height: selected.bounds.height * image.height)
                        .position(x: image.minX + selected.bounds.midX * image.width,
                                  y: image.minY + selected.bounds.midY * image.height)
                    if let eye = selected.eye(eyePriority), !result.missing {
                        Rectangle().stroke(color, lineWidth: 2).frame(width: 18, height: 18)
                            .position(ViewfinderGeometry.display(eye, imageAspect: imageAspect, size: geometry.size))
                    }
                }
            }.animation(.linear(duration: 0.1), value: result.selected?.bounds)
        }
    }
}
