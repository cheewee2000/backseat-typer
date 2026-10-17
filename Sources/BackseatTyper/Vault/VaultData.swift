// Ported unchanged from Form Filler (iOS) Shared/VaultData.swift.
import Foundation

struct Profile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var role: String
    var values: [String: String]

    init(id: String, name: String, role: String = "", values: [String: String] = [:]) {
        self.id = id; self.name = name; self.role = role; self.values = values
    }

    enum CodingKeys: String, CodingKey { case id, name, role, values }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        values = try c.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
    }
}

/// The whole vault. Same JSON shape as the web version's vault.
struct VaultData: Codable {
    var v: Int = 1
    var custom: [FieldDef] = []
    var nextP: Int = 2
    var profiles: [Profile] = [Profile(id: "P1", name: "Me")]

    init() {}

    enum CodingKeys: String, CodingKey { case v, custom, nextP, profiles }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        custom = try c.decodeIfPresent([FieldDef].self, forKey: .custom) ?? []
        nextP = try c.decodeIfPresent(Int.self, forKey: .nextP) ?? 2
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? [Profile(id: "P1", name: "Me")]
        if profiles.isEmpty { profiles = [Profile(id: "P1", name: "Me")] }
    }

    var allFields: [FieldDef] { Schema.base + custom }
    func field(_ key: String) -> FieldDef? { allFields.first { $0.key == key } }
    func profile(_ id: String) -> Profile? { profiles.first { $0.id == id } }
    func value(_ pid: String, _ key: String) -> String { profile(pid)?.values[key] ?? "" }

    var groups: [String] {
        var out: [String] = []
        for g in Schema.groupOrder where allFields.contains(where: { $0.group == g }) { out.append(g) }
        for f in allFields where !out.contains(f.group) { out.append(f.group) }
        return out
    }

    mutating func addCustomField(label: String, kind: FieldKind, sensitive: Bool) -> String {
        var key = label.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if key.isEmpty { key = "field" }
        key = String(key.prefix(40))
        while field(key) != nil { key += "_2" }
        custom.append(FieldDef(key, label, "Custom", kind: kind, sensitive: sensitive, custom: true))
        return key
    }

    mutating func setValue(_ pid: String, _ key: String, _ value: String) {
        guard let i = profiles.firstIndex(where: { $0.id == pid }) else { return }
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { profiles[i].values.removeValue(forKey: key) } else { profiles[i].values[key] = value }
    }
}
