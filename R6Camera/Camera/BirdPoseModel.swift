import CoreML
import CoreImage

/// Loads only a build-time, provenance-checked bundle. No runtime downloads/imports.
final class BirdPoseModel {
    private let model: MLModel
    private let context = CIContext(options: [.cacheIntermediates: false])
    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "BirdEyePose", withExtension: "mlmodelc") else {
            throw NSError(domain: "BirdModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "鳥眼模型未隨此驗證版本封裝。"])
        }
        let configuration = MLModelConfiguration(); configuration.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: configuration)
        guard let image = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
              image.pixelsWide == 640, image.pixelsHigh == 640,
              model.modelDescription.outputDescriptionsByName["pose_output"]?.multiArrayConstraint?.shape.map(\.intValue) == [1,23,8400] else {
            throw NSError(domain: "BirdModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "鳥眼模型輸入／輸出不符已驗證版本。"])
        }
    }
    func observations(_ buffer: CVPixelBuffer, at timestamp: Double) throws -> [BirdPoseObservation] {
        var target: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 640, 640, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &target)
        guard status == kCVReturnSuccess, let target else { return [] }
        let source = CIImage(cvPixelBuffer: buffer)
        let size = source.extent.size
        let scale = 640 / max(size.width, size.height)
        let scaled = source.transformed(by: .init(scaleX: scale, y: scale))
            .transformed(by: .init(translationX: (640-size.width*scale)/2, y: (640-size.height*scale)/2))
        let black = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 640))
        context.render(scaled.composited(over: black), to: target)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: target)])
        let result = try model.prediction(from: provider)
        guard let array = result.featureValue(for: "pose_output")?.multiArrayValue,
              array.shape.map(\.intValue) == [1,23,8400] else { return [] }
        return BirdPoseDecoder.decode(imageSize: size, anchors: 8400, at: timestamp) { row, column in
            array[[0, NSNumber(value: row), NSNumber(value: column)]].doubleValue
        }
    }
}
