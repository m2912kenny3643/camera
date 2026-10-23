import SwiftUI
import ImageIO

struct GalleryView: View {
    @ObservedObject var store: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var images: [URL] = []
    @State private var selection = 0
    @State private var zoom: CGFloat = 1
    @State private var showInfo = true
    @State private var deletePrompt = false
    @State private var error: String?
    @State private var deleteTarget: URL?
    @State private var retryTarget: URL?
    private var current: PhotoLibraryStore.Item? {
        guard images.indices.contains(selection) else { return nil }
        return store.items.first { $0.url == images[selection] }
    }
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color.black
                if images.indices.contains(selection) {
                    GalleryImage(url: images[selection], zoom: zoom, showInfo: showInfo).id(images[selection]).clipped()
                } else { Text("尚未拍攝照片").frame(maxHeight: .infinity) }
                VStack {
                    HStack {
                        Text(images.isEmpty ? "0 / 0" : "\(selection + 1) / \(images.count)")
                        Spacer()
                        if let current { Text(current.exportError ?? current.exportLabel).lineLimit(2).font(.system(size: 10)) }
                    }
                    Spacer()
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 38, height: 45).background(.black.opacity(0.5)) }.disabled(selection <= 0)
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 38, height: 45).background(.black.opacity(0.5)) }.disabled(selection + 1 >= images.count)
                    }
                    Spacer()
                }.padding(10)
            }.clipped().gesture(DragGesture(minimumDistance: 40).onEnded { value in move(value.translation.width < 0 ? 1 : -1) })
            HStack(spacing: 22) {
                Button { zoom = zoom == 1 ? 2 : 1 } label: { Image(systemName: zoom == 1 ? "plus.magnifyingglass" : "minus.magnifyingglass") }.accessibilityLabel("放大縮小")
                Button { deleteTarget = current?.url; deletePrompt = true } label: { Image(systemName: "trash") }.disabled(current == nil || current?.busy == true).accessibilityLabel("刪除")
                Spacer()
                Button("INFO") { showInfo.toggle() }
                if let current, !current.busy, current.exportState != .exported {
                    Button("匯出相簿") { retryTarget = current.url }.accessibilityIdentifier("gallery.export")
                }
                if images.indices.contains(selection) {
                    ShareLink(item: images[selection]) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享照片")
                    let raw = images[selection].deletingPathExtension().appendingPathExtension("dng")
                    if raw != images[selection] && FileManager.default.fileExists(atPath: raw.path) { ShareLink(item: raw) { Text("RAW") } }
                }
                Button { dismiss() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("返回拍攝").accessibilityIdentifier("gallery.close")
            }.padding(.horizontal, 20).frame(height: 40)
        }.background(.black).foregroundStyle(.white).buttonStyle(.plain).preferredColorScheme(.dark)
            .onAppear { images = store.items.map(\.url); store.refresh() }
            .onChange(of: store.items) { _, items in
                let previous = images.indices.contains(selection) ? images[selection] : nil
                images = items.map(\.url)
                selection = previous.flatMap { images.firstIndex(of: $0) } ?? max(0, min(selection, images.count - 1))
            }
            .confirmationDialog("刪除此照片與對應 RAW？", isPresented: $deletePrompt) {
                Button("刪除 App 內照片", role: .destructive) { deleteCurrent() }
            } message: { Text("不會刪除已存入系統相簿的副本。") }
            .confirmationDialog("匯出此照片至系統相簿？", isPresented: Binding(get: { retryTarget != nil }, set: { if !$0 { retryTarget = nil } })) {
                if let url = retryTarget { Button("確認匯出") { store.retryExport(url); retryTarget = nil } }
            } message: { Text("原檔保留在 App。舊版本或中斷後的狀態未知，重試可能產生相簿副本；已確認成功者不會重複匯出。") }
            .alert("回放提示", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("確定") { error = nil } } message: { Text(error ?? "") }
    }
    private func move(_ delta: Int) { guard !images.isEmpty else { return }; selection = min(images.count - 1, max(0, selection + delta)); zoom = 1 }
    private func deleteCurrent() {
        guard let url = deleteTarget else { return }
        store.delete(url) { error = $0 }; deleteTarget = nil; zoom = 1
    }
}
private struct GalleryImage: View {
    let url: URL
    let zoom: CGFloat
    let showInfo: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var asset: GalleryLoader.Asset?
    var body: some View {
        GeometryReader { g in
            let pixels = Int((max(g.size.width, g.size.height) * displayScale * zoom).rounded(.up))
            ZStack(alignment: .bottom) {
                Group {
                    if let image = asset?.image { Image(uiImage: image).resizable().scaledToFit().scaleEffect(zoom) }
                    else if let error = asset?.error { Text(error) }
                    else { ProgressView() }
                }.frame(width: g.size.width, height: g.size.height).clipped()
                if showInfo { Text(asset?.metadata ?? "").font(.system(size: 12, design: .monospaced)).padding(5).background(.black.opacity(0.6)) }
            }.task(id: pixels) {
                let loaded = await GalleryLoader.shared.load(url, maxPixels: pixels)
                guard !Task.isCancelled else { return }
                asset = loaded
            }
        }
    }
}
