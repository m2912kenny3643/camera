import SwiftUI

struct GalleryView: View {
    let urls: [URL]
    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0
    var body: some View {
        NavigationStack {
            Group {
                if urls.isEmpty {
                    ContentUnavailableView("尚未拍攝照片", systemImage: "photo.on.rectangle")
                } else {
                    TabView(selection: $selection) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            GalleryImage(url: url).tag(index)
                        }
                    }.tabViewStyle(.page)
                }
            }
            .background(.black)
            .navigationTitle(urls.isEmpty ? "回放" : "\(selection + 1) / \(urls.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("返回") { dismiss() } }
                if urls.indices.contains(selection) {
                    ToolbarItem(placement: .bottomBar) {
                        ShareLink(item: urls[selection]) { Label("分享照片", systemImage: "square.and.arrow.up") }
                    }
                    if FileManager.default.fileExists(atPath: urls[selection].deletingPathExtension().appendingPathExtension("dng").path) {
                        ToolbarItem(placement: .bottomBar) {
                            ShareLink(item: urls[selection].deletingPathExtension().appendingPathExtension("dng")) { Text("分享 RAW") }
                        }
                    }
                }
            }
        }.preferredColorScheme(.dark)
    }
}
private struct GalleryImage: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { ProgressView() }
        }.task(id: url) {
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
        }
    }
}
