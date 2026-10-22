import Foundation

/// Keep successful resources even if another photo callback fails.
struct PhotoCaptureData {
    let processed: Data?
    let raw: Data?
    let warning: String?
    var isEmpty: Bool { processed == nil && raw == nil }

    static func galleryItems(_ urls: [URL]) -> [URL] {
        let processed = urls.filter { ["jpg", "heic"].contains($0.pathExtension.lowercased()) }
        let stems = Set(processed.map { $0.deletingPathExtension().path })
        let rawOnly = urls.filter { $0.pathExtension.lowercased() == "dng" && !stems.contains($0.deletingPathExtension().path) }
        return (processed + rawOnly).sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    init(processed: Data?, raw: Data?, requiresRAW: Bool, error: String?) {
        self.processed = processed; self.raw = raw
        var warnings = [String]()
        if let error { warnings.append(error) }
        if processed == nil { warnings.append("缺少處理後照片") }
        if requiresRAW && raw == nil { warnings.append("缺少 RAW／DNG") }
        warning = warnings.isEmpty ? nil : warnings.joined(separator: "；")
    }

    func persist(in directory: URL, stem: String, processedExtension: String) throws -> (processed: URL?, raw: URL?, warning: String?) {
        var processedURL: URL?, rawURL: URL?
        var failures = [String]()
        var firstError: Error?
        if let processed {
            let url = directory.appendingPathComponent(stem).appendingPathExtension(processedExtension)
            do { try processed.write(to: url, options: .atomic); processedURL = url }
            catch { firstError = error; failures.append("處理後照片寫入失敗：\(error.localizedDescription)") }
        }
        if let raw {
            let url = directory.appendingPathComponent(stem).appendingPathExtension("dng")
            do { try raw.write(to: url, options: .atomic); rawURL = url }
            catch { if firstError == nil { firstError = error }; failures.append("RAW 寫入失敗：\(error.localizedDescription)") }
        }
        if processedURL == nil && rawURL == nil, let firstError { throw firstError }
        return (processedURL, rawURL, failures.isEmpty ? nil : failures.joined(separator: "；"))
    }
}
