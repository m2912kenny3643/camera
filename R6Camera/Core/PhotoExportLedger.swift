import Foundation

struct PhotoExportLedger: Codable {
    enum State: String, Codable { case queued, exporting, exported, failed, uncertain }
    struct Entry: Codable { var state: State; var error: String? }
    private(set) var entries: [String: Entry] = [:]
    mutating func recoverInterrupted() {
        for (key, entry) in entries where entry.state == .queued || entry.state == .exporting {
            entries[key] = Entry(state: .uncertain, error: "上次匯出未確認，重試可能產生相簿副本")
        }
    }
    mutating func enqueue(_ key: String, retry: Bool = false) -> Bool {
        if let state = entries[key]?.state {
            guard state != .exported && state != .queued && state != .exporting else { return false }
            guard retry else { return false }
        }
        entries[key] = Entry(state: .queued, error: nil); return true
    }
    mutating func start(_ key: String) { entries[key] = Entry(state: .exporting, error: nil) }
    mutating func finish(_ key: String, error: String?) {
        entries[key] = Entry(state: error == nil ? .exported : .failed, error: error)
    }
    func isBusy(_ key: String) -> Bool {
        guard let state = entries[key]?.state else { return false }
        return state == .queued || state == .exporting
    }
    mutating func remove(_ key: String) { entries.removeValue(forKey: key) }
}
