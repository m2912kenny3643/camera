import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum PhotoRenderer {
    static func applyStyle(_ input: CIImage, settings: CameraSettings) -> CIImage {
        var contrast = 1.0, saturation = 1.0
        switch settings.style {
        case .standard: contrast = 1.04; saturation = 1.05
        case .portrait: contrast = 0.98; saturation = 0.98
        case .landscape: contrast = 1.12; saturation = 1.18
        case .neutral: contrast = 0.94; saturation = 0.92
        case .faithful: contrast = 0.98; saturation = 1
        case .mono: contrast = 1.06; saturation = 0
        }
        let colored = input.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: contrast + settings.contrast * 0.04,
            kCIInputSaturationKey: settings.style == .mono ? 0 : saturation + settings.saturation * 0.08
        ]).applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: settings.hue * 0.015])
        return colored.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.2 + settings.sharpness * 0.12])
    }

    static func render(_ data: Data, settings: CameraSettings, type: UTType,
                       context: CIContext) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw NSError(domain: "Photo", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法解碼照片。"])
        }
        let styled = applyStyle(original, settings: settings)
        guard let image = context.createCGImage(styled, from: styled.extent) else {
            throw NSError(domain: "Photo", code: 2, userInfo: [NSLocalizedDescriptionKey: "無法處理照片風格。"])
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Photo", code: 3, userInfo: [NSLocalizedDescriptionKey: "無法建立照片格式。"])
        }
        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = image.width
        properties[kCGImagePropertyPixelHeight] = image.height
        properties[kCGImageDestinationLossyCompressionQuality] = 0.95
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "Photo", code: 4, userInfo: [NSLocalizedDescriptionKey: "照片編碼失敗。"])
        }
        return output as Data
    }
}
