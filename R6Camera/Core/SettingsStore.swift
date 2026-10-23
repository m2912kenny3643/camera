import Foundation

struct SettingsStore {
    struct LoadResult { let settings: CameraSettings?; let diagnostic: String? }
    private struct Envelope: Codable { let version: Int; let settings: CameraSettings }
    private struct Header: Decodable { let version: Int }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load(_ key: String = "current") -> CameraSettings? { inspect(key).settings }
    func inspect(_ key: String = "current") -> LoadResult {
        guard let stored = defaults.object(forKey: "camera.\(key)") else { return LoadResult(settings: nil, diagnostic: nil) }
        do {
            guard let data = stored as? Data else { throw Failure.invalid }
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalid }
            if object["version"] != nil || object["settings"] != nil {
                guard try JSONDecoder().decode(Header.self, from: data).version == 1,
                      let payload = object["settings"] as? [String: Any] else { throw Failure.version }
                object = payload
            }
            // Legacy payloads can omit newer fields. Invalid known values still fail decoding.
            let encoded = try JSONEncoder().encode(CameraSettings())
            guard var merged = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { throw Failure.invalid }
            merged.merge(object) { _, saved in saved }
            let restored = try JSONDecoder().decode(CameraSettings.self, from: JSONSerialization.data(withJSONObject: merged))
            return LoadResult(settings: restored, diagnostic: nil)
        } catch {
            return LoadResult(settings: nil, diagnostic: "\(key) 設定損壞或版本不支援；原始資料保留，暫停覆寫。可在設定頁確認復原。")
        }
    }
    @discardableResult func save(_ settings: CameraSettings, key: String = "current") -> Bool {
        guard inspect(key).diagnostic == nil,
              let data = try? JSONEncoder().encode(Envelope(version: 1, settings: settings)) else { return false }
        defaults.set(data, forKey: "camera.\(key)"); return true
    }
    /// Called only after explicit recovery confirmation. Preserve each exact failed payload.
    func recoverInvalid() {
        for key in ["current", "C1", "C2", "C3"] where inspect(key).diagnostic != nil {
            if let stored = defaults.object(forKey: "camera.\(key)") {
                defaults.set(stored, forKey: "camera.recovery.\(key).\(UUID().uuidString)")
                defaults.removeObject(forKey: "camera.\(key)")
            }
        }
    }
    var diagnostics: String? {
        let messages = ["current", "C1", "C2", "C3"].compactMap { inspect($0).diagnostic }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
    private enum Failure: Error { case invalid, version }
}
