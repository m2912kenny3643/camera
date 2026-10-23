import Photos

protocol PhotoLibraryExporting {
    func export(_ url: URL, raw: URL?, completion: @escaping (String?) -> Void)
}

struct PhotoLibraryExporter: PhotoLibraryExporting {
    func export(_ url: URL, raw: URL?, completion: @escaping (String?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { authorization in
            guard authorization == .authorized || authorization == .limited else {
                completion("相簿權限未開啟；原檔保留在 App，可重試"); return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions(); options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: url, options: options)
                if let raw { request.addResource(with: .alternatePhoto, fileURL: raw, options: options) }
            } completionHandler: { success, error in
                completion(success ? nil : error?.localizedDescription ?? "相簿匯出失敗")
            }
        }
    }
}
