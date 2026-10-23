import Foundation
import Combine
import CoreImage

/// Serial ownership of disk writes, deletion and export bookkeeping; Photos copies originals.
final class PhotoLibraryStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let url: URL
        let exportState: PhotoExportLedger.State?
        let exportError: String?
        var id: URL { url }
        var busy: Bool { exportState == .queued || exportState == .exporting }
        var exportLabel: String {
            switch exportState {
            case .queued: return "等待匯出"
            case .exporting: return "匯出中"
            case .exported: return "已匯出相簿"
            case .failed: return "匯出失敗，可重試"
            case .uncertain, nil: return "匯出狀態未知，重試可能重複"
            }
        }
    }
    struct Stored { let url: URL; let dimensions: String?; let complete: Bool; let warning: String? }
    @Published private(set) var items: [Item] = []
    @Published private(set) var bytes: Int64 = 0
    @Published private(set) var freeBytes: Int64?
    @Published private(set) var message: String?
    private let queue = DispatchQueue(label: "camera.photo.storage", qos: .userInitiated)
    private let context = CIContext()
    private let directory: URL
    private let exporter: any PhotoLibraryExporting
    private var ledger = PhotoExportLedger()
    private var loaded = false
    private var exportQueue: [URL] = []
    private var exporting: URL?
    private var indexURL: URL { directory.appendingPathComponent(".r6-exports.json") }
    init(directory: URL? = nil, exporter: any PhotoLibraryExporting = PhotoLibraryExporter()) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.exporter = exporter
    }
    func refresh() { queue.async { self.loadLedger(); self.publish() } }
    private func key(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }
    private func loadLedger() {
        guard !loaded else { return }; loaded = true
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexURL)
            ledger = try JSONDecoder().decode(PhotoExportLedger.self, from: data)
            ledger.recoverInterrupted()
        } catch {
            // Preserve an unreadable index before any new export updates replace it.
            do { try FileManager.default.copyItem(at: indexURL, to: directory.appendingPathComponent(".r6-exports-recovery-\(UUID().uuidString).json")) }
            catch { notify("匯出紀錄無法備份；新匯出已停用：\(error.localizedDescription)"); loaded = false; return }
            notify("匯出紀錄無法讀取，已備份；舊照片匯出狀態未知")
        }
    }
    @discardableResult private func saveLedger() -> Bool {
        do { try JSONEncoder().encode(ledger).write(to: indexURL, options: .atomic); return true }
        catch { notify("匯出紀錄寫入失敗；未確認的匯出不放行：\(error.localizedDescription)"); return false }
    }
    private func notify(_ text: String) { DispatchQueue.main.async { self.message = text } }
    private func publish() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            let photos = PhotoCaptureData.galleryItems(urls)
            let items = photos.map { url -> Item in
                let entry = ledger.entries[key(url)]
                return Item(url: url, exportState: entry?.state, exportError: entry?.error)
            }
            let bytes = try urls.filter { ["jpg", "heic", "dng"].contains($0.pathExtension.lowercased()) }.reduce(Int64(0)) {
                $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
            let free = (try? FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber)?.int64Value
            DispatchQueue.main.async { self.items = items; self.bytes = bytes; self.freeBytes = free }
        } catch { notify("無法讀取 App 照片：\(error.localizedDescription)") }
    }
    func store(_ result: Result<PhotoJob.Output, Error>, id: Int64, rendering: @escaping () -> Void,
               completion: @escaping (Result<Stored, Error>) -> Void) {
        queue.async {
            self.loadLedger()
            rendering()
            let saved: Result<Stored, Error> = Result { try autoreleasepool { () throws -> Stored in
                let output = try result.get()
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                let stem = "R6_\(Int(Date().timeIntervalSince1970))_\(id)_\(UUID().uuidString.prefix(8))"
                let files = try output.data.persist(in: self.directory, stem: stem, processedExtension: output.type == .heic ? "heic" : "jpg")
                var warnings = [output.data.warning, files.warning].compactMap { $0 }
                if let url = files.processed, let processed = output.data.processed {
                    do {
                        let rendered = try PhotoRenderer.render(processed, settings: output.settings, type: output.type, context: self.context)
                        try rendered.write(to: url, options: .atomic)
                    } catch { warnings.append("風格處理失敗，原始照片已保留：\(error.localizedDescription)") }
                }
                guard let url = files.processed ?? files.raw else { throw self.failure("沒有成功存檔的照片") }
                return Stored(url: url, dimensions: output.dimensions, complete: warnings.isEmpty,
                              warning: warnings.isEmpty ? nil : warnings.joined(separator: "；"))
            } }
            if case .success(let photo) = saved { self.enqueueExport(photo.url, retry: false) }
            self.publish(); completion(saved)
        }
    }
    func retryExport(_ url: URL) {
        queue.async { self.loadLedger(); self.enqueueExport(url, retry: true); self.publish() }
    }
    private func enqueueExport(_ url: URL, retry: Bool) {
        guard loaded, url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path), ledger.enqueue(key(url), retry: retry) else { return }
        guard saveLedger() else { ledger.finish(key(url), error: "匯出紀錄寫入失敗，原檔保留，請稍後重試"); return }
        exportQueue.append(url); drainExports()
    }
    private func drainExports() {
        guard exporting == nil, !exportQueue.isEmpty else { return }
        let url = exportQueue.removeFirst(); exporting = url
        ledger.start(key(url))
        guard saveLedger() else { completeExport(url, error: "匯出紀錄寫入失敗，原檔保留，請稍後重試"); return }
        publish()
        let raw = url.deletingPathExtension().appendingPathExtension("dng")
        exporter.export(url, raw: raw != url && FileManager.default.fileExists(atPath: raw.path) ? raw : nil) {
            self.completeExport(url, error: $0)
        }
    }
    private func completeExport(_ url: URL, error: String?) {
        queue.async {
            self.ledger.finish(self.key(url), error: error); self.exporting = nil
            self.saveLedger(); self.publish(); self.drainExports()
        }
    }
    func delete(_ url: URL, completion: @escaping (String?) -> Void) {
        queue.async {
            self.loadLedger()
            do {
                guard !self.ledger.isBusy(self.key(url)) else { throw self.failure("照片正在等待或執行匯出，請完成後再刪除") }
                guard url.deletingLastPathComponent().standardizedFileURL == self.directory.standardizedFileURL else { throw self.failure("無效的照片位置") }
                let raw = url.deletingPathExtension().appendingPathExtension("dng")
                if raw != url && FileManager.default.fileExists(atPath: raw.path) { try FileManager.default.removeItem(at: raw) }
                try FileManager.default.removeItem(at: url)
                self.ledger.remove(self.key(url)); self.saveLedger(); self.publish()
                DispatchQueue.main.async { completion(nil) }
            } catch { self.publish(); DispatchQueue.main.async { completion(error.localizedDescription) } }
        }
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "PhotoStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
