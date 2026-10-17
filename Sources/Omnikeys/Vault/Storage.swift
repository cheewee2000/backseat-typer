// Ported from Form Filler (iOS) Shared/Storage.swift: same vault encryption and the same passphrase backup
// format, so a backup exported from the iPhone app or the web version restores here unchanged.
import Foundation
import Security
import CryptoKit
import CommonCrypto

enum Keychain {
    static func get(_ account: String) -> Data? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    static func set(_ data: Data, _ account: String) -> Bool {
        SecItemDelete(base(account) as CFDictionary)
        var q = base(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) { SecItemDelete(base(account) as CFDictionary) }

    private static func base(_ account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Omnikeys",
            kSecAttrAccount as String: account,
        ]
        return q
    }
}

enum VaultError: LocalizedError {
    case missingKey, badBackup, wrongPassphrase
    var errorDescription: String? {
        switch self {
        case .missingKey: return "The vault's key is missing from this device's keychain. Restore a backup or erase the vault."
        case .badBackup: return "That file isn't a Form Filler backup."
        case .wrongPassphrase: return "That passphrase doesn't open this backup."
        }
    }
}

/// The vault on disk: AES-256-GCM with a random key held in the keychain (this device only).
enum VaultFile {
    static var url: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Omnikeys", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("vault.enc")
    }
    private static let keyAccount = "vault-key"

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    private static func key(create: Bool) throws -> SymmetricKey {
        if let d = Keychain.get(keyAccount) { return SymmetricKey(data: d) }
        guard create else { throw VaultError.missingKey }
        let k = SymmetricKey(size: .bits256)
        Keychain.set(k.withUnsafeBytes { Data($0) }, keyAccount)
        return k
    }

    static func load() throws -> VaultData? {
        guard exists else { return nil }
        let blob = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: blob)
        let pt = try AES.GCM.open(box, using: try key(create: false))
        return try JSONDecoder().decode(VaultData.self, from: pt)
    }

    static func save(_ v: VaultData) throws {
        let pt = try JSONEncoder().encode(v)
        let box = try AES.GCM.seal(pt, using: try key(create: true))
        guard let combined = box.combined else { return }
        try combined.write(to: url, options: [.atomic])
    }

    static func erase() {
        try? FileManager.default.removeItem(at: url)
        Keychain.delete(keyAccount)
    }
}

/// Passphrase-protected backup, byte-compatible with the web version
/// (PBKDF2-SHA256, AES-256-GCM, ciphertext followed by the 16-byte tag, base64 fields).
enum Backup {
    struct File: Codable {
        var app: String
        var v: Int
        var kdf: String
        var iter: Int
        var salt: String
        var iv: String
        var ct: String
    }

    static let iterations = 600_000

    static func deriveKey(_ pass: String, salt: Data, iter: Int) -> SymmetricKey {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(pass.utf8)
        let saltBytes = [UInt8](salt)
        pw.withUnsafeBufferPointer { pwp in
            pwp.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pw.count) { pwc in
                _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwc, pw.count,
                                         saltBytes, saltBytes.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iter),
                                         &out, out.count)
            }
        }
        return SymmetricKey(data: Data(out))
    }

    static func export(_ vault: VaultData, passphrase: String) throws -> Data {
        var salt = Data(count: 16); salt.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let key = deriveKey(passphrase, salt: salt, iter: iterations)
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(try JSONEncoder().encode(vault), using: key, nonce: nonce)
        let file = File(app: "form-filler", v: 1, kdf: "PBKDF2-SHA256", iter: iterations,
                        salt: salt.base64EncodedString(), iv: nonce.withUnsafeBytes { Data($0) }.base64EncodedString(),
                        ct: (box.ciphertext + box.tag).base64EncodedString())
        return try JSONEncoder().encode(file)
    }

    static func open(_ data: Data, passphrase: String) throws -> VaultData {
        guard let f = try? JSONDecoder().decode(File.self, from: data), f.app == "form-filler",
              let salt = Data(base64Encoded: f.salt), let iv = Data(base64Encoded: f.iv),
              let ct = Data(base64Encoded: f.ct), ct.count > 16 else { throw VaultError.badBackup }
        let key = deriveKey(passphrase, salt: salt, iter: f.iter)
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ct.prefix(ct.count - 16), tag: ct.suffix(16))
            let pt = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode(VaultData.self, from: pt)
        } catch {
            throw VaultError.wrongPassphrase
        }
    }
}
