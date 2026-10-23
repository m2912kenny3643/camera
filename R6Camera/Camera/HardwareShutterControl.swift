import AVFoundation

enum HardwareShutterControl {
    /// One fixed value keeps the public overlay path without exposing any sliding adjustment.
    static func make(queue: DispatchQueue) -> AVCaptureIndexPicker {
        let picker = AVCaptureIndexPicker("快門", symbolName: "camera", localizedIndexTitles: ["對焦／返回"])
        picker.setActionQueue(queue) { _ in } // No index can change a setting.
        return picker
    }
}
