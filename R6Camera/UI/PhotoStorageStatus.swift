import SwiftUI

struct PhotoStorageStatus: View {
    @ObservedObject var store: PhotoLibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("App 照片 \(store.items.count) 張 · \(ByteCountFormatter.string(fromByteCount: store.bytes, countStyle: .file))")
            if let free = store.freeBytes { Text("裝置剩餘 \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))") }
            let failed = store.items.filter { $0.exportState == .failed }.count
            let busy = store.items.filter(\.busy).count
            if failed > 0 || busy > 0 { Text("等待／匯出中 \(busy) · 失敗 \(failed)；回放可確認後重試或刪除") }
            Text("照片不會自動清除；刪除 App 副本需在回放確認。")
            if let message = store.message { Text(message).foregroundStyle(.yellow) }
        }.font(.system(size: 10)).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("storage.status").onAppear { store.refresh() }
    }
}
