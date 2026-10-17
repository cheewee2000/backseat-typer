import Foundation

/// Typing history for personalization. Plain JSON in Application Support.
/// ponytail: unencrypted; wrap with CryptoKit + a Keychain key if the data ever needs it.
final class History {
    static let shared = History()
    struct Sample: Codable { var app: String; var text: String; var ts: Date }
    private(set) var samples: [Sample] = []
    private let url: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BackseatTyper", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("history.json")
    }()
    init() { if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode([Sample].self, from: d) { samples = s } }
    private func save() { if let d = try? JSONEncoder().encode(samples) { try? d.write(to: url, options: .atomic) } }

    func record(app: String, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 80 else { return }                 // skips search boxes, quick forms, revealed passwords
        if let i = samples.firstIndex(where: { $0.app == app && (t.hasPrefix($0.text) || $0.text.hasPrefix(t)) }) { samples.remove(at: i) }
        samples.append(Sample(app: app, text: String(t.suffix(1200)), ts: Date()))
        if samples.count > 400 { samples.removeFirst(samples.count - 400) }
        save()
    }
    func count(for app: String) -> Int { samples.filter { $0.app == app }.count }
    /// Strength 0 = off … 5 = max. Recent samples from this app first, then others.
    func examples(for app: String, strength: Int) -> [String] {
        guard strength > 0, !samples.isEmpty else { return [] }
        let n = [0, 2, 4, 6, 9, 12][min(5, strength)]
        let own = samples.filter { $0.app == app }.suffix(n).reversed()
        let rest = samples.filter { $0.app != app }.suffix(max(0, n - own.count)).reversed()
        return (Array(own) + Array(rest)).map { String($0.text.suffix(240)) }
    }
    func deleteAll() { samples = []; save() }
}
