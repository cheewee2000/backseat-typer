import Foundation
import Observation

/// Your form answers, encrypted at rest (see Storage.swift). What Form Filler keeps on the iPhone, kept here on the Mac.
@Observable final class Vault {
    static let shared = Vault()
    var data: VaultData
    var loadError: String?
    private var plainTest = false   // --e2e only: a plain JSON vault that is never written back

    init() {
        do { data = try VaultFile.load() ?? VaultData() } catch { data = VaultData(); loadError = error.localizedDescription }
    }
    func save() { guard !plainTest else { return }; do { try VaultFile.save(data) } catch { loadError = error.localizedDescription } }
    func loadPlain(path: String) {
        guard let d = FileManager.default.contents(atPath: path), let v = try? JSONDecoder().decode(VaultData.self, from: d) else { return }
        data = v; plainTest = true
    }
    func importBackup(url: URL, passphrase: String) throws {
        data = try Backup.open(try Data(contentsOf: url), passphrase: passphrase); save()
    }
    func erase() { data = VaultData(); VaultFile.erase() }
    var isEmpty: Bool { data.profiles.allSatisfy { $0.values.isEmpty } }
}
