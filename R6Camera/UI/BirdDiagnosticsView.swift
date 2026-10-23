import SwiftUI
import AVFoundation
import ImageIO

/// Fixed photographs exercise the bundled model, never masquerading as live camera accuracy.
struct BirdDiagnosticsView: View {
    @StateObject private var run = BirdDiagnosticRun()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("鳥眼／頭部模型功能測試").font(.headline)
                Spacer()
                Button("返回") { dismiss() }.accessibilityIdentifier("bird.test.close")
            }
            Text("固定照片；人工遮眼素材有標記。不是100張獨立準確度或相機端到端效能驗收。")
                .font(.caption2).foregroundStyle(.gray)
            HStack(spacing: 5) {
                ForEach(BirdDiagnosticCase.allCases) { sample in
                    Button(sample.title) { run.load(sample) }
                        .font(.caption2).padding(5)
                        .overlay(Rectangle().stroke(run.selected == sample ? Color.yellow : .gray))
                        .accessibilityIdentifier("bird.test.case.\(sample.rawValue)")
                        .disabled(run.busy)
                }
            }
            GeometryReader { g in
                ZStack {
                    Color.black
                    if let image = run.image {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                            .frame(width: g.size.width, height: g.size.height)
                            .accessibilityHidden(false).accessibilityElement(children: .ignore)
                            .accessibilityLabel(run.selected.title).accessibilityIdentifier("bird.test.image")
                        if let bird = run.observations.first {
                            let bounds = bird.detection.focusBounds(.automatic)
                            let imageRect = ViewfinderGeometry.imageRect(imageAspect: CGFloat(image.width)/CGFloat(image.height), in: g.size)
                            Rectangle().stroke(.cyan, lineWidth: 2)
                                .frame(width: bounds.width*imageRect.width, height: bounds.height*imageRect.height)
                                .position(x: imageRect.minX+bounds.midX*imageRect.width, y: imageRect.minY+bounds.midY*imageRect.height)
                                .accessibilityElement().accessibilityLabel("唯一測試鎖框")
                                .accessibilityValue(run.level).accessibilityIdentifier("bird.test.box")
                        }
                    }
                    if run.busy { ProgressView().tint(.white) }
                }
            }
            HStack {
                Text(run.status).font(.caption).lineLimit(2)
                    .accessibilityIdentifier("bird.test.status").accessibilityValue(run.busy ? "處理中" : run.level)
                Spacer()
                if let report = run.report {
                    ShareLink(item: report) { Text("分享本張JSON").font(.caption) }
                }
                Button("下一張") { run.next() }.font(.caption).disabled(run.busy)
                    .accessibilityIdentifier("bird.test.next")
            }
        }.padding(12).foregroundStyle(.white).background(.black).buttonStyle(.plain)
            .onAppear { if run.image == nil && !run.busy { run.load(.eagle) } }
    }

    /// CGImage pixels are drawn directly into native BGRA rows, without UIImage orientation guesses.
    static func makeBuffer(_ image: CGImage) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
                                        kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferCGImageCompatibilityKey: true,
                                         kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &result)
        guard status == kCVReturnSuccess, let result else { throw BirdONNXModel.error("無法建立測試影像緩衝") }
        CVPixelBufferLockBaseAddress(result, [])
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(result), width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(result),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw BirdONNXModel.error("無法讀取測試照片像素")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return result
    }
}

private enum BirdDiagnosticCase: String, CaseIterable, Identifiable {
    case eagle, head, body, frontal, distant, background
    var id: String { rawValue }
    var title: String {
        switch self {
        case .eagle: return "側面眼睛"
        case .head: return "人工遮眼／頭部"
        case .body: return "人工遮眼／身體"
        case .frontal: return "正面雙眼"
        case .distant: return "遠距多鳥"
        case .background: return "無鳥背景裁切"
        }
    }
    var fileExtension: String { self == .eagle || self == .background ? "png" : "jpg" }
    var isArtificial: Bool { self == .head || self == .body }
}

private final class BirdDiagnosticRun: ObservableObject {
    @Published var selected = BirdDiagnosticCase.eagle
    @Published var image: CGImage?
    @Published var observations: [BirdPoseObservation] = []
    @Published var busy = false
    @Published var status = "尚未測試"
    @Published var level = "尚未測試"
    @Published var report: String?
    private let queue = DispatchQueue(label: "camera.bird-fixture", qos: .userInitiated)
    private var model: BirdONNXModel? // Only the serial queue accesses inference state.

    func next() {
        let cases = BirdDiagnosticCase.allCases
        let index = cases.firstIndex(of: selected) ?? 0
        load(cases[(index+1) % cases.count])
    }
    func load(_ sample: BirdDiagnosticCase) {
        guard !busy else { return }
        selected = sample; busy = true; image = nil; observations = []; report = nil
        status = "正在執行離線模型"; level = "處理中"
        queue.async {
            do {
                guard let url = Bundle.main.url(forResource: "BirdFixture-\(sample.rawValue)", withExtension: sample.fileExtension),
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw BirdONNXModel.error("找不到測試照片：\(sample.rawValue)")
                }
                if self.model == nil { self.model = try BirdONNXModel() }
                guard let model = self.model else { throw BirdONNXModel.error("鳥眼模型未載入") }
                let buffer = try BirdDiagnosticsView.makeBuffer(image)
                let started = ProcessInfo.processInfo.systemUptime
                let observations = try model.observations(buffer, at: started, region: nil, padding: 1)
                let milliseconds = (ProcessInfo.processInfo.systemUptime-started)*1000
                let label = Self.level(observations.first?.detection)
                let payload: [String: Any] = [
                    "model_sha256": BirdPoseDecoder.androidSHA256, "fixture": sample.rawValue,
                    "artificial_occlusion": sample.isArtificial, "result": label,
                    "latency_ms": milliseconds, "latency_scope": "fixture_buffer_to_decoded_observations",
                    "independent_accuracy_evaluation": false,
                    "observations": observations.map { pose -> [String: Any] in
                        ["body": [pose.body.minX, pose.body.minY, pose.body.width, pose.body.height],
                         "confidence": pose.confidence, "image_timestamp": pose.timestamp,
                         "points": pose.keypoints.map { key, value -> [String: Any] in
                             ["landmark": key.rawValue, "x": value.position.x, "y": value.position.y,
                              "confidence": value.confidence]
                         }]
                    }
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                DispatchQueue.main.async {
                    self.image = image; self.observations = observations; self.level = label
                    self.status = "\(sample.title)：\(label) · 固定圖推論 \(String(format: "%.1f", milliseconds)) ms（非相機效能）"
                    self.report = String(data: data, encoding: .utf8); self.busy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = "測試失敗：\(error.localizedDescription)"; self.level = "失敗"; self.busy = false
                }
            }
        }
    }
    private static func level(_ detection: SubjectDetection?) -> String {
        guard let detection else { return "未辨識" }
        if detection.eye(.automatic) != nil { return "眼睛" }
        return detection.headBounds == nil ? "身體" : "頭部"
    }
}
