import Foundation

/// Fuzzy matching for learned (custom) fields: labels agree when their content words agree,
/// so "Tell us about yourself" finds the answer learned under "Describe yourself".
extension Matcher {
    private static let stop: Set<String> = ["a", "an", "the", "your", "you", "yours", "us", "we", "our", "me", "my", "i", "please", "enter", "type",
                                            "of", "for", "to", "in", "on", "at", "about", "tell", "describe", "provide", "give", "what", "is", "are", "do", "does",
                                            "and", "or", "any", "if", "this", "that", "here", "below", "field", "required", "optional", "other", "additional", "info", "information", "details"]
    static func stems(_ label: String) -> Set<String> {
        Set(label.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init).filter { !stop.contains($0) && $0.count > 1 }.map { String($0.prefix(5)) })
    }
    /// The custom field whose label shares at least half of the content words, best match first.
    static func fuzzyCustom(_ label: String, vault: VaultData) -> FieldDef? {
        let a = stems(label)
        guard !a.isEmpty else { return nil }
        var best: (FieldDef, Double)?
        for c in vault.custom {
            let b = stems(c.label)
            guard !b.isEmpty else { continue }
            let score = Double(a.intersection(b).count) / Double(a.union(b).count)
            if score >= 0.5, score > (best?.1 ?? 0) { best = (c, score) }
        }
        return best?.0
    }
}
