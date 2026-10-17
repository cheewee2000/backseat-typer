// Ported unchanged from Form Filler (iOS) Shared/Template.swift.
import Foundation

/// Templates are plain text with placeholders like `{P1.family_name}, {P1.given_name}`.
/// Pipes: `|MM/DD/YYYY` (any mix of YYYY YY MM DD M D Mon Month), `|digits`, `|last4`,
/// `|upper`, `|lower`, `|initial`, `|lines` (keep list items on separate lines).
enum Template {
    static let placeholder = try! NSRegularExpression(pattern: #"\{(?:(P\d+)\.)?([A-Za-z0-9_]+)((?:\|[^|}]+)*)\}"#)
    private static let months = ["January", "February", "March", "April", "May", "June", "July",
                                 "August", "September", "October", "November", "December"]

    static func isoToday() -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    struct Ref: Hashable { let pid: String; let key: String }

    static func refs(in t: String) -> [Ref] {
        let ns = t as NSString
        return placeholder.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { m in
            let pid = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : "P1"
            return Ref(pid: pid, key: ns.substring(with: m.range(at: 2)))
        }
    }

    static func isSensitive(_ t: String, _ vault: VaultData) -> Bool {
        refs(in: t).contains { vault.field($0.key)?.sensitive == true }
    }

    static func render(_ t: String, _ vault: VaultData) -> String {
        guard !t.isEmpty else { return "" }
        let ns = t as NSString
        var out = ""
        var last = 0
        for m in placeholder.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let pid = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : "P1"
            let key = ns.substring(with: m.range(at: 2))
            let pipeText = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ""
            let pipes = pipeText.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var v = key == "today" ? isoToday() : vault.value(pid, key)
            let items = v.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            v = items.joined(separator: pipes.contains("lines") ? "\n" : ", ")
            for p in pipes { v = applyPipe(v, p) }
            out += v
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        out = out.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "(,\\s*){2,}", with: ", ", options: .regularExpression)
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,;/"))
    }

    static func applyPipe(_ v: String, _ p: String) -> String {
        guard !v.isEmpty else { return v }
        switch p {
        case "digits": return v.filter(\.isNumber)
        case "last4": return String(v.filter(\.isNumber).suffix(4))
        case "upper": return v.uppercased()
        case "lower": return v.lowercased()
        case "initial": return v.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? ""
        case "lines": return v
        default:
            if p.contains("YY") || p.contains("MM") || p.contains("DD") || p.contains("Mon") { return formatDate(v, p) }
            return v
        }
    }

    static func formatDate(_ iso: String, _ fmt: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, let mo = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(mo) else { return iso }
        let y = String(parts[0])
        let tokens: [(String, String)] = [
            ("YYYY", y), ("Month", months[mo - 1]), ("Mon", String(months[mo - 1].prefix(3))),
            ("YY", String(y.suffix(2))), ("MM", String(format: "%02d", mo)), ("DD", String(format: "%02d", d)),
            ("M", String(mo)), ("D", String(d)),
        ]
        var out = ""
        var rest = Substring(fmt)
        outer: while !rest.isEmpty {
            for (tok, val) in tokens where rest.hasPrefix(tok) {
                out += val
                rest = rest.dropFirst(tok.count)
                continue outer
            }
            out.append(rest.removeFirst())
        }
        return out
    }

    /// For HTML date inputs, which only accept YYYY-MM-DD.
    static func forcingISODates(_ t: String) -> String {
        t.replacingOccurrences(of: #"\|[^|}]*(YY|MM|DD|Mon)[^|}]*"#, with: "|YYYY-MM-DD", options: .regularExpression)
    }

    static func mask(_ v: String) -> String {
        if v.contains(",") || v.contains("\n") || v.count > 24 { return "•••• hidden" }
        return v.count <= 4 ? "••••" : "•••• " + v.suffix(4)
    }

    /// What a template displays, masking sensitive values unless revealed.
    static func display(_ t: String, _ vault: VaultData, reveal: Bool) -> String {
        let v = render(t, vault)
        return (!v.isEmpty && !reveal && isSensitive(t, vault)) ? mask(v) : v
    }
}
