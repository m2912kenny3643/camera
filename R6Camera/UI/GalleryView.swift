import SwiftUI
import ImageIO

struct GalleryView: View {
    let urls: [URL]
    @Environment(\.dismiss) private var dismiss
    @State private var images: [URL] = []
    @State private var selection = 0
    @State private var zoom: CGFloat = 1
    @State private var showInfo = true
    @State private var deletePrompt = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color.black
                if images.indices.contains(selection) {
                    GalleryImage(url: images[selection]).id(images[selection]).scaleEffect(zoom).clipped()
                } else { Text("尚未拍攝照片").frame(maxHeight: .infinity) }
                VStack {
                    HStack {
                        Text(images.isEmpty ? "0 / 0" : "\(selection + 1) / \(images.count)")
                        Spacer()
                        if images.indices.contains(selection) { Text(images[selection].deletingPathExtension().lastPathComponent).lineLimit(1).font(.system(size: 10)) }
                    }
                    Spacer()
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 38, height: 45).background(.black.opacity(0.5)) }.disabled(selection <= 0)
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 38, height: 45).background(.black.opacity(0.5)) }.disabled(selection + 1 >= images.count)
                    }
                    Spacer()
                    if showInfo && images.indices.contains(selection) { Text(metadata(images[selection])).font(.system(size: 12, design: .monospaced)).padding(5).background(.black.opacity(0.6)) }
                }.padding(10)
            }.clipped().gesture(DragGesture(minimumDistance: 40).onEnded { value in move(value.translation.width < 0 ? 1 : -1) })
            HStack(spacing: 22) {
                Button { zoom = zoom == 1 ? 2 : 1 } label: { Image(systemName: zoom == 1 ? "plus.magnifyingglass" : "minus.magnifyingglass") }.accessibilityLabel("放大縮小")
                Button { deletePrompt = true } label: { Image(systemName: "trash") }.disabled(images.isEmpty).accessibilityLabel("刪除")
                Spacer()
                Button("INFO") { showInfo.toggle() }
                if images.indices.contains(selection) {
                    ShareLink(item: images[selection]) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享照片")
                    let raw = images[selection].deletingPathExtension().appendingPathExtension("dng")
                    if raw != images[selection] && FileManager.default.fileExists(atPath: raw.path) { ShareLink(item: raw) { Text("RAW") } }
                }
                Button { dismiss() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("返回拍攝").accessibilityIdentifier("gallery.close")
            }.padding(.horizontal, 20).frame(height: 40)
        }.background(.black).foregroundStyle(.white).buttonStyle(.plain).preferredColorScheme(.dark)
            .onAppear { images = urls }
            .confirmationDialog("刪除此照片與對應 RAW？", isPresented: $deletePrompt) {
                Button("刪除 App 內照片", role: .destructive) { deleteCurrent() }
            } message: { Text("不會刪除已存入系統相簿的副本。") }
            .alert("回放提示", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("確定") { error = nil } } message: { Text(error ?? "") }
    }
    private func move(_ delta: Int) { guard !images.isEmpty else { return }; selection = min(images.count - 1, max(0, selection + delta)); zoom = 1 }
    private func deleteCurrent() {
        guard images.indices.contains(selection) else { return }
        let url = images[selection], raw = images[selection].deletingPathExtension().appendingPathExtension("dng")
        do {
            if raw != url && FileManager.default.fileExists(atPath: raw.path) { try FileManager.default.removeItem(at: raw) }
            try FileManager.default.removeItem(at: url)
            images.remove(at: selection); selection = max(0, min(selection, images.count - 1)); zoom = 1
        } catch { self.error = error.localizedDescription }
    }
    private func metadata(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return "" }
        let seconds = (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue
        let aperture = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue
        let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        return [seconds.map(CameraSettings.shutterLabel), aperture.map { String(format: "F%.1f", $0) }, iso.map { "ISO \($0)" }].compactMap { $0 }.joined(separator: "    ")
    }
}
private struct GalleryImage: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
        }.task(id: url) {
            image = nil
            let loaded = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
