import UIKit
import ImageIO

/// Serial background decoding with a bounded cache; never decodes a full-resolution gallery image.
actor GalleryLoader {
    static let shared = GalleryLoader()
    struct Asset { let image: UIImage?; let metadata: String; let error: String? }
    private final class Cached: NSObject {
        let asset: Asset
        init(_ asset: Asset) { self.asset = asset }
    }
    private let cache = NSCache<NSString, Cached>()
    init() { cache.countLimit = 6; cache.totalCostLimit = 32 * 1024 * 1024 }
    func load(_ url: URL, maxPixels: Int) -> Asset? {
        guard !Task.isCancelled else { return nil }
        let pixels = min(4096, max(256, maxPixels))
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "\(url.path)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)|\(pixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached.asset }
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                return Asset(image: nil, metadata: "", error: "無法讀取照片或 RAW 預覽")
            }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true]
            guard !Task.isCancelled, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return Asset(image: nil, metadata: "", error: "無法解碼照片預覽")
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let seconds = (exif?[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue
            let aperture = (exif?[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue
            let iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
            let text = [seconds.map(CameraSettings.shutterLabel), aperture.map { String(format: "F%.1f", $0) }, iso.map { "ISO \($0)" }].compactMap { $0 }.joined(separator: "    ")
            let asset = Asset(image: UIImage(cgImage: image), metadata: text, error: nil)
            if !Task.isCancelled { cache.setObject(Cached(asset), forKey: key, cost: image.bytesPerRow * image.height) }
            return asset
        }
    }
}
