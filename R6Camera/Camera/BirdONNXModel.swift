import AVFoundation
import CryptoKit
import OnnxRuntimeBindings

/// Pinned Android model. The serial inference owner reuses the input tensor storage.
final class BirdONNXModel: BirdPosePredicting {
    static let resource = "BirdEyePose"
    private let environment: ORTEnv
    private let session: ORTSession
    private let storage = NSMutableData(length: 3*320*320*MemoryLayout<Float>.size)!

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: Self.resource, withExtension: "onnx") else {
            throw Self.error("此版本未封裝Android鳥眼模型")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        guard digest == BirdPoseDecoder.androidSHA256 else { throw Self.error("鳥眼模型雜湊不符，拒絕載入") }
        environment = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        session = try ORTSession(env: environment, modelPath: url.path, sessionOptions: options)
        guard try session.inputNames() == ["images"], try session.outputNames() == ["output0"] else {
            throw Self.error("鳥眼ONNX名稱不符合固定契約")
        }
    }
    func observations(_ buffer: CVPixelBuffer, at timestamp: Double, region: CGRect?, padding: CGFloat) throws -> [BirdPoseObservation] {
        try prepare(buffer, region: region, padding: padding)
        let input = try ORTValue(tensorData: storage, elementType: .float, shape: [1,3,320,320])
        let results = try session.run(withInputs: ["images": input], outputNames: ["output0"], runOptions: nil)
        guard let output = results["output0"] else { throw Self.error("鳥眼模型沒有輸出") }
        let shape = try output.tensorTypeAndShapeInfo()
        guard shape.elementType == .float, shape.shape.map(\.intValue) == [1,23,2100] else {
            throw Self.error("鳥眼ONNX輸出不符合[1,23,2100]")
        }
        let data = try output.tensorData()
        guard data.length == 23*2100*MemoryLayout<Float>.size else { throw Self.error("鳥眼張量長度錯誤") }
        let floats = data.bytes.assumingMemoryBound(to: Float.self)
        return withExtendedLifetime(output) {
            BirdPoseDecoder.decode(imageSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)),
                                   anchors: 2100, at: timestamp, contract: .android320, region: region, padding: padding) { row, index in
                Double(floats[row*2100+index])
            }
        }
    }
    func preparedInputData(_ buffer: CVPixelBuffer, region: CGRect? = nil, padding: CGFloat = 1) throws -> Data {
        try prepare(buffer, region: region, padding: padding)
        return Data(bytes: storage.bytes, count: storage.length)
    }
    /// Sample native BGRA rows directly: no implicit Core Image color/orientation conversion.
    func prepare(_ buffer: CVPixelBuffer, region: CGRect?, padding: CGFloat) throws {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { throw Self.error("鳥眼輸入必須是BGRA") }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw Self.error("無法讀取鳥眼影像") }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let crop = BirdCrop(imageSize: CGSize(width: width, height: height), region: region ?? CGRect(x: 0,y: 0,width: 1,height: 1), padding: padding)
        guard [crop.square.minX,crop.square.minY,crop.square.width].allSatisfy({ $0.isFinite }), crop.square.width > 0, crop.square.width.isFinite else { throw Self.error("鳥眼裁切區域無效") }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let target = storage.mutableBytes.assumingMemoryBound(to: Float.self)
        func pixel(_ x: Int, _ y: Int, _ channel: Int) -> Float {
            guard x >= 0, x < width, y >= 0, y < height else { return 114 }
            return Float(bytes[y*stride+x*4+(2-channel)])
        }
        for y in 0..<320 {
            let sy = crop.square.minY+(CGFloat(y)+0.5)*crop.square.height/320-0.5
            let y0 = Int(floor(sy)), fy = Float(sy-CGFloat(y0))
            for x in 0..<320 {
                let sx = crop.square.minX+(CGFloat(x)+0.5)*crop.square.width/320-0.5
                let x0 = Int(floor(sx)), fx = Float(sx-CGFloat(x0))
                for c in 0..<3 {
                    let top = pixel(x0,y0,c)*(1-fx)+pixel(x0+1,y0,c)*fx
                    let bottom = pixel(x0,y0+1,c)*(1-fx)+pixel(x0+1,y0+1,c)*fx
                    target[c*320*320+y*320+x] = (top*(1-fy)+bottom*fy)/255
                }
            }
        }
    }
    static func error(_ message: String) -> NSError { NSError(domain: "BirdONNX", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
